#!/usr/bin/env python3
"""
narrate.py — Build the en-US TTS narration for the InteropMCP final video and
mix it into the concatenated video (intro + tutorial + outro).

Pipeline:
  1. For each narration cue (text + anchor time on the FINAL timeline), synthesize
     speech with edge-tts (neural en-US voice) and convert to mono 48 kHz WAV.
  2. Schedule cues sequentially so they never overlap: each cue starts at
     max(anchor, previous_end + gap).
  3. Mix all delayed cues onto a silent bed of the exact final duration and apply
     loudness normalization.
  4. Mux the audio into final.mp4 (video stream copied) -> interopmcp-final.mp4.

Requires: edge-tts (installed in a venv) and the local static ffmpeg build.

Run with the venv that has edge-tts, e.g.:
    /tmp/opencode/ttsvenv/bin/python demo-web/scripts/narrate.py
"""

import asyncio
import json
import os
import subprocess
import sys
import tempfile

try:
    import edge_tts
except ImportError:
    sys.exit("edge-tts is not installed. Run: pip install edge-tts")

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.normpath(os.path.join(HERE, "..", "output"))
FINAL_VIDEO = os.path.join(OUTPUT_DIR, "final.mp4")
OUT_VIDEO = os.path.join(OUTPUT_DIR, "interopmcp-final.mp4")

FFMPEG = "/tmp/opencode/ffmpeg/ffmpeg"
FFPROBE = "/tmp/opencode/ffmpeg/ffprobe"

VOICE = "en-US-AndrewNeural"
BASE_RATE = "+0%"
MIN_GAP = 0.25          # seconds of silence kept between cues

# Timeline anchors (seconds on the FINAL video)
INTRO_END = 67.96       # tutorial starts here
TOTAL = 305.56          # intro + tutorial + outro

# --- Intro cues (anchored to the 7 scenes; text mirrors the on-screen captions) ---
INTRO_CUES = [
    (0.6,  "InteropMCP: turn your InterSystems IRIS productions into native MCP tools for AI agents."),
    (6.4,  "The problem: traditional integration requires manual REST endpoints and loses native traceability."),
    (14.4, "Non-invasive gateway: Business Services are auto-discovered and exposed as typed MCP tools."),
    (24.4, "Native execution: invokes existing Business Services directly, via CreateBusinessService and ProcessInput."),
    (36.4, "Governance and safety: per-tool classification, read-only, write, or critical, with human-in-the-loop IRIS Workflow approval."),
    (50.4, "Built on the InterSystems AI HUB framework and deployed as a containerized workload."),
    (60.6, "Ready to see it in action? Next up: a live demo."),
]

# --- Tutorial cues: (relative_to_tutorial_start, text). Mirrors subtitles.srt ---
TUTORIAL_CUES_REL = [
    (8.899,  "InteropMCP. Turn your IRIS Interoperability Productions into MCP tools for AI agents."),
    (12.302, "The demo production is only an example. InteropMCP publishes any IRIS Interoperability Production."),
    (15.714, "Call the readonly PayLookup tool."),
    (45.453, "In the IRIS Message Viewer, every call flows through the same Business Service, Business Process, and Business Operation production as before."),
    (55.669, "Call the write CustomerUpdate tool. The guardrail logs the decision."),
    (78.178, "The message is processed by the existing production."),
    (87.388, "Call the critical AccountBlock tool. It is held for human approval."),
    (118.435, "GetInvocationStatus shows pending-approval. Nothing reached the production yet."),
    (138.684, "The approval is a native IRIS Workflow task for the operator."),
    (148.891, "The operator approves via the IRIS terminal. After approval, status is completed and the Business Service executed."),
    (168.554, "For a non-restricted CNPJ, the agent calls RiskCheck directly."),
    (185.223, "The RiskCheck request appears in the production."),
    (193.429, "For a restricted CNPJ, the agent creates a Workflow task instead of calling RiskCheck."),
    (211.541, "A new approval task is created. Humans retain final authority."),
    (221.754, "InteropMCP lets AI agents talk to any IRIS Interoperability Production without rewriting it."),
]

# --- Outro cue ---
OUTRO_CUES = [
    (295.9, "Thank you for your time. InteropMCP is built on InterSystems IRIS and AI HUB."),
]


def log(*a):
    print(*a, flush=True)


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def duration_of(path):
    out = subprocess.check_output([
        FFPROBE, "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", path,
    ], text=True).strip()
    return float(out)


async def synth(text, voice, rate, out_mp3):
    comm = edge_tts.Communicate(text, voice, rate=rate)
    await comm.save(out_mp3)


async def synth_with_retry(text, rate, out_mp3, attempts=6):
    """Retry transient edge-tts failures with backoff."""
    last = None
    for k in range(attempts):
        try:
            await synth(text, VOICE, rate, out_mp3)
            if os.path.exists(out_mp3) and os.path.getsize(out_mp3) > 1000:
                return
        except Exception as e:  # noqa: BLE001
            last = e
        await asyncio.sleep(1.0 + k)
    raise last if last else RuntimeError("TTS failed")


def synth_fallback_split(text, mp3, wav):
    """Split a stubborn cue into sentences, synthesize each, and concat them."""
    import re
    parts = [s.strip() for s in re.split(r'(?<=[.!?])\s+', text) if s.strip()]
    if len(parts) <= 1:
        parts = [text]
    piece_mp3s = []
    for j, part in enumerate(parts):
        pm = f"{mp3}.part{j}.mp3"
        asyncio.run(synth_with_retry(part, BASE_RATE, pm, attempts=6))
        piece_mp3s.append(pm)
    list_file = f"{mp3}.concat.txt"
    with open(list_file, "w") as fh:
        for pm in piece_mp3s:
            fh.write(f"file '{os.path.abspath(pm)}'\n")
    run([FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", list_file,
         "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", wav])


def synthesize_cues(cues, tmp):
    """cues: list of (anchor, text). Returns list of dicts with wav path + duration."""
    result = []
    for idx, (anchor, text) in enumerate(cues):
        mp3 = os.path.join(tmp, f"cue_{idx:02d}.mp3")
        wav = os.path.join(tmp, f"cue_{idx:02d}.wav")
        try:
            asyncio.run(synth_with_retry(text, BASE_RATE, mp3))
            run([FFMPEG, "-y", "-i", mp3, "-ar", "48000", "-ac", "1",
                 "-c:a", "pcm_s16le", wav])
        except Exception as e:  # noqa: BLE001
            log(f"  cue {idx:02d}: direct synth failed ({e}); splitting by sentence")
            synth_fallback_split(text, mp3, wav)
        result.append({"anchor": anchor, "text": text, "wav": wav,
                       "duration": duration_of(wav)})
        log(f"  cue {idx:02d}: {result[-1]['duration']:5.2f}s  anchor {anchor:7.2f}  | {text[:60]}")
    return result


def build_track(cues, total, out_wav):
    """Mix cues (already scheduled with .start) onto a silent bed of `total` seconds."""
    n = len(cues)
    inputs = []
    for c in cues:
        inputs += ["-i", c["wav"]]

    parts = []
    for i, c in enumerate(cues):
        ms = int(round(c["start"] * 1000))
        parts.append(f"[{i}:a]adelay={ms}:all=1[a{i}]")
    mix_in = "".join(f"[a{i}]" for i in range(n))
    parts.append(f"{mix_in}amix=inputs={n}:normalize=0:dropout_transition=0[mix]")
    parts.append(
        f"[mix]apad=whole_dur={total},atrim=0:{total},"
        f"loudnorm=I=-16:TP=-1.5:LRA=11[aout]"
    )
    filter_complex = ";".join(parts)

    run([FFMPEG, "-y", *inputs, "-filter_complex", filter_complex,
         "-map", "[aout]", "-ar", "48000", "-ac", "2",
         "-c:a", "pcm_s16le", out_wav])


def main():
    for p in (FINAL_VIDEO,):
        if not os.path.exists(p):
            sys.exit(f"Missing {p}. Run the concat step first.")

    all_cues = (
        [(a, t) for a, t in INTRO_CUES]
        + [(INTRO_END + r, t) for r, t in TUTORIAL_CUES_REL]
        + [(a, t) for a, t in OUTRO_CUES]
    )

    with tempfile.TemporaryDirectory(prefix="narr_") as tmp:
        log(f"Synthesizing {len(all_cues)} cues with {VOICE} ...")
        cues = synthesize_cues(all_cues, tmp)

        # Sequential, non-overlapping schedule anchored to the timeline.
        prev_end = -999.0
        for c in cues:
            start = max(c["anchor"], prev_end + MIN_GAP)
            c["start"] = start
            prev_end = start + c["duration"]
        # Clamp the very last cue so it cannot exceed the video.
        if cues and cues[-1]["start"] + cues[-1]["duration"] > TOTAL:
            log(f"WARNING: last cue ends past {TOTAL}s; it will be trimmed by atrim.")

        log("\nSchedule (start..end on final timeline):")
        for i, c in enumerate(cues):
            log(f"  {i:02d}  {c['start']:7.2f} .. {c['start']+c['duration']:7.2f}  "
                f"(anchor {c['anchor']:7.2f})  {c['text'][:50]}")

        mixed_wav = os.path.join(tmp, "mixed.wav")
        log("\nMixing cues into a single track ...")
        build_track(cues, TOTAL, mixed_wav)

        log("Muxing audio into video (video stream copied) ...")
        run([FFMPEG, "-y",
             "-i", FINAL_VIDEO,
             "-i", mixed_wav,
             "-map", "0:v:0", "-map", "1:a:0",
             "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart",
             "-shortest", OUT_VIDEO])

    log(f"\nWrote {OUT_VIDEO}")
    log("ffprobe:")
    probe = subprocess.check_output([
        FFPROBE, "-v", "error",
        "-show_entries", "stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels",
        "-show_entries", "format=duration,size",
        "-of", "default=noprint_wrappers=1", OUT_VIDEO,
    ], text=True)
    print(probe.strip())


if __name__ == "__main__":
    main()

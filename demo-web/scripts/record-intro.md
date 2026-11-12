# Recording the Introduction Animation (en-US)

This document explains how to run `record-intro.mjs` to produce the InteropMCP
introduction video in English (en-US).

The intro is a **self-contained dark canvas animation** derived from
`demo-web/interopmcp_animation_v5.html`. It reuses the tutorial's caption style
(monospace, bottom-centered, semi-transparent) and runs a fixed 68-second
7-scene timeline:

| # | Scene | Duration |
|---|-------|----------|
| 1 | Overview | 6s |
| 2 | The Integration Problem | 8s |
| 3 | Non-Invasive Gateway | 10s |
| 4 | Native Execution | 12s |
| 5 | Governance & Safety | 14s |
| 6 | AI HUB Framework | 10s |
| 7 | Live Demo Hook | 8s |

Output: `demo-web/output/intro.mp4` (h264, 1280×720, 25 fps, `yuv420p`) — format
matches `tutorial-raw.mp4` so the two can be concatenated without re-encoding.

---

## Key design decisions

- **Dark theme.** Same accent hues as the reference (agent blue, MCP purple,
  IRIS green, warning yellow, critical pink) on a `#0F172A` surface with
  `#1E293B` panels and `#334155` borders. This matches the dark-mode tutorial.
- **No on-screen controls.** The reference's Pause / Restart / progress bar /
  scene indicator (`div.controls`, buttons, CSS, and listeners) are intentionally
  removed. The page exposes a small `window.__intro` API instead so the recorder
  can drive it deterministically.
- **Bundled local assets.** No network at record time:
  - `assets/PJSSans.woff2` — Plus Jakarta Sans (variable, `font-weight: 400 800`).
  - `assets/iris-logo.png` — InterSystems logo.
- **1280×720 output.** Scenes are still authored in the reference's 1000×600
  coordinate space and mapped onto the canvas with
  `ctx.translate(40,0); ctx.scale(1.2,1.2)` (uniform, no distortion; 600×1.2=720).
- **Caption at the bottom.** The `#caption` div uses the exact tutorial style
  (`font-size: 20px` monospace, `background: rgba(0,0,0,0.25)`,
  `border: 1px solid rgba(255,255,255,0.28)`, `border-radius: 8px`,
  `box-shadow`) anchored at `bottom: 40px`. Each scene's subtitle is written to
  it every frame.

---

## Prerequisites

### ffmpeg

The recorder calls the local static ffmpeg build (not on `PATH`):

```
/tmp/opencode/ffmpeg/ffmpeg
/tmp/opencode/ffmpeg/ffprobe
```

### Node.js + Playwright

Playwright is already installed in `demo-web/scripts/node_modules`.

```bash
cd demo-web/scripts
node -e "import('playwright').then(m => console.log('playwright', !!m.chromium))"
```

The demo-web stack does **not** need to be running — the intro is a standalone
`file://` page.

---

## Run

```bash
cd demo-web/scripts
node record-intro.mjs
```

What the script does, in order:

1. Launches headless Chromium and creates a context with `recordVideo`
   (viewport 1280×720, `size` 1280×720, `colorScheme: 'dark'`).
2. Opens `file://…/intro.html?record=1`.
3. Waits for `window.__intro.ready === true` (local font + logo settled) and
   records the wall-clock time to compute the pre-roll.
4. Calls `window.__intro.start()` — the page starts **paused**, so the timeline
   begins exactly here.
5. Waits until `window.__intro.elapsed >= totalDuration` (68s), then holds
   ~0.7s for encode margin.
6. Closes the context, reads the recorded WebM from `page.video()`.
7. Runs ffmpeg: `-ss <pre-roll> -t 68 -r 25 -c:v libx264 -preset slow -crf 22
   -pix_fmt yuv420p -movflags +faststart`.
8. Writes `demo-web/output/intro.mp4` and prints `ffprobe` (duration/resolution).

The pre-roll trim removes the load/paused lead-in so the video starts exactly at
scene 1, progress 0.

---

## Expected output

| File | Description |
|------|-------------|
| `output/intro.mp4` | Final intro (h264, 1280×720, 25 fps, ~68s, ~0.9 MB) |

ffprobe should report:

```
width=1280
height=720
r_frame_rate=25/1
duration≈67.96
```

---

## Re-recording

Everything lives in `demo-web/scripts/`. To re-record:

```bash
cd demo-web/scripts
node record-intro.mjs
```

`output/intro.mp4` is overwritten (`-y`).

---

## Outro (closing)

`outro.html` + `record-outro.mjs` produce `demo-web/output/outro.mp4` (same
format: h264, 1280×720, 25 fps, `yuv420p`, ~10s). It repeats the reference's
scene 1 (ring + AI Agents / InteropMCP / IRIS Production + title + tagline) and
adds an en-US thank-you message, then fades to black:

- Canvas text: **"Thank you for your time!"** + "InteropMCP — built on
  InterSystems IRIS and AI HUB".
- Entrance ramps over ~1.7s; fade-out over the final 1.0s.

```bash
cd demo-web/scripts
node record-outro.mjs
```

## Final assembly

`intro.mp4`, `tutorial-raw.mp4`, and `outro.mp4` share codec/resolution/fps, so
they concatenate with a stream copy (no re-encode):

```bash
cd demo-web/output
printf "file '%s'\nfile '%s'\nfile '%s'\n" \
  "$PWD/intro.mp4" "$PWD/tutorial-raw.mp4" "$PWD/outro.mp4" > /tmp/concat.txt
/tmp/opencode/ffmpeg/ffmpeg -y -f concat -safe 0 -i /tmp/concat.txt -c copy final.mp4
```

Result: `demo-web/output/final.mp4` (~305.6s = 67.96 + 227.64 + 9.96). This is
**video-only**; narration/TTS audio is still to be added later.

## Narration (TTS) & final mix

`narrate.py` adds an en-US neural voiceover to `final.mp4` and writes the
deliverable `demo-web/output/interopmcp-final.mp4` (video stream copied, AAC
audio added).

It synthesizes one clip per narration cue with **edge-tts** (`en-US-AndrewNeural`),
schedules the cues sequentially (never overlapping), mixes them onto a silent
bed of the exact final duration, loudness-normalizes (`loudnorm I=-16`), and muxes.

Cues mirror the on-screen text: the 7 intro captions, the 16 tutorial subtitles
(shifted by `INTRO_END = 67.96s`), and the outro thank-you. Since a few caption
windows are shorter than the spoken line, the scheduler pushes a cue later rather
than overlapping it (so a couple of early tutorial lines arrive a few seconds
after their caption anchor).

Setup (one-time, isolated venv):

```bash
python3 -m venv /tmp/opencode/ttsvenv
/tmp/opencode/ttsvenv/bin/pip install edge-tts
```

Run:

```bash
cd /home/jose/dev/tmp/interopmcp
/tmp/opencode/ttsvenv/bin/python demo-web/scripts/narrate.py
```

Expected output: `interopmcp-final.mp4` — h264 1280×720 25 fps + AAC 48 kHz
stereo, ~305.6s, ~11 MB. Verify with `volumedetect` (speech ≈ -19 dB mean,
silence gaps ≈ -91 dB, peaks ≈ -4.5 dB).

Tunables at the top of `narrate.py`: `VOICE`, `BASE_RATE`, `MIN_GAP`, and the
`*_CUES` lists.

## Notes

- **Language:** all on-screen text is **en-US**.
- **No ngrok:** the intro is a local `file://` page; nothing is exposed.
- **Demo is an example:** the intro states InteropMCP works with *any* IRIS
  Interoperability Production; the demo is only an illustration.
- **Concat:** `intro.mp4` and `tutorial-raw.mp4` share codec/resolution/fps, so a
  simple `ffmpeg -f concat` list works.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Playwright can't find Chromium | `npx playwright install chromium` in `demo-web/scripts/`. |
| Font renders as fallback | Confirm `assets/PJSSans.woff2` exists next to `intro.html`. |
| Logo missing in scenes 2–4 | Confirm `assets/iris-logo.png` exists. |
| Video is black / no animation | Open `intro.html` in a browser; check the console. |
| Duration is not ~68s | Check the `ffprobe` line printed at the end; the trim uses the measured pre-roll. |

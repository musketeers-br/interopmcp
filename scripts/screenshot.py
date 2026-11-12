"""Capture screenshots for InteropMCP tutorial articles.

Implements the three functions documented in docs/articles/article-writer-agent.md:

- capture_web(url, selector, out_path)   - Playwright + Chromium headless
- capture_tty(command, out_path)         - asciinema rec -> termtosvg -> ImageMagick
- capture_gui(window_id_or_root, out_path) - gnome-screenshot / scrot

Each returns the output path. Environment variables:
  SCREENSHOT_VIEWPORT  viewport size for web captures (default 1324x736)
  SCREENSHOT_BROWSER   chromium channel/executable hint (default chromium)
  SCREENSHOT_TIMEOUT   seconds to wait for page load (default 30)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_VIEWPORT = os.environ.get("SCREENSHOT_VIEWPORT", "1324x736")
DEFAULT_TIMEOUT = int(os.environ.get("SCREENSHOT_TIMEOUT", "30"))


def _fail(message: str) -> str:
    print(f"screenshot.py: {message}", file=sys.stderr)
    return ""


def capture_web(url: str, selector: str | None, out_path: str | Path,
                viewport: str = DEFAULT_VIEWPORT, timeout: int = DEFAULT_TIMEOUT) -> str:
    """Screenshot of a Web UI (IRIS Management Portal, MCP endpoint, etc.).

    Uses Playwright + Chromium headless, same mechanism as
    demo-web/scripts/record-screenshots.mjs.
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:
        return _fail(f"playwright is required for capture_web: {exc}")

    width, height = (int(v) for v in viewport.split("x"))
    out_path = Path(out_path)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=[
            "--force-dark-mode",
            "--enable-features=WebContentsForceDark",
            "--blink-settings=forceDarkModeEnabled=true",
        ])
        context = browser.new_context(
            viewport={"width": width, "height": height},
            color_scheme="dark",
            locale="en-US",
        )
        page = context.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=timeout * 1000)
        page.wait_for_load_state("load", timeout=timeout * 1000)
        if selector:
            locator = page.locator(selector)
            locator.wait_for(state="visible", timeout=timeout * 1000)
            locator.screenshot(path=str(out_path))
        else:
            page.screenshot(path=str(out_path), full_page=True)
        browser.close()

    if not out_path.exists():
        return _fail(f"web capture did not produce {out_path}")
    print(f"screenshot.py: web -> {out_path}")
    return str(out_path)


def capture_tty(command: str, out_path: str | Path, duration: int = 15) -> str:
    """Screenshot of a TUI (terminal, docker logs, ANSI output).

    Records with asciinema, renders with termtosvg, converts to PNG with
    ImageMagick.
    """
    out_path = Path(out_path)
    cast_path = out_path.with_suffix(".cast")
    svg_path = out_path.with_suffix(".svg")

    asciinema = shutil.which("asciinema")
    termtosvg = shutil.which("termtosvg")
    convert = shutil.which("convert")
    missing = [name for name, bin_ in (("asciinema", asciinema), ("termtosvg", termtosvg),
                                       ("convert", convert)) if not bin_]
    if missing:
        return _fail(f"capture_tty requires: {', '.join(missing)}")

    try:
        subprocess.run(
            [asciinema, "rec", "-c", command, str(cast_path)],
            check=True, capture_output=True, timeout=duration + 10,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        return _fail(f"asciinema rec failed: {exc}")

    try:
        subprocess.run(
            [termtosvg, str(cast_path), "-o", str(svg_path)],
            check=True, capture_output=True, timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        return _fail(f"termtosvg failed: {exc}")

    try:
        subprocess.run(
            [convert, str(svg_path), str(out_path)],
            check=True, capture_output=True, timeout=30,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        return _fail(f"convert failed: {exc}")

    # limpeza de artefatos intermediarios
    for artifact in (cast_path, svg_path):
        try:
            artifact.unlink()
        except OSError:
            pass

    if not out_path.exists():
        return _fail(f"tty capture did not produce {out_path}")
    print(f"screenshot.py: tty -> {out_path}")
    return str(out_path)


def capture_gui(window_id_or_root: str | None, out_path: str | Path) -> str:
    """Screenshot of a GUI desktop window (X11/GNOME).

    Prefers gnome-screenshot (window id), falls back to scrot, then to
    flameshot when available.
    """
    out_path = Path(out_path)
    gnome = shutil.which("gnome-screenshot")
    scrot = shutil.which("scrot")
    flameshot = shutil.which("flameshot")

    if gnome:
        cmd = ["gnome-screenshot", "-f", str(out_path)]
        if window_id_or_root and window_id_or_root != "root":
            cmd = ["gnome-screenshot", "-w", "-i", window_id_or_root, "-f", str(out_path)]
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=30)
        except subprocess.CalledProcessError as exc:
            return _fail(f"gnome-screenshot failed: {exc}")
    elif scrot:
        cmd = ["scrot", "-u", str(out_path)] if window_id_or_root else ["scrot", str(out_path)]
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=30)
        except subprocess.CalledProcessError as exc:
            return _fail(f"scrot failed: {exc}")
    elif flameshot:
        return _fail("flameshot requires interactive selection; use gnome-screenshot or scrot")
    else:
        return _fail("no GUI capture tool available (gnome-screenshot/scrot/flameshot)")

    if not out_path.exists():
        return _fail(f"gui capture did not produce {out_path}")
    print(f"screenshot.py: gui -> {out_path}")
    return str(out_path)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Capture screenshots for InteropMCP docs")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_web = sub.add_parser("web", help="capture a web page")
    p_web.add_argument("url")
    p_web.add_argument("--selector")
    p_web.add_argument("out")
    p_web.add_argument("--viewport", default=DEFAULT_VIEWPORT)

    p_tty = sub.add_parser("tty", help="capture a terminal command")
    p_tty.add_argument("command")
    p_tty.add_argument("out")
    p_tty.add_argument("--duration", type=int, default=15)

    p_gui = sub.add_parser("gui", help="capture a GUI window")
    p_gui.add_argument("out")
    p_gui.add_argument("--window")

    args = parser.parse_args()

    if args.cmd == "web":
        ok = bool(capture_web(args.url, args.selector, args.out, args.viewport))
    elif args.cmd == "tty":
        ok = bool(capture_tty(args.command, args.out, args.duration))
    else:
        ok = bool(capture_gui(args.window, args.out))

    raise SystemExit(0 if ok else 1)

#!/usr/bin/env node
/**
 * record-intro.mjs — Records the InteropMCP introduction animation (en-US).
 *
 * Pipeline:
 *   - Playwright Chromium headless with recordVideo (viewport 1280x720)
 *   - Loads demo-web/scripts/intro.html, which is a self-contained dark
 *     canvas animation based on interopmcp_animation_v5.html.
 *   - The page owns its captions (a #caption div in the tutorial's caption
 *     style, anchored at the bottom). No caption injection here.
 *   - The page starts paused; we call window.__intro.start() once assets are
 *     ready, then wait until window.__intro.elapsed reaches the total duration.
 *   - ffmpeg (local static build) trims the pre-roll and encodes MP4.
 *
 * Usage: node record-intro.mjs
 */

import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { mkdirSync, existsSync } from 'fs';
import { execFileSync } from 'child_process';
import { chromium } from 'playwright';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SCRIPT_DIR = __dirname;
const OUTPUT_DIR = join(SCRIPT_DIR, '..', 'output');
const INTRO_HTML = join(SCRIPT_DIR, 'intro.html');

const WIDTH = 1280;
const HEIGHT = 720;
const FPS = 25;
const FFMPEG = '/tmp/opencode/ffmpeg/ffmpeg';
const FFPROBE = '/tmp/opencode/ffmpeg/ffprobe';

function log(...args) {
  const ts = new Date().toISOString().replace(/T/, ' ').substring(0, 19);
  console.log(`[${ts}]`, ...args);
}

function run(cmd, args = [], opts = {}) {
  log('$', cmd, args.join(' '));
  return execFileSync(cmd, args, { stdio: 'inherit', encoding: 'utf8', ...opts });
}

function ensureDir(p) {
  if (!existsSync(p)) mkdirSync(p, { recursive: true });
}

async function main() {
  ensureDir(OUTPUT_DIR);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: WIDTH, height: HEIGHT },
    deviceScaleFactor: 1,
    colorScheme: 'dark',
    recordVideo: { dir: OUTPUT_DIR, size: { width: WIDTH, height: HEIGHT } },
  });

  const page = await context.newPage();

  // Video timeline starts roughly at page creation; measure it for trimming.
  const tCtx = Date.now();

  await page.goto('file://' + INTRO_HTML + '?record=1', {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });

  // Wait for local font + logo to settle (page flips __intro.ready).
  await page.waitForFunction(
    () => window.__intro && window.__intro.ready === true,
    null,
    { timeout: 20000, polling: 100 },
  );
  const tReady = Date.now();
  const totalDuration = await page.evaluate(() => window.__intro.totalDuration);
  log('Ready. totalDuration =', totalDuration, 's');

  // Start the timeline.
  await page.evaluate(() => window.__intro.start());
  log('Animation started.');

  // Wait until the animation reaches the end. `elapsed` is clamped at
  // totalDuration, so poll just below it, then hold briefly for encode margin.
  await page.waitForFunction(
    (d) => window.__intro.elapsed >= d,
    totalDuration - 0.05,
    { timeout: (totalDuration + 40) * 1000, polling: 200 },
  );
  await page.waitForTimeout(700);
  log('Animation finished. elapsed =', await page.evaluate(() => window.__intro.elapsed));

  const video = page.video();
  await context.close();
  await browser.close();

  const webmPath = await video.path();
  log('WebM recorded:', webmPath);

  // Pre-roll = wall time between context creation and the start of the timeline.
  const preRoll = Math.max(0, (tReady - tCtx) / 1000);
  log('Computed pre-roll trim:', preRoll.toFixed(2), 's');

  const mp4Path = join(OUTPUT_DIR, 'intro.mp4');
  run(FFMPEG, [
    '-y',
    '-ss', preRoll.toFixed(3),
    '-i', webmPath,
    '-t', String(totalDuration),
    '-r', String(FPS),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '22',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
    mp4Path,
  ]);

  log('MP4 written:', mp4Path);

  // Report final duration/resolution for sanity.
  try {
    const probe = execFileSync(
      FFPROBE,
      ['-v', 'error', '-select_streams', 'v:0',
       '-show_entries', 'stream=width,height,r_frame_rate:format=duration',
       '-of', 'default=noprint_wrappers=1', mp4Path],
      { encoding: 'utf8' },
    );
    log('ffprobe:\n' + probe.trim());
  } catch (e) {
    log('ffprobe unavailable:', e.message);
  }
}

main().catch((err) => {
  console.error('ERROR:', err);
  process.exit(1);
});

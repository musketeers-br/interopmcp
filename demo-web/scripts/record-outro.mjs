#!/usr/bin/env node
/**
 * record-outro.mjs — Records the InteropMCP closing/outro animation (en-US).
 *
 * Mirrors record-intro.mjs: loads outro.html (dark, single scene that repeats
 * the reference overview + a thank-you message), waits for the local font/logo,
 * starts the timeline, waits for it to finish, then trims the pre-roll and
 * encodes MP4 (h264, 1280x720, 25 fps) so it can be concatenated after the
 * tutorial.
 *
 * Usage: node record-outro.mjs
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
const OUTRO_HTML = join(SCRIPT_DIR, 'outro.html');

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
  const tCtx = Date.now();

  await page.goto('file://' + OUTRO_HTML + '?record=1', {
    waitUntil: 'domcontentloaded',
    timeout: 30000,
  });

  await page.waitForFunction(
    () => window.__outro && window.__outro.ready === true,
    null,
    { timeout: 20000, polling: 100 },
  );
  const tReady = Date.now();
  const totalDuration = await page.evaluate(() => window.__outro.totalDuration);
  log('Ready. duration =', totalDuration, 's');

  await page.evaluate(() => window.__outro.start());
  log('Outro started.');

  await page.waitForFunction(
    (d) => window.__outro.elapsed >= d,
    totalDuration - 0.05,
    { timeout: (totalDuration + 40) * 1000, polling: 200 },
  );
  await page.waitForTimeout(700);
  log('Outro finished. elapsed =', await page.evaluate(() => window.__outro.elapsed));

  const video = page.video();
  await context.close();
  await browser.close();

  const webmPath = await video.path();
  log('WebM recorded:', webmPath);

  const preRoll = Math.max(0, (tReady - tCtx) / 1000);
  log('Computed pre-roll trim:', preRoll.toFixed(2), 's');

  const mp4Path = join(OUTPUT_DIR, 'outro.mp4');
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

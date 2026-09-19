/**
 * Opt-in rendering microbenchmark; never included in normal tests or builds.
 * Requires an already running Vite dev server and Playwright's Chromium.
 * The video scenarios generate a 2-second 720p/30fps H.264 clip with ffmpeg;
 * its temporary directory is removed on success and failure. No project/room is created.
 *
 * Example:
 *   pnpm exec vite --host 127.0.0.1 --port 5173
 *   node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5173 --output test-results/benchmarks/rendering.json
 *   node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5173 --skip-video
 *
 * Timings include browser scheduling and asynchronous rendering, not physical GPU
 * completion. Headless Chromium often uses SwiftShader (software GPU). Compare
 * runs on the same machine/configuration; these results are NOT user-visible FPS
 * or a measurement of React, networking, Yjs synchronization, or input latency.
 * Run separately from other browsers, tests, builds and encoders to reduce noise.
 */
import { chromium } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { environment } from './benchmark-environment.mjs';

const options = {
  url: process.env.POIETRA_BENCH_URL || 'http://127.0.0.1:5173',
  output: process.env.POIETRA_BENCH_OUTPUT || 'test-results/benchmarks/rendering.json',
  ffmpeg: process.env.FFMPEG_PATH || 'ffmpeg', frames: 20, video: true,
};
for (let index = 2; index < process.argv.length; index++) {
  const flag = process.argv[index];
  if (flag === '--help') {
    console.log('Usage: node scripts/benchmark-rendering.mjs [--url VITE_URL] [--output JSON_PATH] [--frames 3..60] [--ffmpeg PATH] [--skip-video]\nRequires an already running Vite server and Playwright Chromium; video also requires ffmpeg/libx264.\nCHROME_PATH optionally selects an installed Chromium executable.');
    process.exit(0);
  }
  if (flag === '--skip-video') { options.video = false; continue; }
  const key = { '--url': 'url', '--output': 'output', '--frames': 'frames', '--ffmpeg': 'ffmpeg' }[flag];
  const value = process.argv[++index];
  if (!key || !value || value.startsWith('--')) throw new Error(`Unknown or incomplete argument: ${flag}. Use --help.`);
  options[key] = key === 'frames' ? Number(value) : value;
}
if (!Number.isInteger(options.frames) || options.frames < 3 || options.frames > 60) throw new Error('--frames must be an integer from 3 to 60.');
const base = new URL(options.url);
if (!['http:', 'https:'].includes(base.protocol)) throw new Error('--url must be an HTTP(S) Vite server URL.');
const outputPath = resolve(options.output);
const mediaPath = `/api/rooms/poietra_performance_x/media/${'a'.repeat(64)}`;
let temporary, browser;
const measuredEnvironment = environment();
try {
  try {
    const response = await fetch(new URL('/src/engine/evaluate.js', base), { signal: AbortSignal.timeout(5000) });
    if (!response.ok || !response.headers.get('content-type')?.includes('javascript')) throw new Error('Source modules are not served.');
  } catch (error) { throw new Error(`Start a Vite dev server at ${base.origin} before running this benchmark.`, { cause: error }); }
  let media;
  if (options.video) {
    temporary = await mkdtemp(join(tmpdir(), 'poietra-render-bench-'));
    const sourcePath = join(temporary, 'source.mp4');
    try {
      execFileSync(options.ffmpeg, ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '22', '-pix_fmt', 'yuv420p', '-an', '-y', sourcePath], { timeout: 30000, stdio: ['ignore', 'ignore', 'pipe'] });
    } catch (error) { throw new Error('The video benchmark requires ffmpeg with libx264. Set --ffmpeg PATH or use --skip-video.', { cause: error }); }
    media = await readFile(sourcePath);
  }
  browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.route('**/__poietra_render_bench', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><html><body><div id="svg"></div></body></html>' }));
  if (media) await page.route(`**${mediaPath}`, route => route.fulfill({ contentType: 'video/mp4', body: media }));
  await page.goto(new URL('/__poietra_render_bench', base).href);
  const result = await page.evaluate(async ({ frameCount, video, mediaPath }) => {
    const renderer = await import('/src/engine/renderer.js');
    const { compileScene, compositionFrame } = await import('/src/engine/evaluate.js');
    const { defaultState } = await import('/shared/model.js');
    const { loadKernel } = await import('/src/engine/kernel.js');
    const { createFramePainter } = await import('/src/engine/painter.js');
    // Resolve through Vite, sharing the application's exact Mediabunny instance.
    const bunny = await import('/tests/e2e/fixtures/media-dependencies.ts');
    const kernel = await loadKernel();
    function stats(values) {
      const sorted = [...values].sort((a, b) => a - b), sum = sorted.reduce((a, b) => a + b, 0);
      return { n: sorted.length, mean: sum / sorted.length, p50: sorted[Math.floor(sorted.length * .5)], p95: sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * .95) - 1)], sum, samples: [...values] };
    }
    async function measure(count, callback) {
      const samples = [];
      for (let index = 0; index < count; index++) { const start = performance.now(); await callback(index); samples.push(performance.now() - start); }
      return stats(samples);
    }
    function scene(count, compositionCount = 2, kind = 'circle') {
      const value = { id: 'bench', name: 'Bench', width: 1280, height: 720, background: '#08090b', objects: {}, compositions: {}, compositionOrder: [], transitions: {}, audioTracks: {} };
      for (let index = 0; index < count; index++) value.objects[`o${index}`] = { id: `o${index}`, name: `Object ${index}`, kind, order: index, locked: false, groupId: null };
      for (let index = 0; index < compositionCount; index++) {
        const id = `c${index}`; value.compositionOrder.push(id);
        value.compositions[id] = { id, name: id, duration: 1000, states: {} };
        for (let object = 0; object < count; object++) value.compositions[id].states[`o${object}`] = defaultState(kind, { x: 30 + (object % 25) * 48 + index * 3, y: 30 + Math.floor(object / 25) * 32, width: 20, height: 20, strokeWidth: 1, fontSize: 12, text: `x^2+y^2=${object}` });
        if (index) value.transitions[`t${index}`] = { id: `t${index}`, fromId: `c${index - 1}`, toId: id, duration: 1000, tracks: {} };
      }
      return value;
    }
    const marks = { decode: [], sequentialDecode: [], png: [], pngBytes: [], fetches: 0 };
    const originalGetCanvas = bunny.CanvasSink.prototype.getCanvas;
    bunny.CanvasSink.prototype.getCanvas = async function (...args) {
      const start = performance.now();
      try { return await originalGetCanvas.apply(this, args); }
      finally { marks.decode.push(performance.now() - start); }
    };
    const originalCanvases = bunny.CanvasSink.prototype.canvases;
    bunny.CanvasSink.prototype.canvases = function (...args) {
      const iterator = originalCanvases.apply(this, args), next = iterator.next.bind(iterator);
      iterator.next = async (...nextArgs) => {
        const start = performance.now();
        try { return await next(...nextArgs); }
        finally { marks.sequentialDecode.push(performance.now() - start); }
      };
      return iterator;
    };
    const originalPng = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function (...args) {
      const start = performance.now(), image = originalPng.apply(this, args);
      marks.png.push(performance.now() - start); marks.pngBytes.push(image.length); return image;
    };
    const originalFetch = window.fetch;
    window.fetch = async (...args) => { if (String(args[0]).includes('/media/')) marks.fetches++; return originalFetch(...args); };
    function reset() { for (const key of ['decode', 'sequentialDecode', 'png', 'pngBytes']) marks[key] = []; marks.fetches = 0; }
    function reportMarks() {
      return { ...Object.fromEntries(['decode', 'sequentialDecode', 'png', 'pngBytes'].map(key => [key, marks[key].length ? stats(marks[key]) : null])), fetches: marks.fetches };
    }
    const shapes = [];
    for (const count of [100, 500]) {
      const value = scene(count), frame = compositionFrame(value, value.compositions.c0);
      const program = compileScene(value, kernel);
      await renderer.prepareScene(value);
      const canvas = document.createElement('canvas'); canvas.width = 1280; canvas.height = 720; document.body.append(canvas);
      const painter = await createFramePainter(canvas);
      try {
        await painter.render(frame); reset(); // Exclude initialization/raster warmup.
        const evaluation = await measure(100, index => program.evaluate(1200 + index));
        const cloning = await measure(100, () => structuredClone(frame));
        const svg = await measure(30, () => renderer.frameToSvg(frame));
        const container = document.getElementById('svg'), markup = renderer.frameToSvg(frame);
        const dom = await measure(15, () => { container.innerHTML = markup; void container.getBoundingClientRect().width; }); container.innerHTML = '';
        // Includes the explicit frame clone and asynchronous publication by the painter.
        const moving = await measure(30, index => { const next = structuredClone(frame); next.objects[0].state.x += index; return painter.render(next); });
        shapes.push({ count, backend: painter.backend, evaluation, cloning, svg, svgBytes: markup.length, dom, moving, marks: reportMarks() });
      } finally { painter.dispose(); canvas.remove(); }
    }
    const preparations = [];
    for (const [objects, compositions, kind] of [[100, 2, 'circle'], [100, 50, 'circle'], [100, 50, 'text']]) {
      const value = scene(objects, compositions, kind); await renderer.prepareScene(value);
      preparations.push({ objects, compositions, kind, prepare: await measure(30, () => renderer.prepareScene(value)) });
    }
    const videos = [];
    let decodeOnly = null;
    if (video) {
      const value = scene(1);
      Object.assign(value.objects.o0, { kind: 'video', media: { src: mediaPath, mime: 'video/mp4', duration: 2000, width: 1280, height: 720, hasAudio: false }, playback: { start: 0, offset: 0, duration: 2000 } });
      for (const composition of Object.values(value.compositions)) composition.states.o0 = defaultState('video', { x: 640, y: 360, width: 1280, height: 720, strokeWidth: 0 });
      const program = compileScene(value, kernel);
      const canvas = document.createElement('canvas'); canvas.width = 1280; canvas.height = 720; document.body.append(canvas);
      const scenarios = [
        ['30fps', Array.from({ length: frameCount }, (_, index) => (index + 0.1) * 1000 / 30)],
        ['60fps-same-source-frames', Array.from({ length: frameCount }, (_, index) => (index + 0.1) * 1000 / 60)],
        ['alternating-still-compare', Array.from({ length: frameCount }, (_, index) => index % 2 ? 1000 : 0)],
      ];
      try {
        for (const [name, times] of scenarios) {
          const painter = await createFramePainter(canvas);
          try {
            await painter.render(program.evaluate(0)); reset();
            const paint = [];
            for (const time of times) {
              const frame = program.evaluate(time);
              const start = performance.now(); await painter.render(frame); paint.push(performance.now() - start);
            }
            videos.push({ name, backend: painter.backend, paint: stats(paint), marks: reportMarks() });
          } finally { painter.dispose(); }
        }
      } finally { canvas.remove(); }
      const input = new bunny.Input({ source: new bunny.BlobSource(await (await fetch(mediaPath)).blob()), formats: bunny.ALL_FORMATS });
      try {
        const sink = new bunny.CanvasSink(await input.getPrimaryVideoTrack(), { poolSize: 1 });
        const times = Array.from({ length: frameCount }, (_, index) => index / 30);
        const random = await measure(times.length, index => sink.getCanvas(times[index]));
        const sequential = []; let start = performance.now();
        for await (const frame of sink.canvasesAtTimestamps(times)) { sequential.push(performance.now() - start); start = performance.now(); }
        decodeOnly = { random, sequential: stats(sequential) };
      } finally { input.dispose(); }
    }
    const gl = document.createElement('canvas').getContext('webgl2'), debug = gl?.getExtension('WEBGL_debug_renderer_info');
    const gpu = debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : null;
    gl?.getExtension('WEBGL_lose_context')?.loseContext();
    return { userAgent: navigator.userAgent, gpu, headless: true, units: 'milliseconds (except counts and pngBytes/svgBytes)', shapes, preparations, video: videos, decodeOnly };
  }, { frameCount: options.frames, video: options.video, mediaPath });
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { viewport: { width: 1440, height: 900 }, canvas: { width: 1280, height: 720 }, videoFrames: options.frames, source: 'Vite development modules with release MoonBit JS/WASM', video: 'Generated 2s H.264 720p30; painter owns preparation, decode and drawing (PNG only on SVG fallback); evaluation excluded', ffmpeg: options.video ? execFileSync(options.ffmpeg, ['-version'], { encoding: 'utf8' }).split('\n')[0] : null }, ...result }, null, 2) + '\n');
  console.log(`Saved ${outputPath}\nGPU: ${result.gpu}\nMean milliseconds; asynchronous microbench timings, not user-visible FPS:`);
  console.table(result.shapes.map(value => ({ objects: value.count, evaluate: value.evaluation.mean, clone: value.cloning.mean, svg: value.svg.mean, domReplace: value.dom.mean, moveAndPaint: value.moving.mean })));
  if (options.video) console.table(result.video.map(value => ({ scenario: value.name, paint: value.paint.mean, randomRequests: value.marks.decode?.n ?? 0, sequentialReads: value.marks.sequentialDecode?.n ?? 0, pngEncodes: value.marks.png?.n ?? 0 })));
} finally {
  try { await browser?.close(); }
  finally { if (temporary) await rm(temporary, { recursive: true, force: true }); }
}

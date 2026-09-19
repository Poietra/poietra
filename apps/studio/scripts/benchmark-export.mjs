// End-to-end WebCodecs export with stage timings. Run separately from builds/tests.
// Uses release MoonBit modules through a local Vite server; no production rooms.
import { chromium } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { environment, root, stats } from './benchmark-environment.mjs';

const base = new URL(process.env.POIETRA_BENCH_URL || 'http://127.0.0.1:5194');
if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname)) throw new Error('Use an isolated local Vite server.');
const output = process.env.POIETRA_BENCH_OUTPUT || 'test-results/export-performance.json';
const runs = Number(process.env.POIETRA_BENCH_RUNS || 3);
if (!Number.isInteger(runs) || runs < 1 || runs > 10) throw new Error('Runs must be 1..10.');
const measuredEnvironment = environment();
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/__export_bench', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><html><body></body></html>' }));
  await page.goto(new URL('/__export_bench', base).href);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Profiler.enable');
  await cdp.send('Profiler.setSamplingInterval', { interval: 1000 });
  await cdp.send('Profiler.start');
  const results = await page.evaluate(async ({ root, runs }) => {
    const exporter = await import(`/@fs${root}_build/js/release/build/browser_export/browser_export.js`);
    const renderer = await import('/src/engine/renderer.js');
    const { createFramePainter } = await import('/src/engine/painter.js');
    const { makeDemoProject } = await import('/shared/demo.js');
    const { defaultState } = await import('/shared/model.js');
    const { loadKernel } = await import('/src/engine/kernel.js');
    const bunny = await import('/tests/e2e/fixtures/media-dependencies.ts');
    const kernel = await loadKernel();
    let marks;
    const timed = async (key, callback) => { const start = performance.now(); try { return await callback(); } finally { marks[key].push(performance.now() - start); } };
    const originals = { add: bunny.CanvasSource.prototype.add, finalize: bunny.Output.prototype.finalize, configure: VideoEncoder.prototype.configure };
    bunny.CanvasSource.prototype.add = function (...args) { return timed('encodeWait', () => originals.add.apply(this, args)); };
    bunny.Output.prototype.finalize = function (...args) { return timed('finalize', () => originals.finalize.apply(this, args)); };
    VideoEncoder.prototype.configure = function (config) { if (marks) marks.codecs.push(config); return originals.configure.call(this, config); };
    const host = {
      prepareScene: scene => timed('prepare', () => renderer.prepareScene(scene)),
      async createFramePainter(canvas) {
        const painter = await timed('painterInit', () => createFramePainter(canvas));
        marks.backend = painter.backend;
        return { render: (...args) => timed('render', () => painter.render(...args)), dispose: () => painter.dispose() };
      },
    };
    function shapes(count) {
      const scene = { id: 'shapes', name: 'Shapes', width: 1280, height: 720, background: '#08090b', objects: {}, compositions: {}, compositionOrder: ['a', 'b'], transitions: {}, audioTracks: {} };
      for (const id of ['a', 'b']) scene.compositions[id] = { id, name: id, duration: 1200, states: {} };
      for (let i = 0; i < count; i++) {
        const id = `object-${i}`;
        scene.objects[id] = { id, name: id, kind: 'circle', order: i, locked: false, groupId: null };
        for (const comp of ['a', 'b']) scene.compositions[comp].states[id] = defaultState('circle', { x: 25 + i % 25 * 48 + (comp === 'b' ? 12 : 0), y: 25 + Math.floor(i / 25) * 32, width: 18, height: 18, strokeWidth: 1 });
      }
      scene.transitions.t = { id: 't', fromId: 'a', toId: 'b', duration: 600, tracks: {} };
      return scene;
    }
    const results = [];
    try {
      for (const [name, scene, format] of [
        ['demo-mp4', makeDemoProject().scenes['scene-1'], 'mp4'],
        ['demo-webm', makeDemoProject().scenes['scene-1'], 'webm'],
        ['100-shapes-mp4', shapes(100), 'mp4'],
        ['500-shapes-mp4', shapes(500), 'mp4'],
      ]) {
        // Warm resources, while each timed sample still owns fresh painter/encoder resources.
        await renderer.prepareScene(scene);
        await document.fonts.ready;
        for (let run = -1; run < runs; run++) {
          marks = { prepare: [], painterInit: [], render: [], encodeWait: [], finalize: [], codecs: [], backend: null };
          let progressCalls = 0;
          const start = performance.now();
          const result = await exporter.exportScene(scene, kernel, { format, fps: 30, width: 1280, height: 720, onProgress: () => progressCalls++ }, host);
          const elapsedMs = performance.now() - start;
          const input = new bunny.Input({ source: new bunny.BlobSource(result.blob), formats: bunny.ALL_FORMATS });
          let frames = 0;
          try {
            const track = await input.getPrimaryVideoTrack();
            for await (const packet of new bunny.EncodedPacketSink(track).packets()) frames++;
            if (frames !== Math.ceil(result.durationMs * 30 / 1000)) throw new Error('Export dropped frames.');
            const sample = await new bunny.VideoSampleSink(track).getSample(0);
            if (!sample) throw new Error('Export cannot be decoded.');
            sample.close();
          } finally { input.dispose(); }
          if (run >= 0) results.push({ name, run: run + 1, elapsedMs, durationMs: result.durationMs, frames, bytes: result.blob.size, codec: result.codec, progressCalls, ...marks });
        }
      }
      const gl = document.createElement('canvas').getContext('webgl2');
      const info = gl?.getExtension('WEBGL_debug_renderer_info');
      return { samples: results, gpu: info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : null };
    } finally {
      bunny.CanvasSource.prototype.add = originals.add;
      bunny.Output.prototype.finalize = originals.finalize;
      VideoEncoder.prototype.configure = originals.configure;
    }
  }, { root, runs });
  const { profile } = await cdp.send('Profiler.stop');
  if (errors.length) throw new Error(errors.join('\n'));
  const names = [...new Set(results.samples.map(sample => sample.name))];
  const summary = names.map(name => {
    const samples = results.samples.filter(sample => sample.name === name);
    return { name, elapsedMs: stats(samples.map(s => s.elapsedMs)), ...Object.fromEntries(['render', 'encodeWait', 'prepare', 'painterInit', 'finalize'].map(key => [key + 'Ms', stats(samples.map(s => s[key].reduce((a, b) => a + b, 0)))])) };
  });
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output + '.cpuprofile', JSON.stringify(profile));
  await writeFile(output, JSON.stringify({ measuredAt: new Date().toISOString(), environment: measuredEnvironment, browser: browser.version(), conditions: { resolution: '1280x720', fps: 30, runs, warmup: 'One unrecorded full export per scenario; scene resources warmed', instrumentation: 'Stage wrappers and CDP 1 ms CPU sampling; includes instrumentation overhead', limitations: 'Local Vite-served release MoonBit modules; software GPU/codec where reported, not representative of user hardware; no audio/video source in these fixtures' }, summary, ...results }, null, 2) + '\n');
  console.log(JSON.stringify(summary, null, 2));
} finally { await browser.close(); }

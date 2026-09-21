import test from 'node:test';
import assert from 'node:assert/strict';
import { renderProjectFile } from '../../../_build/js/release/build/headless_render/headless_render.js';
import { project, addAudio } from './fixtures.mjs';

function backend() {
  const stats = { frames: 0, disposed: 0, finished: 0 };
  const encoder = {
    addVideo() { stats.frames++; }, addAudio() {},
    finish() { stats.finished++; return new Uint8Array([1, 2, 3]); },
    dispose() { stats.disposed++; },
  };
  const host = {
    loadMathRuntime() { throw new Error('No equation in fixture.'); },
    prepare() {}, measureLine() { return { left: 0, right: 0, ascent: 0, descent: 0 }; },
    fontStyles() { return ''; },
    svgBytes: svg => new TextEncoder().encode(svg),
    png: () => new Uint8Array([1]),
    rgba: () => new Uint8Array(320 * 180 * 4),
    readAudio: () => [],
    createEncoder: () => encoder,
    progress() {},
  };
  return { host, encoder, stats };
}

test('typed backend awaits each frame and disposes exactly once after finishing', async () => {
  const { host, encoder, stats } = backend();
  const entered = Promise.withResolvers(), release = Promise.withResolvers();
  encoder.addVideo = async pixels => {
    assert.ok(pixels instanceof Uint8Array);
    stats.frames++;
    if (stats.frames === 1) { entered.resolve(); await release.promise; }
  };
  const pending = renderProjectFile(JSON.stringify(project()), { format: 'mp4' }, host);
  await entered.promise;
  assert.equal(stats.frames, 1); assert.equal(stats.disposed, 0);
  release.resolve();
  const result = await pending;
  assert.equal(result.frames, 25);
  assert.deepEqual(stats, { frames: 25, disposed: 1, finished: 1 });
});

test('backend failure and cancellation preserve their cause while disposing exactly once', async () => {
  for (const stage of ['rgba', 'addVideo', 'addAudio', 'finish', 'progress', 'cancel']) {
    const { host, encoder, stats } = backend();
    const controller = new AbortController(), cause = new Error(stage);
    const p = project();
    if (stage === 'addAudio') addAudio(p);
    if (stage in encoder) encoder[stage] = () => { throw cause; };
    else if (stage === 'cancel') host.progress = () => { controller.abort(cause); };
    else host[stage] = () => { throw cause; };
    encoder.dispose = () => { stats.disposed++; throw new Error('secondary cleanup failure'); };
    await assert.rejects(renderProjectFile(JSON.stringify(p), { format: 'mp4', signal: controller.signal }, host), error => error === cause);
    assert.equal(stats.disposed, 1, stage);
  }
  const { host, encoder, stats } = backend();
  delete encoder.addVideo;
  await assert.rejects(renderProjectFile(JSON.stringify(project()), { format: 'mp4' }, host), /Missing encoder method/);
  assert.equal(stats.disposed, 1, 'factory cleans up a malformed native encoder');
});

test('FFI validates native byte and sample buffers before lifting them into typed values', async () => {
  for (const [result, pattern] of [[new Uint8Array(4), /RGBA dimensions/], [[], /Uint8Array/]]) {
    const { host, stats } = backend(); host.rgba = () => result;
    await assert.rejects(renderProjectFile(JSON.stringify(project()), { format: 'mp4' }, host), pattern);
    assert.equal(stats.disposed, 1);
  }
  for (const packet of [
    { timestamp: 0, sampleRate: 48000, left: [0], right: [0] },
    { timestamp: 0, sampleRate: 48000, left: new Float32Array(2), right: new Float32Array(1) },
    { timestamp: 0, sampleRate: 0.5, left: new Float32Array(1), right: new Float32Array(1) },
  ]) {
    const { host, stats } = backend(), p = project(); addAudio(p);
    host.readAudio = () => [packet];
    await assert.rejects(renderProjectFile(JSON.stringify(p), { format: 'mp4' }, host), /PCM/);
    assert.equal(stats.disposed, 1);
  }
  const { host } = backend(); host.png = () => 'not bytes';
  await assert.rejects(renderProjectFile(JSON.stringify(project()), { format: 'png' }, host), /Uint8Array/);
});

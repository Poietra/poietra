import test from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { renderProjectFile, inspectProjectFile } from '../index.mjs';
import { project, addObject, addImage, addAudio } from './fixtures.mjs';
import { decodeVideo, decodeAudio } from './decode.mjs';
import { normalizePathLengths } from '../runtime-host.mjs';

const pixel = (png, x, y) => [...png.data.subarray((y * png.width + x) * 4, (y * png.width + x) * 4 + 4)];
const render = (p, options) => renderProjectFile(JSON.stringify(p), options);

test('PNG and SVG share hierarchy, intermediate values and independent Scene boundaries', async () => {
  const p = project();
  addObject(p, 'parent', 'rectangle', { x: 20, y: 0, opacity: 0, visible: false });
  p.scenes.scene.objects.box.parentId = 'parent';
  const a = PNG.sync.read(Buffer.from((await render(p, { timeMs: 0 })).bytes));
  const mid = PNG.sync.read(Buffer.from((await render(p, { timeMs: 400 })).bytes));
  assert.deepEqual(pixel(a, 80, 90), [255, 255, 255, 255]);
  assert.deepEqual(pixel(mid, 120, 90), [255, 255, 255, 255]);
  assert.deepEqual(pixel(mid, 80, 90), [0, 0, 0, 255]);
  const svg = new TextDecoder().decode((await render(p, { format: 'svg', timeMs: 400, width: 160, height: 100 })).bytes);
  assert.match(svg, /width="160" height="100" viewBox="0 0 320 180" preserveAspectRatio="none"/);
  assert.match(svg, /matrix\(1 0 0 1 120 90\)/);
  const other = structuredClone(p.scenes.scene); other.id = 'other'; other.background = '#0000ff'; other.objects = {};
  for (const c of Object.values(other.compositions)) c.states = {};
  for (const t of Object.values(other.transitions)) t.tracks = {};
  p.scenes.other = other; p.sceneOrder.push('other');
  const second = PNG.sync.read(Buffer.from((await render(p, { timeMs: 820 })).bytes));
  assert.deepEqual(pixel(second, 80, 90), [0, 0, 255, 255]);
});

test('portable images, Japanese, MathJax and Glow render without missing assets', async () => {
  const p = project(); addImage(p);
  addObject(p, 'text', 'text', { x: 160, y: 30, fontSize: 20, text: '日本語 Poietra', fill: '#ffffff', strokeWidth: 0 });
  addObject(p, 'equation', 'equation', { x: 160, y: 140, fontSize: 26, text: 'x^2+1', fill: '#ffffff', strokeWidth: 0 });
  for (const c of Object.values(p.scenes.scene.compositions)) c.states.box.effect = 'glow';
  const image = PNG.sync.read(Buffer.from((await render(p)).bytes));
  assert.deepEqual(pixel(image, 290, 30), [255, 128, 0, 255]);
  assert.ok(pixel(image, 75, 90)[0] > 1, 'Glow reaches beyond the rectangle');
  const lit = (x0, y0, x1, y1) => { let n = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) n += pixel(image, x, y)[0] > 60; return n; };
  assert.ok(lit(90, 15, 140, 45) > 50, 'Japanese glyphs are present');
  assert.ok(lit(120, 115, 200, 165) > 70, 'equation paths are present');
  const svg = new TextDecoder().decode((await render(p, { format: 'svg' })).bytes);
  assert.match(svg, /data:font\/woff2;base64,/); assert.match(svg, /日本語/); assert.match(svg, /feGaussianBlur/);
});

test('Write uses actual path lengths in the rasterizer, not unit-length dashes', async () => {
  assert.match(normalizePathLengths('<path d="M0 0H100" pathLength="1" stroke-dasharray="1" stroke-dashoffset="0.5"/>'), /stroke-dasharray="100" stroke-dashoffset="50"/);
  const p = project(), s = p.scenes.scene;
  s.objects.box.kind = 'path';
  for (const c of Object.values(s.compositions)) Object.assign(c.states.box, { x: 20, y: 90, width: 200, height: 0, stroke: '#ffffff', strokeWidth: 4, fill: 'none', path: { c1: { x: 60, y: 0 }, c2: { x: 140, y: 0 } } });
  s.compositions.a.states.box.visible = false;
  Object.assign(s.transitions.transition.tracks.box, { type: 'write', keyframes: {} });
  const image = PNG.sync.read(Buffer.from((await render(p, { timeMs: 400 })).bytes));
  assert.ok(pixel(image, 60, 90)[0] > 240);
  assert.ok(pixel(image, 180, 90)[0] < 10);
});

test('H.264 decodes every frame, retains static holds and the exact final partial duration', async () => {
  const p = project(), progress = [];
  const result = await render(p, { format: 'mp4', fps: 30, onProgress: x => progress.push(x) });
  const decoded = await decodeVideo(result.bytes);
  assert.equal(result.frames, 25); assert.equal(decoded.frames.length, 25);
  assert.ok(result.rasterizedFrames < 16);
  assert.equal(decoded.config.codedWidth, 320); assert.equal(decoded.config.codedHeight, 180);
  assert.ok(Math.abs(decoded.duration - 0.82) < 0.0001);
  assert.ok(Math.abs(decoded.packets.at(-1).duration - 0.02) < 0.0001);
  const y = (frame, x) => frame.pixels[90 * frame.width + x];
  assert.ok(y(decoded.frames[0], 60) > 220); assert.ok(y(decoded.frames[0], 260) < 30);
  assert.ok(y(decoded.frames[12], 100) > 220);
  assert.ok(y(decoded.frames.at(-1), 260) > 220);
  assert.ok(decoded.packets.some(packet => packet.type === 'delta'), 'MP4 sync flags reflect actual H.264 key frames');
  assert.equal(progress.at(-1), 1); assert.ok(progress.every((p, i) => !i || p >= progress[i - 1]));
});

test('WAV resampling, trims, gain and mute survive independent MP3 decoding without drift', async () => {
  const p = project(); addAudio(p);
  const result = await render(p, { format: 'mp4' });
  const audio = await decodeAudio(result.bytes);
  assert.equal(result.audioCodec, 'mp3'); assert.equal(audio.sampleRate, 48000); assert.equal(audio.channelData.length, 2);
  assert.deepEqual(audio.errors, []); assert.ok(Math.abs(audio.duration - 0.82) < 0.0001);
  const rms = (channel, start, end) => {
    const from = Math.ceil((start - audio.timestamp) * audio.sampleRate), to = Math.floor((end - audio.timestamp) * audio.sampleRate);
    let power = 0; for (let i = from; i < to; i++) power += channel[i] ** 2;
    return Math.sqrt(power / (to - from));
  };
  const [left, right] = audio.channelData;
  assert.ok(rms(left, 0.01, 0.18) < 0.001, 'leading silence');
  assert.ok(rms(left, 0.62, 0.8) < 0.001, 'trimmed tail');
  assert.ok(rms(left, 0.25, 0.55) > 0.10 && rms(left, 0.25, 0.55) < 0.14, 'gain preserved');
  assert.ok(rms(left, 0.25, 0.55) / rms(right, 0.25, 0.55) > 1.8, 'independent stereo channels');
  const onset = left.findIndex(x => Math.abs(x) > 0.025) / audio.sampleRate + audio.timestamp;
  assert.ok(Math.abs(onset - 0.2) < 0.002, `audio onset ${onset}`);
  let cross = 0, expectedPower = 0, actualPower = 0;
  for (let i = Math.ceil((0.3 - audio.timestamp) * 48000); i < Math.floor((0.5 - audio.timestamp) * 48000); i++) {
    const expected = Math.sin((audio.timestamp + i / 48000 - 0.2 + 0.137) * 440 * 2 * Math.PI);
    cross += left[i] * expected; expectedPower += expected ** 2; actualPower += left[i] ** 2;
  }
  assert.ok(cross / Math.sqrt(expectedPower * actualPower) > 0.99, 'source offset and resampling phase are preserved');
});

test('consecutive static Scenes invalidate pixels and shift audio on the project clock', async () => {
  const p = project(), first = p.scenes.scene;
  first.compositionOrder = ['a']; delete first.compositions.b; first.transitions = {};
  first.compositions.a.duration = 400;
  const second = structuredClone(first); second.id = 'second'; second.background = '#0000ff'; second.objects = {}; second.compositions.a.states = {};
  addAudio({ scenes: { scene: second } });
  p.scenes.second = second; p.sceneOrder.push('second');
  const result = await render(p, { format: 'mp4' });
  assert.equal(result.durationMs, 1000, 'audio extends the final static Composition');
  assert.equal(result.rasterizedFrames, 2);
  const video = await decodeVideo(result.bytes);
  assert.ok(video.frames[0].pixels[90 * 320 + 60] > 220);
  assert.ok(video.frames[12].pixels[90 * 320 + 60] < 80, 'second Scene replaces the previous cached pixels');
  const audio = await decodeAudio(result.bytes);
  const onset = audio.channelData[0].findIndex(x => Math.abs(x) > 0.025) / audio.sampleRate + audio.timestamp;
  assert.ok(Math.abs(onset - 0.6) < 0.002, `second Scene audio onset ${onset}`);
});

test('invalid files, unsupported media and resource limits fail explicitly', async () => {
  assert.throws(() => inspectProjectFile('{"__proto__":{}}'), /JSON|形式/);
  const p = project(); addImage(p);
  p.scenes.scene.objects.image.image.src = 'data:image/webp;base64,AAAA';
  await assert.rejects(render(p), /Embed a PNG or JPEG/);
  p.scenes.scene.objects.image.image.src = 'data:image/png;base64,AAAA';
  await assert.rejects(render(p), /Invalid PNG/);
  const video = project(); addObject(video, 'movie', 'video', {});
  video.scenes.scene.objects.movie.media = { src: 'data:video/mp4;base64,AAAA', mime: 'video/mp4', duration: 1000, hasAudio: false, width: 20, height: 20 };
  video.scenes.scene.objects.movie.playback = { start: 0, offset: 0, duration: 1000 };
  await assert.rejects(render(video), /Video decoding is not available/);
  for (const options of [{ width: 1921 }, { width: 1920, height: 1920 }, { timeMs: -1 }, { timeMs: 821 }, { fps: 10 }, { format: 'webm' }, { format: 'mp4', timeMs: 10 }]) {
    await assert.rejects(render(project(), options));
  }
  const long = project(); long.scenes.scene.compositions.b.duration = 60000;
  await assert.rejects(render(long, { format: 'mp4' }), /60 seconds/);
});

test('cancellation, timeout and callback failure release the worker and allow another render', async () => {
  const controller = new AbortController();
  await assert.rejects(render(project(), { format: 'mp4', signal: controller.signal, onProgress() { controller.abort(); } }), { name: 'AbortError' });
  await assert.rejects(render(project(), { timeoutMs: 1 }), { name: 'TimeoutError' });
  await assert.rejects(render(project(), { format: 'mp4', onProgress() { throw new Error('consumer stopped'); } }), /consumer stopped/);
  const next = await render(project()); assert.equal(next.mimeType, 'image/png');
});

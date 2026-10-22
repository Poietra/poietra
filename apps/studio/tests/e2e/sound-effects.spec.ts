import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile } from 'node:fs/promises';
import { renderProjectFile } from '../../../render/index.mjs';
import { open, observer, field } from './media-helpers';
import { chooseOption } from './select';
import { applyChanges } from '../../shared/document';
import { makeBlankScene } from '../../shared/demo';
import { defaultState, type Scene } from '../../shared/model';
import { parseProjectFile } from '../../shared/project-file';

declare global {
  interface Window {
    soundProbe: { starts: { offset: number; duration: number | undefined; samples: number[] }[]; contexts: AudioContext[] };
  }
}

async function captureAudio(page: Page) {
  await page.addInitScript(() => {
    window.soundProbe = { starts: [], contexts: [] };
    const create = AudioContext.prototype.createBufferSource;
    AudioContext.prototype.createBufferSource = function () {
      if (!window.soundProbe.contexts.includes(this)) window.soundProbe.contexts.push(this);
      const source = create.call(this), start = source.start;
      source.start = (when = 0, offset = 0, duration?: number) => {
        window.soundProbe.starts.push({ offset, duration, samples: [...source.buffer!.getChannelData(0)] });
        start.call(source, when, offset, duration);
      };
      return source;
    };
  });
}

async function setup(page: Page) {
  const room = await open(page), watch = await observer(page, room);
  const scene = makeBlankScene('scene-1', 'Sound design');
  scene.compositions[scene.compositionOrder[0]].duration = 1000;
  applyChanges(watch.doc, [{ path: ['scenes', scene.id], value: scene }], 'fixture');
  await expect(page.getByRole('tab', { name: 'Sound design', exact: true })).toBeVisible();
  return { room, watch, scene: () => watch.project().scenes[scene.id] };
}

const dialog = (page: Page) => page.getByRole('dialog', { name: '効果音を追加', exact: true });
async function palette(page: Page) {
  await page.getByRole('button', { name: '効果音を追加', exact: true }).click();
  await expect(dialog(page)).toBeVisible();
}

test('auditioned PCM becomes a shared trimmed track in one Undo and is embedded in portable files', async ({ page, browser }, info) => {
  await captureAudio(page);
  const { room, watch, scene } = await setup(page);
  const context = await browser.newContext(), peer = await context.newPage();
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  try {
    await open(peer, room);
    await palette(page);
    await dialog(page).getByLabel('効果音を検索', { exact: true }).fill('移動');
    await expect(dialog(page).getByRole('button', { name: 'Whoosh', exact: true })).toBeVisible();
    await expect(dialog(page).getByRole('button', { name: 'Chime', exact: true })).toHaveCount(0);
    await field(page, '効果音の長さ', '900');
    await field(page, '効果音の高さ', '-3');
    await field(page, '効果音の音量', '35');
    await chooseOption(dialog(page).getByRole('combobox', { name: '効果音を合わせる位置', exact: true }), 'start');
    await dialog(page).getByRole('button', { name: '試聴', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.soundProbe.starts.length)).toBe(1);
    const audition = await page.evaluate(() => window.soundProbe.starts[0]);
    expect(audition.samples).toHaveLength(43200);
    expect(audition.offset).toBeGreaterThan(.1); // peak is aimed at Scene zero, trimming pre-roll
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect(dialog(page)).toBeHidden();
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
    await expect(peer.getByTestId('audio-track')).toHaveCount(1);
    await expect.poll(() => Object.keys(scene().audioTracks ?? {}).length).toBe(1);
    const track = Object.values(scene().audioTracks!)[0];
    expect(track).toMatchObject({ name: 'Whoosh', volume: .35, start: 0, asset: { mime: 'audio/wav', duration: 900, hasAudio: true } });
    expect(track.offset).toBeCloseTo(audition.offset * 1000, 7);
    expect(track.duration).toBeCloseTo(audition.duration! * 1000, 7);
    expect(track.asset.waveform).toHaveLength(128);
    const decoded = await page.evaluate(async src => {
      const context = new AudioContext({ sampleRate: 48000 });
      try {
        const decoded = await context.decodeAudioData(await (await fetch(src)).arrayBuffer());
        return { channels: decoded.numberOfChannels, rate: decoded.sampleRate, pcm: [...decoded.getChannelData(0)] };
      } finally { await context.close(); }
    }, track.asset.src);
    expect(decoded.channels).toBe(1); expect(decoded.rate).toBe(48000);
    const wave = await (await page.request.get(track.asset.src)).body();
    expect(decoded.pcm).toHaveLength(audition.samples.length);
    let storedError = 0, decodedError = 0;
    for (let i = 0; i < audition.samples.length; i++) {
      storedError = Math.max(storedError, Math.abs(wave.readInt16LE(44 + i * 2) / 32768 - audition.samples[i]));
      decodedError = Math.max(decodedError, Math.abs(decoded.pcm[i] - audition.samples[i]));
    }
    expect(storedError).toBe(0);
    // Browser decoders can scale positive PCM16 by 32767, negative by 32768.
    expect(decodedError).toBeLessThan(1 / 32768);
    await expect.poll(() => page.evaluate(() => window.soundProbe.contexts.every(context => context.state === 'closed'))).toBe(true);
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(peer.getByTestId('audio-track')).toHaveCount(0);
    await page.getByRole('button', { name: 'やり直す (⌘⇧Z)', exact: true }).click();
    await expect(peer.getByTestId('audio-track')).toHaveCount(1);
    await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Save project', exact: true }).click();
    const download = await downloadPromise, path = info.outputPath('sound.poietra.json');
    await download.saveAs(path);
    const portable = parseProjectFile(await readFile(path, 'utf8'));
    expect(Object.values(portable.scenes['scene-1'].audioTracks!)[0].asset.src).toMatch(/^data:audio\/wav;base64,/);
    await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles(path);
    await expect(page).not.toHaveURL(new RegExp(room));
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
    expect(errors).toEqual([]);
  } finally { watch.close(); await context.close(); }
});

test('the measured peak follows selected motion timing including a peer change during upload', async ({ page }, info) => {
  await captureAudio(page);
  const { watch, scene } = await setup(page);
  try {
    // One editable moving object, 400..1300 ms within the selected Transition.
    const a = scene().compositionOrder[0], b = 'second', tid = 'motion';
    const moving: Scene = { ...scene(),
      objects: { dot: { id: 'dot', name: 'Moving circle', kind: 'circle', order: 0, locked: false, groupId: null } },
      compositionOrder: [a, b],
      compositions: {
        [a]: { ...scene().compositions[a], states: { dot: defaultState('circle', { x: 100, y: 180 }) } },
        [b]: { ...scene().compositions[a], id: b, name: 'Second', states: { dot: defaultState('circle', { x: 800, y: 180 }) } },
      },
      transitions: { [tid]: { id: tid, fromId: a, toId: b, duration: 2000, tracks: { dot: { objectId: 'dot', type: 'move', start: 0, duration: 2000, positionTiming: { start: 400, duration: 900, easing: 'linear' }, easing: 'linear', order: 'together', path: null, keyframes: {} } } } },
    };
    applyChanges(watch.doc, [{ path: ['scenes', 'scene-1'], value: moving }], 'fixture');
    await page.getByRole('button', { name: 'Transition 2,000 ms', exact: true }).click();
    await page.locator('[data-layer-id="dot"] .layer-select').click();
    await palette(page);
    await chooseOption(dialog(page).getByRole('combobox', { name: '効果音を合わせる属性', exact: true }), 'position');
    await expect(dialog(page).getByTestId('sound-cue')).toContainText('1.850 s');
    // The open palette observes peer timing without invalidating the media lanes.
    applyChanges(watch.doc, [{ path: ['scenes', 'scene-1', 'transitions', tid, 'tracks', 'dot', 'positionTiming', 'start'], value: 600 }], 'peer');
    await expect(dialog(page).getByTestId('sound-cue')).toContainText('2.050 s');
    await dialog(page).getByRole('button', { name: '試聴', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.soundProbe.starts.length)).toBe(1);
    await expect(dialog(page).getByRole('button', { name: '試聴を停止', exact: true })).toBeVisible();
    await dialog(page).getByRole('button', { name: '試聴を停止', exact: true }).click();
    await page.setViewportSize({ width: 1100, height: 800 });
    await expect(dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true })).toBeInViewport();
    await page.screenshot({ path: info.outputPath('sound-palette.png') });
    await page.setViewportSize({ width: 1440, height: 900 });
    let release!: () => void;
    const held = new Promise<void>(resolve => { release = resolve; });
    let requested = false;
    await page.route('**/api/rooms/*/media', async route => { requested = true; await held; await route.continue(); });
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect.poll(() => requested).toBe(true);
    applyChanges(watch.doc, [{ path: ['scenes', 'scene-1', 'transitions', tid, 'tracks', 'dot', 'positionTiming', 'start'], value: 800 }], 'peer');
    await expect(dialog(page).getByTestId('sound-cue')).toContainText('2.250 s');
    release();
    await expect(dialog(page)).toBeHidden();
    await expect.poll(() => Object.values(scene().audioTracks ?? {}).length).toBe(1);
    const track = Object.values(scene().audioTracks!)[0];
    const peak = await page.evaluate(() => {
      const x = window.soundProbe.starts[0].samples, windowSize = 240, hop = 48;
      let best = 0, bestIndex = 0;
      for (let from = 0; from + windowSize <= x.length; from += hop) {
        let energy = 0;
        for (let i = from; i < from + windowSize; i++) energy += x[i] ** 2;
        if (energy > best) { best = energy; bestIndex = from + windowSize / 2; }
      }
      return bestIndex / 48;
    });
    expect(track.start + peak - track.offset).toBeCloseTo(2250, 5);
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(page.getByTestId('audio-track')).toHaveCount(0);
    expect(scene().transitions[tid].tracks.dot.positionTiming?.start).toBe(800);
  } finally { watch.close(); }
});

test('closing or cancelling an upload suppresses its late completion; failures remain retryable', async ({ page }) => {
  const { watch, scene } = await setup(page);
  try {
    let requested = 0;
    const releases: (() => void)[] = [];
    await page.route('**/api/rooms/*/media', async route => {
      requested++;
      if (requested <= 2) {
        const response = await route.fetch();
        await new Promise<void>(resolve => { releases.push(resolve); });
        await route.fulfill({ response }).catch(() => {});
      } else await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: '保存のテストエラー' }) });
    });
    await palette(page);
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect.poll(() => releases.length).toBe(1);
    await dialog(page).getByRole('button', { name: '追加を中止', exact: true }).click();
    releases.shift()!();
    await expect(dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true })).toBeEnabled();
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect.poll(() => releases.length).toBe(1);
    await page.keyboard.press('Escape');
    await expect(dialog(page)).toBeHidden();
    releases.shift()!();
    await palette(page);
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect(dialog(page).getByRole('alert')).toContainText('保存のテストエラー');
    await expect(page.getByTestId('audio-track')).toHaveCount(0);
    expect(Object.keys(scene().audioTracks ?? {})).toHaveLength(0);
    await page.unroute('**/api/rooms/*/media');
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect(dialog(page)).toBeHidden();
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
  } finally { watch.close(); }
});

test('a synthesized cue retains its timing and gain in browser WebM and headless MP4 exports', async ({ page }, info) => {
  test.setTimeout(90000);
  const { watch } = await setup(page);
  try {
    await palette(page);
    await dialog(page).getByRole('button', { name: 'Chime', exact: true }).click();
    await chooseOption(dialog(page).getByRole('combobox', { name: '効果音を合わせる位置', exact: true }), 'middle');
    await field(page, '効果音の音量', '40');
    await dialog(page).getByRole('button', { name: 'タイムラインに追加', exact: true }).click();
    await expect(dialog(page)).toBeHidden();
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
    await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
    const saving = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Save project', exact: true }).click();
    const saved = await saving, projectPath = info.outputPath('export.poietra.json');
    await saved.saveAs(projectPath);
    // Project operations are a popup rather than a modal; Escape closes it.
    await page.keyboard.press('Escape');
    await page.getByRole('button', { name: 'Export', exact: true }).click();
    await chooseOption(page.getByRole('combobox', { name: 'Export format', exact: true }), 'webm');
    const exporting = page.waitForEvent('download', { timeout: 60000 });
    await page.getByRole('button', { name: 'Export video', exact: true }).click();
    const browserVideo = await exporting, browserPath = info.outputPath('sound.webm');
    await browserVideo.saveAs(browserPath);
    const file = await readFile(projectPath, 'utf8');
    const headless = await renderProjectFile(file, { format: 'mp4', width: 160, fps: 24 });
    const headlessPath = info.outputPath('sound.mp4');
    await writeFile(headlessPath, headless.bytes);
    const execute = promisify(execFile);
    const levels: number[][] = [];
    for (const path of [browserPath, headlessPath]) {
      const { stdout } = await execute('ffmpeg', ['-v', 'error', '-i', path, '-vn', '-ac', '1', '-ar', '48000', '-f', 'f32le', 'pipe:1'], { encoding: 'buffer', maxBuffer: 2 * 1024 * 1024 });
      const samples = new Float32Array(stdout.buffer, stdout.byteOffset, stdout.byteLength / 4);
      const rms = (from: number, to: number) => {
        let sum = 0;
        for (let i = Math.round(from * 48000); i < Math.round(to * 48000); i++) sum += samples[i] ** 2;
        return Math.sqrt(sum / ((to - from) * 48000));
      };
      expect(rms(.05, .35)).toBeLessThan(.0001);
      expect(rms(.52, .68)).toBeGreaterThan(.02);
      expect(rms(.52, .68)).toBeLessThan(.2);
      levels.push([rms(.52, .68), rms(.7, .85), rms(1, 1.15)]);
    }
    for (let i = 0; i < 3; i++) expect(Math.abs(levels[0][i] - levels[1][i])).toBeLessThan(.012);
  } finally { watch.close(); }
});

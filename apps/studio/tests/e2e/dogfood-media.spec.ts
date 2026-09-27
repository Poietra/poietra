import { open, observer, field } from './media-helpers';
import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { parseProjectFile } from '../../shared/project-file';

function wave(name = 'Tone.wav') {
  const samples = 16000 * 2, bytes = Buffer.alloc(44 + samples * 2);
  bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22); bytes.writeUInt32LE(16000, 24); bytes.writeUInt32LE(32000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34); bytes.write('data', 36); bytes.writeUInt32LE(samples * 2, 40);
  for (let i = 0; i < samples; i++) bytes.writeInt16LE(Math.round(Math.sin(i * 440 * Math.PI * 2 / 16000) * 14000), 44 + i * 2);
  return { name, mimeType: 'audio/wav', buffer: bytes };
}
async function uploadWave(page: Page) { await page.getByLabel('音声・動画ファイル', { exact: true }).setInputFiles(wave()); await expect(page.getByTestId('audio-track')).toHaveCount(1); }

async function pasteMixedAssets(page: Page, broken = false) {
  const audio = wave();
  await page.evaluate(({ bytes, broken }) => {
    const canvas = document.createElement('canvas'); canvas.width = 40; canvas.height = 20;
    canvas.getContext('2d')!.fillRect(0, 0, 40, 20);
    const png = Uint8Array.from(atob(canvas.toDataURL().split(',')[1]), c => c.charCodeAt(0));
    const clipboardData = new DataTransfer();
    clipboardData.items.add(new File([png], 'Mixed.png', { type: 'image/png' }));
    clipboardData.items.add(new File([broken ? 'invalid' : new Uint8Array(bytes)], 'Batch.wav', { type: 'audio/wav' }));
    (document.activeElement as HTMLElement)?.blur();
    document.body.dispatchEvent(new ClipboardEvent('paste', { clipboardData, bubbles: true, cancelable: true }));
  }, { bytes: [...audio.buffer], broken });
}

test('a mixed image/audio paste commits together and has one Undo item', async ({ page }) => {
  const room = await open(page), watch = await observer(page, room);
  try {
    await pasteMixedAssets(page);
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Mixed', exact: true })).toBeVisible();
    await expect.poll(() => Object.values(watch.project().scenes['scene-1'].objects).filter(o => o.kind === 'image').length).toBe(1);
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(page.getByTestId('audio-track')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Mixed', exact: true })).toHaveCount(0);
    await expect.poll(() => Object.values(watch.project().scenes['scene-1'].objects).filter(o => o.kind === 'image').length).toBe(0);
    await page.getByRole('button', { name: 'やり直す (⌘⇧Z)', exact: true }).click();
    await expect(page.getByTestId('audio-track')).toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Mixed', exact: true })).toBeVisible();
  } finally { watch.close(); }
});

test('a failed second item leaves the entire mixed paste out of shared data', async ({ page }) => {
  const room = await open(page), watch = await observer(page, room);
  try {
    await pasteMixedAssets(page, true);
    await expect(page.locator('.media-import-status.is-error')).toBeVisible();
    await expect(page.getByTestId('audio-track')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Mixed', exact: true })).toHaveCount(0);
    expect(Object.values(watch.project().scenes['scene-1'].objects).filter(o => o.kind === 'image')).toHaveLength(0);
    await expect(page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true })).toBeDisabled();
  } finally { watch.close(); }
});

test('audio is a shared independent waveform track with trim, volume, mute, and undo', async ({ page, browser }, info) => {
  const room = await open(page), watch = await observer(page, room), context = await browser.newContext(), peer = await context.newPage();
  try {
    await open(peer, room); await uploadWave(page);
    await expect(peer.getByTestId('audio-track')).toHaveCount(1);
    expect(await page.locator('.media-waveform line').count()).toBeGreaterThan(50);
    const track = Object.values(watch.project().scenes['scene-1'].audioTracks!)[0];
    expect(track.asset.src).toContain(`/api/rooms/${room}/media/`);
    expect(Object.values(watch.project().scenes['scene-1'].objects).some(object => object.name === 'Tone')).toBe(false);
    await page.getByRole('button', { name: '音声クリップ Tone', exact: true }).click();
    await field(page, '素材の開始位置', '500'); await field(page, '素材のトリム開始', '250'); await field(page, '素材の再生時間', '1000'); await field(page, '音量', '35');
    await peer.getByRole('button', { name: '音声クリップ Tone', exact: true }).click();
    await expect(peer.getByRole('spinbutton', { name: '素材の開始位置', exact: true })).toHaveValue('500');
    await expect(peer.getByRole('spinbutton', { name: '音量', exact: true })).toHaveValue('35');
    await page.getByRole('button', { name: 'Tone をミュート', exact: true }).click();
    await expect(peer.getByRole('button', { name: 'Tone のミュートを解除', exact: true })).toBeVisible();
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(peer.getByRole('button', { name: 'Tone をミュート', exact: true })).toBeVisible();
    // Request partial bytes as a second client would when seeking in a media element.
    const response = await peer.request.get(track.asset.src, { headers: { Range: 'bytes=0-43' } });
    expect(response.status()).toBe(206); expect((await response.body()).length).toBe(44);
    await page.screenshot({ path: info.outputPath('audio-track.png'), fullPage: true });
  } finally { watch.close(); await context.close(); }
});

test('media save embeds source and opening restores independent room assets', async ({ page }, info) => {
  const room = await open(page); await uploadWave(page);
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: 'Save project', exact: true }).click()]);
  const path = info.outputPath('audio.poietra.json'); await download.saveAs(path);
  const project = parseProjectFile(await readFile(path, 'utf8'));
  expect(Object.values(project.scenes['scene-1'].audioTracks!)[0].asset.src).toMatch(/^data:audio\/wav;base64,/);
  await page.route(`**/api/rooms/${room}/media/**`, route => route.abort());
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles(path);
  await expect(page).not.toHaveURL(new RegExp(room)); await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await expect(page.getByTestId('audio-track')).toHaveCount(1);
  const nextRoom = new URL(page.url()).searchParams.get('room')!, watch = await observer(page, nextRoom);
  try { expect(Object.values(watch.project().scenes['scene-1'].audioTracks!)[0].asset.src).toContain(`/api/rooms/${nextRoom}/media/`); } finally { watch.close(); }
});

test('invalid and cancelled imports provide local feedback without adding tracks', async ({ page }) => {
  await open(page);
  await page.getByLabel('音声・動画ファイル', { exact: true }).setInputFiles({ name: 'broken.mp4', mimeType: 'video/mp4', buffer: Buffer.from('not a movie') });
  await expect(page.locator('.media-import-status.is-error')).toBeVisible(); await expect(page.getByTestId('audio-track')).toHaveCount(0);
  let requested = false;
  await page.route('**/api/rooms/*/media', async route => { requested = true; await new Promise(resolve => setTimeout(resolve, 1200)); await route.abort().catch(() => {}); });
  await page.getByLabel('音声・動画ファイル', { exact: true }).setInputFiles(wave());
  await expect.poll(() => requested).toBe(true);
  await expect(page.getByRole('progressbar', { name: '素材の読み込み進捗' })).toBeVisible();
  await page.getByRole('button', { name: '中止', exact: true }).click();
  await expect(page.getByTestId('audio-track')).toHaveCount(0);
  await expect(page.locator('.toast')).toContainText('中止');
});

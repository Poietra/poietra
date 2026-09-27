import { expect, test } from '@playwright/test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { open, observer, upload, field } from './media-helpers';

const execute = promisify(execFile);

for (const format of ['mp4', 'webm'] as const) test(`the actual ${format} contains image colors and transparency`, async ({ page }, testInfo) => {
  test.setTimeout(90000); await open(page); await upload(page); await field(page, 'Width', '320');
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  await page.getByRole('combobox', { name: 'Export format', exact: true }).selectOption(format);
  await expect(page.getByRole('button', { name: 'Export video', exact: true })).toBeEnabled();
  const [download] = await Promise.all([page.waitForEvent('download', { timeout: 60000 }), page.getByRole('button', { name: 'Export video', exact: true }).click()]);
  const path = testInfo.outputPath(`image.${format}`); await download.saveAs(path);
  const decoded = await execute('ffmpeg', ['-v', 'error', '-i', path, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'], { encoding: 'buffer', maxBuffer: 10 * 1024 * 1024 });
  const probe = await execute('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'json', path]);
  const size = JSON.parse(probe.stdout).streams[0]; expect(size).toMatchObject({ width: 1280, height: 720 });
  const pixel = (x: number, y: number) => [...decoded.stdout.subarray((y * 1280 + x) * 3, (y * 1280 + x) * 3 + 3)];
  const red = pixel(540, 320), green = pixel(740, 320), hole = pixel(640, 360);
  expect(red[0]).toBeGreaterThan(220); expect(red[1]).toBeLessThan(30);
  expect(green[1]).toBeGreaterThan(220); expect(green[0]).toBeLessThan(30);
  expect(Math.max(...hole)).toBeLessThan(30);
});

test('MP4 import creates a visible video object and a separate soundtrack', async ({ page }, info) => {
  const file = info.outputPath('Clip.mp4');
  await execute('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=10:duration=2', '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000:duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', file]);
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  const room = await open(page), watch = await observer(page, room);
  try {
    await page.getByLabel('音声・動画ファイル', { exact: true }).setInputFiles(file);
    await expect(page.getByTestId('video-track')).toHaveCount(1, { timeout: 15_000 }); await expect(page.getByTestId('audio-track')).toHaveCount(1);
    const scene = watch.project().scenes['scene-1'], video = Object.values(scene.objects).find(object => object.kind === 'video')!;
    expect(video.media).toMatchObject({ width: 160, height: 90, hasAudio: true });
    expect(Object.values(scene.audioTracks!)[0].asset.src).toBe(video.media!.src);
    const surface = page.locator('.stage-surface').first();
    const hit = surface.locator(`[data-object-id="${video.id}"] rect`);
    await expect(hit).toBeVisible();
    await expect.poll(() => surface.evaluate((element, id) => {
      const canvas = element.querySelector('canvas.scene-canvas') as HTMLCanvasElement;
      if (!canvas || getComputedStyle(canvas).visibility !== 'visible') return 0;
      const hit = element.querySelector(`[data-object-id="${id}"]`)!.getBoundingClientRect();
      const bounds = canvas.getBoundingClientRect(), ctx = canvas.getContext('2d')!;
      const colors = new Set<string>();
      for (const x of [.2, .4, .6, .8]) for (const y of [.2, .4, .6, .8]) {
        const pixel = ctx.getImageData((hit.left - bounds.left + hit.width * x) * canvas.width / bounds.width,
          (hit.top - bounds.top + hit.height * y) * canvas.height / bounds.height, 1, 1).data;
        colors.add([...pixel].map(value => Math.round(value / 32)).join(','));
      }
      return colors.size;
    }, video.id)).toBeGreaterThan(4);
    // Deselect, then select the visible video through its transparent hit region.
    await page.keyboard.press('Escape');
    await hit.click();
    await expect(page.getByRole('textbox', { name: 'Object name', exact: true })).toHaveValue('Clip');
    await expect(page.getByRole('spinbutton', { name: 'Position X', exact: true })).toBeVisible();
    await page.getByRole('button', { name: '動画クリップ Clip', exact: true }).click();
    await field(page, '素材のトリム開始', '500'); await field(page, '素材の再生時間', '1000');
    await page.getByRole('button', { name: 'シーンを再生', exact: true }).click();
    await expect(page.getByRole('button', { name: '一時停止', exact: true })).toBeVisible();
    await page.getByRole('button', { name: '一時停止', exact: true }).click();
    expect(errors).toEqual([]);
    await page.screenshot({ path: info.outputPath('video-audio-tracks.png'), fullPage: true });
  } finally { watch.close(); }
});

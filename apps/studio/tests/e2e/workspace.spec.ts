import { expect, test, type Page } from '@playwright/test';

async function open(page: Page, room = crypto.randomUUID()) {
  await page.goto(`/?room=${room}`);
  await expect(page.locator('.connection-status')).toContainText('Live', { timeout: 15000 });
  await expect(page.getByTestId('stage-main')).toBeVisible();
}
const transition = (page: Page) => page.getByRole('button', { name: 'Transition 800 ms', exact: true });
const preview = (page: Page) => page.getByRole('slider', { name: 'Transition preview position', exact: true });
const chrome = (page: Page) => page.locator('.workspace-heading, .workspace-actions .subtle-button:nth-child(-n+2), .workspace, .timeline, .composition-strip, .transport').evaluateAll(nodes => nodes.map(node => {
  const { x, y, width, height } = node.getBoundingClientRect();
  return { x, y, width, height };
}));

test('selection switches between state editing and motion comparison within a fixed workspace', async ({ page }) => {
  await open(page);
  for (const width of [1440, 960, 760]) {
    await page.setViewportSize({ width, height: 900 });
    await page.getByRole('button', { name: 'Composition 1', exact: true }).click();
    await expect(page.getByTestId('stage-from')).toHaveCount(0);
    await expect(page.getByTestId('stage-main')).toBeVisible();
    await expect(page.locator('.floating-tools')).toBeVisible();
    const before = await chrome(page);
    const tools = await page.locator('.floating-tools').boundingBox();
    const canvas = await page.getByTestId('stage-main').boundingBox();
    for (let i = 0; i < 3; i++) {
      await transition(page).click();
      await expect(page.getByTestId('stage-from')).toBeVisible();
      await expect(page.getByTestId('stage-to')).toBeVisible();
      await expect(page.locator('.floating-tools')).toHaveCount(0);
      await expect(page.locator('.tool-instruction')).toHaveCount(0);
      const from = (await page.getByTestId('stage-from').boundingBox())!;
      const to = (await page.getByTestId('stage-to').boundingBox())!;
      expect(from.width).toBe(to.width);
      expect(from.height).toBe(to.height);
      expect(from.x + from.width).toBeLessThan(to.x);
      expect(to.width).toBeLessThan(canvas!.width);
      expect(await chrome(page)).toEqual(before);
      await expect(preview(page)).toBeInViewport({ ratio: 1 });
      await expect(page.getByRole('button', { name: 'Transition をプレビュー', exact: true })).toBeInViewport({ ratio: 1 });
      const fromCircle = page.locator('[data-testid="stage-from"] .scene-svg [data-object-id="circle"]');
      const start = await fromCircle.getAttribute('transform');
      await preview(page).fill('300');
      await expect(fromCircle).toHaveAttribute('transform', start!);
      await expect(page.locator('[data-testid="stage-to"] .scene-svg [data-object-id="circle"]')).toHaveAttribute('transform', 'translate(588.75 355) rotate(0)');
      await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
      await expect(page.locator('.floating-tools')).toBeVisible();
      expect(await page.locator('.floating-tools').boundingBox()).toEqual(tools);
      await expect.poll(() => page.getByTestId('stage-main').boundingBox()).toEqual(canvas);
      expect(await chrome(page)).toEqual(before);
    }
  }
});

test('overflowing tracks and media remain reachable without moving the cards or transport', async ({ page }) => {
  await page.setViewportSize({ width: 960, height: 640 });
  await open(page);
  await transition(page).click();
  const fixed = await chrome(page);
  const lastTrack = page.locator('.track-row').last();
  await lastTrack.scrollIntoViewIfNeeded();
  await expect(lastTrack).toBeInViewport({ ratio: 1 });
  const addAudio = page.getByRole('button', { name: '音声を追加', exact: true });
  await addAudio.scrollIntoViewIfNeeded();
  await expect(addAudio).toBeInViewport({ ratio: 1 });
  const wave = Buffer.alloc(44 + 8000, 128);
  wave.write('RIFF', 0); wave.writeUInt32LE(wave.length - 8, 4); wave.write('WAVEfmt ', 8);
  wave.writeUInt32LE(16, 16); wave.writeUInt16LE(1, 20); wave.writeUInt16LE(1, 22);
  wave.writeUInt32LE(8000, 24); wave.writeUInt32LE(8000, 28);
  wave.writeUInt16LE(1, 32); wave.writeUInt16LE(8, 34); wave.write('data', 36); wave.writeUInt32LE(8000, 40);
  await page.getByLabel('音声・動画ファイル', { exact: true }).setInputFiles({ name: 'layout.wav', mimeType: 'audio/wav', buffer: wave });
  await expect(page.locator('.media-track-row')).toHaveCount(1);
  await expect(page.locator('.media-import-status')).toHaveCount(0);
  // Import selects the media track; return to the transition to expose its controls.
  await transition(page).click();
  await page.locator('.media-track-row').scrollIntoViewIfNeeded();
  await expect(page.locator('.media-track-row')).toBeInViewport({ ratio: 1 });
  expect(await chrome(page)).toEqual(fixed);
  await expect(transition(page)).toBeInViewport({ ratio: 1 });
  await expect(preview(page)).toBeInViewport({ ratio: 1 });
  await page.getByRole('button', { name: 'Composition 1', exact: true }).click();
  expect(await chrome(page)).toEqual(fixed);
});

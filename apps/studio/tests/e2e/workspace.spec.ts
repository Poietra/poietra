import { expect, test, type Page } from '@playwright/test';
import { chooseOption } from './select';

async function open(page: Page, room = crypto.randomUUID()) {
  await page.goto(`/?room=${room}`);
  await expect(page.locator('.connection-status')).toContainText('Live', { timeout: 15000 });
  await expect(page.getByTestId('stage-main')).toBeVisible();
}
const transition = (page: Page) => page.getByRole('button', { name: 'Transition 800 ms', exact: true });
const compare = (page: Page) => page.getByRole('button', { name: '開始と終了を比較', exact: true });
const divider = (page: Page) => page.getByRole('separator', { name: 'タイムラインの高さ', exact: true });
const preview = (page: Page) => page.getByRole('slider', { name: 'Transition preview position', exact: true });
const height = async (page: Page) => (await page.locator('.timeline').boundingBox())!.height;
const chrome = (page: Page) => page.locator('.workspace-heading, .main-stage-area, .floating-tools, .timeline, .composition-strip, .transport').evaluateAll(nodes => nodes.map(node => {
  const { x, y, width, height } = node.getBoundingClientRect();
  return { x, y, width, height };
}));

test('selection keeps the canvas, tools, cards and playback controls in place at wide and narrow sizes', async ({ page }) => {
  await open(page);
  for (const width of [1440, 960, 760]) {
    await page.setViewportSize({ width, height: 900 });
    await page.getByRole('button', { name: 'Composition 1', exact: true }).click();
    await expect(compare(page)).toBeDisabled();
    await expect(page.getByTestId('stage-main')).toBeVisible();
    const before = await chrome(page);
    const canvas = await page.getByTestId('stage-main').boundingBox();
    for (let i = 0; i < 3; i++) {
      await transition(page).click();
      await expect(page.getByTestId('stage-from')).toHaveCount(0);
      await expect.poll(() => page.getByTestId('stage-to').boundingBox()).toEqual(canvas);
      expect(await chrome(page)).toEqual(before);
      await expect(preview(page)).toBeInViewport({ ratio: 1 });
      await expect(compare(page)).toBeInViewport({ ratio: 1 });
      await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
      await expect.poll(() => page.getByTestId('stage-main').boundingBox()).toEqual(canvas);
      expect(await chrome(page)).toEqual(before);
    }
  }
});

test('comparison is optional, keeps the scrubbed frame, and returns to the same single-canvas zoom', async ({ page }) => {
  await open(page);
  await chooseOption(page.getByRole('combobox', { name: 'キャンバスのズーム', exact: true }), '0.75');
  const canvas = await page.getByTestId('stage-main').boundingBox();
  await transition(page).click();
  await expect.poll(() => page.getByTestId('stage-to').boundingBox()).toEqual(canvas);
  await preview(page).fill('300');
  const circle = page.locator('[data-testid="stage-to"] .scene-svg [data-object-id="circle"]');
  await expect(circle).toHaveAttribute('transform', 'translate(588.75 355) rotate(0)');
  const before = await chrome(page);
  await compare(page).click();
  await expect(compare(page)).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('stage-from')).toBeVisible();
  await expect(circle).toHaveAttribute('transform', 'translate(588.75 355) rotate(0)');
  expect(await chrome(page)).toEqual(before);
  await compare(page).click();
  await expect(page.getByTestId('stage-from')).toHaveCount(0);
  await expect.poll(() => page.getByTestId('stage-to').boundingBox()).toEqual(canvas);
  await expect(preview(page)).toHaveValue('300');
  await expect(circle).toHaveAttribute('transform', 'translate(588.75 355) rotate(0)');
  await page.getByRole('button', { name: 'Transition をプレビュー', exact: true }).click();
  await expect(page.getByRole('button', { name: 'プレビューを停止', exact: true })).toBeVisible();
  await compare(page).click();
  await expect(page.getByTestId('stage-from')).toBeVisible();
  await expect.poll(async () => Number(await preview(page).inputValue())).toBeGreaterThan(300);
});

test('panel resizing is local, preserves Undo, cancels safely, and stays bounded after a window resize', async ({ browser }) => {
  const alice = await browser.newPage(), bob = await browser.newPage(), room = crypto.randomUUID();
  try {
    await Promise.all([open(alice, room), open(bob, room)]);
    await alice.getByRole('button', { name: 'Circle', exact: true }).click();
    const x = alice.getByRole('spinbutton', { name: 'Position X', exact: true });
    await x.fill('320'); await x.press('Tab');
    const initial = await height(alice), peerHeight = await height(bob);
    const resize = divider(alice);
    const begin = async () => {
      const box = (await resize.boundingBox())!;
      await alice.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await alice.mouse.down();
      await alice.mouse.move(box.x + box.width / 2, box.y + box.height / 2 - 55, { steps: 3 });
    };
    await begin(); await alice.mouse.up();
    await expect.poll(() => height(alice)).toBeCloseTo(initial + 55, 0);
    expect(await height(bob)).toBe(peerHeight);
    const resized = await height(alice);
    await transition(alice).click();
    expect(await height(alice)).toBe(resized);
    for (const cancel of ['escape', 'blur', 'pointercancel', 'lostcapture']) {
      await begin();
      await expect.poll(() => height(alice)).toBeGreaterThan(resized + 30);
      if (cancel === 'escape') await alice.keyboard.press('Escape');
      else if (cancel === 'blur') await alice.evaluate(() => window.dispatchEvent(new Event('blur')));
      else if (cancel === 'pointercancel') await resize.dispatchEvent('pointercancel', { pointerId: 1 });
      else await resize.evaluate(element => element.releasePointerCapture(1));
      await alice.mouse.up();
      await expect.poll(() => height(alice)).toBe(resized);
    }
    await resize.focus(); await resize.press('ArrowUp');
    await expect.poll(() => height(alice)).toBeCloseTo(resized + 20, 0);
    await resize.press('Delete');
    await expect(alice.locator('[data-layer-id="circle"]')).toBeVisible();
    await alice.getByRole('button', { name: 'Composition 1', exact: true }).click();
    await alice.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(x).toHaveValue('245');
    expect(await height(alice)).toBeCloseTo(resized + 20, 0);
    await resize.focus(); await resize.press('End');
    await alice.setViewportSize({ width: 960, height: 640 });
    await expect.poll(async () => Number(await resize.getAttribute('aria-valuenow'))).toBeLessThanOrEqual(384);
    await expect(alice.locator('.transport')).toBeInViewport({ ratio: 1 });
    await resize.press('Home');
    await expect.poll(() => height(alice)).toBe(280);
  } finally { await alice.close(); await bob.close(); }
});

test('overflowing tracks and media remain reachable without moving the cards or transport', async ({ page }) => {
  await page.setViewportSize({ width: 960, height: 740 });
  await open(page);
  await transition(page).click();
  await divider(page).focus(); await divider(page).press('Home');
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
  expect(await height(page)).toBe(280);
});

import { expect, test, type Page } from '@playwright/test';
import { chooseOption } from './select';

async function open(page: Page, room = crypto.randomUUID()) {
  await page.goto(`/?room=${room}`);
  await expect(page.locator('.connection-status')).toContainText('Live', { timeout: 15000 });
  await expect(page.getByTestId('stage-main')).toBeVisible();
}
const transition = (page: Page) => page.getByRole('button', { name: 'Transition 800 ms', exact: true });
const divider = (page: Page) => page.getByRole('separator', { name: 'タイムラインの高さ', exact: true });
const preview = (page: Page) => page.getByRole('slider', { name: 'Transition preview position', exact: true });
const height = async (page: Page) => (await page.locator('.timeline').boundingBox())!.height;
const chrome = (page: Page) => page.locator('.workspace-heading, .main-stage-area, .floating-tools, .timeline, .composition-strip, .transport').evaluateAll(nodes => nodes.map(node => {
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
    const before = await chrome(page);
    const canvas = await page.getByTestId('stage-main').boundingBox();
    for (let i = 0; i < 3; i++) {
      await transition(page).click();
      await expect(page.getByTestId('stage-from')).toBeVisible();
      await expect(page.getByTestId('stage-to')).toBeVisible();
      const from = (await page.getByTestId('stage-from').boundingBox())!;
      const to = (await page.getByTestId('stage-to').boundingBox())!;
      expect(from.width).toBe(to.width);
      expect(from.height).toBe(to.height);
      expect(from.x + from.width).toBeLessThan(to.x);
      expect(to.width).toBeLessThan(canvas!.width);
      expect(await chrome(page)).toEqual(before);
      await expect(preview(page)).toBeInViewport({ ratio: 1 });
      await expect(page.getByRole('button', { name: '比較しながらモーションを再生', exact: true })).toBeInViewport({ ratio: 1 });
      await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
      await expect.poll(() => page.getByTestId('stage-main').boundingBox()).toEqual(canvas);
      expect(await chrome(page)).toEqual(before);
    }
  }
});

test('easing and timing edits update the compared motion at the current time and preserve Composition zoom', async ({ page }) => {
  await open(page);
  await chooseOption(page.getByRole('combobox', { name: 'キャンバスのズーム', exact: true }), '0.75');
  const canvas = await page.getByTestId('stage-main').boundingBox();
  await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await transition(page).click();
  await expect(page.getByTestId('stage-from')).toBeVisible();
  await preview(page).fill('150');
  const from = page.locator('[data-testid="stage-from"] .scene-svg [data-object-id="circle"]');
  const circle = page.locator('[data-testid="stage-to"] .scene-svg [data-object-id="circle"]');
  const start = await from.getAttribute('transform');
  const eased = await circle.getAttribute('transform');
  const before = await chrome(page);
  const compared = await page.getByTestId('stage-to').boundingBox();
  await chooseOption(page.getByRole('combobox', { name: 'Easing', exact: true }), 'linear');
  await expect(circle).not.toHaveAttribute('transform', eased!);
  const linear = await circle.getAttribute('transform');
  const duration = page.getByRole('spinbutton', { name: 'Animation duration', exact: true });
  await duration.fill('400'); await duration.press('Tab');
  await expect(circle).not.toHaveAttribute('transform', linear!);
  await expect(from).toHaveAttribute('transform', start!);
  await expect(preview(page)).toHaveValue('150');
  expect(await page.getByTestId('stage-to').boundingBox()).toEqual(compared);
  expect(await chrome(page)).toEqual(before);
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(circle).toHaveAttribute('transform', linear!);
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(circle).toHaveAttribute('transform', eased!);
  await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await expect(page.getByTestId('stage-from')).toHaveCount(0);
  await expect.poll(() => page.getByTestId('stage-main').boundingBox()).toEqual(canvas);
  await expect(page.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue('955');
  await transition(page).click();
  await expect(page.getByTestId('stage-from')).toBeVisible();
  expect(await page.getByTestId('stage-to').boundingBox()).toEqual(compared);
});

test('comparison plays and scrubs motion on the right while retaining the start state and layout', async ({ page }) => {
  await open(page);
  await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await transition(page).click();
  const duration = page.getByRole('spinbutton', { name: 'Transition duration', exact: true });
  await duration.fill('8000'); await duration.press('Tab');
  const play = page.getByRole('button', { name: '比較しながらモーションを再生', exact: true });
  const pause = page.getByRole('button', { name: '比較プレビューを一時停止', exact: true });
  const from = page.locator('[data-testid="stage-from"] .scene-svg [data-object-id="circle"]');
  const motion = page.locator('[data-testid="stage-to"] .scene-svg [data-object-id="circle"]');
  const start = await from.getAttribute('transform');
  for (const width of [1440, 760]) {
    await page.setViewportSize({ width, height: 900 });
    await preview(page).fill('0');
    const fixed = await chrome(page);
    const canvas = await page.getByTestId('stage-to').boundingBox();
    await expect(play).toBeInViewport({ ratio: 1 });
    await play.click();
    await expect.poll(async () => Number(await preview(page).inputValue())).toBeGreaterThan(120);
    await expect(from).toHaveAttribute('transform', start!);
    await pause.click();
    // Playback paints Canvas directly; the retained SVG catches up when paused.
    await expect(motion).not.toHaveAttribute('transform', start!);
    expect(await chrome(page)).toEqual(fixed);
    expect(await page.getByTestId('stage-to').boundingBox()).toEqual(canvas);
    await preview(page).fill('300');
    await expect(motion).toHaveAttribute('transform', 'translate(588.75 355) rotate(0)');
    await expect(from).toHaveAttribute('transform', start!);
    await expect(page.getByRole('slider', { name: '再生位置', exact: true })).toHaveCount(0);
    await expect(page.getByTestId('stage-from')).toBeVisible();
  }
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

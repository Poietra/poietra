import { expect, test, type Page, type Locator } from '@playwright/test';
import { readFile } from 'node:fs/promises';

const select = (page: Page, name: string) => page.getByRole('button', { name, exact: true }).click();
async function open(page: Page, url = `/?room=${crypto.randomUUID()}`) {
  await page.goto(url);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(shape(page)).toBeVisible();
}
async function field(page: Page, name: string, value: number) {
  const control = page.getByRole('spinbutton', { name, exact: true });
  await control.fill(String(value)); await control.press('Tab');
  await expect.poll(async () => Number(await control.inputValue())).toBeCloseTo(value, 4);
}
function shape(page: Page, stage = 'main') { return page.locator(`[data-testid="stage-${stage}"] .scene-svg [data-object-id="circle"]`); }
async function matrix(page: Page, stage = 'main') {
  return shape(page, stage).evaluate(node => {
    const element = node as SVGGraphicsElement;
    const m = element.ownerSVGElement!.getScreenCTM()!.inverse().multiply(element.getScreenCTM()!);
    return [m.a, m.b, m.c, m.d, m.e, m.f];
  });
}
function near(a: number[], b: number[]) { a.forEach((value, index) => expect(value).toBeCloseTo(b[index], 3)); }
async function center(locator: Locator) {
  const box = (await locator.boundingBox())!;
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function drag(page: Page, target: Locator, dx: number, dy: number) {
  const at = await center(target);
  await page.mouse.move(at.x, at.y); await page.mouse.down();
  await page.mouse.move(at.x + dx, at.y + dy, { steps: 6 }); await page.mouse.up();
}

test('parents and anchors preserve geometry, inherited transforms support dragging, resizing and Undo', async ({ page }) => {
  await open(page);
  await select(page, 'Equation'); await field(page, 'Rotation', 31); await field(page, 'Scale X', 180); await field(page, 'Scale Y', 75);
  await select(page, 'Circle'); const before = await matrix(page);
  await page.getByRole('combobox', { name: 'Parent object' }).selectOption('equation');
  await expect(page.getByRole('combobox', { name: 'Parent object' })).toHaveValue('equation');
  near(await matrix(page), before);
  await field(page, 'Anchor X', 17); await field(page, 'Anchor Y', -9);
  near(await matrix(page), before);
  const initial = await center(shape(page));
  await drag(page, shape(page), 32, -19);
  const moved = await center(shape(page));
  expect(moved.x - initial.x).toBeCloseTo(32, 0); expect(moved.y - initial.y).toBeCloseTo(-19, 0);
  const fixed = await center(page.locator('[data-transform-handle="nw"]'));
  await drag(page, page.locator('[data-transform-handle="se"]'), 24, 16);
  const corner = await center(page.locator('[data-transform-handle="nw"]'));
  expect(corner.x).toBeCloseTo(fixed.x, 1); expect(corner.y).toBeCloseTo(fixed.y, 1);
  await select(page, '元に戻す (⌘Z)');
  await expect(page.getByRole('spinbutton', { name: 'Width', exact: true })).toHaveValue('42');
  const attached = await matrix(page);
  await page.getByRole('combobox', { name: 'Parent object' }).selectOption('');
  near(await matrix(page), attached);
});

test('intermediate values stretch with timing, follow endpoint edits and survive reload with a collaborator', async ({ page, browser }) => {
  await open(page); await select(page, 'Circle'); await field(page, 'Position X', 100);
  await select(page, 'Composition 2'); await field(page, 'Position X', 100);
  await select(page, 'Transition 800 ms');
  await field(page, 'Position animation start', 0); await field(page, 'Position animation duration', 800);
  await page.getByRole('combobox', { name: 'Keyframe property' }).selectOption('x');
  await select(page, '中間点を追加'); await field(page, 'X keyframe 1 value', 500);
  const slider = page.getByRole('slider', { name: 'Transition preview position', exact: true });
  await slider.fill('400');
  await expect.poll(async () => (await matrix(page, 'to'))[4]).toBeCloseTo(500, 3);
  await expect(page.getByRole('img', { name: 'X value curve' })).toBeVisible();
  await field(page, 'Position animation duration', 400);
  await slider.fill('200');
  await expect.poll(async () => (await matrix(page, 'to'))[4]).toBeCloseTo(500, 3);
  await expect(page.getByRole('spinbutton', { name: 'X keyframe 1 time' })).toHaveValue('50');
  const context = await browser.newContext(); const peer = await context.newPage();
  try {
    await open(peer, page.url()); await select(peer, 'Circle'); await select(peer, 'Transition 800 ms');
    await expect(peer.getByRole('spinbutton', { name: 'X keyframe 1 value' })).toHaveValue('500');
    await select(peer, 'Composition 2'); await field(peer, 'Position X', 250);
    await slider.fill('400');
    await expect.poll(async () => (await matrix(page, 'to'))[4]).toBeCloseTo(250, 3);
    await page.reload(); await expect(page.getByText('Live', { exact: true })).toBeVisible();
    await select(page, 'Circle'); await select(page, 'Transition 800 ms');
    await expect(page.getByRole('spinbutton', { name: 'X keyframe 1 value' })).toHaveValue('500');
    await page.getByRole('img', { name: 'X value curve' }).scrollIntoViewIfNeeded();
    await page.screenshot({ path: test.info().outputPath('keyframe-inspector.png'), fullPage: true });
  } finally { await context.close(); }
});

test('a version 2 saved project opens in a fresh room with its parenting and intermediate points intact', async ({ page }) => {
  await open(page); await select(page, 'Circle');
  await page.getByRole('combobox', { name: 'Parent object' }).selectOption('equation');
  await select(page, 'Transition 800 ms'); await select(page, '中間点を追加'); await field(page, 'X keyframe 1 value', 350);
  await select(page, 'プロジェクトを開く');
  const downloading = page.waitForEvent('download'); await select(page, 'Save project');
  const download = await downloading; const saved = await readFile((await download.path())!);
  const project = JSON.parse(saved.toString());
  expect(project.version).toBe(2);
  expect(project.scenes['scene-1'].objects.circle.parentId).toBe('equation');
  expect(Object.values(project.scenes['scene-1'].transitions['transition-1'].tracks.circle.keyframes)).toEqual(expect.arrayContaining([expect.objectContaining({ property: 'x', value: 350 })]));
  const original = page.url();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'primitives.poietra.json', mimeType: 'application/json', buffer: saved });
  await expect(page).not.toHaveURL(original);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await select(page, 'Circle'); await expect(page.getByRole('combobox', { name: 'Parent object' })).toHaveValue('equation');
  await select(page, 'Transition 800 ms');
  await expect(page.getByRole('spinbutton', { name: 'X keyframe 1 value' })).toHaveValue('350');
});

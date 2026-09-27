import { expect, test } from '@playwright/test';

test('Canvas project preview never builds the unused SVG representation', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/project-preview.html');
  const frame = page.getByTestId('project-preview-frame'), canvas = frame.locator('canvas');
  await expect(canvas).toHaveCSS('visibility', 'visible');
  const slider = page.getByRole('slider', { name: 'Project preview position', exact: true });
  for (const time of [250, 750, 1000, 1500, 300]) {
    await slider.fill(String(time)); await expect(canvas).toHaveCSS('visibility', 'visible');
  }
  expect(await page.evaluate(() => ({ svg: window.projectPreviewProbe.svg, views: window.projectPreviewProbe.views, frames: window.projectPreviewProbe.frames }))).toEqual({ svg: 0, views: 0, frames: 0 });
  await expect(frame.locator('.project-preview-svg')).toHaveCount(0);
  expect(await canvas.evaluate(canvas => {
    const context = (canvas as HTMLCanvasElement).getContext('2d')!;
    return context.getImageData(0, 0, 1, 1).data[3];
  })).toBe(255);
});

for (const mode of ['svg', 'fail']) test(`${mode} project preview retains SVG elements and updates Scene geometry`, async ({ page }) => {
  await page.goto(`/tests/e2e/fixtures/project-preview.html?mode=${mode}`);
  const frame = page.getByTestId('project-preview-frame'), box = frame.locator('[data-object-id="box"]');
  await expect(box).toHaveAttribute('fill', '#ff0000');
  const node = await box.elementHandle(), body = await box.locator('rect').elementHandle();
  const before = await box.getAttribute('transform');
  const slider = page.getByRole('slider', { name: 'Project preview position', exact: true });
  await slider.fill('700'); await expect(box).not.toHaveAttribute('transform', before!);
  expect(await box.evaluate((value, old) => value === old, node)).toBe(true);
  expect(await box.locator('rect').evaluate((value, old) => value === old, body)).toBe(true);
  await slider.fill('1000');
  await expect(frame).toHaveAttribute('data-scene-id', 'second');
  await expect(box).toHaveAttribute('fill', '#00ffff');
  await expect(frame.locator('svg')).toHaveAttribute('viewBox', '0 0 180 320');
  expect(await page.evaluate(() => window.projectPreviewProbe.svg)).toBe(0);
  expect(await page.evaluate(() => window.projectPreviewProbe.views)).toBeGreaterThan(1);
});

test('a renderer with only serialized SVG keeps its project preview fallback', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/project-preview.html?mode=legacy');
  const box = page.getByTestId('project-preview-frame').locator('[data-object-id="box"]');
  await expect(box).toHaveAttribute('fill', '#ff0000');
  await page.getByRole('slider', { name: 'Project preview position', exact: true }).fill('1000');
  await expect(box).toHaveAttribute('fill', '#00ffff');
  expect(await page.evaluate(() => window.projectPreviewProbe.svg)).toBeGreaterThan(1);
  expect(await page.evaluate(() => window.projectPreviewProbe.views)).toBe(0);
});

test('late SVG video preparation cannot cross Scene boundaries and retries after failure', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/project-preview.html?mode=svg');
  await expect(page.locator('[data-object-id="box"]')).toBeVisible();
  await page.evaluate(() => { window.projectPreviewProbe.hold = true; window.projectPreviewProbe.addVideo(); });
  await expect.poll(() => page.evaluate(() => window.projectPreviewProbe.frames)).toBeGreaterThan(0);
  const slider = page.getByRole('slider', { name: 'Project preview position', exact: true });
  await slider.fill('1000'); await page.evaluate(() => window.projectPreviewProbe.release());
  await expect(page.getByTestId('project-preview-frame')).toHaveAttribute('data-scene-id', 'second');
  await expect(page.locator('[data-object-id="clip"]')).toHaveCount(0);
  await page.evaluate(() => { window.projectPreviewProbe.failFrame = true; });
  await slider.fill('100');
  await expect(page.getByRole('alert')).toContainText('Simulated video preparation failure');
  await page.evaluate(() => { window.projectPreviewProbe.failFrame = false; });
  await slider.fill('300');
  await expect(page.locator('[data-object-id="clip"] image')).toHaveAttribute('href', /^data:image\/png/);
  await expect(page.getByRole('alert')).toHaveCount(0);
  await page.evaluate(() => window.projectPreviewProbe.close());
  await expect(page.getByRole('dialog')).toHaveCount(0);
});

for (const mode of ['canvas', 'svg']) test(`${mode} preview holds a static frame while clock, Scene and document updates remain live`, async ({ page }) => {
  await page.goto(`/tests/e2e/fixtures/project-preview.html?mode=${mode}`);
  const frame = page.getByTestId('project-preview-frame'), slider = page.getByRole('slider', { name: 'Project preview position', exact: true });
  if (mode === 'canvas') await expect(frame.locator('canvas')).toHaveCSS('visibility', 'visible');
  else await expect(frame.locator('[data-object-id="box"]')).toHaveAttribute('fill', '#ff0000');
  const settle = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const count = () => page.evaluate(() => window.projectPreviewProbe.paints + window.projectPreviewProbe.views);
  await settle(); const initial = await count();
  for (const time of [20, 80, 30, 99]) { await slider.fill(String(time)); await expect(slider).toHaveValue(String(time)); await settle(); }
  expect(await count()).toBe(initial);
  // A new immutable program invalidates a hold even when its time/key is unchanged.
  await page.evaluate(() => window.projectPreviewProbe.recolor());
  await expect.poll(count).toBeGreaterThan(initial);
  if (mode === 'svg') await expect(frame.locator('[data-object-id="box"]')).toHaveAttribute('fill', '#ffff00');
  const edited = await count();
  await slider.fill('500'); await expect.poll(count).toBeGreaterThan(edited);
  const transition = await count();
  await slider.fill('600'); await expect.poll(count).toBeGreaterThan(transition);
  await slider.fill('1000'); await expect(frame).toHaveAttribute('data-scene-id', 'second');
  if (mode === 'canvas') await expect(frame.locator('canvas')).toHaveCSS('visibility', 'visible');
  else await expect(frame.locator('[data-object-id="box"]')).toHaveAttribute('fill', '#00ffff');
  await settle(); const second = await count();
  await slider.fill('1080'); await settle(); expect(await count()).toBe(second);
  // Returning to the first Scene cannot reuse the second Scene's same-numbered hold.
  await slider.fill('0'); await expect(frame).toHaveAttribute('data-scene-id', 'first');
  await expect.poll(count).toBeGreaterThan(second);
  if (mode === 'svg') await expect(frame.locator('[data-object-id="box"]')).toHaveAttribute('fill', '#ffff00');
});

test('video time remains dynamic during an otherwise static project hold', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/project-preview.html?mode=svg');
  await expect(page.locator('[data-object-id="box"]')).toBeVisible();
  await page.evaluate(() => window.projectPreviewProbe.addVideo());
  const video = page.locator('[data-object-id="clip"] image');
  await expect(video).toHaveAttribute('href', /^data:image\/png/);
  const first = await page.evaluate(() => window.projectPreviewProbe.frames);
  const slider = page.getByRole('slider', { name: 'Project preview position', exact: true });
  await slider.fill('50');
  await expect.poll(() => page.evaluate(() => window.projectPreviewProbe.frames)).toBeGreaterThan(first);
  const next = await page.evaluate(() => window.projectPreviewProbe.frames);
  await slider.fill('90');
  await expect.poll(() => page.evaluate(() => window.projectPreviewProbe.frames)).toBeGreaterThan(next);
});

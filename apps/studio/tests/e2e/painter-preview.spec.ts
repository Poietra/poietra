import { expect, test, type Page } from '@playwright/test';
import { countEditorRenders } from './render-counts';

async function open(page: Page) {
  await page.goto(`/tests/e2e/fixtures/painter-preview.html?room=${crypto.randomUUID()}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(page.locator('[data-testid="stage-main"] .scene-hit-svg')).toHaveCount(1);
}
const circle = (page: Page, stage = 'main') => page.locator(`[data-testid="stage-${stage}"] .scene-svg [data-object-id="circle"]`);

test('pose edits reuse resources and panel content while names, visibility and timing still update', async ({ page }) => {
  await countEditorRenders(page);
  await open(page);
  await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const changes = await page.evaluate(async () => {
    window.renderCounts = {};
    const prepared = window.painterPreview.preparations;
    await window.painterPreview.positions([310, 330, 350, 370]);
    return { counts: window.renderCounts, prepared: window.painterPreview.preparations - prepared };
  });
  await expect(page.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue('370');
  expect(changes.prepared).toBe(0);
  for (const name of ['sidebar__content', 'scene__tabs__content', 'timeline__structure', 'media__timeline__content']) expect(changes.counts[name] ?? 0, name).toBe(0);
  await page.evaluate(() => window.painterPreview.renameCircle('Moving dot'));
  await expect(page.getByRole('button', { name: 'Moving dot', exact: true })).toBeVisible();
  await page.evaluate(() => window.painterPreview.updateCircle({ visible: false }));
  await expect(page.getByRole('button', { name: 'Moving dot を表示', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Moving dot を表示', exact: true }).click();
  await expect(circle(page)).toHaveAttribute('transform', 'translate(370 520) rotate(0)');
  await page.evaluate(() => { window.painterPreview.renameComposition('Opening'); window.painterPreview.duration(1200); });
  await expect(page.getByRole('button', { name: 'Opening', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Opening 1,200 ms', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
  await expect(page.locator('.track-label').filter({ hasText: 'Moving dot' })).toBeVisible();
});

test('text preparation follows content in every Composition and ignores size, color and poses', async ({ page }) => {
  await open(page);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const initial = await page.evaluate(() => window.painterPreview.preparations);
  await page.evaluate(() => window.painterPreview.updateEquation('x^3 + 1', 'comp-2'));
  await expect.poll(() => page.evaluate(() => window.painterPreview.preparations)).toBeGreaterThan(initial);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const prepared = await page.evaluate(() => window.painterPreview.preparations);
  await page.evaluate(() => window.painterPreview.updateCircle({ x: 440, fill: '#123456', fontSize: 60 }));
  await expect(circle(page)).toHaveAttribute('transform', 'translate(440 520) rotate(0)');
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  expect(await page.evaluate(() => window.painterPreview.preparations)).toBe(prepared);
  await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await page.getByRole('button', { name: 'Equation', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'LaTeX expression', exact: true })).toHaveValue('x^3 + 1');
});

test('failed resource preparation can be retried without changing or losing the edited content', async ({ page }) => {
  await open(page);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  await page.evaluate(() => { window.painterPreview.preparationError = true; window.painterPreview.updateEquation('x^4 + 2'); });
  await expect(page.getByRole('alert').filter({ hasText: 'Simulated resource failure' })).toBeVisible();
  await page.evaluate(() => { window.painterPreview.updateCircle({ x: 480 }); window.painterPreview.preparationError = false; });
  await page.getByRole('button', { name: '描画の準備を再試行', exact: true }).click();
  await expect(page.getByRole('alert').filter({ hasText: 'Simulated resource failure' })).toHaveCount(0);
  await expect(circle(page)).toHaveAttribute('transform', 'translate(480 520) rotate(0)');
  await page.getByRole('button', { name: 'Equation', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'LaTeX expression', exact: true })).toHaveValue('x^4 + 2');
});

test('replacing a hidden image defers preparation until it becomes visible', async ({ page }) => {
  await open(page);
  const images = await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = canvas.height = 8;
    const ctx = canvas.getContext('2d')!;
    return ['#ff0000', '#00ff00'].map(color => { ctx.fillStyle = color; ctx.fillRect(0, 0, 8, 8); return canvas.toDataURL(); });
  });
  await page.getByLabel('画像ファイル', { exact: true }).setInputFiles({ name: 'Asset.png', mimeType: 'image/png', buffer: Buffer.from(images[0].split(',')[1], 'base64') });
  await expect(page.getByRole('button', { name: 'Asset', exact: true })).toBeVisible();
  await expect(page.locator('.scene-svg image')).toHaveAttribute('href', /^data:image/);
  await page.getByRole('button', { name: 'Asset を非表示', exact: true }).click();
  await expect(page.locator('.scene-svg image')).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const prepared = await page.evaluate(() => window.painterPreview.preparations);
  await page.evaluate(src => window.painterPreview.replaceImage(src), images[1]);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  expect(await page.evaluate(() => window.painterPreview.preparations)).toBe(prepared);
  await page.getByRole('button', { name: 'Asset を表示', exact: true }).click();
  await expect(page.locator('.scene-svg image')).toHaveAttribute('href', images[1]);
  await expect.poll(() => page.evaluate(() => window.painterPreview.preparations)).toBeGreaterThan(prepared);
});

test('public useEditor accepts an external Context and keeps unchanged snapshots stable', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/tests/e2e/fixtures/editor-context.html');
  await expect(page.locator('output')).toHaveText('125:Alice');
  await page.getByRole('button', { name: 'Local render', exact: true }).click();
  await expect(page.getByTestId('stable')).toHaveText('true');
  await page.getByRole('button', { name: 'Update context', exact: true }).click();
  await expect(page.locator('output')).toHaveText('375:Bob');
  expect(errors).toEqual([]);
});

test('presence and playback notify their consumers without rendering document panels', async ({ page }) => {
  await countEditorRenders(page);
  await open(page);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const presence = await page.evaluate(async () => {
    window.renderCounts = {};
    await window.painterPreview.cursors(12);
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return window.renderCounts;
  });
  for (const name of ['studio', 'sidebar', 'inspector', 'timeline', 'media__timeline', 'studio__main', 'studio__dialogs', 'scene__tabs']) expect(presence[name] ?? 0, name).toBe(0);
  expect(presence.stage).toBeGreaterThan(0);
  await page.getByRole('button', { name: 'シーンを再生', exact: true }).click();
  await expect(page.getByRole('button', { name: '一時停止', exact: true })).toBeVisible();
  const playback = await page.evaluate(async () => {
    for (let i = 0; i < 4; i++) await new Promise(requestAnimationFrame);
    window.renderCounts = {};
    const before = Number(document.querySelector('.time-code strong')!.textContent!.replaceAll(',', ''));
    for (let i = 0; i < 24; i++) await new Promise(requestAnimationFrame);
    const after = Number(document.querySelector('.time-code strong')!.textContent!.replaceAll(',', ''));
    return { counts: window.renderCounts, before, after };
  });
  expect(playback.after).toBeGreaterThan(playback.before);
  for (const name of ['studio', 'sidebar', 'timeline', 'media__timeline', 'studio__main', 'studio__dialogs', 'scene__tabs', 'assistant__panel']) expect(playback.counts[name] ?? 0, name).toBe(0);
  await page.getByRole('button', { name: '一時停止', exact: true }).click();
  await page.getByRole('slider', { name: '再生位置', exact: true }).fill('2500');
  await expect(circle(page)).toHaveAttribute('transform', 'translate(955 190) rotate(0)');
  await page.getByRole('button', { name: 'この場面を編集', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Composition 2', exact: true })).toHaveAttribute('aria-pressed', 'true');
});

test('incoming chat updates and marking messages read stay inside the chat panel', async ({ page }) => {
  await countEditorRenders(page);
  await open(page);
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  for (const active of [false, true]) {
    if (active) {
      await page.getByRole('button', { name: 'Chat', exact: true }).click();
      await expect(page.getByLabel('1 件の未読', { exact: true })).toHaveCount(0);
    }
    await page.evaluate(active => { window.renderCounts = {}; window.painterPreview.message(active ? 'Visible message' : 'Unread message'); }, active);
    if (active) await expect(page.getByRole('log').getByText('Visible message', { exact: true })).toBeVisible();
    else await expect(page.getByLabel('1 件の未読', { exact: true })).toBeVisible();
    const counts = await page.evaluate(() => window.renderCounts);
    expect(counts.assistant__panel).toBeGreaterThan(0);
    for (const name of ['studio', 'sidebar', 'inspector', 'timeline', 'media__timeline', 'stage', 'studio__main', 'studio__dialogs', 'scene__tabs']) expect(counts[name] ?? 0, name).toBe(0);
  }
});

test('moving and recoloring retain SVG geometry; resizing and hiding update it', async ({ page }) => {
  await open(page);
  const group = await circle(page).elementHandle();
  const shape = await circle(page).locator('ellipse').elementHandle();
  const sibling = await page.locator('.scene-svg [data-object-id="sigmoid"]').elementHandle();
  await page.evaluate(() => window.painterPreview.updateCircle({ x: 430, fill: '#123456' }));
  await expect(circle(page)).toHaveAttribute('transform', 'translate(430 520) rotate(0)');
  await expect(circle(page)).toHaveAttribute('fill', '#123456');
  expect(await group!.evaluate(node => node === document.querySelector('.scene-svg [data-object-id="circle"]'))).toBe(true);
  expect(await shape!.evaluate(node => node === document.querySelector('.scene-svg [data-object-id="circle"] ellipse'))).toBe(true);
  expect(await sibling!.evaluate(node => node === document.querySelector('.scene-svg [data-object-id="sigmoid"]'))).toBe(true);
  await page.evaluate(() => window.painterPreview.updateCircle({ width: 160 }));
  await expect(circle(page).locator('ellipse')).toHaveAttribute('rx', '80');
  expect(await group!.evaluate(node => node.isConnected)).toBe(true);
  expect(await shape!.evaluate(node => node.isConnected)).toBe(false);
  await page.evaluate(() => window.painterPreview.updateCircle({ visible: false }));
  await expect(circle(page)).toHaveCount(0);
  await page.evaluate(() => window.painterPreview.updateCircle({ visible: true }));
  await expect(circle(page).locator('ellipse')).toHaveAttribute('rx', '80');
});

test('retained SVG and serialized export SVG produce identical pixels with transforms and Glow', async ({ page }) => {
  await open(page);
  await page.evaluate(() => window.painterPreview.updateCircle({ effect: 'glow', rotation: 23, scaleX: 1.3, scaleY: .8 }));
  await expect(circle(page)).toHaveAttribute('filter', /glow/);
  const difference = await page.evaluate(async () => {
    const source = document.querySelector('.scene-svg svg')!.outerHTML;
    async function pixels(svg: string) {
      const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
      try {
        const image = new Image(); image.src = url; await image.decode();
        const canvas = document.createElement('canvas'); canvas.width = 1280; canvas.height = 720;
        const context = canvas.getContext('2d')!; context.drawImage(image, 0, 0);
        return context.getImageData(0, 0, 1280, 720).data;
      } finally { URL.revokeObjectURL(url); }
    }
    const [view, reference] = await Promise.all([pixels(source), pixels(window.painterPreview.referenceSvg())]);
    return view.reduce((count, value, index) => count + Number(value !== reference[index]), 0);
  });
  expect(difference).toBe(0);
});

test('cursor updates keep the unchanged canvas and SVG frame instead of repainting the scene', async ({ page }) => {
  await open(page);
  for (const compare of [false, true]) {
    if (compare) await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
    const counts = await page.evaluate(async () => {
      const before = { svg: window.painterPreview.svgCalls, paint: window.painterPreview.renders.length };
      await window.painterPreview.cursors(12);
      return { svg: window.painterPreview.svgCalls - before.svg, paint: window.painterPreview.renders.length - before.paint };
    });
    expect(counts).toEqual({ svg: 0, paint: 0 });
  }
  // A real scene change must still invalidate both rendering paths.
  await page.getByRole('button', { name: 'Composition 1', exact: true }).click();
  await page.evaluate(() => window.painterPreview.positions([430]));
  await expect(circle(page)).toHaveAttribute('transform', 'translate(430 520) rotate(0)');
});

test('the Canvas and transparent SVG preserve selection, resize and Bézier editing', async ({ page }) => {
  await open(page);
  await expect(page.locator('.scene-hit-svg')).toHaveCSS('opacity', '0');
  await expect(page.locator('.scene-canvas')).toBeVisible();
  await circle(page).click();
  const handle = page.locator('[data-transform-handle="se"]'), box = await handle.boundingBox();
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2); await page.mouse.down();
  await page.mouse.move(box!.x + box!.width / 2 + 25, box!.y + box!.height / 2 + 25, { steps: 4 }); await page.mouse.up();
  await expect.poll(async () => Number(await page.getByRole('spinbutton', { name: 'Width', exact: true }).inputValue())).toBeGreaterThan(70);
  await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
  await expect(page.locator('[data-testid="stage-to"] .scene-hit-svg')).toHaveCount(1);
  await page.getByRole('button', { name: 'Edit Bézier path', exact: true }).click();
  const control = page.locator('[data-path-handle="c1"]'), before = await control.boundingBox();
  await page.mouse.move(before!.x + before!.width / 2, before!.y + before!.height / 2); await page.mouse.down();
  await page.mouse.move(before!.x + before!.width / 2, before!.y - 20, { steps: 3 }); await page.mouse.up();
  await expect.poll(async () => (await control.boundingBox())!.y).toBeLessThan(before!.y - 15);
});

test('slow painting coalesces pending frames and eventually displays the latest position', async ({ page }) => {
  await open(page);
  const result = await page.evaluate(async () => {
    const start = window.painterPreview.renders.length;
    window.painterPreview.delay = 80;
    await window.painterPreview.positions([300, 320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520]);
    return { start };
  });
  await expect(circle(page)).toHaveAttribute('transform', 'translate(520 520) rotate(0)');
  await expect.poll(() => page.evaluate(() => window.painterPreview.active)).toBe(0);
  const after = await page.evaluate(start => ({ calls: window.painterPreview.renders.slice(start), maximum: window.painterPreview.maximumConcurrentPerInstance }), result.start);
  expect(after.maximum).toBe(1);
  expect(after.calls.length).toBeLessThan(10);
  expect(after.calls.at(-1)?.x).toBe(520);
  expect(after.calls.at(-1)?.finished).toBe(true);
});

test('switching compositions aborts the old painter and cannot publish its old position', async ({ page }) => {
  await open(page);
  await page.evaluate(async () => { window.painterPreview.hold = true; await window.painterPreview.positions([390]); });
  await expect.poll(() => page.evaluate(() => window.painterPreview.renders.some(item => item.x === 390 && !item.finished))).toBe(true);
  await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await page.evaluate(() => window.painterPreview.release());
  await expect(page.locator('[data-testid="stage-main"] .scene-hit-svg')).toHaveCount(1);
  await expect(circle(page)).toHaveAttribute('transform', 'translate(955 190) rotate(0)');
  const report = await page.evaluate(() => ({ disposals: window.painterPreview.disposals, staleAborted: window.painterPreview.renders.some(item => item.x === 390 && item.aborted), active: window.painterPreview.active }));
  expect(report.disposals).toBeGreaterThanOrEqual(1); expect(report.staleAborted).toBe(true); expect(report.active).toBe(0);
});

test('a painter error restores the current SVG and keeps subsequent edits usable', async ({ page }) => {
  await open(page);
  await page.evaluate(async () => { window.painterPreview.failNext = true; await window.painterPreview.positions([390]); });
  await expect(page.locator('.scene-hit-svg')).toHaveCount(0);
  await expect(page.locator('.scene-canvas')).not.toBeVisible();
  await expect(circle(page)).toHaveAttribute('transform', 'translate(390 520) rotate(0)');
  await circle(page).click();
  await page.getByRole('spinbutton', { name: 'Position X', exact: true }).fill('420');
  await page.getByRole('spinbutton', { name: 'Position X', exact: true }).press('Tab');
  await expect(circle(page)).toHaveAttribute('transform', 'translate(420 520) rotate(0)');
});

test('the backing canvas follows viewport size and device pixel density', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  const page = await context.newPage(); await open(page);
  for (const viewport of [{ width: 1440, height: 900 }, { width: 1100, height: 800 }]) {
    await page.setViewportSize(viewport);
    await expect.poll(() => page.locator('[data-testid="stage-main"] .scene-canvas').evaluate((canvas: HTMLCanvasElement) => Math.abs(canvas.width - canvas.getBoundingClientRect().width * devicePixelRatio))).toBeLessThan(1);
    await expect(page.locator('[data-testid="stage-main"] .scene-hit-svg')).toHaveCount(1);
  }
  await context.close();
});

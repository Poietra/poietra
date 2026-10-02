import { expect, test, type Locator, type Page } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import { applyChanges, readProject } from '../../shared/document';

async function open(page: Page) {
  await page.goto(`/?room=${crypto.randomUUID()}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(page.locator('[data-testid="stage-main"] [data-object-id="circle"]')).toBeVisible();
}
async function field(page: Page, name: string, value: number) {
  const input = page.getByRole('spinbutton', { name, exact: true });
  await input.fill(String(value)); await input.press('Tab');
}
async function center(locator: Locator) {
  const box = await locator.boundingBox(); expect(box).not.toBeNull();
  return { x: box!.x + box!.width / 2, y: box!.y + box!.height / 2 };
}
async function drag(page: Page, locator: Locator, dx: number, dy: number) {
  const at = await center(locator);
  await page.mouse.move(at.x, at.y); await page.mouse.down();
  await page.mouse.move(at.x + dx, at.y + dy, { steps: 5 }); await page.mouse.up();
}
function shape(page: Page, id = 'circle', stage = 'main') { return page.locator(`[data-testid="stage-${stage}"] .scene-svg [data-object-id="${id}"]`); }
async function origin(page: Page, id = 'circle') {
  const transform = await shape(page, id).getAttribute('transform');
  const result = /translate\(([-\d.]+) ([-\d.]+)\)/.exec(transform || '');
  return { x: Number(result![1]), y: Number(result![2]) };
}

async function peer(page: Page) {
  const doc = new Y.Doc(), endpoint = new URL(page.url());
  const room = endpoint.searchParams.get('room')!;
  endpoint.protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:'; endpoint.pathname = '/sync'; endpoint.search = '';
  const provider = new WebsocketProvider(endpoint.toString(), room, doc, { WebSocketPolyfill: WebSocket as never, disableBc: true });
  const close = () => { provider.destroy(); doc.destroy(); };
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Canvas peer did not sync')), 10000);
      provider.on('sync', synced => { if (synced) { clearTimeout(timer); resolve(); } });
    });
  } catch (error) { close(); throw error; }
  return { doc, scene: () => readProject(doc)!.scenes['scene-1'], close };
}

test('resize starts from a committed draft and preserves peer fields through Undo and lock cancellation', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Circle', exact: true }).click();
  const data = await peer(page);
  try {
    const composition = data.scene().compositionOrder[0];
    const state = () => data.scene().compositions[composition].states.circle;
    const initial = structuredClone(state());
    const statePath = ['scenes', 'scene-1', 'compositions', composition, 'states', 'circle'];
    const width = page.getByRole('spinbutton', { name: 'Width', exact: true });
    const stage = page.getByTestId('stage-main');
    // Pointer focus must commit the draft before capturing the resize baseline.
    await width.fill('90');
    const at = await center(stage.locator('[data-transform-handle="se"]'));
    await page.mouse.move(at.x, at.y); await page.mouse.down();
    await expect.poll(() => state().width).toBe(90);
    await page.mouse.move(at.x + 20, at.y + 10, { steps: 3 });
    await expect.poll(() => state().width).toBeGreaterThan(90);
    applyChanges(data.doc, [
      { path: [...statePath, 'fill'], value: '#f4ce55' },
      { path: [...statePath, 'fontSize'], value: 91 },
    ], 'peer');
    await expect(shape(page)).toHaveAttribute('fill', '#f4ce55');
    await page.mouse.move(at.x + 40, at.y + 20, { steps: 3 }); await page.mouse.up();
    await expect.poll(() => state().width).toBeGreaterThan(130);
    expect(state()).toMatchObject({ fill: '#f4ce55', fontSize: 91 });
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect.poll(() => state().width).toBe(90);
    expect(state()).toMatchObject({ x: initial.x, y: initial.y, fill: '#f4ce55', fontSize: 91 });

    const next = await center(stage.locator('[data-transform-handle="se"]'));
    await page.mouse.move(next.x, next.y); await page.mouse.down();
    await page.mouse.move(next.x + 25, next.y + 15, { steps: 3 });
    await expect.poll(() => state().width).toBeGreaterThan(90);
    applyChanges(data.doc, [{ path: ['scenes', 'scene-1', 'objects', 'circle', 'locked'], value: true }], 'peer');
    await expect(stage.locator('[data-transform-handle]')).toHaveCount(0);
    await page.mouse.move(next.x + 35, next.y + 20); await page.mouse.up();
    await expect(stage.locator('.stage-feedback')).toHaveAttribute('data-feedback-state', 'cancelled');
    await expect.poll(() => state().width).toBe(90);
    expect(state()).toMatchObject({ x: initial.x, y: initial.y, fill: '#f4ce55', fontSize: 91 });
    expect(data.scene().objects.circle.locked).toBe(true);
    // Cancellation must leave the earlier draft edit available as the next Undo.
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect.poll(() => state().width).toBe(initial.width);
    expect(state()).toMatchObject({ fill: '#f4ce55', fontSize: 91 });
  } finally { data.close(); }
});

for (const transition of [false, true]) test(`Bézier gestures retain the other peer-edited control point on cancellation (transition=${transition})`, async ({ page }) => {
  await open(page);
  await page.getByRole('button', { name: transition ? 'Circle' : 'Sigmoid path', exact: true }).click();
  if (transition) {
    await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
    await page.getByRole('button', { name: 'Edit Bézier path', exact: true }).click();
  }
  const data = await peer(page);
  try {
    const composition = data.scene().compositionOrder[0];
    const path = () => transition ? data.scene().transitions['transition-1'].tracks.circle.path! : data.scene().compositions[composition].states.sigmoid.path;
    const base = ['scenes', 'scene-1', ...(transition ? ['transitions', 'transition-1', 'tracks', 'circle'] : ['compositions', composition, 'states', 'sigmoid']), 'path'];
    const initial = structuredClone(path());
    const handle = page.locator('[data-path-handle="c1"]'), other = page.locator('[data-path-handle="c2"]');
    const at = await center(handle), beforeOther = await center(other);
    await page.mouse.move(at.x, at.y); await page.mouse.down();
    await page.mouse.move(at.x + 20, at.y - 10, { steps: 3 });
    await expect.poll(() => path().c1).not.toEqual(initial.c1);
    const c2 = { x: initial.c2.x + 20, y: initial.c2.y + 30 };
    applyChanges(data.doc, [{ path: [...base, 'c2', 'x'], value: c2.x }, { path: [...base, 'c2', 'y'], value: c2.y }], 'peer');
    await expect.poll(() => center(other)).not.toEqual(beforeOther);
    await page.mouse.move(at.x + 35, at.y - 20, { steps: 3 });
    await expect.poll(async () => (await center(handle)).x - at.x).toBeCloseTo(35, 0);
    await expect.poll(async () => (await center(handle)).y - at.y).toBeCloseTo(-20, 0);
    await page.keyboard.press('Escape'); await page.mouse.up();
    await expect.poll(() => path()).toEqual({ c1: initial.c1, c2 });
  } finally { data.close(); }
});

test('resize keeps the opposite corner fixed, rotation snaps, and each gesture can be undone', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Circle', exact: true }).click();
  const fixed = await center(page.locator('[data-transform-handle="nw"]'));
  await drag(page, page.locator('[data-transform-handle="se"]'), 40, 25);
  await expect.poll(async () => Number(await page.getByRole('spinbutton', { name: 'Width', exact: true }).inputValue())).toBeGreaterThan(80);
  const after = await center(page.locator('[data-transform-handle="nw"]'));
  expect(after.x).toBeCloseTo(fixed.x, 1); expect(after.y).toBeCloseTo(fixed.y, 1);
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'Width', exact: true })).toHaveValue('42');
  const pivot = await center(shape(page)); const handle = await center(page.locator('[data-transform-handle="rotate"]'));
  const distance = Math.hypot(handle.x - pivot.x, handle.y - pivot.y);
  await page.mouse.move(handle.x, handle.y); await page.mouse.down(); await page.keyboard.down('Shift');
  await page.mouse.move(pivot.x + distance, pivot.y, { steps: 5 }); await page.mouse.up(); await page.keyboard.up('Shift');
  await expect(page.getByRole('spinbutton', { name: 'Rotation', exact: true })).toHaveValue('90');
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'Rotation', exact: true })).toHaveValue('0');
});

test('equation corner handles scale visible glyphs using font size', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await page.getByRole('button', { name: 'Equation', exact: true }).click();
  const before = await shape(page, 'equation').boundingBox();
  await drag(page, page.locator('[data-transform-handle="se"]'), 45, 10);
  await expect.poll(async () => Number(await page.getByRole('spinbutton', { name: 'Font size', exact: true }).inputValue())).toBeGreaterThan(50);
  await expect.poll(async () => (await shape(page, 'equation').boundingBox())!.width).toBeGreaterThan(before!.width + 20);
});

test('linked objects move together and locked objects expose no transform handles', async ({ page }) => {
  await open(page);
  await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await page.getByRole('button', { name: 'Sigmoid path', exact: true }).click({ modifiers: ['Shift'] });
  await page.getByRole('button', { name: 'Group', exact: true }).click();
  await page.getByRole('button', { name: 'Circle', exact: true }).click();
  const initialCircle = await origin(page), initialPath = await origin(page, 'sigmoid');
  await drag(page, shape(page), 35, -20);
  const movedCircle = await origin(page), movedPath = await origin(page, 'sigmoid');
  expect(movedCircle.x - initialCircle.x).toBeGreaterThan(30);
  expect(movedCircle.x - initialCircle.x).toBeCloseTo(movedPath.x - initialPath.x, 1);
  expect(movedCircle.y - initialCircle.y).toBeCloseTo(movedPath.y - initialPath.y, 1);
  await page.getByRole('button', { name: 'ロック', exact: true }).click();
  await expect(page.locator('[data-transform-handle]')).toHaveCount(0);
  await drag(page, shape(page), 30, 10);
  expect(await origin(page)).toEqual(movedCircle); expect(await origin(page, 'sigmoid')).toEqual(movedPath);
});

test('Escape cancels an active transform and pointer cancellation never creates a drawing', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Circle', exact: true }).click();
  const initial = await origin(page), at = await center(shape(page));
  await page.mouse.move(at.x, at.y); await page.mouse.down(); await page.mouse.move(at.x + 60, at.y - 25, { steps: 4 });
  expect((await origin(page)).x).toBeGreaterThan(initial.x);
  await page.keyboard.press('Escape'); await page.mouse.up();
  expect(await origin(page)).toEqual(initial);
  await page.getByRole('button', { name: '四角形 (R)', exact: true }).click();
  const stage = page.getByTestId('stage-main'), start = await center(stage);
  await page.mouse.move(start.x, start.y); await page.mouse.down(); await page.mouse.move(start.x + 50, start.y + 30, { steps: 4 });
  await expect(shape(page, 'drawing-preview')).toBeVisible();
  await stage.dispatchEvent('pointercancel', { pointerId: 1 }); await page.mouse.up();
  await expect(stage.locator('.scene-svg [data-object-id]')).toHaveCount(2);
  await expect(page.getByRole('button', { name: 'Rectangle 1', exact: true })).toHaveCount(0);
  // The canceled gesture must not absorb the next real edit into its undo entry.
  await page.keyboard.press('Escape'); await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await field(page, 'Position X', 330); await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  expect(await origin(page)).toEqual(initial);
});

test('a rotated Bézier handle follows the cursor without jumping into unrotated coordinates', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Sigmoid path', exact: true }).click();
  await field(page, 'Position X', 250); await field(page, 'Position Y', 250); await field(page, 'Rotation', 30);
  const handle = page.locator('[data-path-handle="c1"]'); const before = await center(handle);
  await drag(page, handle, 30, -10);
  const after = await center(handle);
  expect(after.x - before.x).toBeCloseTo(30, 0); expect(after.y - before.y).toBeCloseTo(-10, 0);
  const curve = await shape(page, 'sigmoid').locator('path').getAttribute('d');
  expect(curve).toMatch(/710 -330$/);
});

test('a paused transition frame can be selected without changing the destination state', async ({ page }) => {
  await open(page); await page.getByRole('button', { name: 'Circle', exact: true }).click();
  await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
  const slider = page.getByRole('slider', { name: 'Transition preview position', exact: true });
  await slider.fill('300');
  const circle = shape(page, 'circle', 'to');
  const before = await circle.getAttribute('transform'); await drag(page, circle, 35, 10);
  await expect(circle).toHaveAttribute('transform', before!);
  await expect(page.locator('[data-testid="stage-to"] [data-transform-handle]')).toHaveCount(0);
  await page.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue('955');
});

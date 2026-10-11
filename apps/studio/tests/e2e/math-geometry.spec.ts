import { chooseOption } from './select';
import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { geometryProject } from '../geometry-fixture';
import { defaultState } from '../../shared/model';

const choose = (page: Page, name: string) => page.getByRole('button', { name, exact: true }).click();
const element = (page: Page) => page.getByRole('combobox', { name: 'Geometry element', exact: true });
const coordinate = (page: Page, axis: string) => page.getByRole('spinbutton', { name: `Geometry point ${axis}`, exact: true });
const handle = (page: Page, id: string) => page.locator(`[data-testid="stage-main"] [data-geometry-handle="${id}"]`);
const curve = (page: Page, id: string) => page.locator(`[data-testid="stage-main"] .scene-svg [data-geometry-element="${id}"]`);
async function live(page: Page, url = `/?room=${crypto.randomUUID()}`) {
  await page.goto(url); await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
}
async function imported(page: Page, project = geometryProject()) {
  await live(page); await choose(page, 'プロジェクトを開く');
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'geometry.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await choose(page, 'Mathematical diagram'); await expect(element(page)).toBeVisible();
}
async function target(page: Page, x: number, y: number) {
  return page.locator('[data-testid="stage-main"] .scene-svg [data-object-id="diagram"]').evaluate((node, { x, y }) => {
    const point = new DOMPoint(x * 45, -y * 45).matrixTransform((node as SVGGraphicsElement).getScreenCTM()!);
    return { x: point.x, y: point.y };
  }, { x, y });
}
async function drag(page: Page, id: string, point: { x: number; y: number }, cancel = false) {
  const box = await handle(page, id).boundingBox(); expect(box).not.toBeNull();
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2); await page.mouse.down();
  await page.mouse.move(point.x, point.y, { steps: 8 });
  if (cancel) await page.keyboard.press('Escape');
  await page.mouse.up();
}
async function saved(page: Page) {
  await choose(page, 'プロジェクトを開く');
  const download = page.waitForEvent('download'); await choose(page, 'Save project');
  return readFile((await (await download).path())!);
}

test('one searchable mathematics menu creates an editable diagram and keeps the equation shortcut', async ({ page }) => {
  await live(page); await choose(page, '数学');
  const dialog = page.getByRole('dialog', { name: '数学の表現を追加' });
  await expect(dialog).toBeVisible();
  await page.getByRole('searchbox', { name: '数学の表現を検索' }).fill('中点');
  await expect(dialog.getByRole('button', { name: '幾何の図', exact: true })).toBeVisible();
  await expect(dialog.getByRole('button', { name: '数式グラフ', exact: true })).toHaveCount(0);
  await choose(page, '幾何の図'); await expect(dialog).toHaveCount(0);
  const box = await page.getByTestId('stage-main').boundingBox();
  await page.mouse.click(box!.x + box!.width * .5, box!.y + box!.height * .35);
  await expect(element(page)).toHaveAttribute('data-value', 'points/a');
  await expect(page.locator('[data-testid="stage-main"] [data-geometry-handle]')).toHaveCount(3);
  await choose(page, '中点を追加');
  await expect(page.getByTestId('geometry-value')).toContainText('中点');
  await page.getByRole('spinbutton', { name: 'Position X', exact: true }).blur();
  await page.getByTestId('stage-main').focus(); await page.keyboard.press('e');
  await page.mouse.click(box!.x + box!.width * .8, box!.y + box!.height * .25);
  await expect(page.getByRole('textbox', { name: 'LaTeX expression', exact: true })).toBeFocused();
});

test('point gestures update dependent elements, synchronize peers, selectively undo and cancel, then save and reload semantic data', async ({ page, browser }) => {
  test.setTimeout(60000); await imported(page);
  const peerContext = await browser.newContext();
  try {
    const peer = await peerContext.newPage(); await live(peer, page.url()); await choose(peer, 'Mathematical diagram');
    const before = await curve(page, 'vectors/ab').getAttribute('d');
    await drag(page, 'a', await target(page, 0, -1));
    await expect.poll(async () => Number(await coordinate(page, 'X').inputValue())).toBeCloseTo(0, 5);
    await expect.poll(async () => Number(await coordinate(peer, 'X').inputValue())).toBeCloseTo(0, 5);
    await expect(curve(page, 'vectors/ab')).not.toHaveAttribute('d', before!);
    await chooseOption(element(page), 'points/m'); await expect(page.getByTestId('geometry-value')).toContainText('中点：(1, -1)');
    await chooseOption(element(peer), 'points/b');
    await peer.getByRole('textbox', { name: 'Geometry element label', exact: true }).fill('Peer B');
    await chooseOption(element(page), 'points/b'); await expect(page.getByRole('textbox', { name: 'Geometry element label', exact: true })).toHaveValue('Peer B');
    await choose(page, '元に戻す (⌘Z)'); await expect(curve(page, 'vectors/ab')).toHaveAttribute('d', before!);
    await expect(page.getByRole('textbox', { name: 'Geometry element label', exact: true })).toHaveValue('Peer B');
    await chooseOption(element(page), 'points/a');
    await drag(page, 'a', await target(page, 1, 0), true);
    await expect.poll(async () => Number(await coordinate(page, 'X').inputValue())).toBeCloseTo(-2, 5);
    await chooseOption(element(page), 'points/m');
    await chooseOption(page.getByRole('combobox', { name: 'Geometry First point', exact: true }), 'm');
    await expect(page.getByRole('alert').filter({ hasText: '循環' })).toBeVisible();
    await expect(page.getByRole('combobox', { name: 'Geometry First point', exact: true })).toHaveAttribute('data-value', 'a');
    const bytes = await saved(page), project = JSON.parse(bytes.toString());
    expect(project.version).toBe(5);
    expect(project.scenes['scene-1'].compositions['comp-1'].states.diagram.geometry.points.b.label).toBe('Peer B');
    expect(bytes.toString()).not.toMatch(/"(?:curves|world|unresolved)":/);
    await page.reload(); await expect(page.getByText('Live', { exact: true })).toBeVisible();
    await choose(page, 'Mathematical diagram'); await chooseOption(element(page), 'points/b');
    await expect(page.getByRole('textbox', { name: 'Geometry element label', exact: true })).toHaveValue('Peer B');
    await choose(page, 'プロジェクトを開く');
    await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'geometry.poietra.json', mimeType: 'application/json', buffer: bytes });
    await expect(page.getByText('Live', { exact: true })).toBeVisible(); await choose(page, 'Mathematical diagram');
    await expect(curve(page, 'vectors/ab')).toHaveAttribute('d', before!);
  } finally { await peerContext.close(); }
});

test('point gestures invert parent affine transforms and clipped or locked points have no drag handles', async ({ page }) => {
  const project = geometryProject(), scene = project.scenes['scene-1'];
  scene.objects.clip = { id: 'clip', name: 'Clip', kind: 'rectangle', order: -1, groupId: null, locked: false, clipChildren: true };
  scene.objects.diagram.parentId = 'clip';
  for (const composition of Object.values(scene.compositions)) {
    composition.states.clip = defaultState('rectangle', { x: 640, y: 360, width: 200, height: 200, rotation: 25, scaleX: 1.4, scaleY: .8, visible: false });
    Object.assign(composition.states.diagram, { x: 0, y: 0, rotation: -10, scaleX: .9, scaleY: 1.1 });
  }
  await imported(page, project); await drag(page, 'a', await target(page, -1, 0));
  await expect.poll(async () => Number(await coordinate(page, 'X').inputValue())).toBeCloseTo(-1, 5);
  await expect.poll(async () => Number(await coordinate(page, 'Y').inputValue())).toBeCloseTo(0, 5);
  await chooseOption(element(page), 'points/b'); await coordinate(page, 'X').fill('4'); await coordinate(page, 'X').press('Tab');
  await expect(handle(page, 'b')).toHaveCount(0); await expect(handle(page, 'a')).toHaveCount(1);
  await choose(page, 'ロック'); await expect(page.locator('[data-testid="stage-main"] [data-geometry-handle]')).toHaveCount(0);
});

for (const fallback of [false, true]) test(`semantic diagrams agree between SVG and ${fallback ? 'Canvas fallback' : 'GPU painter'} during Write and coordinate changes`, async ({ page }) => {
  if (fallback) await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(this: HTMLCanvasElement, kind: string, ...args: unknown[]) {
      if (kind === 'webgl2') return null;
      return (original as Function).apply(this, [kind, ...args]);
    } as typeof original;
  });
  await page.goto('/');
  const report = await page.evaluate(async project => {
    const { compositionFrame } = await import('/src/engine/evaluate.js' as string);
    const { frameToSvg, prepareScene } = await import('/src/engine/renderer.js' as string);
    const { createFramePainter } = await import('/src/engine/painter.js' as string);
    const scene = project.scenes['scene-1']; Object.assign(scene, { width: 320, height: 180, background: '#000000' });
    const state = scene.compositions['comp-1'].states.diagram;
    Object.assign(state, { x: 160, y: 90, width: 240, height: 120, stroke: '#ffffff', fill: '#ffffff', strokeWidth: 3 });
    await prepareScene(scene);
    const canvas = document.createElement('canvas'); canvas.width = 320; canvas.height = 180;
    const painter = await createFramePainter(canvas);
    const samples: { canvas: number[]; svg: number[]; expected: number }[] = [];
    try {
      for (const [aX, aY, progress, opacity, x, y, expected] of [
        [-2, -1, 1, 1, 145, 105, 255], [0, 1, 1, 1, 175, 90, 255], [0, 1, 1, 1, 145, 105, 0],
        [-2, -1, .5, 1, 145, 105, 255], [-2, -1, .5, 1, 180, 105, 0], [-2, -1, 0, 1, 145, 105, 0],
        [-2, -1, 1, .5, 145, 105, 128],
      ]) {
        Object.assign(state.geometry!.points.a, { x: aX, y: aY }); state.opacity = opacity;
        const frame = compositionFrame(scene, scene.compositions['comp-1']); frame.objects[0].writeProgress = progress;
        await painter.render(frame);
        const reference = document.createElement('canvas'); reference.width = 320; reference.height = 180;
        const url = URL.createObjectURL(new Blob([frameToSvg(frame)], { type: 'image/svg+xml' }));
        try {
          const image = new Image(); image.src = url; await image.decode(); reference.getContext('2d')!.drawImage(image, 0, 0);
          const pixel = (target: HTMLCanvasElement) => [...target.getContext('2d')!.getImageData(x, y, 1, 1).data];
          samples.push({ canvas: pixel(canvas), svg: pixel(reference), expected });
        } finally { URL.revokeObjectURL(url); }
      }
      return { backend: painter.backend, samples };
    } finally { painter.dispose(); }
  }, geometryProject());
  expect(report.backend).toBe(fallback ? 'canvas2d' : 'webgl2');
  for (const sample of report.samples) {
    for (const values of [sample.canvas, sample.svg]) expect(Math.abs(values[0] - sample.expected)).toBeLessThanOrEqual(1);
    sample.canvas.forEach((value, i) => expect(Math.abs(value - sample.svg[i])).toBeLessThanOrEqual(1));
  }
});

import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { graphProject } from '../graph-fixture';
import { defaultState } from '../../shared/model';

const select = (page: Page, name: string) => page.getByRole('button', { name, exact: true }).click();
const expression = (page: Page) => page.getByRole('textbox', { name: 'Graph expression' });
const curve = (page: Page, stage = 'main') => page.locator(`[data-testid="stage-${stage}"] .scene-svg [data-graph-curve]`);
async function live(page: Page, url = `/?room=${crypto.randomUUID()}`) {
  await page.goto(url); await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
}
async function number(page: Page, name: string, value: number) {
  const control = page.getByRole('spinbutton', { name, exact: true });
  await control.fill(String(value)); await control.press('Tab'); await expect(control).toHaveValue(String(value));
}
async function saved(page: Page) {
  await select(page, 'プロジェクトを開く');
  const downloading = page.waitForEvent('download'); await select(page, 'Save project');
  return readFile((await (await downloading).path())!);
}
async function importGraph(page: Page, project = graphProject()) {
  await live(page); await select(page, 'プロジェクトを開く');
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'graph.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await select(page, 'Function graph'); await expect(expression(page)).toHaveValue('x^3 - a*x');
}

const graphSelection = (page: Page) => page.locator('[data-testid="stage-main"] [data-selection-id="graph"]');
async function graphPoint(page: Page, x: number, y: number) {
  return curve(page).evaluate((path, { x, y }) => {
    const matrix = (path as SVGGraphicsElement).getScreenCTM()!;
    const point = new DOMPoint(x, y).matrixTransform(matrix);
    return { x: point.x, y: point.y };
  }, { x, y });
}
async function curvePoint(page: Page, x: number, offset: number) {
  return curve(page).evaluate((node, { x, offset }) => {
    const path = node as SVGPathElement, matrix = path.getScreenCTM()!;
    let low = 0, high = path.getTotalLength();
    for (let i = 0; i < 40; i++) {
      const mid = (low + high) / 2;
      if (path.getPointAtLength(mid).x < x * 560 / 6) low = mid; else high = mid;
    }
    const length = (low + high) / 2;
    const at = path.getPointAtLength(length), before = path.getPointAtLength(length - .25), after = path.getPointAtLength(length + .25);
    const point = new DOMPoint(at.x, at.y).matrixTransform(matrix);
    const dx = matrix.a * (after.x - before.x) + matrix.c * (after.y - before.y);
    const dy = matrix.b * (after.x - before.x) + matrix.d * (after.y - before.y);
    const magnitude = Math.hypot(dx, dy);
    return { x: point.x - dy / magnitude * offset, y: point.y + dx / magnitude * offset };
  }, { x, offset });
}
async function clearGraph(page: Page) {
  if (await graphSelection(page).count()) await page.getByRole('button', { name: 'Function graph', exact: true }).click({ modifiers: ['Shift'] });
  await expect(graphSelection(page)).toHaveCount(0);
}
async function clickAt(page: Page, point: { x: number; y: number }) { await page.mouse.click(point.x, point.y); }

test('picks near a thin graph curve and drags its selected empty viewport with peer sync, Undo and cancellation', async ({ page, browser }) => {
  await importGraph(page);
  await page.getByRole('checkbox', { name: 'Show axes', exact: true }).uncheck();
  await page.getByRole('checkbox', { name: 'Show grid', exact: true }).uncheck();
  const original = await curve(page).getAttribute('d');
  await clearGraph(page); await clickAt(page, await curvePoint(page, 1.4, 8));
  await expect(graphSelection(page)).toHaveCount(0);
  const near = await curvePoint(page, 1.4, 4);
  expect(await page.evaluate(at => document.elementFromPoint(at.x, at.y)?.closest('[data-object-id]')?.getAttribute('data-object-id') ?? null, near)).toBeNull();
  await clickAt(page, near); await expect(graphSelection(page)).toHaveCount(1);
  await expect(curve(page)).toHaveAttribute('d', original!);
  const context = await browser.newContext();
  try {
    const peer = await context.newPage(); await live(peer, page.url()); await select(peer, 'Function graph');
    const empty = await graphPoint(page, 31, -70);
    await page.mouse.move(empty.x, empty.y); await page.mouse.down();
    await page.mouse.move(empty.x + 36, empty.y, { steps: 6 }); await page.mouse.up();
    const x = page.getByRole('spinbutton', { name: 'Position X', exact: true });
    await expect.poll(async () => Number(await x.inputValue())).toBeGreaterThan(640);
    const moved = await x.inputValue();
    await expect(peer.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue(moved);
    await expect(graphSelection(page)).toHaveCount(1); await expect(curve(page)).toHaveAttribute('d', original!);
    await select(page, '元に戻す (⌘Z)'); await expect(x).toHaveValue('640');
    await expect(peer.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue('640');
    await page.mouse.move(empty.x, empty.y); await page.mouse.down();
    await page.mouse.move(empty.x + 24, empty.y, { steps: 4 });
    await expect.poll(async () => Number(await x.inputValue())).toBeGreaterThan(640);
    await page.keyboard.press('Escape'); await page.mouse.up(); await expect(x).toHaveValue('640');
    await expect(graphSelection(page)).toHaveCount(1);
  } finally { await context.close(); }
});

test('keeps graph picking in screen pixels across zoom, affine transforms and coefficient changes', async ({ page }) => {
  await importGraph(page);
  await page.getByRole('checkbox', { name: 'Show axes', exact: true }).uncheck();
  await page.getByRole('checkbox', { name: 'Show grid', exact: true }).uncheck();
  await number(page, 'Rotation', 37); await number(page, 'Scale X', 180); await number(page, 'Scale Y', 55);
  for (const zoom of ['0.5', '1.5']) {
    await page.getByRole('combobox', { name: 'キャンバスのズーム', exact: true }).selectOption(zoom);
    await clearGraph(page); await clickAt(page, await curvePoint(page, 1.4, 8));
    await expect(graphSelection(page)).toHaveCount(0);
    await clickAt(page, await curvePoint(page, 1.4, 4)); await expect(graphSelection(page)).toHaveCount(1);
  }
  const old = await curvePoint(page, 1.4, 4), previousCurve = await curve(page).getAttribute('d');
  await number(page, 'Graph parameter a', 1); await expect(curve(page)).not.toHaveAttribute('d', previousCurve!);
  await clearGraph(page); await clickAt(page, old); await expect(graphSelection(page)).toHaveCount(0);
  await clickAt(page, await curvePoint(page, 1.4, 4)); await expect(graphSelection(page)).toHaveCount(1);
  await number(page, 'Stroke width', 0); await clearGraph(page);
  await clickAt(page, await curvePoint(page, 1.4, 4)); await expect(graphSelection(page)).toHaveCount(0);
});

for (const foreground of [false, true]) test(`graph picking respects nested rotated clips and ${foreground ? 'foreground' : 'underlying'} painted objects`, async ({ page }) => {
  const project = graphProject(), scene = project.scenes['scene-1'];
  scene.objects = {
    ...scene.objects,
    frame: { id: 'frame', name: 'Outer frame', kind: 'rectangle', order: -2, groupId: null, locked: false, clipChildren: true },
    inner: { id: 'inner', name: 'Inner frame', kind: 'rectangle', order: -1, groupId: null, locked: false, clipChildren: true, parentId: 'frame' },
    circle: { id: 'circle', name: 'Overlap circle', kind: 'circle', order: foreground ? 2 : 0, groupId: null, locked: false },
  };
  scene.objects.graph.order = 1; scene.objects.graph.parentId = 'inner';
  for (const composition of Object.values(scene.compositions)) {
    composition.states.frame = defaultState('rectangle', { x: 640, y: 360, width: 300, height: 300, rotation: 23, visible: false, opacity: 0 });
    composition.states.inner = defaultState('rectangle', { x: 0, y: 0, width: 100, height: 150, rotation: -23, visible: false, opacity: 0 });
    composition.states.circle = defaultState('circle', { x: 640 + .4 * 560 / 6, y: 360 + (.4 * 3 - .4 ** 3) * 45, strokeWidth: 0 });
    Object.assign(composition.states.graph, { x: 0, y: 0 });
    Object.assign(composition.states.graph.graph!, { axes: false, grid: false });
  }
  await importGraph(page, project);
  await clearGraph(page); await clickAt(page, await curvePoint(page, .9, 0));
  await expect(graphSelection(page)).toHaveCount(0);
  await select(page, 'Function graph'); await clickAt(page, await graphPoint(page, 60, -40));
  await expect(graphSelection(page)).toHaveCount(0);
  await select(page, 'Function graph'); await clickAt(page, await graphPoint(page, -30, -40));
  await expect(graphSelection(page)).toHaveCount(1);
  await clearGraph(page); await clickAt(page, await curvePoint(page, .4, 4));
  await expect(page.locator('[data-testid="stage-main"] [data-selection-id="circle"]')).toHaveCount(1);
  await expect(graphSelection(page)).toHaveCount(0);
  await select(page, 'Function graph'); await clickAt(page, await curvePoint(page, .4, 4));
  await expect(page.locator('[data-testid="stage-main"] [data-selection-id="circle"]')).toHaveCount(1);
});

test('draws an editable function object, validates local drafts and reopens its version 4 definition', async ({ page }) => {
  await live(page); await select(page, '関数グラフ');
  const stage = await page.getByTestId('stage-main').locator('.scene-svg').boundingBox();
  expect(stage).not.toBeNull();
  await page.mouse.move(stage!.x + stage!.width * .3, stage!.y + stage!.height * .2); await page.mouse.down();
  await page.mouse.move(stage!.x + stage!.width * .75, stage!.y + stage!.height * .75, { steps: 8 }); await page.mouse.up();
  await expect(expression(page)).toHaveValue('x^3 - a*x'); await expect(curve(page)).toHaveCount(1);
  const original = await curve(page).getAttribute('d');
  await expression(page).fill('x+'); await expression(page).press('Enter');
  await expect(page.getByRole('alert').filter({ hasText: '指定してください' })).toBeVisible();
  await expect(curve(page)).toHaveAttribute('d', original!);
  await expression(page).fill('a*sin(x)+b'); await expression(page).press('Enter');
  await expect(expression(page)).toHaveValue('a*sin(x)+b');
  await expect(page.getByRole('alert').filter({ hasText: '指定してください' })).toHaveCount(0);
  await number(page, 'Graph parameter a', 2); await number(page, 'Graph parameter b', 1);
  await expect(curve(page)).not.toHaveAttribute('d', original!);
  const buffer = await saved(page), project = JSON.parse(buffer.toString());
  expect(project.version).toBe(4);
  const scene = project.scenes[project.sceneOrder[0]], graphs = Object.values(scene.objects).filter((o: any) => o.kind === 'graph') as { id: string }[];
  expect(graphs).toHaveLength(1);
  expect(scene.compositions['comp-1'].states[graphs[0].id].graph).toMatchObject({ expression: 'a*sin(x)+b', a: 2, b: 1 });
  expect(buffer.toString()).not.toContain('"segments"');
  const before = page.url();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'function.poietra.json', mimeType: 'application/json', buffer });
  await expect(page).not.toHaveURL(before); await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await select(page, scene.objects[graphs[0].id].name); await expect(expression(page)).toHaveValue('a*sin(x)+b');
  await expect(page.getByRole('spinbutton', { name: 'Graph parameter a', exact: true })).toHaveValue('2');
  await expect(curve(page)).toHaveCount(1);
  await page.screenshot({ path: test.info().outputPath('function-graph.png'), fullPage: true });
});

test('shares coefficients with a peer, preserves them through Undo and reload, and edits graph keyframes', async ({ page, browser }) => {
  await importGraph(page);
  const context = await browser.newContext(); const peer = await context.newPage();
  try {
    await live(peer, page.url()); await select(peer, 'Function graph');
    await expression(page).fill('a*sin(x)+b'); await expression(page).press('Enter');
    await expect(expression(peer)).toHaveValue('a*sin(x)+b');
    await number(peer, 'Graph parameter a', 5);
    await expect(page.getByRole('spinbutton', { name: 'Graph parameter a', exact: true })).toHaveValue('5');
    await select(page, '元に戻す (⌘Z)');
    await expect(expression(peer)).toHaveValue('x^3 - a*x');
    await expect(page.getByRole('spinbutton', { name: 'Graph parameter a', exact: true })).toHaveValue('5');
    await select(peer, 'Composition 2'); await number(peer, 'Graph parameter a', 7);
    await select(page, 'Transition 800 ms');
    await page.getByRole('combobox', { name: 'Animation property' }).selectOption('graph');
    await number(page, 'Graph parameters animation start', 100); await number(page, 'Graph parameters animation duration', 600);
    await page.getByRole('combobox', { name: 'Keyframe property' }).selectOption('graphA');
    await select(page, '中間点を追加');
    await number(page, 'Parameter a keyframe 1 value', 9);
    const slider = page.getByRole('slider', { name: 'Transition preview position', exact: true });
    await slider.fill('400'); await expect(curve(page, 'to')).toHaveCount(1);
    await page.reload(); await expect(page.getByText('Live', { exact: true })).toBeVisible();
    await select(page, 'Function graph'); await select(page, 'Transition 800 ms');
    await page.getByRole('combobox', { name: 'Animation property' }).selectOption('graph');
    await expect(page.getByRole('spinbutton', { name: 'Parameter a keyframe 1 value', exact: true })).toHaveValue('9');
    const project = JSON.parse((await saved(page)).toString()), scene = project.scenes['scene-1'];
    expect(scene.compositions['comp-1'].states.graph.graph.a).toBe(5);
    expect(scene.compositions['comp-2'].states.graph.graph.a).toBe(7);
    expect(scene.transitions['transition-1'].tracks.graph.graphTiming).toMatchObject({ start: 100, duration: 600 });
  } finally { await context.close(); }
});

for (const fallback of [false, true]) test(`mathematical curves agree between SVG and ${fallback ? 'Canvas fallback' : 'GPU painter'} with Write and discontinuities`, async ({ page }) => {
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
    const state = scene.compositions['comp-1'].states.graph;
    Object.assign(state, { x: 160, y: 90, width: 240, height: 120, fill: '#ffffff', stroke: '#ffffff', strokeWidth: 4 });
    Object.assign(state.graph!, { expression: 'a*x', a: 1, xMin: -2, xMax: 2, yMin: -2, yMax: 2, axes: false, grid: false });
    await prepareScene(scene);
    const canvas = document.createElement('canvas'); canvas.width = 320; canvas.height = 180;
    const painter = await createFramePainter(canvas);
    const samples: { canvas: number[]; svg: number[]; expected: number }[] = [];
    try {
      for (const [source, a, progress, opacity, x, y, expected] of [['a*x', 1, 1, 1, 100, 120, 255], ['a*x', 1, .5, 1, 220, 60, 0], ['1/x', 1, 1, 1, 160, 90, 0], ['1/x', 1, 1, 1, 220, 60, 255], ['a*x', 1, 1, .5, 100, 120, 128], ['a*x', 0, 1, .5, 100, 120, 0], ['a*x', 0, 1, .5, 100, 90, 128]] as const) {
        state.graph!.expression = source; state.graph!.a = a; state.opacity = opacity;
        state.graph!.breaks = source === '1/x' ? [0] : [];
        const frame = compositionFrame(scene, scene.compositions['comp-1']); frame.objects[0].writeProgress = progress;
        await painter.render(frame);
        const reference = document.createElement('canvas'); reference.width = 320; reference.height = 180;
        const url = URL.createObjectURL(new Blob([frameToSvg(frame)], { type: 'image/svg+xml' }));
        try {
          const image = new Image(); image.src = url; await image.decode(); reference.getContext('2d')!.drawImage(image, 0, 0);
          const pixel = (canvas: HTMLCanvasElement) => [...canvas.getContext('2d')!.getImageData(x, y, 1, 1).data];
          samples.push({ canvas: pixel(canvas), svg: pixel(reference), expected });
        } finally { URL.revokeObjectURL(url); }
      }
      return { backend: painter.backend, samples };
    } finally { painter.dispose(); }
  }, graphProject());
  expect(report.backend).toBe(fallback ? 'canvas2d' : 'webgl2');
  for (const sample of report.samples) {
    for (const values of [sample.canvas, sample.svg]) expect(Math.abs(values[0] - sample.expected)).toBeLessThanOrEqual(1);
    sample.canvas.forEach((value, i) => expect(Math.abs(value - sample.svg[i])).toBeLessThanOrEqual(1));
  }
});

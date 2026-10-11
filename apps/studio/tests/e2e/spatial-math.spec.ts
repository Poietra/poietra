import { chooseOption } from './select';
import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { spatialMathProject } from '../spatial-math-fixture';
import { defaultState } from '../../shared/model';

const choose = (page: Page, name: string) => page.getByRole('button', { name, exact: true }).click();
const element = (page: Page) => page.getByRole('combobox', { name: 'Network element', exact: true });
const coordinate = (page: Page, axis: string) => page.getByRole('spinbutton', { name: `Network node ${axis}`, exact: true });
const curve = (page: Page, id: string) => page.locator(`[data-testid="stage-main"] .scene-svg [data-geometry-element="${id}"]`);
const faces = (page: Page) => page.locator('[data-testid="stage-main"] .scene-svg [data-geometry-element^="faces/"]');
const expression = (page: Page) => page.getByRole('textbox', { name: 'Surface Z expression', exact: true });
const number = async (page: Page, name: string, value: number) => {
  const input = page.getByRole('spinbutton', { name, exact: true }); await input.fill(String(value)); await input.press('Tab');
};
async function live(page: Page, url = `/?room=${crypto.randomUUID()}`) {
  await page.goto(url); await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
}
async function imported(page: Page, kind: 'network' | 'surface', project = spatialMathProject(kind)) {
  await live(page); await choose(page, 'プロジェクトを開く');
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'mathematics.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await choose(page, kind === 'network' ? 'Network diagram' : '3D surface');
}
async function drag(page: Page, id: string, x: number, y: number, cancel = false) {
  const target = await page.locator('[data-testid="stage-main"] .scene-svg [data-object-id="diagram"]').evaluate((node, { x, y }) => {
    const point = new DOMPoint(x * 45, -y * 45).matrixTransform((node as SVGGraphicsElement).getScreenCTM()!);
    return { x: point.x, y: point.y };
  }, { x, y });
  const handle = page.locator(`[data-testid="stage-main"] [data-geometry-handle="${id}"]`);
  await expect(handle).toBeVisible(); const box = (await handle.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2); await page.mouse.down();
  await page.mouse.move(target.x, target.y, { steps: 8 });
  if (cancel) await page.keyboard.press('Escape');
  await page.mouse.up();
}
async function saved(page: Page) {
  await choose(page, 'プロジェクトを開く');
  const download = page.waitForEvent('download'); await choose(page, 'Save project');
  return readFile((await (await download).path())!);
}

test('the shared mathematics palette creates networks and 3D surfaces without adding toolbar buttons', async ({ page }) => {
  await live(page); await choose(page, '数学');
  const dialog = page.getByRole('dialog', { name: '数学の表現を追加' });
  await expect(dialog.getByRole('button', { name: 'グラフ理論の図', exact: true })).toBeVisible();
  await expect(dialog.getByRole('button', { name: '3D曲面', exact: true })).toBeVisible();
  await page.getByRole('searchbox', { name: '数学の表現を検索' }).fill('重み');
  await expect(dialog.getByRole('button', { name: 'グラフ理論の図', exact: true })).toBeVisible();
  await expect(dialog.getByRole('button', { name: '3D曲面', exact: true })).toHaveCount(0);
  await choose(page, 'グラフ理論の図');
  const box = (await page.getByTestId('stage-main').boundingBox())!;
  await page.mouse.click(box.x + box.width * .5, box.y + box.height * .35);
  await expect(element(page)).toHaveAttribute('data-value', 'nodes/a');
  await expect(page.locator('[data-testid="stage-main"] [data-geometry-handle]')).toHaveCount(3);
  await choose(page, '数学'); await page.getByRole('searchbox', { name: '数学の表現を検索' }).fill('');
  await page.screenshot({ path: test.info().outputPath('mathematics-palette.png'), fullPage: true });
  await choose(page, '3D曲面');
  await expect(dialog).toBeHidden();
  const surfaceBox = (await page.getByTestId('stage-main').boundingBox())!;
  await page.getByTestId('stage-main').click({ position: { x: surfaceBox.width * .6, y: surfaceBox.height * .5 } });
  await expect(expression(page)).toHaveValue('a*sin(x)*cos(y)');
  await chooseOption(page.getByRole('combobox', { name: 'Surface example', exact: true }), 'sphere');
  await expect(page.getByRole('combobox', { name: 'Surface kind', exact: true })).toHaveAttribute('data-value', 'parametric');
  await expect(page.getByRole('textbox', { name: 'Surface X expression', exact: true })).toHaveValue('a*cos(u)*sin(v)');
  await page.screenshot({ path: test.info().outputPath('surface-editor.png'), fullPage: true });
});

test('network node gestures sync, selectively undo and cancel, then loops, parallel edges and weights persist', async ({ page, browser }) => {
  test.setTimeout(60000); await imported(page, 'network');
  const context = await browser.newContext();
  try {
    const peer = await context.newPage(); await live(peer, page.url()); await choose(peer, 'Network diagram');
    const before = await curve(page, 'edges/ab').getAttribute('d');
    await drag(page, 'a', 0, -1);
    await expect.poll(async () => Number(await coordinate(peer, 'X').inputValue())).toBeCloseTo(0, 5);
    await expect(curve(page, 'edges/ab')).not.toHaveAttribute('d', before!);
    await chooseOption(element(peer), 'edges/ab');
    await peer.getByRole('textbox', { name: 'Network element label', exact: true }).fill('Peer edge');
    await chooseOption(element(page), 'edges/ab'); await expect(page.getByRole('textbox', { name: 'Network element label', exact: true })).toHaveValue('Peer edge');
    await choose(page, '元に戻す (⌘Z)'); await expect(curve(page, 'edges/ab')).toHaveAttribute('d', before!);
    await chooseOption(element(page), 'nodes/a'); await drag(page, 'a', 1, 0, true);
    await expect.poll(async () => Number(await coordinate(page, 'X').inputValue())).toBeCloseTo(-2, 5);
    await choose(page, 'この要素を削除'); await expect(page.getByRole('alert').filter({ hasText: '参照' })).toBeVisible();
    await choose(page, '辺を追加'); const loop = (await element(page).getAttribute('data-value'))!;
    await chooseOption(page.getByRole('combobox', { name: 'Network To node', exact: true }), 'a');
    await page.getByRole('checkbox', { name: 'Network Directed edge', exact: true }).check();
    await page.getByRole('checkbox', { name: 'Network Weighted edge', exact: true }).check();
    await number(page, 'Network edge weight', 7);
    await expect(curve(page, loop)).toHaveAttribute('d', /C/);
    await choose(page, '辺を追加'); const parallel = (await element(page).getAttribute('data-value'))!;
    await number(page, 'Network edge bend', 1);
    await expect(curve(page, parallel)).not.toHaveAttribute('d', before!);
    await chooseOption(element(page), 'nodes/a'); await expect(page.getByTestId('network-degree')).toContainText('入次数 2');
    await choose(page, '円形に配置'); await expect(coordinate(page, 'X')).toHaveValue('2.5');
    const bytes = await saved(page), project = JSON.parse(bytes.toString()), network = project.scenes['scene-1'].compositions['comp-1'].states.diagram.network;
    expect(project.version).toBe(6); expect(network.edges[loop.split('/')[1]]).toMatchObject({ from: 'a', to: 'a', directed: true, weight: 7 });
    expect(network.edges.ab.label).toBe('Peer edge'); expect(bytes.toString()).not.toMatch(/"(?:curves|triangles|world)":/);
    await page.reload(); await expect(page.getByText('Live', { exact: true })).toBeVisible(); await choose(page, 'Network diagram');
    await expect(curve(page, loop)).toHaveAttribute('d', /C/);
    await chooseOption(element(page), 'edges/ab'); await expect(page.getByRole('textbox', { name: 'Network element label', exact: true })).toHaveValue('Peer edge');
  } finally { await context.close(); }
});

test('surface formulas, presets and view edits sync independently, retain invalid drafts and survive save/import', async ({ page, browser }) => {
  test.setTimeout(60000); await imported(page, 'surface');
  const context = await browser.newContext();
  try {
    const peer = await context.newPage(); await live(peer, page.url()); await choose(peer, '3D surface');
    await expression(page).fill('a*(x^2-y^2)/4'); await expression(page).press('Enter');
    await expect(expression(peer)).toHaveValue('a*(x^2-y^2)/4');
    await number(peer, 'Surface Yaw', 95); await expect(page.getByRole('spinbutton', { name: 'Surface Yaw', exact: true })).toHaveValue('95');
    await choose(page, '元に戻す (⌘Z)'); await expect(expression(page)).toHaveValue('a*sin(x)*cos(y)');
    await expect(page.getByRole('spinbutton', { name: 'Surface Yaw', exact: true })).toHaveValue('95');
    await expression(page).fill('sin('); await expression(page).press('Enter');
    await expect(page.getByRole('alert').filter({ hasText: /式|括弧|引数/ })).toBeVisible();
    await expect(expression(page)).toHaveValue('sin('); await expect(expression(peer)).toHaveValue('a*sin(x)*cos(y)');
    await expression(page).focus(); await expression(page).press('Escape'); await expect(expression(page)).toHaveValue('a*sin(x)*cos(y)');
    await expression(page).fill('1/x'); await expression(page).press('Enter');
    await expect(page.getByTestId('surface-sampling')).toContainText('省略');
    await chooseOption(page.getByRole('combobox', { name: 'Surface example', exact: true }), 'torus');
    await expect(page.getByRole('textbox', { name: 'Surface Z expression', exact: true })).toHaveValue('b*sin(v)');
    await number(page, 'Surface Parameter b', .9);
    await page.getByRole('checkbox', { name: 'Surface Wireframe', exact: true }).uncheck();
    await expect(faces(page).first()).toHaveAttribute('stroke', 'none');
    const bytes = await saved(page), project = JSON.parse(bytes.toString()), surface = project.scenes['scene-1'].compositions['comp-1'].states.diagram.surface;
    expect(project.version).toBe(6); expect(surface).toMatchObject({ kind: 'parametric', b: .9, wireframe: false });
    expect(bytes.toString()).not.toMatch(/"(?:curves|triangles|world)":/);
    await page.reload(); await expect(page.getByText('Live', { exact: true })).toBeVisible(); await choose(page, '3D surface');
    await expect(expression(page)).toHaveValue('b*sin(v)');
    await choose(page, 'プロジェクトを開く');
    await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'surface.poietra.json', mimeType: 'application/json', buffer: bytes });
    await expect(page.getByText('Live', { exact: true })).toBeVisible(); await choose(page, '3D surface');
    await expect(page.getByRole('spinbutton', { name: 'Surface Parameter b', exact: true })).toHaveValue('0.9');
  } finally { await context.close(); }
});

test('network gestures invert parent affine transforms and omit clipped or locked node handles', async ({ page }) => {
  const project = spatialMathProject('network'), scene = project.scenes['scene-1'];
  scene.objects.clip = { id: 'clip', name: 'Clip', kind: 'rectangle', order: -1, groupId: null, locked: false, clipChildren: true };
  scene.objects.diagram.parentId = 'clip';
  for (const composition of Object.values(scene.compositions)) {
    composition.states.clip = defaultState('rectangle', { x: 640, y: 360, width: 200, height: 200, rotation: 25, scaleX: 1.4, scaleY: .8, visible: false });
    Object.assign(composition.states.diagram, { x: 0, y: 0, rotation: -10, scaleX: .9, scaleY: 1.1 });
  }
  await imported(page, 'network', project); await drag(page, 'a', -1, 0);
  await expect.poll(async () => Number(await coordinate(page, 'X').inputValue())).toBeCloseTo(-1, 5);
  await expect.poll(async () => Number(await coordinate(page, 'Y').inputValue())).toBeCloseTo(0, 5);
  await chooseOption(element(page), 'nodes/b'); await number(page, 'Network node X', 4);
  await expect(page.locator('[data-testid="stage-main"] [data-geometry-handle="b"]')).toHaveCount(0);
  await choose(page, 'ロック'); await expect(page.locator('[data-testid="stage-main"] [data-geometry-handle]')).toHaveCount(0);
});

for (const fallback of [false, true]) test(`networks and filled surfaces agree between SVG and ${fallback ? 'Canvas fallback' : 'GPU painter'} with Write, opacity and style changes`, async ({ page }) => {
  if (fallback) await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(this: HTMLCanvasElement, kind: string, ...args: unknown[]) {
      if (kind === 'webgl2') return null;
      return (original as Function).apply(this, [kind, ...args]);
    } as typeof original;
  });
  await page.goto('/');
  const report = await page.evaluate(async projects => {
    const { compositionFrame } = await import('/src/engine/evaluate.js' as string);
    const { frameToSvg, prepareScene } = await import('/src/engine/renderer.js' as string);
    const { createFramePainter } = await import('/src/engine/painter.js' as string);
    const canvas = document.createElement('canvas'); canvas.width = 320; canvas.height = 180;
    const painter = await createFramePainter(canvas);
    const samples: { canvas: number[]; svg: number[]; visible: boolean }[] = [];
    try {
      for (const project of projects) {
        const scene = project.scenes['scene-1']; Object.assign(scene, { width: 320, height: 180, background: '#000000' });
        const state = scene.compositions['comp-1'].states.diagram;
        Object.assign(state, { x: 160, y: 90, width: 240, height: 120, stroke: '#ffffff', fill: '#ffffff', strokeWidth: 2 });
        if (state.surface) Object.assign(state.surface, { zExpression: '0', yaw: 0, pitch: 45, steps: 8, uMin: -2, uMax: 2, vMin: -2, vMax: 2, axes: false, wireframe: false });
        await prepareScene(scene);
        for (const [progress, opacity, fill] of [[1, 1, '#ffffff'], [1, .5, '#ffffff'], [.5, 1, '#ffffff'], [0, 1, '#ffffff'], [1, 1, '#ff0000']] as const) {
          state.opacity = opacity; state.fill = fill;
          const frame = compositionFrame(scene, scene.compositions['comp-1']); frame.objects[0].writeProgress = progress;
          await painter.render(frame);
          const reference = document.createElement('canvas'); reference.width = 320; reference.height = 180;
          const url = URL.createObjectURL(new Blob([frameToSvg(frame)], { type: 'image/svg+xml' }));
          try {
            const image = new Image(); image.src = url; await image.decode(); reference.getContext('2d')!.drawImage(image, 0, 0);
            const [x, y] = state.network ? [132, 106] : [147, 87];
            const pixel = (target: HTMLCanvasElement) => [...target.getContext('2d')!.getImageData(x, y, 1, 1).data];
            samples.push({ canvas: pixel(canvas), svg: pixel(reference), visible: progress > 0 });
          } finally { URL.revokeObjectURL(url); }
        }
        if (state.surface) for (const torus of [false, true]) {
          Object.assign(state.surface, { kind: 'parametric',
            xExpression: torus ? '(a+b*cos(v))*cos(u)' : 'a*cos(u)*sin(v)',
            yExpression: torus ? '(a+b*cos(v))*sin(u)' : 'a*sin(u)*sin(v)',
            zExpression: torus ? 'b*sin(v)' : 'a*cos(v)',
            uMin: 0, uMax: 2 * Math.PI, vMin: 0, vMax: torus ? 2 * Math.PI : Math.PI,
            a: 2, b: .7, yaw: 35, pitch: torus ? 89 : 35, steps: 20, wireframe: true });
          state.fill = '#ffffff'; state.opacity = 1; state.strokeWidth = 1;
          const frame = compositionFrame(scene, scene.compositions['comp-1']); await painter.render(frame);
          const reference = document.createElement('canvas'); reference.width = 320; reference.height = 180;
          const url = URL.createObjectURL(new Blob([frameToSvg(frame)], { type: 'image/svg+xml' }));
          try {
            const image = new Image(); image.src = url; await image.decode(); reference.getContext('2d')!.drawImage(image, 0, 0);
            for (const [x, y, visible] of [[161, 91, !torus], [torus ? 190 : 170, 90, true], [torus ? 160 : 150, torus ? 60 : 95, true]] as const) {
              const pixel = (target: HTMLCanvasElement) => [...target.getContext('2d')!.getImageData(x, y, 1, 1).data];
              samples.push({ canvas: pixel(canvas), svg: pixel(reference), visible });
            }
          } finally { URL.revokeObjectURL(url); }
        }
      }
      return { backend: painter.backend, samples };
    } finally { painter.dispose(); }
  }, [spatialMathProject('network'), spatialMathProject('surface')]);
  expect(report.backend).toBe(fallback ? 'canvas2d' : 'webgl2');
  for (const sample of report.samples) {
    for (const values of [sample.canvas, sample.svg]) expect(values[0] > 20).toBe(sample.visible);
    sample.canvas.forEach((value, i) => expect(Math.abs(value - sample.svg[i])).toBeLessThanOrEqual(2));
  }
});

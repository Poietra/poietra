import { expect, test } from '@playwright/test';
import { clippingProject } from '../clipping-fixture';

test('clipping can be toggled, undone, shared and selected through the retained SVG', async ({ page, browser }) => {
  await page.goto(`/?room=${crypto.randomUUID()}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'clip.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(clippingProject())) });
  await expect(page.getByRole('button', { name: 'Clipping frame', exact: true })).toBeVisible();
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Clipping frame', exact: true }).click();
  const checkbox = page.getByRole('checkbox', { name: 'Clip children' });
  await expect(checkbox).toBeChecked();
  const clip = page.locator('[data-testid="stage-main"] .scene-svg g[clip-path]');
  await expect(clip).toHaveCount(1);
  await checkbox.uncheck(); await expect(clip).toHaveCount(0);
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(checkbox).toBeChecked(); await expect(clip).toHaveCount(1);
  const context = await browser.newContext();
  try {
    const peer = await context.newPage(); await peer.goto(page.url());
    await expect(peer.getByText('Live', { exact: true })).toBeVisible();
    await peer.getByRole('button', { name: 'Clipping frame', exact: true }).click();
    await expect(peer.getByRole('checkbox', { name: 'Clip children' })).toBeChecked();
    await peer.getByRole('checkbox', { name: 'Clip children' }).uncheck();
    await expect(checkbox).not.toBeChecked();
  } finally { await context.close(); }
});

for (const fallback of [false, true]) test(`clipping agrees across SVG and ${fallback ? 'Canvas fallback' : 'GPU painter'} including Glow`, async ({ page }) => {
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
    const scene = project.scenes['scene-1']; await prepareScene(scene);
    const canvas = document.createElement('canvas'); canvas.width = 200; canvas.height = 160;
    const painter = await createFramePainter(canvas);
    const pixel = (ctx: CanvasRenderingContext2D, x: number, y: number) => [...ctx.getImageData(x, y, 1, 1).data];
    const samples = [];
    try {
      for (const effect of ['none', 'glow']) {
        scene.compositions['comp-1'].states.child.effect = effect as 'none' | 'glow';
        const frame = compositionFrame(scene, scene.compositions['comp-1']);
        await painter.render(frame);
        const output = canvas.getContext('2d')!;
        const svg = document.createElement('canvas'); svg.width = 200; svg.height = 160;
        const url = URL.createObjectURL(new Blob([frameToSvg(frame)], { type: 'image/svg+xml' }));
        try {
          const image = new Image(); image.src = url; await image.decode();
          const reference = svg.getContext('2d')!; reference.drawImage(image, 0, 0);
          samples.push({ inside: pixel(output, 100, 80), outside: pixel(output, 45, 80), referenceInside: pixel(reference, 100, 80), referenceOutside: pixel(reference, 45, 80) });
        } finally { URL.revokeObjectURL(url); }
      }
      return { backend: painter.backend, samples };
    } finally { painter.dispose(); }
  }, clippingProject());
  expect(report.backend).toBe(fallback ? 'canvas2d' : 'webgl2');
  for (const sample of report.samples) {
    expect(sample.inside).toEqual([255, 255, 255, 255]);
    expect(sample.outside).toEqual([0, 0, 0, 255]);
    expect(sample.referenceInside).toEqual(sample.inside);
    expect(sample.referenceOutside).toEqual(sample.outside);
  }
});

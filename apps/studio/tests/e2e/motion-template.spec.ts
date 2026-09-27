import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';
import { parseProjectFile } from '../../shared/project-file';
import { clippingProject } from '../clipping-fixture';

function textMotion() {
  const project = clippingProject(), scene = project.scenes['scene-1'];
  scene.objects.child.kind = 'text'; scene.objects.child.name = 'Reusable title';
  for (const composition of Object.values(scene.compositions)) {
    Object.assign(composition.states.child, { text: 'Hello', fontSize: 20, height: 30 });
  }
  scene.compositions['comp-2'].states.child.x = 20;
  return project;
}

test('saves selected motion, substitutes text/color, inserts into another Scene and shares an undoable independent copy', async ({ page, browser }) => {
  await page.goto(`/?room=${crypto.randomUUID()}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  const projects = page.getByRole('button', { name: 'プロジェクトを開く', exact: true });
  await projects.click();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'title.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(textMotion())) });
  await page.getByRole('button', { name: 'Reusable title', exact: true }).click();
  await projects.click();
  await page.getByRole('textbox', { name: 'Motion name', exact: true }).fill('Reusable title');
  const downloading = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Save motion', exact: true }).click();
  const download = await downloading;
  expect(download.suggestedFilename()).toBe('Reusable title.motion.poietra.json');
  const text = await readFile((await download.path())!, 'utf8');
  const captured = parseProjectFile(text), motion = captured.scenes[captured.sceneOrder[0]];
  expect(motion.objects.child.parentId).toBe('frame');
  expect(motion.objects.frame.clipChildren).toBe(true);
  expect(motion.compositions['comp-2'].states.child.x).toBe(20);
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('button', { name: 'Scene を追加', exact: true }).click();
  await projects.click();
  await page.getByLabel('動きのファイル', { exact: true }).setInputFiles({ name: download.suggestedFilename(), mimeType: 'application/json', buffer: Buffer.from(text) });
  await page.getByRole('textbox', { name: '文字・数式: Hello', exact: true }).fill('Goodbye');
  await page.getByRole('textbox', { name: '色: #ffffff', exact: true }).fill('#ff0000');
  await page.getByRole('button', { name: 'Insert motion', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Projects', exact: true })).not.toBeVisible();
  await page.getByRole('button', { name: 'Reusable title', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Text content', exact: true })).toHaveValue('Goodbye');
  const peerContext = await browser.newContext();
  try {
    const peer = await peerContext.newPage(); await peer.goto(page.url());
    await expect(peer.getByText('Live', { exact: true })).toBeVisible();
    await peer.getByRole('tab', { name: 'Scene 2', exact: true }).click();
    await expect(peer.getByRole('button', { name: 'Reusable title', exact: true })).toBeVisible();
    await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
    await expect(peer.getByRole('button', { name: 'Reusable title', exact: true })).not.toBeVisible();
    await page.getByRole('button', { name: 'やり直す (⌘⇧Z)', exact: true }).click();
    await expect(peer.getByRole('button', { name: 'Reusable title', exact: true })).toBeVisible();
    await projects.click();
    const saving = page.waitForEvent('download'); await page.getByRole('button', { name: 'Save project', exact: true }).click();
    const saved = parseProjectFile(await readFile((await (await saving).path())!, 'utf8'));
    const [source, target] = saved.sceneOrder.map(id => saved.scenes[id]);
    expect(source.compositions['comp-1'].states.child.text).toBe('Hello');
    const child = Object.values(target.objects).find(o => o.kind === 'text')!;
    expect(child.id).not.toBe('child'); expect(child.parentId).not.toBe('frame');
    expect(target.objects[child.parentId!].clipChildren).toBe(true);
    for (const id of target.compositionOrder.slice(1)) {
      expect(target.compositions[id].states[child.id]).toMatchObject({ text: 'Goodbye', fill: '#ff0000' });
    }
  } finally { await peerContext.close(); }
});

test('cancellation and closing the dialog suppress a late motion file read', async ({ page }) => {
  await page.addInitScript(() => {
    const original = File.prototype.text;
    File.prototype.text = function() {
      if (!this.name.startsWith('delayed.motion')) return original.call(this);
      const file = this;
      return new Promise<string>((resolve, reject) => {
        (window as any).finishMotionRead = () => original.call(file).then(resolve, reject);
      });
    };
  });
  await page.goto(`/?room=${crypto.randomUUID()}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  const projects = page.getByRole('button', { name: 'プロジェクトを開く', exact: true });
  const payload = { name: 'delayed.motion.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(textMotion())) };
  for (const close of [false, true]) {
    await projects.click();
    await page.getByLabel('動きのファイル', { exact: true }).setInputFiles(payload);
    await expect(page.getByRole('button', { name: 'Cancel motion', exact: true })).toBeVisible();
    await page.getByRole('button', { name: close ? '閉じる' : 'Cancel motion', exact: true }).click();
    await page.evaluate(() => (window as any).finishMotionRead());
    if (close) await projects.click();
    await expect(page.getByRole('button', { name: 'Insert motion', exact: true })).not.toBeVisible();
    await expect(page.getByRole('button', { name: 'Load motion', exact: true })).toBeEnabled();
    await page.getByRole('button', { name: '閉じる', exact: true }).click();
  }
});

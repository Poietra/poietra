import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { makeDemoProject } from '../../shared/demo';
import { defaultState, defaultTrack } from '../../shared/model';
import { parseProjectFile } from '../../shared/project-file';
import { createProjectMessages } from '../../src/editor/projects';
import * as Y from 'yjs';

test('opening a saved project creates a separate shared room and leaves collaborators in the original', async ({ browser }) => {
  const context = await browser.newContext();
  const original = await context.newPage(); const imported = await context.newPage();
  const originalRoom = crypto.randomUUID();
  await Promise.all([original.goto(`/?room=${originalRoom}`), imported.goto(`/?room=${originalRoom}`)]);
  await expect(original.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await expect(imported.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  const project = makeDemoProject(); project.name = 'Restored project';
  project.scenes['scene-1'].compositions['comp-1'].states.circle.x = 412;
  await imported.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await imported.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'example.poietra.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await expect(imported).not.toHaveURL(new RegExp(originalRoom));
  await expect(imported.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('Restored project');
  await expect(original.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('A little motion');
  const secondContext = await browser.newContext(); const collaborator = await secondContext.newPage();
  await collaborator.goto(imported.url());
  await expect(collaborator.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await collaborator.getByRole('button', { name: 'Circle', exact: true }).click();
  await expect(collaborator.getByRole('spinbutton', { name: 'Position X', exact: true })).toHaveValue('412');
  await imported.reload();
  await expect(imported.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('Restored project');
  await context.close(); await secondContext.close();
});

test('invalid files preserve the current room and a blank project starts with no objects', async ({ page }) => {
  const room = crypto.randomUUID(); await page.goto(`/?room=${room}`);
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'bad.json', mimeType: 'application/json', buffer: Buffer.from('{"version":2}') });
  await expect(page.getByRole('alert')).toContainText('形式');
  await expect(page).toHaveURL(new RegExp(room));
  await page.getByRole('button', { name: 'New project', exact: false }).click();
  await expect(page).not.toHaveURL(new RegExp(room));
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('Untitled project');
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await expect(page.locator('[data-testid="stage-main"] [data-object-id]')).toHaveCount(0);
});

test('closing a pending file read permits another operation and ignores the old result', async ({ page }) => {
  const room = crypto.randomUUID(); await page.goto(`/?room=${room}`);
  await page.evaluate(() => {
    const original = File.prototype.text;
    File.prototype.text = function () {
      if (this.name !== 'delayed.json') return original.call(this);
      return new Promise(resolve => {
        (window as unknown as { releaseProjectFile: () => Promise<void> }).releaseProjectFile = async () => resolve(await original.call(this));
      });
    };
  });
  const open = () => page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await open();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'delayed.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(makeDemoProject())) });
  await expect(page.locator('.project-progress')).toContainText('開いています');
  await page.getByRole('button', { name: '閉じる', exact: true }).click(); await open();
  await expect(page.getByRole('button', { name: 'Open project', exact: false })).toBeEnabled();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'invalid.json', mimeType: 'application/json', buffer: Buffer.from('{"version":2}') });
  await expect(page.getByRole('alert')).toContainText('形式');
  await page.evaluate(async () => {
    await (window as unknown as { releaseProjectFile: () => Promise<void> }).releaseProjectFile();
    await new Promise(requestAnimationFrame); await new Promise(requestAnimationFrame);
  });
  await expect(page).toHaveURL(new RegExp(room));
  await expect(page.getByRole('alert')).toContainText('形式');
  await expect(page.getByRole('button', { name: 'Save project', exact: true })).toBeEnabled();
});

for (const legacy of [false, true]) test(`an import above 2 MiB survives acknowledgment, reload and save (legacy tracks: ${legacy})`, async ({ page }) => {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  project.name = 'Large imported project';
  project.version = legacy ? 1 : 2;
  scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
  for (let i = 0; i < 500; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'circle', order: i, groupId: null, locked: false };
  for (let c = 0; c < 12; c++) {
    const id = `c${c}`; scene.compositionOrder.push(id);
    if (legacy && c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c - 1}`, toId: id, duration: 250, tracks: {} };
    scene.compositions[id] = { id, name: `Composition ${c}`, accent: '#123456', duration: 1000,
      states: Object.fromEntries(Object.keys(scene.objects).map((id, i) => [id, defaultState('circle', {
        x: 25 + (i % 25) * 48 + c, y: 25 + Math.floor(i / 25) * 32, width: 20, height: 20,
      })])) };
  }
  if (!legacy) {
    scene.transitions.t1 = { id: 't1', fromId: 'c0', toId: 'c1', duration: 250, tracks: {} };
    for (const objectId of ['o0', 'o1']) scene.transitions.t1.tracks[objectId] = defaultTrack(objectId, {
      duration: 250, easing: 'linear',
      keyframes: Object.fromEntries(Array.from({ length: 1000 }, (_, i) => [
        `point-${i}`.padEnd(64, 'x'),
        { property: 'x' as const, at: (i + 1) / 1001, value: i, easing: 'linear' as const },
      ])),
    });
  }
  const text = JSON.stringify(project);
  expect(parseProjectFile(text)).toEqual(project);
  const empty = new Y.Doc();
  try {
    const { updateMessages } = createProjectMessages(empty, project);
    expect(updateMessages.length).toBeGreaterThan(1);
    expect(updateMessages.length).toBeLessThan(100);
    expect(updateMessages.reduce((total, message) => total + message.byteLength, 0)).toBeGreaterThan(2 * 1048576);
    for (const message of updateMessages) expect(message.byteLength).toBeLessThanOrEqual(1048576);
  } finally { empty.destroy(); }
  const originalRoom = crypto.randomUUID(); await page.goto(`/?room=${originalRoom}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await page.getByLabel('プロジェクトファイル', { exact: true }).setInputFiles({ name: 'large.json', mimeType: 'application/json', buffer: Buffer.from(text) });
  await expect(page).not.toHaveURL(new RegExp(originalRoom));
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue(project.name);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await expect(page.getByTestId('stage-main').locator('.scene-svg [data-object-id]')).toHaveCount(500);
  await page.reload();
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue(project.name);
  await page.getByRole('button', { name: 'Composition 11', exact: true }).click();
  await expect(page.getByTestId('stage-main').locator('[data-object-id="o0"]')).toHaveAttribute('transform', 'translate(36 25) rotate(0)');
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  const downloading = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  const saved = parseProjectFile(await readFile((await (await downloading).path())!, 'utf8'));
  expect(saved.scenes['scene-1'].compositions).toEqual(scene.compositions);
  if (!legacy) for (const objectId of ['o0', 'o1']) {
    expect(saved.scenes['scene-1'].transitions.t1.tracks[objectId]).toEqual(scene.transitions.t1.tracks[objectId]);
  }
});

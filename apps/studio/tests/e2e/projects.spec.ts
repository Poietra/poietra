import { expect, test } from '@playwright/test';
import { makeDemoProject } from '../../shared/demo';

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

import { expect, test } from '@playwright/test';

type Probe = { pending: Array<{ signal: AbortSignal }>; unmount(): void; finish(index: number): void; fail(index: number): void };

test('a native component failure still renders the localized recovery screen', async ({ page }) => {
  await page.goto('/tests/e2e/fixtures/site-lifecycle.html?failure');
  await expect(page.getByRole('heading', { name: 'Could not open this page' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Reload', exact: true })).toBeVisible();
  await expect(page.getByText('Check your connection and try again.', { exact: true })).toBeVisible();
});

test('cancel and unmount invalidate delayed project publication without navigation', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto('/tests/e2e/fixtures/site-lifecycle.html');
  const start = page.getByRole('button', { name: 'New project', exact: true });
  await start.click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.pending.length)).toBe(1);
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  await start.click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.pending.length)).toBe(2);
  await page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.finish(0));
  await expect(start).toBeDisabled();
  await expect(page.locator('.landing-launch-status')).toContainText('Preparing your new project');
  expect(page.url()).toContain('site-lifecycle.html');
  await page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.unmount());
  expect(await page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.pending.every(entry => entry.signal.aborted))).toBe(true);
  await page.evaluate(() => (window as unknown as { siteProbe: Probe }).siteProbe.finish(1));
  await page.waitForTimeout(100);
  expect(page.url()).toContain('site-lifecycle.html');
  expect(errors).toEqual([]);
});

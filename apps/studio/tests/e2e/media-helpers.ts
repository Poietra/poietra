import { expect, type Page } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import { readProject } from '../../shared/document';

export async function open(page: Page, room = crypto.randomUUID()) {
  await page.goto(`/?room=${room}`); await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  return room;
}
export async function fixture(page: Page, name = 'Together.png') {
  const encoded = await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = 80; canvas.height = 40;
    const ctx = canvas.getContext('2d')!; ctx.fillStyle = '#ff0000'; ctx.fillRect(0, 0, 40, 40); ctx.fillStyle = '#00ff00'; ctx.fillRect(40, 0, 40, 40); ctx.clearRect(32, 12, 16, 16);
    return canvas.toDataURL('image/png').split(',')[1];
  });
  return { name, mimeType: 'image/png', buffer: Buffer.from(encoded, 'base64') };
}
export async function observer(page: Page, room: string) {
  const endpoint = new URL(page.url()); endpoint.protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:'; endpoint.pathname = '/sync'; endpoint.search = '';
  const doc = new Y.Doc(), provider = new WebsocketProvider(endpoint.toString(), room, doc, { WebSocketPolyfill: WebSocket as never, disableBc: true });
  await new Promise<void>(resolve => provider.on('sync', (synced: boolean) => { if (synced) resolve(); }));
  return { doc, project: () => readProject(doc)!, close: () => { provider.destroy(); doc.destroy(); } };
}
export async function upload(page: Page, name?: string) {
  await page.getByLabel('画像ファイル', { exact: true }).setInputFiles(await fixture(page, name));
  await expect(page.getByRole('button', { name: name?.replace('.png', '') || 'Together', exact: true })).toBeVisible();
  await expect(page.locator('.scene-svg image').first()).toHaveAttribute('href', /^data:image\/png;base64,/);
}
export async function field(page: Page, name: string, value: string) { const input = page.getByRole('spinbutton', { name, exact: true }); await input.fill(value); await input.press('Tab'); }


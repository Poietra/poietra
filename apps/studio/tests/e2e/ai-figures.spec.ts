import { expect, test, type Page, type Route } from '@playwright/test';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import WebSocket from 'ws';
import type { z } from 'zod';
import { compileProposal, type EditProposalSchema } from '../../shared/ai';
import { readProject } from '../../shared/document';

type Operation = z.infer<typeof EditProposalSchema>['operations'][number];
const reply = (route: Route, value: unknown, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(value) });
const composer = (page: Page) => page.getByRole('textbox', { name: 'チャットメッセージ', exact: true });
const log = (page: Page) => page.getByRole('log', { name: '共同編集チャット', exact: true });
const attached = (page: Page, number: number) => page.locator('.assistant-composer').getByRole('img', { name: `添付画像 ${number}`, exact: true });

// The structure of a right triangle figure with labelled vertices and an equation.
const segment = (ref: string, name: string, x: number, y: number, width: number, height: number): Operation[] => [
  { action: 'createObject', ref, compositionId: 'comp-1', name, kind: 'path', x, y, width, height, fill: '#ffffff', text: '', fontSize: 36 },
  { action: 'setShapePath', compositionId: 'comp-1', objectId: ref, path: { c1: { x: width / 3, y: height / 3 }, c2: { x: 2 * width / 3, y: 2 * height / 3 } } },
  { action: 'setState', compositionId: 'comp-1', objectId: ref, property: 'stroke', value: '#f2f2f2' },
];
const label = (ref: string, name: string, kind: 'text' | 'equation', text: string, x: number, y: number): Operation =>
  ({ action: 'createObject', ref, compositionId: 'comp-1', name, kind, x, y, width: 80, height: 48, fill: '#f2f2f2', text, fontSize: 36 });
const triangle: Operation[] = [
  ...segment('@ab', 'Segment AB', 320, 600, 600, 0),
  ...segment('@bc', 'Segment BC', 920, 600, 0, -500),
  ...segment('@ac', 'Segment AC', 320, 600, 600, -500),
  ...segment('@ad', 'Segment AD', 320, 600, 600, -200),
  label('@a', 'Label A', 'text', 'A', 290, 630),
  label('@b', 'Label B', 'text', 'B', 950, 630),
  label('@c', 'Label C', 'text', 'C', 950, 90),
  label('@d', 'Label D', 'text', 'D', 950, 400),
  label('@cos', 'Label cos θ', 'equation', '\\cos\\theta', 620, 650),
];

// Draws a figure in the page and pastes it as a clipboard file, as a browser does for a screenshot.
async function pasteFigure(page: Page) {
  await composer(page).evaluate(async element => {
    const canvas = document.createElement('canvas'); canvas.width = 912; canvas.height = 550;
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#ffffff'; context.fillRect(0, 0, 912, 550);
    context.strokeStyle = '#000000'; context.lineWidth = 2;
    context.beginPath(); context.moveTo(135, 470); context.lineTo(670, 470); context.lineTo(670, 68); context.closePath(); context.moveTo(135, 470); context.lineTo(670, 292); context.stroke();
    context.font = '36px serif'; context.fillStyle = '#000000';
    for (const [text, x, y] of [['A', 85, 520], ['B', 690, 520], ['C', 690, 50], ['D', 690, 305], ['cos θ', 355, 525]] as const) context.fillText(text, x, y);
    const blob = await new Promise<Blob>(resolve => canvas.toBlob(value => resolve(value!), 'image/png'));
    const data = new DataTransfer();
    data.items.add(new File([blob], 'figure.png', { type: 'image/png' }));
    element.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  });
}

async function open(page: Page, room: string) {
  await page.route('**/api/health', route => reply(route, { ok: true, ai: true }));
  await page.goto(`/?room=${room}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await page.getByRole('button', { name: 'Chat', exact: true }).click();
}

test('a pasted figure goes to Codex with the mention and becomes editable objects', async ({ page, browser }) => {
  const room = crypto.randomUUID(), doc = new Y.Doc();
  let provider: WebsocketProvider | undefined;
  const peerContext = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const peer = await peerContext.newPage();
  await peer.route('**/api/ai/propose', route => route.abort('blockedbyclient'));
  const requests: Record<string, unknown>[] = [];
  // AI HTTP is stubbed; chat sync, compilation, guards and Apply are real.
  await page.route('**/api/ai/propose', route => {
    const input = route.request().postDataJSON();
    requests.push(input);
    return reply(route, compileProposal(doc, readProject(doc)!, input.sceneId, { message: '図を編集できるオブジェクトで再現しました。', operations: triangle }));
  });
  try {
    await Promise.all([open(page, room), open(peer, room)]);
    const endpoint = new URL(page.url()); endpoint.protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:'; endpoint.pathname = '/sync'; endpoint.search = '';
    provider = new WebsocketProvider(endpoint.toString(), room, doc, { WebSocketPolyfill: WebSocket as never, disableBc: true });
    await new Promise<void>(resolve => provider!.on('sync', (synced: boolean) => { if (synced) resolve(); }));

    await pasteFigure(page);
    const thumbnail = attached(page, 1);
    await expect(thumbnail).toBeVisible();
    // A figure is for Codex, so pasting one addresses the message to Codex.
    await expect(composer(page)).toHaveValue('@codex ');
    await composer(page).fill('@codex この図を編集できるオブジェクトで再現して');
    await page.getByRole('button', { name: '送信', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Apply edits', exact: true })).toBeVisible();
    await expect(thumbnail).toHaveCount(0);

    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ prompt: 'この図を編集できるオブジェクトで再現して', images: [expect.stringMatching(/^data:image\/png;base64,/)] });

    await page.getByRole('button', { name: 'Apply edits', exact: true }).click();
    for (const name of ['Segment AB', 'Segment AC', 'Label cos θ']) await expect(peer.getByRole('button', { name, exact: true })).toBeVisible();
    const scene = readProject(doc)!.scenes['scene-1'];
    const segmentAC = Object.values(scene.objects).find(object => object.name === 'Segment AC')!;
    expect(scene.compositions['comp-1'].states[segmentAC.id]).toMatchObject({ x: 320, y: 600, width: 600, height: -500, path: { c1: { x: 200, y: -500 / 3 }, c2: { x: 400, y: -1000 / 3 } } });
  } finally { provider?.destroy(); doc.destroy(); await peerContext.close(); }
});

test('figures need the mention, can be removed, and return to the composer when a request is stopped', async ({ page }) => {
  const pending: Route[] = [];
  await page.route('**/api/ai/propose', route => { pending.push(route); });
  await open(page, crypto.randomUUID());
  await pasteFigure(page);
  await expect(attached(page, 1)).toBeVisible();
  await composer(page).fill('この図をメンバーに共有');
  await page.getByRole('button', { name: '送信', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('図は @codex への依頼に添付できます。');
  expect(pending).toHaveLength(0);

  await pasteFigure(page);
  await expect(attached(page, 2)).toBeVisible();
  await page.getByRole('button', { name: '添付画像 2 を削除', exact: true }).click();
  await expect(attached(page, 2)).toHaveCount(0);
  await expect(attached(page, 1)).toBeVisible();

  // A bare mention with a figure stands for recreating it.
  await composer(page).fill('@codex');
  await page.getByRole('button', { name: '送信', exact: true }).click();
  await expect.poll(() => pending.length).toBe(1);
  expect(pending[0].request().postDataJSON()).toMatchObject({ prompt: '添付した図を、編集できるオブジェクトで再現して。', images: [expect.any(String)] });
  await log(page).getByRole('button', { name: '停止', exact: true }).click();
  await expect(attached(page, 1)).toBeVisible();
  await expect(composer(page)).toHaveValue('@codex');
  await expect(log(page).getByText('停止しました', { exact: true })).toBeVisible();
});

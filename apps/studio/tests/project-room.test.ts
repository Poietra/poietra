import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { createProjectRoom } from '../src/editor/projects';
import { largeImportProject } from './helpers/project-import';

const hooks = vi.hoisted(() => ({ prepared: vi.fn(), connected: vi.fn(), instances: [] as Provider[] }));
interface Provider {
  doc: Y.Doc; ws: EventTarget & { readyState: number; send: ReturnType<typeof vi.fn> };
  handlers: Map<string, (...args: unknown[]) => void>;
  awareness: { destroy: ReturnType<typeof vi.fn>; setLocalState: ReturnType<typeof vi.fn> };
  destroy: ReturnType<typeof vi.fn>;
}
vi.mock('../src/editor/images', () => ({ storeProjectImages: hooks.prepared }));
vi.mock('y-websocket', () => ({ WebsocketProvider: class implements Provider {
  handlers = new Map<string, (...args: unknown[]) => void>();
  ws = Object.assign(new EventTarget(), { readyState: 1, send: vi.fn() });
  awareness = { destroy: vi.fn(), setLocalState: vi.fn() };
  destroy = vi.fn();
  constructor(_url: string, _room: string, public doc: Y.Doc) { hooks.instances.push(this); }
  on(name: string, callback: (...args: unknown[]) => void) { this.handlers.set(name, callback); }
  off(name: string) { this.handlers.delete(name); }
  connect() { hooks.connected(); this.handlers.get('sync')?.(true); }
} }));
beforeEach(() => {
  hooks.instances.length = 0; hooks.prepared.mockReset().mockImplementation(async project => structuredClone(project)); hooks.connected.mockReset();
  vi.stubGlobal('location', { protocol: 'http:', host: 'local.test', href: 'http://local.test/?room=original' });
  vi.stubGlobal('WebSocket', { OPEN: 1 });
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });
async function publishing() {
  await vi.waitFor(() => expect(hooks.instances[0]?.ws.send.mock.calls.length).toBeGreaterThan(1));
  return hooks.instances[0];
}
function expectReleased(provider: Provider) {
  expect(provider.handlers.size).toBe(0); expect(provider.doc.isDestroyed).toBe(true);
  expect(provider.destroy).toHaveBeenCalledOnce(); expect(provider.awareness.destroy).toHaveBeenCalledOnce();
}

it('a synchronous connect failure still removes listeners and destroys acquired resources', async () => {
  const failure = new Error('connect failed'); hooks.connected.mockImplementationOnce(() => { throw failure; });
  await expect(createProjectRoom(makeDemoProject())).rejects.toBe(failure);
  expectReleased(hooks.instances[0]);
});

function acknowledge(provider: Provider) {
  provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array([0, 1]).buffer }));
}

it('bounds publication windows and waits for the final ordered acknowledgment', async () => {
  const project = largeImportProject();
  const scene = project.scenes['scene-1'];
  scene.objects.o0.kind = 'equation';
  scene.compositions.c0.states.o0.text = 'x'.repeat(900000);
  const task = createProjectRoom(project), provider = await publishing();
  const remove = vi.spyOn(provider.ws, 'removeEventListener');
  let completed = false, start = 0, windows = 0, oversized = false;
  void task.then(() => { completed = true; });
  const sent = provider.ws.send.mock.calls.length;
  for (const bytes of [[], [1, 1], [0, 0]]) {
    provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array(bytes).buffer }));
  }
  expect(provider.ws.send).toHaveBeenCalledTimes(sent);
  while (true) {
    const end = provider.ws.send.mock.calls.length;
    const updates = provider.ws.send.mock.calls.slice(start, end - 1).map(([packet]) => packet as Uint8Array);
    expect(updates.length).toBeGreaterThan(0);
    expect(updates.length).toBeLessThanOrEqual(16);
    if (updates[0].byteLength > 524288) {
      expect(updates).toHaveLength(1);
      expect(updates[0].byteLength).toBeLessThanOrEqual(1048576);
      oversized = true;
    } else {
      expect(updates.reduce((sum, update) => sum + update.byteLength, 0)).toBeLessThanOrEqual(524288);
    }
    await Promise.resolve();
    expect(completed).toBe(false);
    expect(provider.ws.send).toHaveBeenCalledTimes(end);
    windows++;
    acknowledge(provider);
    if (provider.ws.send.mock.calls.length === end) break;
    start = end;
  }
  const url = await task;
  expect(url.searchParams.get('room')).not.toBe('original');
  expect(windows).toBeGreaterThan(1);
  expect(oversized).toBe(true);
  expectReleased(provider);
  expect(remove).toHaveBeenCalledWith('message', expect.any(Function));
});

it.each(['abort', 'disconnect', 'send'] as const)('stops a partial import after %s and ignores late acknowledgments', async failure => {
  const controller = new AbortController(), task = createProjectRoom(largeImportProject(), controller.signal);
  const rejected = failure === 'abort'
    ? expect(task).rejects.toMatchObject({ name: 'AbortError' })
    : expect(task).rejects.toThrow(failure === 'disconnect' ? '接続が切れ' : 'send failed');
  const provider = await publishing(); acknowledge(provider);
  const remove = vi.spyOn(controller.signal, 'removeEventListener');
  const before = provider.ws.send.mock.calls.length;
  if (failure === 'abort') controller.abort();
  else if (failure === 'disconnect') provider.handlers.get('status')?.({ status: 'disconnected' });
  else {
    provider.ws.send.mockImplementationOnce(() => { throw new Error('send failed'); }); acknowledge(provider);
  }
  await rejected; const sent = provider.ws.send.mock.calls.length; acknowledge(provider);
  expect(sent).toBe(before + (failure === 'send' ? 1 : 0));
  expect(provider.ws.send).toHaveBeenCalledTimes(sent); expectReleased(provider);
  expect(remove).toHaveBeenCalledWith('abort', expect.any(Function));
});

it('renews the acknowledgment timeout only when a publication window makes progress', async () => {
  vi.useFakeTimers();
  const task = createProjectRoom(largeImportProject()), rejected = expect(task).rejects.toThrow('接続できません');
  const provider = await publishing();
  await vi.advanceTimersByTimeAsync(10000); acknowledge(provider);
  const sent = provider.ws.send.mock.calls.length;
  await vi.advanceTimersByTimeAsync(10000);
  expect(provider.destroy).not.toHaveBeenCalled();
  provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array([0, 2]).buffer }));
  await vi.advanceTimersByTimeAsync(5000); await rejected;
  acknowledge(provider); expect(provider.ws.send).toHaveBeenCalledTimes(sent);
  expectReleased(provider); expect(vi.getTimerCount()).toBe(0);
});

import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import * as sync from 'y-protocols/sync';
import { makeDemoProject } from '../shared/demo';
import { readProject } from '../shared/document';
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
async function sending() {
  await vi.waitFor(() => expect(hooks.instances[0]?.ws.send).toHaveBeenCalledTimes(2));
  return hooks.instances[0];
}
function expectReleased(provider: Provider) {
  expect(provider.handlers.size).toBe(0); expect(provider.doc.isDestroyed).toBe(true);
  expect(provider.destroy).toHaveBeenCalledOnce(); expect(provider.awareness.destroy).toHaveBeenCalledOnce();
}

it('publishes the validated update then waits for the ordered sync acknowledgment', async () => {
  const task = createProjectRoom(makeDemoProject()), provider = await sending();
  const remove = vi.spyOn(provider.ws, 'removeEventListener');
  let completed = false; void task.then(() => { completed = true; });
  for (const bytes of [[], [1, 1], [0, 0]]) provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array(bytes).buffer }));
  await Promise.resolve(); expect(completed).toBe(false);
  provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array([0, 1]).buffer }));
  const url = await task; expect(url.searchParams.get('room')).not.toBe('original');
  expectReleased(provider); expect(remove).toHaveBeenCalledWith('message', expect.any(Function));
});

it('aborting acknowledgment wait closes subscriptions and its isolated document', async () => {
  const controller = new AbortController(), task = createProjectRoom(makeDemoProject(), controller.signal);
  const rejected = expect(task).rejects.toMatchObject({ name: 'AbortError' }), provider = await sending();
  const remove = vi.spyOn(controller.signal, 'removeEventListener'); controller.abort(); await rejected;
  expectReleased(provider); expect(remove).toHaveBeenCalledWith('abort', expect.any(Function));
  provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array([0, 1]).buffer }));
  expect(provider.destroy).toHaveBeenCalledOnce();
});

it('disconnecting before acknowledgment rejects the open operation', async () => {
  const task = createProjectRoom(makeDemoProject()), rejected = expect(task).rejects.toThrow('接続が切れ');
  const provider = await sending(); provider.handlers.get('status')?.({ status: 'disconnected' }); await rejected;
  expectReleased(provider);
});

it('a synchronous connect failure still removes listeners and destroys acquired resources', async () => {
  const failure = new Error('connect failed'); hooks.connected.mockImplementationOnce(() => { throw failure; });
  await expect(createProjectRoom(makeDemoProject())).rejects.toBe(failure);
  expectReleased(hooks.instances[0]);
});

function acknowledge(provider: Provider) {
  provider.ws.dispatchEvent(new MessageEvent('message', { data: new Uint8Array([0, 1]).buffer }));
}

async function publishing() {
  await vi.waitFor(() => expect(hooks.instances[0]?.ws.send.mock.calls.length).toBeGreaterThan(1));
  return hooks.instances[0];
}

it('bounds each publication window and waits for every ordered acknowledgment before completing', async () => {
  const project = largeImportProject(), task = createProjectRoom(project), provider = await publishing();
  const server = new Y.Doc(); let completed = false, start = 0, windows = 0, totalBytes = 0;
  void task.then(() => { completed = true; });
  try {
    while (readProject(server)?.name !== project.name) {
      const end = provider.ws.send.mock.calls.length;
      const packets = provider.ws.send.mock.calls.slice(start, end).map(([packet]) => packet as Uint8Array);
      const updates = packets.slice(0, -1), bytes = updates.reduce((sum, update) => sum + update.byteLength, 0);
      expect(updates.length).toBeGreaterThan(0); expect(updates.length).toBeLessThanOrEqual(16);
      expect(bytes).toBeLessThanOrEqual(Math.max(524288, ...updates.map(update => update.byteLength)));
      for (const packet of packets) {
        const decoder = decoding.createDecoder(packet); expect(decoding.readVarUint(decoder)).toBe(0);
        const type = sync.readSyncMessage(decoder, encoding.createEncoder(), server, 'import');
        expect(type).toBe(packet === packets.at(-1) ? sync.messageYjsSyncStep1 : sync.messageYjsUpdate);
      }
      await Promise.resolve(); expect(completed).toBe(false);
      expect(provider.ws.send).toHaveBeenCalledTimes(end);
      totalBytes += bytes; windows++; start = end;
      acknowledge(provider);
    }
    await task;
    expect(totalBytes).toBeGreaterThan(2 * 1048576); expect(windows).toBeGreaterThan(1);
    expect(readProject(server)).toEqual(project); expectReleased(provider);
  } finally { server.destroy(); }
});

it('sends a legal indivisible frame above the window budget on its own', async () => {
  const project = makeDemoProject();
  for (const composition of Object.values(project.scenes['scene-1'].compositions)) composition.states.equation.text = 'x'.repeat(900000);
  const controller = new AbortController(), task = createProjectRoom(project, controller.signal);
  const rejected = expect(task).rejects.toMatchObject({ name: 'AbortError' }), provider = await publishing();
  let start = 0, found = false;
  while (!found) {
    const end = provider.ws.send.mock.calls.length;
    const updates = provider.ws.send.mock.calls.slice(start, end - 1).map(([packet]) => packet as Uint8Array);
    if (updates.some(packet => packet.byteLength > 524288)) {
      expect(updates).toHaveLength(1); expect(updates[0].byteLength).toBeLessThanOrEqual(1048576); found = true;
    } else { start = end; acknowledge(provider); }
  }
  const sent = provider.ws.send.mock.calls.length;
  controller.abort(); await rejected; acknowledge(provider);
  expect(provider.ws.send).toHaveBeenCalledTimes(sent); expectReleased(provider);
});

it.each(['abort', 'disconnect', 'send', 'timeout'] as const)('stops a partial import after %s and ignores late acknowledgments', async failure => {
  const timers = vi.spyOn(globalThis, 'setTimeout');
  const controller = new AbortController(), task = createProjectRoom(largeImportProject(), controller.signal);
  const rejected = expect(task).rejects.toMatchObject(failure === 'abort' ? { name: 'AbortError' } : { name: 'Error' });
  const provider = await publishing(); acknowledge(provider);
  const before = provider.ws.send.mock.calls.length;
  if (failure === 'abort') controller.abort();
  else if (failure === 'disconnect') provider.handlers.get('status')?.({ status: 'disconnected' });
  else if (failure === 'send') {
    provider.ws.send.mockImplementationOnce(() => { throw new Error('send failed'); }); acknowledge(provider);
  } else {
    const timeout = timers.mock.calls.findLast(([, delay]) => delay === 15000);
    expect(timeout).toBeDefined(); (timeout![0] as () => void)();
  }
  await rejected; const sent = provider.ws.send.mock.calls.length; acknowledge(provider);
  expect(sent).toBe(before + (failure === 'send' ? 1 : 0));
  expect(provider.ws.send).toHaveBeenCalledTimes(sent); expectReleased(provider);
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

import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { createProjectRoom } from '../src/editor/projects';

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
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });
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

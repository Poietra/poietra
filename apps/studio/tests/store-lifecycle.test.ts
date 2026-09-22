import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import { initializeDocument } from '../shared/document';
import { makeDemoProject } from '../shared/demo';

const mocks = vi.hoisted(() => {
  class Events {
    events = new Map<string, Set<(...args: any[]) => void>>();
    on(name: string, callback: (...args: any[]) => void) { if (!this.events.has(name)) this.events.set(name, new Set()); this.events.get(name)!.add(callback); }
    off(name: string, callback: (...args: any[]) => void) { this.events.get(name)?.delete(callback); }
    emit(name: string, ...args: any[]) { for (const callback of this.events.get(name) ?? []) callback(...args); }
  }
  const providers: Provider[] = [], persistence: Persistence[] = [];
  class Provider extends Events {
    local: any = {};
    awareness = Object.assign(new Events(), {
      getStates: vi.fn(() => new Map([[this.doc.clientID, this.local]])),
      getLocalState: () => this.local,
      setLocalState: (value: any) => { this.local = value; },
      setLocalStateField: (key: string, value: any) => { this.local = { ...this.local, [key]: value }; this.awareness.emit('change'); },
    });
    destroy = vi.fn(); disconnect = vi.fn(); connect = vi.fn();
    constructor(_url: string, _room: string, readonly doc: Y.Doc) { super(); providers.push(this); }
  }
  class Persistence extends Events {
    resolve!: (db: any) => void;
    _db = new Promise(resolve => { this.resolve = resolve; });
    db: any;
    constructor() { super(); persistence.push(this); }
  }
  return { Provider, Persistence, providers, persistence };
});
vi.mock('y-websocket', () => ({ WebsocketProvider: mocks.Provider }));
vi.mock('y-indexeddb', () => ({ IndexeddbPersistence: mocks.Persistence }));
import { EditorStore } from '../src/editor/store';

const stores: EditorStore[] = [];
beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal('location', { protocol: 'http:', host: 'localhost' });
  const storage = { getItem: () => null, setItem() {} };
  vi.stubGlobal('localStorage', storage); vi.stubGlobal('sessionStorage', storage);
});
afterEach(() => {
  for (const store of stores.splice(0)) if (!store.doc.isDestroyed) store.doc.destroy();
  mocks.providers.length = 0; mocks.persistence.length = 0;
  vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals();
});
function create() { const store = new EditorStore(crypto.randomUUID()); stores.push(store); initializeDocument(store.doc, makeDemoProject()); return store; }

test('project writes reuse presence until awareness changes', () => {
  const store = create(), awareness = mocks.providers[0].awareness;
  const peers = store.snapshot().peers;
  awareness.getStates.mockClear();
  store.setProjectName('Edited');
  store.updateState('scene-1', 'comp-1', 'circle', { x: 300 });
  expect(store.snapshot().peers).toBe(peers);
  expect(awareness.getStates).not.toHaveBeenCalled();
  store.presence({ selectedIds: ['circle'] });
  expect(awareness.getStates).toHaveBeenCalledTimes(1);
  expect(store.snapshot().peers[0].selectedIds).toEqual(['circle']);
});

test('unavailable preference storage does not prevent editing or rename', () => {
  const denied = { getItem() { throw new Error('Blocked storage'); }, setItem() { throw new Error('Blocked storage'); } };
  vi.stubGlobal('localStorage', denied); vi.stubGlobal('sessionStorage', denied);
  const store = create();
  expect(store.chatAuthorId).toMatch(/^[\da-f-]{36}$/);
  store.setName('Alice'); store.setProjectName('Local project');
  expect(store.userName).toBe('Alice'); expect(store.project().name).toBe('Local project');
});

test('automatic connection attempts share one deadline and retry retains the document and history', () => {
  const store = create(), provider = mocks.providers[0];
  store.setProjectName('Pending edit');
  const doc = store.doc, manager = store.undoManager;
  vi.advanceTimersByTime(6000); provider.emit('status', { status: 'connecting' });
  vi.advanceTimersByTime(2001);
  expect(store.snapshot().connectionIssue).toContain('時間がかかっています');
  store.retryConnection();
  expect(provider.disconnect).toHaveBeenCalledOnce(); expect(provider.connect).toHaveBeenCalledOnce();
  expect(store.doc).toBe(doc); expect(store.undoManager).toBe(manager); expect(manager.canUndo()).toBe(true);
  provider.emit('status', { status: 'connected' }); provider.emit('sync', true);
  expect(store.snapshot().connectionIssue).toBeNull();
  vi.advanceTimersByTime(9000); expect(store.snapshot().connectionIssue).toBeNull();
});

test('destroy closes the provider and ignores a late database open or sync', async () => {
  const store = create(), provider = mocks.providers[0], persistence = mocks.persistence[0];
  const listener = vi.fn(); store.subscribe(listener);
  store.doc.destroy(); listener.mockClear();
  const before = store.snapshot(), db = { addEventListener: vi.fn(), transaction: vi.fn() };
  persistence.db = db; persistence.resolve(db);
  await Promise.resolve(); persistence.emit('synced'); provider.emit('status', { status: 'connected' });
  vi.advanceTimersByTime(30000);
  expect(provider.destroy).toHaveBeenCalledOnce(); expect(db.addEventListener).not.toHaveBeenCalled(); expect(db.transaction).not.toHaveBeenCalled();
  expect(listener).not.toHaveBeenCalled(); expect(store.snapshot()).toBe(before);
});

test('destroy detaches an in-flight storage transaction and its late completion', async () => {
  const store = create(), persistence = mocks.persistence[0];
  const transaction: any = {};
  const db = { addEventListener: vi.fn(), removeEventListener: vi.fn(), transaction: vi.fn(() => transaction) };
  persistence.db = db; persistence.resolve(db); await Promise.resolve();
  persistence.emit('synced');
  const complete = transaction.oncomplete;
  expect(typeof complete).toBe('function');
  const listener = vi.fn(); store.subscribe(listener);
  store.doc.destroy(); listener.mockClear();
  expect(transaction.oncomplete).toBeNull(); expect(transaction.onerror).toBeNull(); expect(db.removeEventListener).toHaveBeenCalledTimes(3);
  complete(); expect(listener).not.toHaveBeenCalled();
  expect(store.snapshot().localPersistence).toBe('loading');
});

test('cursor bursts keep a trailing latest point and selection flushes the pending cursor', () => {
  const store = create(), awareness = mocks.providers[0].awareness;
  store.presence({ cursor: { x: 1, y: 1 } });
  awareness.getStates.mockClear();
  for (let x = 2; x <= 100; x++) store.presence({ cursor: { x, y: 10 } });
  expect(awareness.getStates).not.toHaveBeenCalled();
  vi.advanceTimersByTime(50);
  expect(awareness.getStates).toHaveBeenCalledTimes(1);
  expect(store.snapshot().peers[0].cursor).toEqual({ x: 100, y: 10 });
  store.presence({ cursor: { x: 200, y: 20 } });
  store.presence({ selectedIds: ['circle'] });
  expect(store.snapshot().peers[0]).toMatchObject({ selectedIds: ['circle'], cursor: { x: 200, y: 20 } });
  store.presence({ cursor: { x: 300, y: 30 } });
  store.doc.destroy(); awareness.getStates.mockClear(); vi.advanceTimersByTime(2000);
  expect(awareness.getStates).not.toHaveBeenCalled();
});

test('a 500-person room bounds cursor publication to once a second while edits stay immediate', () => {
  const store = create(), awareness = mocks.providers[0].awareness;
  const peers = new Map(Array.from({ length: 500 }, (_, i) => [i, { user: { name: `Peer ${i}`, color: '#abcdef' } }]));
  awareness.getStates.mockReturnValue(peers); awareness.emit('change');
  const context = { sceneId: 'scene-1', compositionId: 'comp-1' };
  store.presence({ ...context, cursor: { x: 1, y: 1 } }); awareness.getStates.mockClear();
  // Match StageController.pointer_move, including its repeated context fields.
  for (let x = 2; x <= 25; x++) {
    vi.advanceTimersByTime(40);
    store.presence({ ...context, cursor: { x, y: 2 } });
  }
  store.setProjectName('Immediate');
  vi.advanceTimersByTime(39);
  expect(awareness.getStates).not.toHaveBeenCalled(); expect(store.project().name).toBe('Immediate');
  vi.advanceTimersByTime(1); expect(awareness.getStates).toHaveBeenCalledTimes(1);
  expect(awareness.getLocalState().editor).toEqual({ ...context, cursor: { x: 25, y: 2 } });
});

test('actual context changes, selection and pointer exit flush queued presence immediately', () => {
  const store = create(), awareness = mocks.providers[0].awareness;
  store.presence({ sceneId: 'scene-1', compositionId: 'comp-1', cursor: { x: 1, y: 1 } });
  store.presence({ sceneId: 'scene-1', compositionId: 'comp-1', cursor: { x: 2, y: 2 } });
  expect(awareness.getLocalState().editor.cursor.x).toBe(1);
  store.presence({ sceneId: 'scene-1', compositionId: 'comp-2', cursor: { x: 3, y: 3 } });
  expect(awareness.getLocalState().editor).toMatchObject({ compositionId: 'comp-2', cursor: { x: 3, y: 3 } });
  store.presence({ sceneId: 'scene-2', compositionId: 'comp-2', cursor: { x: 4, y: 4 } });
  expect(awareness.getLocalState().editor.sceneId).toBe('scene-2');
  store.presence({ cursor: { x: 5, y: 5 } });
  store.presence({ selectedIds: ['circle'] });
  expect(awareness.getLocalState().editor).toMatchObject({ selectedIds: ['circle'], cursor: { x: 5, y: 5 } });
  store.presence({ cursor: { x: 6, y: 6 } });
  store.presence({ cursor: null });
  expect(awareness.getLocalState().editor.cursor).toBeNull();
  vi.advanceTimersByTime(1000);
  expect(awareness.getLocalState().editor.cursor).toBeNull();
});

test('gesture completion, undo and page suspension flush document transport and clean up listeners', () => {
  const window = new EventTarget(), document = new EventTarget();
  vi.stubGlobal('addEventListener', window.addEventListener.bind(window));
  vi.stubGlobal('removeEventListener', window.removeEventListener.bind(window));
  vi.stubGlobal('document', document);
  const store = create(), provider = mocks.providers[0];
  const flushDocuments = vi.fn();
  Object.assign(provider, { ws: { flushDocuments } });
  store.beginGesture(); store.updateState('scene-1', 'comp-1', 'circle', { x: 300 }, false); store.endGesture();
  store.undo(); store.redo();
  document.dispatchEvent(new Event('visibilitychange'));
  store.presence({ cursor: { x: 1, y: 1 } }); store.presence({ cursor: { x: 2, y: 2 } });
  window.dispatchEvent(new Event('pagehide'));
  expect(provider.awareness.getLocalState().editor.cursor.x).toBe(2);
  expect(flushDocuments).toHaveBeenCalledTimes(5);
  store.doc.destroy(); flushDocuments.mockClear();
  document.dispatchEvent(new Event('visibilitychange')); window.dispatchEvent(new Event('pagehide'));
  expect(flushDocuments).not.toHaveBeenCalled();
});

test('remote presence packets publish once per frame and preserve unchanged peer references', () => {
  const store = create(), provider = mocks.providers[0], awareness = provider.awareness;
  const peers = new Map([[1, { user: { name: 'A' }, editor: { cursor: { x: 0, y: 0 } } }], [2, { user: { name: 'B' }, editor: { cursor: { x: 0, y: 0 } } }]]);
  awareness.getStates.mockReturnValue(peers); awareness.emit('change');
  const before = store.snapshot().peers;
  awareness.getStates.mockClear();
  for (let x = 1; x <= 50; x++) {
    peers.set(1, { user: { name: 'A' }, editor: { cursor: { x, y: 0 } } });
    awareness.emit('change', {}, provider);
  }
  expect(awareness.getStates).not.toHaveBeenCalled();
  vi.advanceTimersByTime(16);
  expect(awareness.getStates).toHaveBeenCalledOnce();
  expect(store.snapshot().peers[0].cursor?.x).toBe(50);
  expect(store.snapshot().peers[1]).toBe(before[1]);
  peers.delete(1); awareness.emit('change', {}, provider); vi.advanceTimersByTime(16);
  expect(store.snapshot().peers).toEqual([before[1]]);
  awareness.emit('change', {}, provider); store.doc.destroy(); awareness.getStates.mockClear(); vi.advanceTimersByTime(16);
  expect(awareness.getStates).not.toHaveBeenCalled();
});

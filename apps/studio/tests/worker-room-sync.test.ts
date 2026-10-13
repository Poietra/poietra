import { DatabaseSync } from 'node:sqlite';
import { afterEach, beforeAll, beforeEach, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import * as sync from 'y-protocols/sync';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import { projectRoomClass } from '../../../_build/js/release/build/worker_room/worker_room.js';
import { presenceMessage } from '../worker/presence';
import { initializeDocument, readProject } from '../shared/document';
import { largeImportProject } from './helpers/project-import';
import { historicalRoomClass } from './helpers/historical-room';

const databases: DatabaseSync[] = [];
let oldRoomClass: typeof projectRoomClass;
beforeAll(async () => { oldRoomClass = await historicalRoomClass(); }, 120_000);
beforeEach(() => vi.useFakeTimers());
afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); vi.restoreAllMocks(); for (const db of databases.splice(0)) db.close(); });
function socket() {
  let attachment: unknown = null;
  return { readyState: 1, send: vi.fn(), close: vi.fn(),
    serializeAttachment: vi.fn((value: unknown) => { attachment = structuredClone(value); }),
    deserializeAttachment: vi.fn(() => structuredClone(attachment)),
  };
}
function fixture(sockets = [socket(), socket()], env = {}, snapshotLimit = 2 * 1048576) {
  const database = new DatabaseSync(':memory:'); databases.push(database);
  let transaction = 0;
  const ctx = { getWebSockets: vi.fn(() => sockets), abort: vi.fn(() => { throw new Error('aborted'); }), storage: {
    sql: { exec(query: string, ...values: any[]) {
      // node:sqlite has a larger limit; emulate the native error for migration
      // tests. The writer must use SQLite's actual capacity, not a guessed size.
      if (query.startsWith('INSERT OR REPLACE INTO snapshot ') && values[0].byteLength > snapshotLimit) throw new Error('string or blob too big: SQLITE_TOOBIG');
      const rows = database.prepare(query).all(...values); return { toArray: () => rows };
    } },
    transactionSync<T>(run: () => T): T {
      const id = `tx${++transaction}`; database.exec(`SAVEPOINT ${id}`);
      try { const value = run(); database.exec(`RELEASE ${id}`); return value; }
      catch (error) { database.exec(`ROLLBACK TO ${id}; RELEASE ${id}`); throw error; }
    },
  } };
  const create = (factory = projectRoomClass, bindings = env) => new (factory({ Y, sync }))(ctx, bindings);
  const room = create();
  const rows = (query: string) => (database.prepare(query).all() as { data: Uint8Array }[]).map(row => row.data);
  const count = (table: string) => (database.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
  function saved() {
    const doc = new Y.Doc();
    const legacy = rows('SELECT data FROM snapshot WHERE id = 1');
    const snapshot = legacy.length ? legacy : rows('SELECT data FROM snapshot_parts ORDER BY part');
    if (snapshot.length) Y.applyUpdate(doc, Buffer.concat(snapshot));
    for (const data of rows('SELECT data FROM updates ORDER BY seq')) Y.applyUpdate(doc, data);
    return doc;
  }
  return { room, create, ctx, database, sockets, saved, count };
}
function syncStep1() { const e = encoding.createEncoder(); encoding.writeVarUint(e, 0); sync.writeSyncStep1(e, new Y.Doc()); return encoding.toUint8Array(e); }
function wire(update: Uint8Array) { const e = encoding.createEncoder(); encoding.writeVarUint(e, 0); sync.writeUpdate(e, update); return encoding.toUint8Array(e); }
function message(room: any, peer: ReturnType<typeof socket>, bytes: Uint8Array) { room.webSocketMessage(peer, bytes.slice().buffer); }
function readUpdates(peer: ReturnType<typeof socket>, doc: Y.Doc) {
  for (const [bytes] of peer.send.mock.calls) {
    const d = decoding.createDecoder(bytes);
    if (decoding.readVarUint(d) === 0) sync.readSyncMessage(d, encoding.createEncoder(), doc, 'server');
  }
}
function present(id: number, clock: number, name: string | null) {
  return presenceMessage([{ clientId: id, clock, state: name === null ? null : { user: { name, color: '#abcdef' }, editor: { selectedIds: [], cursor: null } } }]);
}
function receivedPresence(peer: ReturnType<typeof socket>) {
  const entries: Array<{ id: number; clock: number; state: any }> = [];
  for (const [bytes] of peer.send.mock.calls) {
    const d = decoding.createDecoder(bytes);
    if (decoding.readVarUint(d) !== 1) continue;
    const update = decoding.createDecoder(decoding.readVarUint8Array(d)), n = decoding.readVarUint(update);
    for (let i = 0; i < n; i++) entries.push({ id: decoding.readVarUint(update), clock: decoding.readVarUint(update), state: JSON.parse(decoding.readVarString(update)) });
  }
  return entries;
}

test('journals every edit before batching and restores a batch interrupted before delivery', () => {
  const f = fixture(), source = f.saved(), updates: Uint8Array[] = [];
  source.on('update', update => updates.push(update));
  source.getMap('project').set('name', 'First'); source.getMap('project').set('name', 'Final');
  for (const update of updates) message(f.room, f.sockets[0], wire(update));
  expect(f.sockets[1].send).not.toHaveBeenCalled();
  message(f.room, f.sockets[0], new Uint8Array([0, 0, 1, 0]));
  const restored = f.saved(); expect(restored.getMap('project').get('name')).toBe('Final');
  vi.advanceTimersByTime(16); expect(f.sockets[1].send).toHaveBeenCalledTimes(1);
  const peer = new Y.Doc(); readUpdates(f.sockets[1], peer); // dependency must be restored before batch
  Y.applyUpdate(peer, Y.encodeStateAsUpdate(restored)); expect(peer.getMap('project').get('name')).toBe('Final');
  source.destroy(); restored.destroy(); peer.destroy();
});

test('coalesces cursor clocks, indexes owners and keeps the replacement through a late close and hibernation', () => {
  const f = fixture([socket(), socket(), socket()]), [old, replacement, observer] = f.sockets;
  message(f.room, old, present(77, 1, 'Old'));
  for (let clock = 2; clock <= 100; clock++) message(f.room, old, present(77, clock, 'Moved'));
  message(f.room, replacement, present(77, 101, 'New'));
  expect(old.close).toHaveBeenCalledWith(1000, 'Connection replaced');
  message(f.room, old, present(77, 999, 'Late retired frame'));
  f.room.webSocketClose(old);
  vi.advanceTimersByTime(100);
  expect(receivedPresence(observer)).toEqual([{ id: 77, clock: 101, state: { user: { name: 'New', color: '#abcdef' }, editor: { selectedIds: [], cursor: null } } }]);
  expect(f.ctx.getWebSockets).toHaveBeenCalledTimes(1);
  expect(old.deserializeAttachment).toHaveBeenCalledTimes(2);
  observer.send.mockClear(); old.readyState = 3;
  const restored = f.create(); restored.webSocketClose(old); vi.advanceTimersByTime(100);
  expect(receivedPresence(observer)).toEqual([]);
  replacement.readyState = 3; restored.webSocketClose(replacement); vi.advanceTimersByTime(100);
  expect(receivedPresence(observer)).toEqual([{ id: 77, clock: 101, state: null }]);
});

test('hibernation followed immediately by disconnect publishes removal even when getWebSockets omits the closed socket', () => {
  const f = fixture(), [leaving, observer] = f.sockets;
  message(f.room, leaving, present(88, 3, 'Leaving')); vi.advanceTimersByTime(100); observer.send.mockClear();
  leaving.readyState = 3; f.sockets.splice(0, 1);
  const restored = f.create(); restored.webSocketClose(leaving); vi.advanceTimersByTime(100);
  expect(receivedPresence(observer)).toEqual([{ id: 88, clock: 3, state: null }]);
});

test('rolls back a failed journal write and aborts without publishing uncommitted state', () => {
  const f = fixture(), source = f.saved();
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; }); source.getMap('project').set('name', 'Must not publish');
  const exec = f.ctx.storage.sql.exec;
  vi.spyOn(f.ctx.storage.sql, 'exec').mockImplementation((query, ...values) => { if (query.startsWith('INSERT INTO updates')) throw new Error('disk full'); return exec(query, ...values); });
  message(f.room, f.sockets[0], wire(update)); message(f.room, f.sockets[0], new Uint8Array([0, 0, 1, 0])); vi.advanceTimersByTime(1000);
  expect(f.ctx.abort).toHaveBeenCalledOnce(); expect(f.sockets[1].send).not.toHaveBeenCalled(); source.destroy();
});

test('accepts the configured room capacity and returns 429 before allocating an extra WebSocket', async () => {
  const f = fixture(Array.from({ length: 512 }, socket));
  const response = await f.room.fetch(new Request('https://test/sync/room', { headers: { Upgrade: 'websocket' } }));
  expect(response.status).toBe(429); expect(f.ctx.getWebSockets).toHaveBeenCalledOnce();
});

test('a malformed frame cannot poison another sender’s queued edits', () => {
  const f = fixture([socket(), socket(), socket()]), source = f.saved();
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; }); source.getMap('project').set('name', 'Valid');
  message(f.room, f.sockets[0], wire(update));
  message(f.room, f.sockets[1], wire(new Uint8Array([255])));
  expect(f.sockets[1].close).toHaveBeenCalledWith(1003, 'Invalid document update');
  vi.advanceTimersByTime(26);
  const recovered = f.saved(); expect(recovered.getMap('project').get('name')).toBe('Valid');
  expect(f.sockets[2].send).toHaveBeenCalledOnce(); expect(f.ctx.abort).not.toHaveBeenCalled();
  source.destroy(); recovered.destroy();
});

test.each([false, true])('large incoming updates preserve a restartable journal until multipart writes are enabled (%s)', multipart => {
  const f = fixture(undefined, multipart ? { ROOM_SNAPSHOT_PARTS_WRITE: 'true' } : {}), source = f.saved();
  expect(f.count('snapshot')).toBe(1); expect(f.count('snapshot_parts')).toBe(1);
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  for (const key of ['first', 'second', 'third']) {
    source.getMap('project').set(key, key + 'x'.repeat(1_500_000));
    message(f.room, f.sockets[0], wire(update));
  }
  expect(f.count('updates')).toBe(multipart ? 0 : 3); expect(f.count('snapshot')).toBe(multipart ? 0 : 1);
  expect(f.count('snapshot_parts')).toBe(multipart ? 5 : 1);
  expect((f.database.prepare('SELECT MAX(LENGTH(data)) AS n FROM snapshot_parts').get() as { n: number }).n).toBeLessThanOrEqual(1048576);
  // A reader-capable release can be rolled back to with the writer gate off.
  const restored = f.create(projectRoomClass, {}); f.sockets[0].send.mockClear();
  message(restored, f.sockets[0], syncStep1());
  const peer = new Y.Doc(); readUpdates(f.sockets[0], peer);
  for (const key of ['first', 'second', 'third']) expect(peer.getMap('project').get(key)).toBe(key + 'x'.repeat(1_500_000));
  expect(peer.getMap('project').get('name')).toBe('A little motion');
  if (!multipart) {
    // The actual previous implementation must recover the retained journal,
    // including a document beyond its own single-row compaction capacity.
    f.sockets[0].send.mockClear(); message(f.create(oldRoomClass), f.sockets[0], syncStep1());
    const oldPeer = new Y.Doc(); readUpdates(f.sockets[0], oldPeer);
    expect(oldPeer.getMap('project').toJSON()).toEqual(peer.getMap('project').toJSON()); oldPeer.destroy();
    f.sockets[0].send.mockClear(); message(f.create(), f.sockets[0], syncStep1());
    const newPeer = new Y.Doc(); readUpdates(f.sockets[0], newPeer);
    expect(newPeer.getMap('project').toJSON()).toEqual(peer.getMap('project').toJSON()); newPeer.destroy();
  }
  source.destroy(); peer.destroy();
});

test('new → actual old → new Room keeps a 500-object / five-composition snapshot and rollback edits', () => {
  const f = fixture(), project = largeImportProject(), scene = project.scenes['scene-1'];
  for (const id of scene.compositionOrder.slice(5)) delete scene.compositions[id];
  scene.compositionOrder = scene.compositionOrder.slice(0, 5);
  const source = f.saved();
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  source.transact(() => { source.getMap('project').clear(); initializeDocument(source, project); });
  message(f.room, f.sockets[0], wire(update));
  const publish = (room: any, doc: Y.Doc, prefix: string) => {
    let next!: Uint8Array; const collect = (bytes: Uint8Array) => { next = bytes; }; doc.on('update', collect);
    for (let i = 0; i < 256; i++) {
      doc.getMap('project').set('name', `${prefix} ${i}`);
      message(room, f.sockets[0], wire(next)); vi.advanceTimersByTime(26);
    }
    doc.off('update', collect);
  };
  publish(f.room, source, 'Before rollback');
  const bytes = (f.database.prepare('SELECT LENGTH(data) AS n FROM snapshot WHERE id = 1').get() as { n: number }).n;
  expect(bytes).toBeGreaterThan(1048576); expect(bytes).toBeLessThan(2 * 1048576);
  expect(f.count('snapshot_parts')).toBe(2);
  const staleParts = f.database.prepare('SELECT data FROM snapshot_parts ORDER BY part').all();
  const read = (room: any) => {
    f.sockets[0].send.mockClear(); message(room, f.sockets[0], syncStep1());
    const doc = new Y.Doc(); readUpdates(f.sockets[0], doc); return doc;
  };
  const oldRoom = f.create(oldRoomClass), oldPeer = read(oldRoom);
  expect(readProject(oldPeer)).toEqual(readProject(source));
  publish(oldRoom, oldPeer, 'Edited after rollback');
  expect(f.database.prepare('SELECT data FROM snapshot_parts ORDER BY part').all()).toEqual(staleParts);
  const newPeer = read(f.create());
  expect(readProject(newPeer)).toEqual(readProject(oldPeer));
  expect(readProject(newPeer)?.scenes['scene-1'].compositionOrder).toHaveLength(5);
  expect(Object.keys(readProject(newPeer)!.scenes['scene-1'].objects)).toHaveLength(500);
  expect(f.ctx.abort).not.toHaveBeenCalled();
  source.destroy(); oldPeer.destroy(); newPeer.destroy();
});

test.each(['incoming', 'constructor'])('journals automatic migration identities when %s compaction is deferred', where => {
  const f = fixture(undefined, {}, 64 * 1024), source = f.saved();
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  source.transact(() => {
    source.getMap('project').set('padding', 'x'.repeat(100_000));
    const scene = (source.getMap('project').get('scenes') as Y.Map<any>).get('scene-1') as Y.Map<any>;
    scene.delete('audioTracks');
    for (const transition of scene.get('transitions').values()) for (const id of [...transition.get('tracks').keys()]) transition.get('tracks').delete(id);
  });
  let room = f.room;
  if (where === 'constructor') {
    f.database.prepare('INSERT INTO updates (data) VALUES (?)').run(update); room = f.create();
  } else { message(room, f.sockets[0], wire(update)); vi.advanceTimersByTime(26); }
  expect(f.count('snapshot')).toBe(1); expect(f.count('updates')).toBeGreaterThan(1);
  const stored = f.saved();
  f.sockets[0].send.mockClear(); message(room, f.sockets[0], syncStep1());
  const live = new Y.Doc(); readUpdates(f.sockets[0], live);
  expect(Y.encodeStateVector(stored)).toEqual(Y.encodeStateVector(live));
  const rowsBeforeRestart = f.count('updates'); f.create();
  expect(f.count('updates')).toBe(rowsBeforeRestart);
  expect(f.ctx.abort).not.toHaveBeenCalled();
  source.destroy(); stored.destroy(); live.destroy();
});

test('a non-size snapshot error aborts and rolls back instead of activating multipart writes', () => {
  const f = fixture(undefined, { ROOM_SNAPSHOT_PARTS_WRITE: 'true' }), source = f.saved();
  const before = f.database.prepare('SELECT data FROM snapshot WHERE id = 1').get();
  const exec = f.ctx.storage.sql.exec;
  vi.spyOn(f.ctx.storage.sql, 'exec').mockImplementation((query, ...values) => {
    if (query.startsWith('INSERT OR REPLACE INTO snapshot ')) throw new Error('disk full');
    return exec(query, ...values);
  });
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  for (const key of ['first', 'second', 'third']) {
    source.getMap('project').set(key, 'x'.repeat(1_500_000));
    message(f.room, f.sockets[0], wire(update));
  }
  expect(f.ctx.abort).toHaveBeenCalledOnce();
  expect(f.database.prepare('SELECT data FROM snapshot WHERE id = 1').get()).toEqual(before);
  expect(f.count('snapshot_parts')).toBe(1); expect(f.count('updates')).toBe(2);
  expect(f.saved().getMap('project').has('third')).toBe(false);
  source.destroy();
});

test('full rosters remain readable by legacy clients with a 16 KiB / 100-entry input budget', () => {
  const f = fixture(Array.from({ length: 500 }, socket));
  for (let i = 0; i < f.sockets.length; i++) message(f.room, f.sockets[i], present(1000 + i, 1, `Peer ${i}`));
  vi.advanceTimersByTime(100); const observer = f.sockets[0]; observer.send.mockClear();
  message(f.room, observer, new Uint8Array([3]));
  const entries = receivedPresence(observer); expect(entries).toHaveLength(500);
  for (const [bytes] of observer.send.mock.calls) expect(bytes.byteLength).toBeLessThan(16384);
  // Simulate a stock y-websocket client relaying the received roster.
  for (const [bytes] of [...observer.send.mock.calls]) message(f.room, observer, bytes);
  expect(observer.close).not.toHaveBeenCalled();
});

test.each([false, true])('reads the latest legacy snapshot and migrates it on compaction (stale parts: %s)', staleParts => {
  const f = fixture(undefined, { ROOM_SNAPSHOT_PARTS_WRITE: 'true' });
  // Old deployments compact only the legacy row, possibly leaving stale parts after a rollback.
  const legacy = f.saved(); legacy.getMap('project').set('name', 'Legacy');
  if (!staleParts) f.database.exec('DELETE FROM snapshot_parts');
  f.database.prepare('INSERT OR REPLACE INTO snapshot (id, data) VALUES (1, ?)').run(Y.encodeStateAsUpdate(legacy));
  legacy.on('update', bytes => f.database.prepare('INSERT INTO updates (data) VALUES (?)').run(bytes));
  legacy.getMap('project').set('name', 'Latest edit'); // depends on the legacy compaction
  const room = f.create();
  expect(f.count('snapshot')).toBe(1); expect(f.count('snapshot_parts')).toBe(staleParts ? 1 : 0);
  message(room, f.sockets[0], syncStep1());
  const peer = new Y.Doc(); readUpdates(f.sockets[0], peer);
  expect(peer.getMap('project').get('name')).toBe('Latest edit');
  const source = f.saved(); let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  for (const key of ['first', 'second', 'third']) {
    source.getMap('project').set(key, 'x'.repeat(1_500_000));
    message(room, f.sockets[0], wire(update));
  }
  expect(f.count('snapshot')).toBe(0); expect(f.count('snapshot_parts')).toBeGreaterThan(1);
  expect(f.saved().getMap('project').get('name')).toBe('Latest edit');
  legacy.destroy(); source.destroy(); peer.destroy();
});

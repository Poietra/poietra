import { DatabaseSync } from 'node:sqlite';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import * as sync from 'y-protocols/sync';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import { projectRoomClass } from '../../../_build/js/release/build/worker_room/worker_room.js';
import { presenceMessage } from '../worker/presence';

const databases: DatabaseSync[] = [];
beforeEach(() => vi.useFakeTimers());
afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); vi.restoreAllMocks(); for (const db of databases.splice(0)) db.close(); });
function socket() {
  let attachment: unknown = null;
  return { readyState: 1, send: vi.fn(), close: vi.fn(),
    serializeAttachment: vi.fn((value: unknown) => { attachment = structuredClone(value); }),
    deserializeAttachment: vi.fn(() => structuredClone(attachment)),
  };
}
function fixture(sockets = [socket(), socket()]) {
  const database = new DatabaseSync(':memory:'); databases.push(database);
  let transaction = 0;
  const ctx = { getWebSockets: vi.fn(() => sockets), abort: vi.fn(() => { throw new Error('aborted'); }), storage: {
    sql: { exec(query: string, ...values: any[]) { const rows = database.prepare(query).all(...values); return { toArray: () => rows }; } },
    transactionSync<T>(run: () => T): T {
      const id = `tx${++transaction}`; database.exec(`SAVEPOINT ${id}`);
      try { const value = run(); database.exec(`RELEASE ${id}`); return value; }
      catch (error) { database.exec(`ROLLBACK TO ${id}; RELEASE ${id}`); throw error; }
    },
  } };
  const Room = projectRoomClass({ Y, sync });
  const create = () => new Room(ctx, {});
  const room = create();
  function saved() {
    const doc = new Y.Doc();
    for (const { data } of database.prepare('SELECT data FROM snapshot UNION ALL SELECT data FROM updates ORDER BY 1').all() as { data: Uint8Array }[]) Y.applyUpdate(doc, data);
    return doc;
  }
  return { room, create, ctx, database, sockets, saved };
}
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

test('large incoming updates compact the journal by bytes, before its row count limit', () => {
  const f = fixture(), source = f.saved();
  let update!: Uint8Array; source.on('update', bytes => { update = bytes; });
  for (let i = 0; i < 3; i++) {
    source.getMap('project').set('name', String(i) + 'x'.repeat(1_500_000));
    message(f.room, f.sockets[0], wire(update));
  }
  expect((f.database.prepare('SELECT COUNT(*) AS n FROM updates').get() as { n: number }).n).toBe(0);
  const recovered = f.saved(); expect(recovered.getMap('project').get('name')).toBe('2' + 'x'.repeat(1_500_000));
  source.destroy(); recovered.destroy();
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

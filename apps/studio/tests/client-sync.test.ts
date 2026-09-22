import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import { batchedWebsocketClass } from '../../../_build/js/release/build/client_sync/client_sync.js';

class NativeSocket extends EventTarget {
  readyState = 1;
  sent: any[] = [];
  send(data: any) { if (this.readyState === 0) throw new Error('Connecting'); if (this.readyState === 1) this.sent.push(data instanceof Uint8Array ? data.slice() : data); }
  close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
}
type Socket = NativeSocket & { flushDocuments(): void };
const sockets: Socket[] = [], docs: Y.Doc[] = [];
beforeEach(() => vi.useFakeTimers());
afterEach(() => { for (const socket of sockets.splice(0)) socket.close(); for (const doc of docs.splice(0)) doc.destroy(); vi.clearAllTimers(); vi.useRealTimers(); });
function socket(interval = 50): Socket { const Type = batchedWebsocketClass(NativeSocket, Y, () => interval); const value = new Type(); sockets.push(value); return value; }
function doc() { const value = new Y.Doc(); docs.push(value); return value; }
function packet(update: Uint8Array, kind = 2) {
  const encoder = encoding.createEncoder(); encoding.writeVarUint(encoder, 0); encoding.writeVarUint(encoder, kind); encoding.writeVarUint8Array(encoder, update); return encoding.toUint8Array(encoder);
}
function apply(socket: Socket, target = doc()) {
  for (const frame of socket.sent) {
    const decoder = decoding.createDecoder(frame);
    expect(decoding.readVarUint(decoder)).toBe(0); expect(decoding.readVarUint(decoder)).toBe(2);
    Y.applyUpdate(target, decoding.readVarUint8Array(decoder));
  }
  return target;
}

test('local edits stay immediate; a 50ms burst becomes one lossless update including deletions', () => {
  const transport = socket(), source = doc();
  source.on('update', update => transport.send(packet(update)));
  for (let i = 0; i < 100; i++) source.getMap('poses').set('x', i);
  source.getMap('poses').set('temporary', true); source.getMap('poses').delete('temporary');
  expect(source.getMap('poses').toJSON()).toEqual({ x: 99 }); expect(transport.sent).toHaveLength(0);
  vi.advanceTimersByTime(49); expect(transport.sent).toHaveLength(0);
  vi.advanceTimersByTime(1); expect(transport.sent).toHaveLength(1);
  expect(apply(transport).getMap('poses').toJSON()).toEqual({ x: 99 });
  expect(vi.getTimerCount()).toBe(0);
});

test('continuous 16ms edits drain every batch window instead of postponing delivery until the pointer stops', () => {
  const transport = socket(), source = doc();
  source.on('update', update => transport.send(packet(update)));
  for (let i = 0; i < 90; i++) {
    source.getMap('poses').set('x', i);
    vi.advanceTimersByTime(16);
    if (i === 3) expect(apply(transport).getMap('poses').get('x')).toBe(3);
  }
  transport.flushDocuments();
  expect(transport.sent).toHaveLength(23);
  expect(apply(transport).getMap('poses').get('x')).toBe(89);
});

test.each([0, 1])('queued edits precede sync step %i and control frames keep their bytes', kind => {
  const transport = socket(), source = doc(); source.getMap('data').set('x', 1);
  transport.send(packet(Y.encodeStateAsUpdate(source)));
  const barrier = packet(Y.encodeStateVector(source), kind); transport.send(barrier);
  expect(transport.sent).toHaveLength(2); expect(transport.sent[1]).toEqual(barrier);
  expect(apply({ sent: [transport.sent[0]] } as Socket).getMap('data').get('x')).toBe(1);
  vi.advanceTimersByTime(1000); expect(transport.sent).toHaveLength(2);
});

test('native buffer ownership, text frames and malformed non-update frames are preserved', () => {
  const transport = socket(), source = doc(); source.getMap('data').set('x', 42);
  const frame = packet(Y.encodeStateAsUpdate(source)); transport.send(frame); frame.fill(0);
  transport.flushDocuments(); expect(apply(transport).getMap('data').get('x')).toBe(42);
  const malformed = new Uint8Array([0, 2, 200]); transport.send(malformed); transport.send('native text');
  expect(transport.sent.slice(1)).toEqual([malformed, 'native text']);
});

test('128-update and 256KiB bounds flush without losing state; large individual updates pass through', () => {
  const transport = socket(), source = doc(); source.on('update', update => transport.send(packet(update)));
  for (let i = 0; i < 129; i++) source.getMap('data').set('x', i);
  expect(transport.sent).toHaveLength(1); transport.flushDocuments(); expect(transport.sent).toHaveLength(2);
  source.getMap('data').set('a', 'a'.repeat(150_000)); source.getMap('data').set('b', 'b'.repeat(150_000));
  expect(transport.sent).toHaveLength(3);
  source.getMap('data').set('c', 'c'.repeat(270_000)); expect(transport.sent).toHaveLength(5);
  expect(apply(transport).getMap('data').toJSON()).toEqual(source.getMap('data').toJSON());
});

test('close flushes first; unexpected loss cancels the old outbox and state can resync on a new connection', () => {
  const transport = socket(), source = doc(); source.getMap('data').set('x', 1);
  transport.send(packet(Y.encodeStateAsUpdate(source))); transport.close();
  expect(transport.sent).toHaveLength(1); expect(vi.getTimerCount()).toBe(0);
  const lost = socket(); source.getMap('data').set('x', 2); lost.send(packet(Y.encodeStateAsUpdate(source)));
  lost.readyState = 3; lost.dispatchEvent(new Event('close')); vi.advanceTimersByTime(500);
  expect(lost.sent).toHaveLength(0); expect(vi.getTimerCount()).toBe(0);
  const next = socket(); next.send(packet(Y.encodeStateAsUpdate(source))); next.flushDocuments();
  expect(apply(next).getMap('data').get('x')).toBe(2);
});

test('out-of-order updates retain missing dependencies through merging', () => {
  const transport = socket(), source = doc(), updates: Uint8Array[] = [];
  source.on('update', update => updates.push(update));
  source.getMap('data').set('first', 1); source.getMap('data').set('second', 2); source.getMap('data').set('third', 3);
  transport.send(packet(updates[2])); transport.send(packet(updates[1])); transport.flushDocuments();
  const target = apply(transport); expect(target.getMap('data').size).toBe(0);
  Y.applyUpdate(target, updates[0]); expect(target.getMap('data').toJSON()).toEqual(source.getMap('data').toJSON());
});

test('local Undo can be merged with a gesture without erasing an independent peer edit', () => {
  const transport = socket(), source = doc(), peer = doc();
  source.getMap('data').set('x', 1); Y.applyUpdate(peer, Y.encodeStateAsUpdate(source));
  const undo = new Y.UndoManager(source.getMap('data'), { trackedOrigins: new Set(['local']) });
  source.on('update', (update, origin) => { if (origin !== 'remote') transport.send(packet(update)); });
  source.transact(() => source.getMap('data').set('x', 2), 'local');
  peer.getMap('data').set('fill', '#abcdef'); Y.applyUpdate(source, Y.encodeStateAsUpdate(peer), 'remote');
  undo.undo(); transport.flushDocuments(); apply(transport, peer);
  expect(peer.getMap('data').toJSON()).toEqual({ x: 1, fill: '#abcdef' }); undo.destroy();
});

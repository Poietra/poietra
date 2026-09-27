import { afterAll, beforeAll, expect, test, vi } from 'vitest';
import { EventEmitter, once } from 'node:events';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { presenceMessage } from '../worker/presence';
import type { Room } from '../server/collaboration';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import * as sync from 'y-protocols/sync';

let directory: string;
let server: WebSocketServer;
let room: Room;
const sockets: WebSocket[] = [];

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), 'poietra-node-collaboration-'));
  vi.stubEnv('POIETRA_DATA_DIR', directory);
  const { Room } = await import('../server/collaboration');
  room = new Room('presence-reconnect-test');
  server = new WebSocketServer({ port: 0 });
  server.on('connection', socket => room.connect(socket));
  await once(server, 'listening');
});

afterAll(async () => {
  for (const socket of sockets) socket.terminate();
  for (const socket of server.clients) socket.terminate();
  await new Promise<void>(resolve => server.close(() => resolve()));
  room.dispose();
  vi.unstubAllEnvs();
  await rm(directory, { recursive: true, force: true });
});

async function connect() {
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing test server address');
  const socket = new WebSocket(`ws://127.0.0.1:${address.port}`);
  sockets.push(socket);
  await once(socket, 'open');
  return socket;
}

function presence(socket: WebSocket, clientId: number, clock: number, name: string | null) {
  socket.send(presenceMessage([{ clientId, clock, state: name === null ? null : {
    user: { name, color: '#abcdef' }, editor: { selectedIds: [], cursor: null },
  } }]));
}

test('the local server preserves socket ownership through reconnect and remote timeout notices', async () => {
  const original = await connect(); const peer = await connect();
  presence(original, 99, 3, 'Alice'); presence(peer, 100, 3, 'Bob');
  await expect.poll(() => room.awareness.getStates().size).toBe(2);
  presence(peer, 99, 3, null);
  presence(peer, 100, 4, 'Bob');
  await expect.poll(() => room.awareness.meta.get(100)?.clock).toBe(4);
  expect(room.awareness.getStates().get(99)?.user.name).toBe('Alice');

  const oldClosed = once(original, 'close');
  const replacement = await connect();
  presence(replacement, 99, 4, 'Alice reconnected');
  await expect.poll(() => room.awareness.getStates().get(99)?.user.name).toBe('Alice reconnected');
  await oldClosed;
  expect(room.connections.size).toBe(2);
  expect(room.awareness.getStates().get(99)?.user.name).toBe('Alice reconnected');
  replacement.close(); await once(replacement, 'close');
  await expect.poll(() => room.awareness.getStates().has(99)).toBe(false);
  expect(room.awareness.getStates().get(100)?.user.name).toBe('Bob');
});

test('new rooms evict saved inactive rooms and restore them without evicting an AI request', async () => {
  const { getRoom, rooms } = await import('../server/collaboration');
  try {
    const busy = getRoom('capacity-room-00000'); busy.aiBusy = true;
    const saved = getRoom('capacity-room-00001'); saved.doc.getMap('project').set('name', 'Saved before eviction');
    const destroyed = vi.fn(); saved.doc.on('destroy', destroyed);
    for (let i = 2; i <= 100; i++) getRoom(`capacity-room-${String(i).padStart(5, '0')}`);
    expect(rooms.size).toBe(100);
    expect(rooms.get('capacity-room-00000')).toBe(busy);
    expect(destroyed).toHaveBeenCalledOnce();
    expect(rooms.has('capacity-room-00001')).toBe(false);
    expect(getRoom('capacity-room-00001').doc.getMap('project').get('name')).toBe('Saved before eviction');
  } finally {
    for (const room of rooms.values()) { room.aiBusy = false; room.dispose(); }
    rooms.clear();
  }
});

test('saves an out-of-order update before disconnect so a restart can finish it when its dependency arrives', async () => {
  const socket = await connect(), peer = new Y.Doc(), updates: Uint8Array[] = [];
  Y.applyUpdate(peer, Y.encodeStateAsUpdate(room.doc));
  peer.on('update', update => updates.push(update));
  const parent = new Y.Map();
  peer.getMap('project').set('pending-parent', parent);
  parent.set('value', 'survives restart');
  expect(updates).toHaveLength(2);
  const send = (update: Uint8Array) => {
    const message = encoding.createEncoder(); encoding.writeVarUint(message, 0);
    sync.writeUpdate(message, update); socket.send(encoding.toUint8Array(message));
  };
  try {
    send(updates[1]);
    await expect.poll(async () => {
      const recovered = new Y.Doc();
      try {
        Y.applyUpdate(recovered, await readFile(join(directory, `${room.id}.yjs`)));
        Y.applyUpdate(recovered, updates[0]);
        return (recovered.getMap('project').get('pending-parent') as Y.Map<string> | undefined)?.get('value');
      } finally { recovered.destroy(); }
    }).toBe('survives restart');
    expect(room.doc.getMap('project').has('pending-parent')).toBe(false);
    send(updates[0]);
    await expect.poll(() => (room.doc.getMap('project').get('pending-parent') as Y.Map<string> | undefined)?.get('value')).toBe('survives restart');
  } finally { socket.close(); peer.destroy(); }
});

// Model ws's public write callback, including a healthy large write that remains
// buffered while its following acknowledgment arrives. No socket-private hooks.
class ControlledSocket extends EventEmitter {
  readyState = 1;
  bufferedAmount = 0;
  sent: Uint8Array[] = [];
  writes: { size: number; done: (error?: Error) => void }[] = [];
  closed: { code: number; reason: string }[] = [];
  onSend?: (data: Uint8Array) => void;
  send(data: Uint8Array, done: (error?: Error) => void) {
    this.onSend?.(data);
    this.sent.push(data); this.bufferedAmount += data.byteLength;
    this.writes.push({ size: data.byteLength, done });
  }
  finish(error?: Error) {
    const write = this.writes.shift();
    if (!write) throw new Error('No pending write');
    this.bufferedAmount -= write.size; write.done(error);
  }
  close(code = 1000, reason = '') {
    this.closed.push({ code, reason }); this.readyState = 3; this.emit('close');
  }
}

function syncPacket(write: (encoder: encoding.Encoder) => void) {
  const encoder = encoding.createEncoder(); encoding.writeVarUint(encoder, 0);
  write(encoder); return encoding.toUint8Array(encoder);
}

test('a large legal update and its ordered acknowledgment wait for write completion without disconnecting', async () => {
  const { Room } = await import('../server/collaboration');
  const target = new Room('large-write-order'), socket = new ControlledSocket(), peer = new Y.Doc();
  try {
    const baseline = Y.encodeStateAsUpdate(target.doc);
    Y.applyUpdate(peer, baseline);
    const before = Y.encodeStateVector(peer), value = 'x'.repeat(1200000);
    peer.getMap('project').set('large-field', value);
    const update = syncPacket(encoder => sync.writeUpdate(encoder, Y.encodeStateAsUpdate(peer, before)));
    expect(update.byteLength).toBeGreaterThan(1048576);
    expect(update.byteLength).toBeLessThan(2097152);
    target.connect(socket as unknown as WebSocket);
    const published: string[] = [];
    socket.onSend = () => {
      const saved = new Y.Doc();
      try {
        Y.applyUpdate(saved, readFileSync(join(directory, `${target.id}.yjs`)));
        published.push(saved.getMap('project').get('large-field') as string);
      } finally { saved.destroy(); }
    };
    // The initial sync request is still being sent when the large update arrives.
    socket.emit('message', update);
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, peer)));
    expect(socket.sent).toHaveLength(1);
    socket.finish(); // sends the large echo
    expect(socket.sent).toHaveLength(2);
    expect(socket.bufferedAmount).toBeGreaterThan(1048576);
    socket.finish(); // sends the acknowledgment only after the echo is drained
    expect(socket.sent).toHaveLength(3);
    socket.finish();
    expect(socket.closed).toEqual([]);
    expect(published).toEqual([value, value]);
    expect(target.doc.getMap('project').get('large-field')).toBe(value);
    const replica = new Y.Doc();
    try {
      Y.applyUpdate(replica, baseline);
      const kinds: number[] = [];
      for (const packet of socket.sent.slice(1)) {
        const decoder = decoding.createDecoder(packet); expect(decoding.readVarUint(decoder)).toBe(0);
        kinds.push(sync.readSyncMessage(decoder, encoding.createEncoder(), replica, null));
      }
      expect(kinds).toEqual([sync.messageYjsUpdate, sync.messageYjsSyncStep2]);
      expect(replica.getMap('project').get('large-field')).toBe(value);
    } finally { replica.destroy(); }
  } finally { socket.close(); peer.destroy(); expect(target.dispose()).toBe(true); }
});

test.each(['bytes', 'packets'] as const)('a stalled peer has bounded %s and late callbacks cannot restart its queue', async limit => {
  const { Room } = await import('../server/collaboration');
  const target = new Room(`stalled-write-${limit}`), socket = new ControlledSocket(), empty = new Y.Doc();
  try {
    target.connect(socket as unknown as WebSocket);
    const request = syncPacket(encoder => sync.writeSyncStep1(encoder, empty));
    let produced = 0;
    while (produced < 130 && socket.readyState === 1) {
      if (limit === 'bytes') target.doc.getMap('project').set('large-field', `${produced}${'x'.repeat(1200000)}`);
      else socket.emit('message', request);
      produced++;
    }
    expect(produced).toBe(limit === 'bytes' ? 2 : 129);
    expect(socket.closed).toEqual([{ code: 1013, reason: 'Slow connection; resynchronize' }]);
    expect(target.connections.size).toBe(0);
    expect(socket.sent).toHaveLength(1);
    socket.finish();
    expect(socket.sent).toHaveLength(1);
  } finally { empty.destroy(); expect(target.dispose()).toBe(true); }
});

test('a large server correction precedes a deferred sync reply without retaining a second correction buffer', async () => {
  const { Room } = await import('../server/collaboration');
  const target = new Room('deferred-large-reply'), socket = new ControlledSocket(), peer = new Y.Doc();
  try {
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(target.doc));
    const before = Y.encodeStateVector(peer); peer.getMap('project').set('import', 'x'.repeat(1200000));
    target.connect(socket as unknown as WebSocket); socket.finish();
    socket.emit('message', syncPacket(encoder => sync.writeUpdate(encoder, Y.encodeStateAsUpdate(peer, before))));
    target.doc.getMap('project').set('server-correction', 'y'.repeat(1200000));
    const request = syncPacket(encoder => sync.writeSyncStep1(encoder, peer));
    socket.emit('message', request); request.fill(255);
    target.doc.getMap('project').set('later', 'also persisted before reply');
    expect(socket.sent).toHaveLength(2);
    expect(socket.closed).toEqual([]);
    socket.finish(); socket.finish(); socket.finish();
    expect(socket.sent).toHaveLength(4);
    const decoder = decoding.createDecoder(socket.sent[3]);
    expect(decoding.readVarUint(decoder)).toBe(0);
    expect(sync.readSyncMessage(decoder, encoding.createEncoder(), peer, null)).toBe(sync.messageYjsSyncStep2);
    expect(peer.getMap('project').get('server-correction')).toBe('y'.repeat(1200000));
    expect(peer.getMap('project').get('later')).toBe('also persisted before reply');
  } finally { socket.close(); peer.destroy(); expect(target.dispose()).toBe(true); }
});

test('a malformed sync vector fails on arrival and cancels replies behind a stalled write', async () => {
  const { Room } = await import('../server/collaboration');
  const target = new Room('invalid-deferred-vector'), socket = new ControlledSocket();
  try {
    target.connect(socket as unknown as WebSocket);
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, target.doc)));
    socket.emit('message', new Uint8Array([0, 0, 1, 255]));
    expect(socket.closed).toEqual([{ code: 1003, reason: 'Invalid document update' }]);
    socket.finish(); expect(socket.sent).toHaveLength(1);
  } finally { expect(target.dispose()).toBe(true); }
});

test('a write callback error discards pending packets and removes only the failed connection', async () => {
  const { Room } = await import('../server/collaboration');
  const target = new Room('failed-write'), socket = new ControlledSocket(), other = new ControlledSocket();
  try {
    target.connect(socket as unknown as WebSocket); target.connect(other as unknown as WebSocket);
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, target.doc)));
    socket.finish(new Error('write failed'));
    expect(socket.closed).toEqual([{ code: 1011, reason: 'Send failed; resynchronize' }]);
    expect(socket.sent).toHaveLength(1);
    expect(target.connections.size).toBe(1);
    other.finish(); expect(other.closed).toEqual([]);
  } finally { other.close(); expect(target.dispose()).toBe(true); }
});

test.each(['ordinary', 'missing dependency'] as const)('ordered sync replies persist an %s update before sending', async kind => {
  const { Room } = await import('../server/collaboration');
  const target = new Room(`ordered-save-${kind.replace(' ', '-')}`), socket = new ControlledSocket(), peer = new Y.Doc();
  const updates: Uint8Array[] = [];
  try {
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(target.doc));
    peer.on('update', update => updates.push(update));
    const parent = new Y.Map(); peer.getMap('project').set('pending', parent);
    parent.set('value', 'durable before reply');
    target.connect(socket as unknown as WebSocket); socket.finish();
    let savedBeforeReply: unknown;
    socket.onSend = () => {
      const saved = new Y.Doc();
      try {
        Y.applyUpdate(saved, readFileSync(join(directory, `${target.id}.yjs`)));
        if (kind === 'missing dependency') Y.applyUpdate(saved, updates[0]);
        savedBeforeReply = (saved.getMap('project').get('pending') as Y.Map<string> | undefined)?.get('value');
      } finally { saved.destroy(); }
    };
    socket.emit('message', syncPacket(encoder => sync.writeUpdate(encoder,
      kind === 'ordinary' ? Y.mergeUpdates(updates) : updates[1])));
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, peer)));
    expect(socket.sent).toHaveLength(2);
    expect(savedBeforeReply).toBe('durable before reply');
    expect(socket.closed).toEqual([]);
  } finally { socket.close(); peer.destroy(); expect(target.dispose()).toBe(true); }
});

test.each(['broadcast', 'ordered reply'] as const)('a storage failure prevents a successful %s', async trigger => {
  const { Room } = await import('../server/collaboration');
  const target = new Room(`failed-save-${trigger.replace(' ', '-')}`), socket = new ControlledSocket(), peer = new Y.Doc();
  const temporary = join(directory, `${target.id}.yjs.tmp`), errors = vi.spyOn(console, 'error').mockImplementation(() => {});
  try {
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(target.doc));
    const before = Y.encodeStateVector(peer);
    peer.getMap('project').set('name', trigger === 'broadcast' ? 'x'.repeat(1200000) : 'not saved yet');
    target.connect(socket as unknown as WebSocket); socket.finish();
    await mkdir(temporary); // force the real atomic writer to fail
    socket.emit('message', syncPacket(encoder => sync.writeUpdate(encoder, Y.encodeStateAsUpdate(peer, before))));
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, peer)));
    expect(socket.sent).toHaveLength(1);
    expect(socket.closed).toEqual([{ code: 1011, reason: 'Storage unavailable; resynchronize' }]);
    expect(target.connections.size).toBe(0);
    expect(errors).toHaveBeenCalled();
  } finally {
    await rm(temporary, { recursive: true, force: true });
    peer.destroy(); expect(target.dispose()).toBe(true); errors.mockRestore();
  }
});

test('a new room cannot acknowledge its initial document when the first save failed', async () => {
  const { Room } = await import('../server/collaboration');
  const id = 'failed-initial-save', temporary = join(directory, `${id}.yjs.tmp`);
  const errors = vi.spyOn(console, 'error').mockImplementation(() => {}), socket = new ControlledSocket();
  let target: Room | undefined;
  try {
    await mkdir(temporary); target = new Room(id);
    target.connect(socket as unknown as WebSocket); socket.finish();
    socket.emit('message', syncPacket(encoder => sync.writeSyncStep1(encoder, target!.doc)));
    expect(socket.sent).toHaveLength(1);
    expect(socket.closed).toEqual([{ code: 1011, reason: 'Storage unavailable; resynchronize' }]);
  } finally {
    await rm(temporary, { recursive: true, force: true });
    if (target) expect(target.dispose()).toBe(true);
    errors.mockRestore();
  }
});

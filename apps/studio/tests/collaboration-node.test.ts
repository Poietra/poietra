import { afterAll, beforeAll, expect, test, vi } from 'vitest';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { presenceMessage } from '../worker/presence';
import type { Room } from '../server/collaboration';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
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

import { expect, it, vi } from 'vitest';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import * as Y from 'yjs';
import * as decoding from 'lib0/decoding';
import * as sync from 'y-protocols/sync';
import { readProject } from '../shared/document';
import { createProjectMessages, createProjectRoom } from '../src/editor/projects';
import type { Room } from '../server/collaboration';
import { largeImportProject } from './helpers/project-import';

it('imports above 2 MiB through real Node sockets without overflowing echoes and returns only after persistence', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'poietra-project-import-'));
  vi.stubEnv('POIETRA_DATA_DIR', directory);
  vi.stubGlobal('WebSocket', WebSocket);
  const { Room } = await import('../server/collaboration');
  const server = new WebSocketServer({ port: 0 });
  let target: Room | undefined, requests = 0;
  const closes: number[] = [];
  server.on('connection', (socket, request) => {
    const id = request.url!.split('/').at(-1)!;
    target = new Room(id);
    socket.on('close', code => closes.push(code));
    socket.on('message', data => {
      const decoder = decoding.createDecoder(new Uint8Array(data as Buffer));
      if (decoding.readVarUint(decoder) === 0 && decoding.readVarUint(decoder) === sync.messageYjsSyncStep1) requests++;
    });
    target.connect(socket);
  });
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Missing test server address');
  const origin = `http://127.0.0.1:${address.port}`;
  vi.stubGlobal('location', { protocol: 'http:', host: `127.0.0.1:${address.port}`, href: `${origin}/?room=original` });
  const project = largeImportProject(), baseline = new Y.Doc();
  try {
    const packets = createProjectMessages(baseline, project).updateMessages;
    expect(packets.length).toBeGreaterThan(16);
    expect(packets.reduce((sum, packet) => sum + packet.byteLength, 0)).toBeGreaterThan(2 * 1048576);
    const result = await createProjectRoom(project);
    const id = result.searchParams.get('room'); expect(id).toBe(target!.id);
    expect(requests).toBeGreaterThan(2);
    // Inspect durable bytes immediately when publication returns, before closing
    // the room could flush an unacknowledged trailing update for this test.
    const persisted = new Y.Doc();
    try {
      Y.applyUpdate(persisted, readFileSync(join(directory, `${id}.yjs`)));
      expect(readProject(persisted)).toEqual(project);
    } finally { persisted.destroy(); }
    await expect.poll(() => target!.connections.size).toBe(0);
    expect(closes).not.toContain(1013);
    expect(target!.dispose()).toBe(true);
    target = new Room(id!);
    expect(readProject(target.doc)).toEqual(project);
  } finally {
    baseline.destroy();
    for (const socket of server.clients) socket.terminate();
    await new Promise<void>(resolve => server.close(() => resolve()));
    target?.dispose();
    vi.unstubAllGlobals(); vi.unstubAllEnvs();
    await rm(directory, { recursive: true, force: true });
  }
}, 30000);

import assert from 'node:assert/strict';
import { parentPort, workerData as config } from 'node:worker_threads';
import { setTimeout as delay } from 'node:timers/promises';
import { monitorEventLoopDelay } from 'node:perf_hooks';
import { WebSocket } from 'ws';
import { WebsocketProvider } from 'y-websocket';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import { Awareness } from 'y-protocols/awareness';
import { ownedAwarenessClass } from '../../../../_build/js/release/build/client_presence/client_presence.js';
import { makeDemoProject } from '../../shared/demo.js';
import { initializeDocument } from '../../shared/document.js';

process.setMaxListeners(config.length + 10);
let wireStartRead = 0, wireStartWritten = 0;
let active = false, received = 0, receivedBytes = 0, transmitted = 0, transmittedBytes = 0, disconnects = 0, epoch = 0, maxSchedulerDelay = 0;
const clients = [], latencies = [], lag = monitorEventLoopDelay({ resolution: 10 });
export async function until(check, reason, timeout = 60000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { if (check()) return; await delay(20); }
  throw new Error(reason);
}
class Socket extends WebSocket {
  send(bytes, ...args) { if (active) { transmitted++; transmittedBytes += bytes.byteLength; } return super.send(bytes, ...args); }
  emit(event, ...args) {
    if (active && event === 'message') { received++; receivedBytes += args[0].byteLength; }
    if (active && event === 'close') disconnects++;
    return super.emit(event, ...args);
  }
}
function states(client) { return client.doc.getMap('project').get('scenes')?.get('scene-1')?.get('compositions')?.get('comp-1')?.get('states'); }
function connect(index) {
  const doc = new Y.Doc(), owned = config.owned && index !== config.legacyIndex;
  const provider = new WebsocketProvider(`${config.origin.replace('http:', 'ws:')}/sync`, config.room, doc, {
    WebSocketPolyfill: Socket, disableBc: true, ...(owned ? { awareness: new (ownedAwarenessClass(Awareness))(doc) } : {}),
  });
  provider.awareness.setLocalState({ user: { name: `Peer ${index}`, color: '#abcdef' }, editor: { sceneId: 'scene-1', compositionId: 'comp-1', selectedIds: [], cursor: null } });
  provider.on('status', ({ status }) => { if (status === 'connected') provider.awareness.setLocalState(provider.awareness.getLocalState()); });
  const client = { index, doc, provider, latest: 0, edits: 0, states: null, nextEdit: 0, nextPresence: 0 };
  clients.push(client); return client;
}
async function roundtrip(client) {
  await new Promise((done, reject) => {
    const ws = client.provider.ws, timer = setTimeout(() => { ws.off('message', receive); reject(new Error('Sync acknowledgment timeout')); }, 15000);
    function receive(bytes) {
      const d = decoding.createDecoder(new Uint8Array(bytes));
      if (decoding.readVarUint(d) === 0 && decoding.readVarUint(d) === 1) { clearTimeout(timer); ws.off('message', receive); done(); }
    }
    ws.on('message', receive);
    const e = encoding.createEncoder(); encoding.writeVarUint(e, 0); encoding.writeVarUint(e, 0); encoding.writeVarUint8Array(e, new Uint8Array([0])); ws.send(encoding.toUint8Array(e));
  });
}
async function seed() {
  const first = connect(0);
  await until(() => first.provider.synced && states(first), 'Seed did not connect');
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  const object = scene.objects.circle, pose = scene.compositions['comp-1'].states.circle;
  scene.objects = {}; scene.compositions = { 'comp-1': { ...scene.compositions['comp-1'], states: {} } }; scene.compositionOrder = ['comp-1']; scene.transitions = {};
  for (let i = 0; i < config.total; i++) {
    const id = `load-${i}`;
    scene.objects[id] = { ...object, id, name: `Object ${i}`, order: i };
    scene.compositions['comp-1'].states[id] = { ...pose, width: 8, height: 8, x: i % 100 * 10, y: Math.floor(i / 100) * 10 };
  }
  project.scenes = { 'scene-1': scene }; project.sceneOrder = ['scene-1'];
  first.doc.transact(() => { first.doc.getMap('project').clear(); initializeDocument(first.doc, project); });
  await roundtrip(first);
}
async function join() {
  for (let i = config.start + clients.length; i < config.start + config.length; i += 5) {
    const group = Array.from({ length: Math.min(5, config.start + config.length - i) }, (_, offset) => connect(i + offset));
    await until(() => group.every(client => client.provider.synced && states(client)?.has(`load-${config.total - 1}`)), `Join failed at ${i} (capacity or overload)`);
  }
  for (const client of clients) {
    client.states = states(client);
    // Deep observers ask Yjs to sort by event.path, which walks sibling maps.
    // Observe known pose maps directly so 500 simulated clients do not spend
    // the benchmark resolving paths. The optional real browser keeps its UI.
    client.states.forEach((pose, owner) => {
      if (owner === `load-${client.index}`) return;
      pose.observe((event, transaction) => {
        if (!active || transaction.local || !event.keysChanged?.has('x')) return;
        const value = pose.get('x');
        if (value >= 1000) latencies.push(Date.now() - (epoch + value - 1000));
      });
    });
  }
}
async function publish({ start, seconds, editHz, presenceHz }) {
  epoch = start;
  await delay(Math.max(0, epoch - Date.now()));
  wireStartRead = clients.reduce((n, c) => n + c.provider.ws._socket.bytesRead, 0);
  wireStartWritten = clients.reduce((n, c) => n + c.provider.ws._socket.bytesWritten, 0);
  lag.enable(); lag.reset(); active = true;
  for (const client of clients) {
    client.nextEdit = start + client.index / config.total * 1000 / editHz;
    client.nextPresence = start + client.index / config.total * 1000 / presenceHz;
  }
  while (Date.now() < start + seconds * 1000) {
    const now = Date.now();
    for (const client of clients) {
      if (now >= client.nextEdit) {
        maxSchedulerDelay = Math.max(maxSchedulerDelay, now - client.nextEdit);
        client.latest = 1000 + Date.now() - epoch; client.edits++;
        client.states.get(`load-${client.index}`).set('x', client.latest);
        client.nextEdit += 1000 / editHz;
      }
      if (now >= client.nextPresence) {
        client.provider.awareness.setLocalStateField('editor', { sceneId: 'scene-1', compositionId: 'comp-1', selectedIds: [`load-${client.index}`], cursor: { x: (now - start) % 1280, y: client.index } });
        client.nextPresence += 1000 / presenceHz;
      }
    }
    await delay(5);
  }
  return clients.map(({ index, latest, edits }) => ({ index, latest, edits }));
}
async function verify(expected) {
  await until(() => clients.every(client => expected.every(({ index, latest }) => client.states.get(`load-${index}`).get('x') === latest)), 'Final poses did not converge');
  const convergedAt = Date.now(); active = false; lag.disable();
  assert.equal(disconnects, 0, 'Disconnected under load');
  return { compression: [...new Set(clients.map(c => c.provider.ws.extensions))], wireReceivedBytes: clients.reduce((n, c) => n + c.provider.ws._socket.bytesRead, 0) - wireStartRead, wireTransmittedBytes: clients.reduce((n, c) => n + c.provider.ws._socket.bytesWritten, 0) - wireStartWritten, convergedAt, latencies, received, receivedBytes, transmitted, transmittedBytes, disconnects, schedulerMaxDelayMs: maxSchedulerDelay, eventLoopP99Ms: lag.percentile(99) / 1e6, heapBytes: process.memoryUsage().heapUsed };
}
parentPort.on('message', async ({ id, command, value }) => {
  try {
    let result;
    if (command === 'seed') await seed();
    if (command === 'join') await join();
    if (command === 'presence') await until(() => clients.every(client => client.provider.awareness.getStates().size === config.total), 'Presence did not converge');
    if (command === 'publish') result = await publish(value);
    if (command === 'verify') result = await verify(value);
    if (command === 'edit') { clients[0].states.get('load-0').set('x', 22222); await roundtrip(clients[0]); }
    if (command === 'check') await until(() => clients.every(client => client.states.get('load-0').get('x') === 22222 && client.provider.awareness.getStates().size === config.total), 'Hibernation lost edits or peers');
    if (command === 'pose') await until(() => clients.every(client => client.states.get(`load-${value.index}`).get('x') === value.x), 'Browser edit did not reach every peer');
    if (command === 'close') { active = false; lag.disable(); for (const { provider, doc } of clients) { provider.destroy(); provider.awareness.destroy(); doc.destroy(); } }
    parentPort.postMessage({ id, result });
  } catch (error) { parentPort.postMessage({ id, error: error.stack }); }
});

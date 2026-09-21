import { afterEach, expect, test } from 'vitest';
import * as Y from 'yjs';
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from 'y-protocols/awareness';
import { ownedAwarenessClass } from '../../../_build/js/release/build/client_presence/client_presence.js';

const docs: Y.Doc[] = [];
afterEach(() => { for (const doc of docs.splice(0)) doc.destroy(); });
function doc() { const value = new Y.Doc(); docs.push(value); return value; }

test('remote awareness remains visible without being echoed, including large joins and timeouts', () => {
  const own = doc(), awareness: Awareness = new (ownedAwarenessClass(Awareness))(own);
  const remote = new Awareness(doc());
  const sent: unknown[] = [], changed: unknown[] = [];
  awareness.on('update', (value: unknown) => sent.push(value)); awareness.on('change', (value: unknown) => changed.push(value));
  remote.setLocalState({ user: { name: 'Peer' } });
  const bytes = encodeAwarenessUpdate(remote, [remote.clientID]);
  applyAwarenessUpdate(awareness, bytes, 'server');
  expect(awareness.getStates().get(remote.clientID)).toEqual({ user: { name: 'Peer' } });
  expect(changed).toHaveLength(1); expect(sent).toHaveLength(0);
  for (let id = 1; id <= 500; id++) { if (id === own.clientID) continue; awareness.states.set(id, {}); awareness.meta.set(id, { clock: 1, lastUpdated: 0 }); }
  removeAwarenessStates(awareness, Array.from({ length: 500 }, (_, i) => i + 1), 'timeout');
  expect(sent).toHaveLength(0);
  awareness.setLocalState({ user: { name: 'Me' } });
  awareness.setLocalState(awareness.getLocalState()); // unchanged heartbeat still publishes its clock
  expect(sent).toHaveLength(2);
  removeAwarenessStates(awareness, [own.clientID, remote.clientID], 'disconnect');
  expect(sent.at(-1)).toEqual({ added: [], updated: [], removed: [own.clientID] });
});

// Audio value edits against immutable Yjs snapshots and mutable public inputs.
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo.js';
import { initializeDocument } from '../shared/document.js';
import { EditorStore } from '../src/editor/store.js';
import { EditorUndoManager } from '../src/editor/undo.js';
import { setAudioTrack } from '../../../_build/js/release/build/browser_editor/browser_editor.js';

const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
const results = []; let checksum = 0;
for (const sourceBytes of [0, 65536, 1048576]) for (const input of ['immutable snapshot', 'mutable caller']) {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  scene.audioTracks = { audio: { id: 'audio', name: 'Audio', start: 0, offset: 0, duration: 5000, volume: .5, muted: false,
    asset: { src: sourceBytes ? 'data:audio/wav;base64,' + 'A'.repeat(sourceBytes) : '/api/rooms/' + 'a'.repeat(32) + '/media/' + 'b'.repeat(64),
      mime: 'audio/wav', duration: 10000, hasAudio: true, waveform: Array(160).fill(.5) } } };
  const doc = new Y.Doc(); initializeDocument(doc, project);
  const undoManager = new EditorUndoManager(doc);
  let next = 0;
  const store = input === 'immutable snapshot' ? Object.assign(Object.create(EditorStore.prototype), { doc, undoManager })
    : { scene: () => scene, edit: changes => { for (const change of changes) scene.audioTracks.audio[change.path.at(-1)] = change.value; } };
  const asset = store.scene('scene-1').audioTracks.audio.asset;
  const run = () => { setAudioTrack(store, 'scene-1', 'audio', { volume: .5 + next++ % 2 * .1 }, false); checksum++; };
  try {
    const start = performance.now(); run(); const coldMs = performance.now() - start;
    const iterations = sourceBytes ? 20 : 500;
    const batch = () => { const start = performance.now(); for (let index = 0; index < iterations; index++) run(); return (performance.now() - start) / iterations; };
    batch(); batch(); const samples = Array.from({ length: 7 }, batch);
    const current = store.scene('scene-1').audioTracks.audio;
    assert.equal(current.asset, asset); assert.equal(current.volume, .5);
    results.push({ sourceBytes, input, iterations, coldMs, msPerOperation: median(samples), samples: { msPerOperation: samples } });
  } finally { undoManager.destroy(); doc.destroy(); }
}
console.log(JSON.stringify({ scope: 'Audio volume command, validation and leaf publication; immutable variant includes real Yjs, selective Undo and snapshot reads. Mutable control applies leaves to a caller-owned record. 160 waveform values. Embedded sizes are base64 characters, not decoded audio bytes. No browser, decoder, network or audio output.', iterations: 'One separately reported first edit; two warmup + seven measured batches, 500 edits for room references and 20 for embedded sources', results, checksum }, null, 2));

import { expect, it, vi } from 'vitest';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { applyChanges, getShared, initializeDocument } from '../shared/document';
import { parseProjectFile } from '../shared/project-file';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { setAudioTrack } from '../../../_build/js/release/build/browser_editor/browser_editor.js';
import type { AudioTrack } from '../shared/media';

const path = ['scenes', 'scene-1', 'audioTracks', 'audio'];
function audio(): AudioTrack {
  return { id: 'audio', name: 'Audio', start: 100, offset: 1000, duration: 5000, volume: .5, muted: false,
    asset: { src: 'data:audio/wav;base64,AQ==', mime: 'audio/wav', duration: 8000, hasAudio: true, waveform: [0, .5, 1] } };
}
function create() {
  const project = makeDemoProject(); project.scenes['scene-1'].audioTracks = { audio: audio() };
  const doc = new Y.Doc(); initializeDocument(doc, project);
  const undoManager = new EditorUndoManager(doc);
  const store = Object.assign(Object.create(EditorStore.prototype), { doc, undoManager }) as EditorStore;
  return { doc, store, close() { undoManager.destroy(); doc.destroy(); } };
}

it('keeps the shared media leaf while clip edits and selective Undo preserve offline source changes', () => {
  const { doc, store, close } = create(), peer = new Y.Doc();
  Y.applyUpdate(peer, Y.encodeStateAsUpdate(doc));
  const before = store.scene('scene-1').audioTracks!.audio;
  const shared = getShared(doc, [...path, 'asset']);
  try {
    store.setAudioTrack('scene-1', 'audio', { volume: .7 });
    const after = store.scene('scene-1').audioTracks!.audio;
    expect(after.asset).toBe(before.asset);
    expect(after).toEqual({ ...before, volume: .7 });
    expect(getShared(doc, [...path, 'asset'])).toBe(shared);
    applyChanges(peer, [{ path: [...path, 'asset', 'duration'], value: 7000 }, { path: [...path, 'name'], value: 'Peer' }]);
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(peer));
    store.undo();
    expect(store.scene('scene-1').audioTracks!.audio).toMatchObject({ name: 'Peer', volume: .5, asset: { duration: 7000 } });
    store.redo();
    expect(store.scene('scene-1').audioTracks!.audio).toMatchObject({ name: 'Peer', volume: .7, asset: { duration: 7000 } });
    expect(before.asset.duration).toBe(8000);
    expect(() => parseProjectFile(JSON.stringify(store.project()))).not.toThrow();
  } finally { peer.destroy(); close(); }
});

it.each([
  ['src', 'https://external.test/audio.wav'], ['duration', 5000], ['hasAudio', false],
  ['waveform', [0, 1.1]], ['mime', 'video/mp4'],
] as const)('revalidates a changed immutable media %s before another clip edit', (key, value) => {
  const { doc, store, close } = create();
  try {
    store.setAudioTrack('scene-1', 'audio', { volume: .6 });
    applyChanges(doc, [{ path: [...path, 'asset', key], value }]);
    const vector = Y.encodeStateVector(doc), before = doc.getMap('project').toJSON();
    expect(() => store.setAudioTrack('scene-1', 'audio', { volume: .7 })).toThrow();
    expect(Y.encodeStateVector(doc)).toEqual(vector);
    expect(doc.getMap('project').toJSON()).toEqual(before);
    applyChanges(doc, [{ path: [...path, 'asset', key], value: audio().asset[key] }]);
    expect(() => store.setAudioTrack('scene-1', 'audio', { volume: .7 })).not.toThrow();
  } finally { close(); }
});

it.each([
  { volume: 1.1 }, { volume: NaN }, { start: -1 }, { offset: 4000 }, { duration: Infinity },
  { duration: undefined }, { name: 'a'.repeat(201) }, { muted: 1 },
])('rejects invalid clip values without publishing even after asset validation: %j', patch => {
  const { doc, store, close } = create();
  try {
    store.setAudioTrack('scene-1', 'audio', { volume: .6 });
    const vector = Y.encodeStateVector(doc);
    expect(() => store.setAudioTrack('scene-1', 'audio', patch as never)).toThrow();
    expect(Y.encodeStateVector(doc)).toEqual(vector);
  } finally { close(); }
});

it('validates in-transaction media writes and retries after an invalid first capture', () => {
  const { doc, store, close } = create();
  try {
    store.setAudioTrack('scene-1', 'audio', { volume: .6 });
    const source = getShared(doc, [...path, 'asset']) as Y.Map<unknown>;
    doc.transact(() => {
      source.set('src', 'invalid');
      expect(() => store.setAudioTrack('scene-1', 'audio', { volume: .7 })).toThrow();
      doc.transact(() => {
        source.set('src', audio().asset.src);
        store.setAudioTrack('scene-1', 'audio', { volume: .7 });
      });
    });
    expect(store.scene('scene-1').audioTracks!.audio.volume).toBe(.7);
    source.set('src', 'invalid');
    expect(() => store.setAudioTrack('scene-1', 'audio', { volume: .8 })).toThrow();
    source.set('src', audio().asset.src);
    store.setAudioTrack('scene-1', 'audio', { volume: .8 });
  } finally { close(); }
});

it.each(['mutable', 'frozen accessor'] as const)('does not trust a %s caller-owned Scene or nested asset', kind => {
  const track = audio(), tracks = { audio: track };
  const scene = kind === 'mutable' ? { audioTracks: tracks } : Object.freeze({ get audioTracks() { return tracks; } });
  const edit = vi.fn(), store = { scene: () => scene, edit };
  setAudioTrack(store, 'scene-1', 'audio', { volume: .6 }, true);
  edit.mockClear(); track.asset.waveform![1] = 2;
  expect(() => setAudioTrack(store, 'scene-1', 'audio', { volume: .6 }, true)).toThrow();
  expect(edit).not.toHaveBeenCalled();
  track.asset.waveform![1] = .5;
  expect(() => setAudioTrack(store, 'scene-1', 'audio', { volume: .6 }, true)).not.toThrow();
});

it('does not infer trust for a replacement asset supplied by a native patch', () => {
  const { store, close } = create();
  try {
    store.setAudioTrack('scene-1', 'audio', { volume: .6 });
    const asset = audio().asset;
    store.setAudioTrack('scene-1', 'audio', { asset } as never);
    asset.src = 'invalid';
    expect(() => store.setAudioTrack('scene-1', 'audio', { asset } as never)).toThrow();
    expect(store.scene('scene-1').audioTracks!.audio.asset.src).toBe(audio().asset.src);
  } finally { close(); }
});

it('validates borrowed frozen assets without stripping caller-owned extension fields', () => {
  const track = Object.assign(audio(), { extra: 'track extension' });
  Object.assign(track.asset, { extra: { retained: true } });
  Object.freeze(track.asset.waveform); Object.freeze(track.asset); Object.freeze(track);
  const before = JSON.stringify(track), edit = vi.fn();
  const store = { scene: () => ({ audioTracks: { audio: track } }), edit };
  setAudioTrack(store, 'scene-1', 'audio', { volume: .6 }, true);
  expect(edit).toHaveBeenCalledOnce();
  expect(JSON.stringify(track)).toBe(before);
});

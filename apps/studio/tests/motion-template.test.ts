import { expect, it } from 'vitest';
import * as Y from 'yjs';
import * as kernel from '../../../_build/js/release/build/motion/motion.js';
import { ensureSceneAnimationTracks, getValue, initializeDocument, readProject } from '../shared/document';
import { parseProjectFile } from '../shared/project-file';
import { makeDemoProject } from '../shared/demo';
import { captureMotion } from '../shared/motion-template';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { evaluateScene } from '../src/engine/evaluate';
import { sceneDuration } from '../shared/model';
import { deleteComposition } from '../src/editor/structure';
import { clippingProject } from './clipping-fixture';

const store = (doc: Y.Doc) => Object.assign(Object.create(EditorStore.prototype), { doc, undoManager: new EditorUndoManager(doc) }) as EditorStore;

it('captures selected subtrees and hidden ancestors and appends the same evaluated animation with independent IDs', () => {
  const source = clippingProject().scenes['scene-1'];
  source.compositions['comp-2'].states.child.x = 25;
  const template = captureMotion(source, ['child'], 'Reusable reveal');
  expect(parseProjectFile(JSON.stringify(template))).toEqual(template);
  expect(template.scenes[source.id].objects.frame.clipChildren).toBe(true);
  const original = JSON.stringify(source), doc = new Y.Doc(), server = new Y.Doc();
  try {
    const project = makeDemoProject(), target = project.scenes['scene-1'];
    const old = structuredClone(target), prefix = sceneDuration(target);
    initializeDocument(doc, project); ensureSceneAnimationTracks(doc); const editor = store(doc);
    const result = editor.insertMotion(target.id, template);
    const next = editor.scene(target.id);
    expect(next.compositionOrder.length).toBe(old.compositionOrder.length + source.compositionOrder.length);
    expect(result.ids).toHaveLength(2);
    expect(next.objects[result.ids[1]].parentId).toBe(result.ids[0]);
    for (const cid of old.compositionOrder) {
      for (const id of Object.keys(old.objects)) expect(next.compositions[cid].states[id]).toEqual(old.compositions[cid].states[id]);
      for (const id of result.ids) expect(next.compositions[cid].states[id].visible).toBe(false);
    }
    const sourceEnd = sceneDuration(source);
    for (const time of [0, sourceEnd / 2, sourceEnd - 1]) {
      const before = evaluateScene(source, time, kernel).objects.find(x => x.object.id === 'child')!;
      const after = evaluateScene(next, prefix + time, kernel).objects.find(x => x.object.id === result.ids[1])!;
      expect(after.state).toEqual(before.state); expect(after.world).toEqual(before.world); expect(after.clips).toEqual(before.clips);
    }
    expect(JSON.stringify(source)).toBe(original);
    Y.applyUpdate(server, Y.encodeStateAsUpdate(doc));
    expect(ensureSceneAnimationTracks(server)).toBe(false);
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(server));
    editor.undo(); expect(editor.scene(target.id).compositionOrder).toEqual(old.compositionOrder);
    expect(Object.keys(editor.scene(target.id).objects)).toEqual(Object.keys(old.objects));
    editor.redo(); expect(editor.scene(target.id).compositionOrder).toContain(result.compositionId);
    expect(readProject(doc)!.version).toBe(3);
  } finally { doc.destroy(); server.destroy(); }
});

it('validates the entire source before writing and keeps peer edits through insertion Undo', () => {
  const a = new Y.Doc(), b = new Y.Doc();
  try {
    initializeDocument(a, makeDemoProject()); Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    const alice = store(a), bob = store(b);
    const template = captureMotion(clippingProject().scenes['scene-1'], ['child'], 'Motion');
    const before = Y.encodeStateVector(a), invalid = structuredClone(template);
    invalid.scenes['scene-1'].compositions['comp-1'].states.child.opacity = 2;
    expect(() => alice.insertMotion('scene-1', invalid)).toThrow();
    expect(Y.encodeStateVector(a)).toEqual(before);
    const inserted = alice.insertMotion('scene-1', template);
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    bob.updateState('scene-1', inserted.compositionId, inserted.ids[1], { fill: '#ff0000' });
    Y.applyUpdate(a, Y.encodeStateAsUpdate(b));
    alice.undo();
    expect(alice.scene('scene-1').compositions[inserted.compositionId].states[inserted.ids[1]].fill).toBe('#ff0000');
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a)); expect(readProject(a)).toEqual(readProject(b));
  } finally { a.destroy(); b.destroy(); }
});

it('rejects capacity overflow without any document writes', () => {
  const doc = new Y.Doc(), project = clippingProject(), target = project.scenes['scene-1'];
  try {
    for (let i = 2; i < 500; i++) {
      const id = `shape-${i}`; target.objects[id] = { ...target.objects.child, id };
      for (const composition of Object.values(target.compositions)) composition.states[id] = structuredClone(composition.states.child);
    }
    initializeDocument(doc, project); const editor = store(doc), before = Y.encodeStateVector(doc);
    expect(() => editor.insertMotion(target.id, captureMotion(clippingProject().scenes['scene-1'], ['child'], 'Motion'))).toThrow(/500/);
    expect(Y.encodeStateVector(doc)).toEqual(before);
  } finally { doc.destroy(); }
});

it('keeps inserted objects hidden in retained compositions when a peer undoes their deletion', () => {
  const a = new Y.Doc(), b = new Y.Doc();
  try {
    initializeDocument(a, makeDemoProject()); ensureSceneAnimationTracks(a); Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    const alice = store(a), bob = store(b);
    deleteComposition(b, 'scene-1', 'comp-2'); Y.applyUpdate(a, Y.encodeStateAsUpdate(b));
    const result = alice.insertMotion('scene-1', captureMotion(clippingProject().scenes['scene-1'], ['child'], 'Motion'));
    for (const id of result.ids) expect(getValue(a, ['scenes', 'scene-1', 'compositions', 'comp-2', 'states', id, 'visible'])).toBe(false);
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a)); bob.undo(); Y.applyUpdate(a, Y.encodeStateAsUpdate(b));
    expect(alice.scene('scene-1').compositionOrder).toContain('comp-2');
    for (const id of result.ids) expect(alice.scene('scene-1').compositions['comp-2'].states[id].visible).toBe(false);
    expect(readProject(a)).toEqual(readProject(b));
    expect(parseProjectFile(JSON.stringify(readProject(a)))).toEqual(readProject(a));
  } finally { a.destroy(); b.destroy(); }
});

it('shifts video playback by the insertion time while retaining trim and independently editable source data', () => {
  const doc = new Y.Doc(), source = clippingProject().scenes['scene-1'];
  source.objects.child = { ...source.objects.child, kind: 'video', media: { src: 'data:video/mp4;base64,AAAA', mime: 'video/mp4', width: 160, height: 90, duration: 5000, hasAudio: false }, playback: { start: 1100, offset: 2000, duration: 1000 } };
  try {
    const target = makeDemoProject(), prefix = sceneDuration(target.scenes['scene-1']);
    initializeDocument(doc, target); const editor = store(doc);
    const result = editor.insertMotion('scene-1', captureMotion(source, ['child'], 'Video reveal'));
    const next = editor.scene('scene-1'), id = result.ids[1];
    expect(next.objects[id].playback).toEqual({ start: prefix + 1100, offset: 2000, duration: 1000 });
    expect(evaluateScene(next, prefix + 1500, kernel).objects.find(o => o.object.id === id)?.videoTimeMs).toBe(2400);
    expect(source.objects.child.playback!.start).toBe(1100);
    expect(parseProjectFile(JSON.stringify(readProject(doc)))).toEqual(readProject(doc));
  } finally { doc.destroy(); }
});

it('merges two offline motion insertions without sharing their identities or breaking portable references', () => {
  const a = new Y.Doc(), b = new Y.Doc();
  try {
    initializeDocument(a, makeDemoProject()); ensureSceneAnimationTracks(a); Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    const alice = store(a), bob = store(b), template = captureMotion(clippingProject().scenes['scene-1'], ['child'], 'Motion');
    const first = alice.insertMotion('scene-1', template), second = bob.insertMotion('scene-1', template);
    const fromA = Y.encodeStateAsUpdate(a), fromB = Y.encodeStateAsUpdate(b); Y.applyUpdate(a, fromB); Y.applyUpdate(b, fromA);
    expect(readProject(a)).toEqual(readProject(b));
    expect(alice.scene('scene-1').compositionOrder).toHaveLength(6);
    expect(first.ids.some(id => second.ids.includes(id))).toBe(false);
    expect(parseProjectFile(JSON.stringify(readProject(a)))).toEqual(readProject(a));
    alice.updateState('scene-1', first.compositionId, first.ids[1], { fill: '#123456' });
    expect(alice.scene('scene-1').compositions[second.compositionId].states[second.ids[1]].fill).toBe('#ffffff');
  } finally { a.destroy(); b.destroy(); }
});

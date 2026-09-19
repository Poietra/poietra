import { afterEach, expect, it } from 'vitest';
import * as Y from 'yjs';
import * as kernel from '../../../_build/js/release/build/motion/motion.js';
import { initializeDocument, readProject, applyChanges } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { parseProjectFile } from '../shared/project-file';
import { copyObjects } from '../shared/clipboard';
import { deleteComposition } from '../src/editor/structure';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { compositionFrame, transitionFrame, compileScene } from '../src/engine/evaluate';
import { compileProposal, validateProposalForApply, type ProposalOperation } from '../shared/ai';
import type { Scene, RenderObject } from '../shared/scene-types';

const docs: Y.Doc[] = [];
afterEach(() => { for (const doc of docs.splice(0)) doc.destroy(); });
function replicas() {
  const seed = new Y.Doc(); docs.push(seed);
  const project = makeDemoProject();
  const scene = project.scenes['scene-1'];
  for (const comp of Object.values(scene.compositions)) Object.assign(comp.states.circle, { x: 100, fill: '#000000', visible: true });
  scene.transitions['transition-1'].duration = 2000;
  Object.assign(scene.transitions['transition-1'].tracks.circle, { start: 200, duration: 600, easing: 'linear', path: null });
  initializeDocument(seed, project);
  const stores = [100, 200].map(clientID => {
    const doc = new Y.Doc(); docs.push(doc); doc.clientID = clientID;
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(seed));
    return Object.assign(Object.create(EditorStore.prototype), { doc, undoManager: new EditorUndoManager(doc) }) as EditorStore;
  });
  const sync = () => {
    Y.applyUpdate(stores[0].doc, Y.encodeStateAsUpdate(stores[1].doc));
    Y.applyUpdate(stores[1].doc, Y.encodeStateAsUpdate(stores[0].doc));
    expect(readProject(stores[0].doc)).toEqual(readProject(stores[1].doc));
  };
  return { alice: stores[0], bob: stores[1], sync };
}
const scene = (store: EditorStore) => store.scene('scene-1');
const track = (store: EditorStore) => scene(store).transitions['transition-1'].tracks.circle;
const state = (store: EditorStore, id = 'circle', cid = 'comp-1') => scene(store).compositions[cid].states[id];
const key = (value = 300) => ({ property: 'x' as const, at: .5, value, easing: 'linear' as const });
const frame = (s: Scene, time: number) => transitionFrame(s, s.transitions['transition-1'], time, kernel);
function corner(item: RenderObject, x = 0, y = 0) {
  const m = item.world;
  if (m) return { x: m.a * x + m.c * y + m.e, y: m.b * x + m.d * y + m.f };
  const r = item.state.rotation * Math.PI / 180;
  return { x: item.state.x + x * Math.cos(r) - y * Math.sin(r), y: item.state.y + x * Math.sin(r) + y * Math.cos(r) };
}
const item = (s: Scene, id: string, cid = 'comp-1') => compositionFrame(s, s.compositions[cid]).objects.find(o => o.object.id === id)!;
const close = (a: {x:number;y:number}, b: {x:number;y:number}) => { expect(a.x).toBeCloseTo(b.x, 7); expect(a.y).toBeCloseTo(b.y, 7); };

it('evaluates intermediate actual values, linked endpoints and stretched timing in both frame APIs', () => {
  const { alice } = replicas();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key());
  for (const [time, expected] of [[0, 100], [200, 100], [350, 200], [500, 300], [650, 200], [800, 100]]) {
    const s = scene(alice);
    expect(frame(s, time).objects.find(o => o.object.id === 'circle')!.state.x).toBe(expected);
    expect(compileScene(s, kernel).transition('transition-1', time)).toEqual(frame(s, time));
  }
  alice.setTrack('scene-1', 'transition-1', 'circle', { duration: 1200 });
  expect(track(alice).keyframes!.middle.at).toBe(.5);
  expect(frame(scene(alice), 800).objects.find(o => o.object.id === 'circle')!.state.x).toBe(300);
  alice.updateState('scene-1', 'comp-2', 'circle', { x: 400 });
  expect(frame(scene(alice), 1400).objects.find(o => o.object.id === 'circle')!.state.x).toBe(400);
});

it('retains simultaneous first keyframes, independent edits, selective Undo and the upgraded format', () => {
  const { alice, bob, sync } = replicas();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'alice', key(300));
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'bob', { ...key(220), at: .25 });
  sync(); expect(Object.keys(track(alice).keyframes!)).toEqual(expect.arrayContaining(['alice', 'bob']));
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'alice', { at: .7 });
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'alice', { value: 500 });
  sync(); expect(track(alice).keyframes!.alice).toMatchObject({ at: .7, value: 500 });
  alice.undo(); sync(); expect(track(alice).keyframes!.alice).toMatchObject({ at: .5, value: 500 });
  alice.undo(); sync(); expect(track(alice).keyframes!.bob.value).toBe(220);
  expect(readProject(alice.doc)!.version).toBe(2);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc))).version).toBe(2);
});

it('undoes keyframe removal without losing an offline peer value edit', () => {
  const { alice, bob, sync } = replicas();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key()); sync();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', null);
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', { value: 700 }); sync();
  expect(track(alice).keyframes!.middle).toMatchObject({ deleted: true, value: 700 });
  alice.undo(); sync(); expect(track(alice).keyframes!.middle.value).toBe(700);
  expect(track(alice).keyframes!.middle.deleted).not.toBe(true);
});

it('rejects invalid curve edits before publishing anything', () => {
  const { alice } = replicas(); const before = Y.encodeStateVector(alice.doc);
  for (const bad of [{...key(), at: 0}, {...key(), at: 1}, {...key(), value: NaN}, {...key(), property: 'opacity' as const, value: 2}]) {
    expect(() => alice.setKeyframe('scene-1', 'transition-1', 'circle', 'bad', bad)).toThrow();
  }
  expect(() => alice.setKeyframe('scene-1', 'transition-1', 'circle', '__proto__', key())).toThrow();
  expect(Y.encodeStateVector(alice.doc)).toEqual(before);
});

it('reparents every Composition without moving geometry, then moves children without child writes', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'equation', { rotation: 37, scaleX: 2, scaleY: .6 });
  const before = scene(alice);
  alice.setParent('scene-1', 'circle', 'equation');
  for (const cid of before.compositionOrder) for (const [x, y] of [[0, 0], [-40, -30], [40, 30]]) {
    close(corner(item(scene(alice), 'circle', cid), x, y), corner(item(before, 'circle', cid), x, y));
  }
  sync(); const localBefore = state(alice);
  const centre = corner(item(scene(alice), 'circle'));
  alice.translate('scene-1', 'comp-1', { equation: state(alice, 'equation') }, 53, 19);
  bob.updateState('scene-1', 'comp-1', 'circle', { fill: '#ff0000' }); sync();
  expect(state(alice)).toEqual({ ...localBefore, fill: '#ff0000' });
  close(corner(item(scene(alice), 'circle')), { x: centre.x + 53, y: centre.y + 19 });
  alice.undo(); sync(); close(corner(item(scene(alice), 'circle')), centre);
  expect(state(alice).fill).toBe('#ff0000');
});

it('projects child dragging through rotated parents and avoids moving a selected child twice', () => {
  const { alice } = replicas();
  alice.updateState('scene-1', 'comp-1', 'equation', { rotation: 90, scaleX: 2, scaleY: .5 });
  alice.setParent('scene-1', 'circle', 'equation');
  let start = corner(item(scene(alice), 'circle'));
  alice.translate('scene-1', 'comp-1', { circle: state(alice) }, 80, -40);
  close(corner(item(scene(alice), 'circle')), { x: start.x + 80, y: start.y - 40 });
  start = corner(item(scene(alice), 'circle')); const localBefore = state(alice);
  alice.translate('scene-1', 'comp-1', { circle: state(alice), equation: state(alice, 'equation') }, 30, 20);
  close(corner(item(scene(alice), 'circle')), { x: start.x + 30, y: start.y + 20 });
  expect(state(alice)).toEqual(localBefore);
});

it('preserves geometry while editing the anchor and prevents singular or cyclic reparenting', () => {
  const { alice } = replicas();
  alice.updateState('scene-1', 'comp-1', 'circle', { rotation: 37, scaleX: 2 });
  const before = item(scene(alice), 'circle');
  alice.setAnchor('scene-1', 'comp-1', 'circle', 33, -21);
  close(corner(item(scene(alice), 'circle'), 30, 45), corner(before, 30, 45));
  alice.setParent('scene-1', 'circle', 'equation');
  const clock = Y.encodeStateVector(alice.doc);
  expect(() => alice.setParent('scene-1', 'equation', 'circle')).toThrow();
  expect(Y.encodeStateVector(alice.doc)).toEqual(clock);
  alice.updateState('scene-1', 'comp-2', 'sigmoid', { scaleX: 0 });
  const singular = Y.encodeStateVector(alice.doc);
  expect(() => alice.setParent('scene-1', 'circle', 'sigmoid')).toThrow();
  expect(Y.encodeStateVector(alice.doc)).toEqual(singular);
});

it('resolves concurrent cycles consistently without deleting the authored links', () => {
  const { alice, bob, sync } = replicas();
  alice.setParent('scene-1', 'circle', 'equation');
  bob.setParent('scene-1', 'equation', 'circle'); sync();
  expect(scene(alice).objects.circle.parentId).toBe('equation');
  expect(scene(alice).objects.equation.parentId).toBe('circle');
  expect(compositionFrame(scene(alice), scene(alice).compositions['comp-1'])).toEqual(compositionFrame(scene(bob), scene(bob).compositions['comp-1']));
  expect(() => parseProjectFile(JSON.stringify(readProject(alice.doc)))).not.toThrow();
});

it('copies a hierarchy with remapped parents, and detaches a copied child at its world pose', () => {
  const { alice } = replicas();
  alice.setParent('scene-1', 'circle', 'equation');
  alice.updateState('scene-1', 'comp-1', 'equation', { rotation: 43, scaleX: 1.7 });
  const source = scene(alice); const before = corner(item(source, 'circle'));
  const detached = copyObjects(source, 'comp-1', ['circle']);
  expect(detached.objects[0].parentId).toBeUndefined();
  const [single] = alice.paste('scene-1', 'comp-1', detached, 0);
  close(corner(item(scene(alice), single)), before);
  const hierarchy = copyObjects(source, 'comp-1', ['circle', 'equation']);
  const ids = alice.paste('scene-1', 'comp-1', hierarchy, 24);
  const child = ids.find(id => scene(alice).objects[id].parentId)!;
  expect(ids).toContain(scene(alice).objects[child].parentId);
  close(corner(item(scene(alice), child)), { x: before.x + 24, y: before.y + 24 });
});

it('round-trips the new data without affecting legacy files or serializing evaluated matrices', () => {
  const { alice } = replicas();
  expect(parseProjectFile(JSON.stringify(makeDemoProject())).version).toBe(1);
  alice.setParent('scene-1', 'circle', 'equation');
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'colour', { property: 'fill', at: .5, value: '#ffffff', easing: 'linear' });
  const saved = JSON.stringify(readProject(alice.doc));
  const loaded = parseProjectFile(saved);
  expect(loaded.version).toBe(2); expect(saved).not.toContain('"world"');
  expect(loaded.scenes['scene-1'].objects.circle.parentId).toBe('equation');
  expect(loaded.scenes['scene-1'].transitions['transition-1'].tracks.circle.keyframes!.colour.value).toBe('#ffffff');
  expect(frame(loaded.scenes['scene-1'], 350).objects.find(o => o.object.id === 'circle')!.state.fill).toBe('#808080');
});


it('keeps existing keyframes when publishing an imported project without erasing point records', () => {
  const { alice } = replicas();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key());
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'colour', { property: 'fill', at: .7, value: '#abcdef', easing: 'easeOut' });
  const saved = parseProjectFile(JSON.stringify(readProject(alice.doc)));
  const loaded = new Y.Doc(); docs.push(loaded); initializeDocument(loaded, saved);
  expect(readProject(loaded)).toEqual(saved);
  expect(readProject(loaded)!.scenes['scene-1'].transitions['transition-1'].tracks.circle.keyframes).toEqual(track(alice).keyframes);
});

it('reparents retained Compositions so a peer can restore them without changing geometry', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-2', 'equation', { rotation: 42, scaleX: 2, scaleY: .7 }); sync();
  const before = corner(item(scene(alice), 'circle', 'comp-2'), 20, 15);
  deleteComposition(bob.doc, 'scene-1', 'comp-2'); sync();
  expect(scene(alice).compositions['comp-2']).toBeUndefined();
  alice.setParent('scene-1', 'circle', 'equation'); sync();
  bob.undo(); sync();
  close(corner(item(scene(alice), 'circle', 'comp-2'), 20, 15), before);
});

const proposal = (store: EditorStore, operations: ProposalOperation[]) => compileProposal(store.doc, readProject(store.doc)!, 'scene-1', { message: 'Edit primitives', operations });
const keyOperation = (keyframeId: string, value = 300): ProposalOperation => ({ action: 'setKeyframe', transitionId: 'transition-1', objectId: 'circle', keyframeId, keyframe: key(value) });

it('applies AI keyframes through the same evaluator, preserving peer points and independent leaf edits', () => {
  const { alice, bob, sync } = replicas();
  const first = proposal(alice, [keyOperation('middle'), keyOperation('middle', 450)]);
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'peer', { ...key(200), at: .25 }); sync();
  alice.applyProposal(first); sync();
  expect(track(alice).keyframes!.peer.value).toBe(200);
  expect(frame(scene(alice), 500).objects.find(o => o.object.id === 'circle')!.state.x).toBe(450);
  const edit = proposal(alice, [keyOperation('middle', 550)]);
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', { at: .6 }); sync();
  alice.applyProposal(edit); sync();
  expect(track(alice).keyframes!.middle).toMatchObject({ at: .6, value: 550 });
  const stale = proposal(alice, [keyOperation('middle', 650)]);
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', null); sync();
  expect(() => validateProposalForApply(alice.doc, stale)).toThrow('提案後');
  expect(readProject(alice.doc)!.version).toBe(2);
});

it('AI parenting and anchors preserve geometry and reject stale parent transforms while allowing color edits', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'equation', { rotation: 28, scaleX: 2, scaleY: .8 }); sync();
  const before = corner(item(scene(alice), 'circle'), 25, 10);
  const edits = proposal(alice, [{ action: 'setParent', objectId: 'circle', parentId: 'equation' }, { action: 'setAnchor', compositionId: 'comp-1', objectId: 'circle', x: 15, y: -10 }]);
  bob.updateState('scene-1', 'comp-1', 'circle', { fill: '#cc0000' }); sync();
  alice.applyProposal(edits); sync();
  close(corner(item(scene(alice), 'circle'), 25, 10), before);
  expect(state(alice).fill).toBe('#cc0000');
  const stale = proposal(alice, [{ action: 'setParent', objectId: 'circle', parentId: null }]);
  bob.updateState('scene-1', 'comp-2', 'equation', { rotation: 17 }); sync();
  expect(() => alice.applyProposal(stale)).toThrow('提案後');
  expect(scene(alice).objects.circle.parentId).toBe('equation');
  alice.undo(); sync(); expect(scene(alice).objects.circle.parentId).toBeUndefined();
  expect(state(alice).fill).toBe('#cc0000');
});

it('rejects an invalid AI curve before any mutation ', () => {
  const { alice } = replicas(); const before = Y.encodeStateVector(alice.doc);
  for (const value of [0, 1]) expect(() => proposal(alice, [{ ...keyOperation('bad'), keyframe: { ...key(), at: value } } as ProposalOperation])).toThrow();
  expect(() => proposal(alice, [{ action: 'setParent', objectId: 'circle', parentId: 'circle' }])).toThrow();
  expect(Y.encodeStateVector(alice.doc)).toEqual(before);
});


it('setTrack preserves keyframe map identities and independent peer edits, and Cut retains inactive points', () => {
  const { alice, bob, sync } = replicas();
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key()); sync();
  alice.setTrack('scene-1', 'transition-1', 'circle', { keyframes: { middle: { ...key(), at: .7 } } });
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', { value: 600 }); sync();
  expect(track(alice).keyframes!.middle).toMatchObject({ at: .7, value: 600 });
  alice.undo(); sync(); expect(track(alice).keyframes!.middle).toMatchObject({ at: .5, value: 600 });
  alice.setTrack('scene-1', 'transition-1', 'circle', { type: 'none' });
  expect(frame(scene(alice), 500).objects.find(o => o.object.id === 'circle')!.state.x).toBe(100);
  alice.setTrack('scene-1', 'transition-1', 'circle', { type: 'move' });
  expect(frame(scene(alice), 500).objects.find(o => o.object.id === 'circle')!.state.x).toBe(600);
});

it('setObject routes parenting through pose-preserving plans and rejects anchor overflow atomically', () => {
  const { alice } = replicas(); const before = corner(item(scene(alice), 'circle'));
  alice.setObject('scene-1', 'circle', { parentId: 'equation', name: 'Child' });
  close(corner(item(scene(alice), 'circle')), before);
  alice.updateState('scene-1', 'comp-1', 'circle', { scaleX: 100000 });
  const clock = Y.encodeStateVector(alice.doc);
  expect(() => alice.setAnchor('scene-1', 'comp-1', 'circle', 100000, 0)).toThrow('保存可能');
  expect(Y.encodeStateVector(alice.doc)).toEqual(clock);
});


it('retains a newly created point used by a peer when its author undoes creation', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'circle', { fill: '#ff0000' });
  alice.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key()); sync();
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', { value: 700 }); sync();
  alice.undo(); sync();
  expect(track(alice).keyframes!.middle).toMatchObject({ property: 'x', at: .5, value: 700, easing: 'linear' });
  expect(state(alice).fill).toBe('#ff0000');
  alice.undo(); sync(); expect(state(alice).fill).toBe('#000000');
  expect(track(alice).keyframes!.middle.value).toBe(700);
});

it('retains a new parent used by a peer child, including its geometry', () => {
  const { alice, bob, sync } = replicas();
  const parent = alice.addObject('scene-1', 'comp-1', 'rectangle', { x: 330, y: 220, rotation: 35 }); sync();
  bob.setParent('scene-1', 'circle', parent); sync();
  const before = corner(item(scene(alice), 'circle'), 20, 15);
  alice.undo(); sync();
  expect(scene(alice).objects[parent]).toBeDefined();
  expect(scene(alice).objects.circle.parentId).toBe(parent);
  close(corner(item(scene(alice), 'circle'), 20, 15), before);
  expect(alice.lastUndoPreservedObjects).toBe(1);
});

it('retains a coordinate space used by a peer while undoing unrelated appearance in the same action', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'equation', { rotation: 37, scaleX: 2, scaleY: .6 });
  alice.applyProposal(proposal(alice, [
    { action: 'setParent', objectId: 'circle', parentId: 'equation' },
    { action: 'setState', compositionId: 'comp-1', objectId: 'circle', property: 'fill', value: '#ff0000' },
  ])); sync();
  bob.updateState('scene-1', 'comp-1', 'circle', { x: 90, rotation: 17 }); sync();
  const before = scene(alice);
  alice.undo(); sync();
  expect(scene(alice).objects.circle.parentId).toBe('equation');
  expect(state(alice).fill).toBe('#000000');
  expect(state(alice)).toMatchObject({ x: 90, rotation: 17 });
  for (const cid of before.compositionOrder) close(corner(item(scene(alice), 'circle', cid), 20, 15), corner(item(before, 'circle', cid), 20, 15));
  expect(alice.lastUndoPreservedObjects).toBe(1);
});

it('retains a detach used by a peer without consuming an earlier Undo action', () => {
  const { alice, bob, sync } = replicas();
  alice.setParent('scene-1', 'circle', 'equation'); sync();
  alice.updateState('scene-1', 'comp-1', 'circle', { fill: '#ff0000' });
  alice.setParent('scene-1', 'circle', null); sync();
  bob.updateState('scene-1', 'comp-2', 'circle', { x: 450 }); sync();
  const before = scene(alice);
  alice.undo(); sync();
  expect(scene(alice).objects.circle.parentId).toBeNull();
  for (const cid of before.compositionOrder) close(corner(item(scene(alice), 'circle', cid), 20, 15), corner(item(before, 'circle', cid), 20, 15));
  expect(state(alice).fill).toBe('#ff0000');
  alice.undo(); sync(); expect(state(alice).fill).toBe('#000000');
});

it('does not retain a later relation because of earlier coordinate edits or unrelated peer appearance', () => {
  const { alice, bob, sync } = replicas();
  alice.setParent('scene-1', 'circle', 'equation'); sync();
  bob.updateState('scene-1', 'comp-1', 'circle', { x: 25 }); sync();
  alice.setParent('scene-1', 'circle', null); sync();
  bob.updateState('scene-1', 'comp-1', 'circle', { fill: '#ff0000' }); sync();
  const before = corner(item(scene(alice), 'circle'));
  alice.undo(); sync();
  expect(scene(alice).objects.circle.parentId).toBe('equation');
  close(corner(item(scene(alice), 'circle')), before);
  expect(state(alice).fill).toBe('#ff0000');
  expect(alice.lastUndoPreservedObjects).toBe(0);
});

it('retains the parent coordinate space used by a peer value curve', () => {
  const { alice, bob, sync } = replicas();
  alice.setParent('scene-1', 'circle', 'equation'); sync();
  bob.setKeyframe('scene-1', 'transition-1', 'circle', 'middle', key()); sync();
  const before = frame(scene(alice), 500).objects.find(o => o.object.id === 'circle')!;
  alice.undo(); sync();
  expect(scene(alice).objects.circle.parentId).toBe('equation');
  close(corner(frame(scene(alice), 500).objects.find(o => o.object.id === 'circle')!), corner(before));
});

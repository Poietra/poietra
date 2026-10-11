import { afterEach, expect, it } from 'vitest';
import * as Y from 'yjs';
import * as kernel from '../../../_build/js/release/build/motion/motion.js';
import { initializeDocument, readProject, getShared } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { parseProjectFile } from '../shared/project-file';
import { copyObjects } from '../shared/clipboard';
import { captureMotion } from '../shared/motion-template';
import { compileProposal, applyProposal, type ProposalOperation } from '../shared/ai';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { transitionFrame } from '../src/engine/evaluate';
import { frameToSvg } from '../src/engine/renderer';
import { shapeGeometry } from '../src/engine/rendering/shape-geometry';
import { geometryProject } from './geometry-fixture';

const docs: Y.Doc[] = [];
afterEach(() => { for (const doc of docs.splice(0)) doc.destroy(); });
function replicas(project = geometryProject()) {
  const seed = new Y.Doc(); docs.push(seed); initializeDocument(seed, project);
  const stores = [new Y.Doc(), new Y.Doc()].map(doc => {
    docs.push(doc); Y.applyUpdate(doc, Y.encodeStateAsUpdate(seed));
    return Object.assign(Object.create(EditorStore.prototype), { doc, undoManager: new EditorUndoManager(doc) }) as EditorStore;
  });
  const sync = () => {
    Y.applyUpdate(stores[0].doc, Y.encodeStateAsUpdate(stores[1].doc));
    Y.applyUpdate(stores[1].doc, Y.encodeStateAsUpdate(stores[0].doc));
    expect(readProject(stores[0].doc)).toEqual(readProject(stores[1].doc));
  };
  return { alice: stores[0], bob: stores[1], sync };
}
const definition = (store: EditorStore, cid = 'comp-1', id = 'diagram') => store.scene('scene-1').compositions[cid].states[id].geometry!;
const path = ['scenes', 'scene-1', 'compositions', 'comp-1', 'states', 'diagram', 'geometry'];
const free = (label = 'P') => ({ kind: 'free' as const, x: 3, y: 2, label });
const valid = (store: EditorStore) => expect(parseProjectFile(JSON.stringify(readProject(store.doc)))).toEqual(readProject(store.doc));

it('creates a semantic diagram, upgrades monotonically, and keeps Composition coordinates independent', () => {
  const { alice } = replicas(makeDemoProject());
  const id = alice.addObject('scene-1', 'comp-1', 'geometry', { geometry: { points: { a: { x: 4 } } } });
  expect(definition(alice, 'comp-1', id).points.a.x).toBe(4);
  expect(readProject(alice.doc)!.version).toBe(5);
  alice.updateState('scene-1', 'comp-2', id, { geometry: { points: { a: { y: 6 } } } });
  expect(definition(alice, 'comp-1', id).points.a.y).toBe(-1);
  expect(definition(alice, 'comp-2', id).points.a.y).toBe(6);
  alice.undo(); alice.undo(); expect(alice.scene('scene-1').objects[id]).toBeUndefined();
  expect(readProject(alice.doc)!.version).toBe(5);
  alice.redo(); valid(alice);
});

it('merges offline coordinates and labels as leaves and keeps all Yjs parent identities through Undo/Redo', () => {
  const { alice, bob, sync } = replicas();
  const point = getShared(alice.doc, [...path, 'points', 'a']), vector = getShared(alice.doc, [...path, 'vectors', 'ab']);
  const before = definition(alice), patch = Object.freeze({ points: Object.freeze({ a: Object.freeze({ x: 1 }) }) });
  alice.updateState('scene-1', 'comp-1', 'diagram', { geometry: patch });
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { a: { y: 3 } }, vectors: { ab: { label: 'peer' } } } });
  sync(); expect(definition(alice).points.a).toMatchObject({ x: 1, y: 3 });
  expect(before.points.a).toMatchObject({ x: -2, y: -1 });
  alice.undo(); sync(); expect(definition(alice).points.a).toMatchObject({ x: -2, y: 3 });
  expect(definition(alice).vectors.ab.label).toBe('peer');
  alice.redo(); sync(); expect(definition(alice).points.a).toMatchObject({ x: 1, y: 3 });
  expect(getShared(alice.doc, [...path, 'points', 'a'])).toBe(point);
  expect(getShared(alice.doc, [...path, 'vectors', 'ab'])).toBe(vector); valid(alice);
});

it('retains a new point referenced by a peer while unrelated coordinates undo, without consuming an earlier action', () => {
  const { alice, bob, sync } = replicas();
  alice.setProjectName('Earlier');
  alice.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { p: free(), a: { x: -4 } } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { vectors: { peer: { from: 'p', to: 'm', label: 'peer vector' } } } }); sync();
  alice.undo(); sync();
  expect(definition(alice).points.p).toMatchObject(free());
  expect(definition(alice).points.a.x).toBe(-2);
  expect(alice.lastPreservedGeometryElements).toBe(1);
  expect(readProject(alice.doc)!.name).toBe('Earlier'); valid(alice);
  alice.redo(); sync(); valid(alice);
});

it('retains a peer edited point and a derived chain but removes an unrelated new point', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: {
    p: free(), q: free('Q'), n: { kind: 'midpoint', x: 0, y: 0, from: 'p', to: 'm', label: 'N' },
  } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { n: { label: 'Peer N' } } } }); sync();
  alice.undo(); sync();
  expect(definition(alice).points.n.label).toBe('Peer N'); expect(definition(alice).points.p).toBeDefined();
  expect(definition(alice).points.q).toBeUndefined(); valid(alice);
});

it('keeps the construction relation needed by a peer when Undo would create a midpoint cycle', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { c: { kind: 'midpoint', x: 0, y: 0, from: 'a', to: 'b' } } } }); sync();
  alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', geometry: { points: { m: { from: 'b', to: 'b' } } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { a: { kind: 'midpoint', from: 'm', to: 'b' } } } }); sync();
  alice.undo(); sync();
  expect(definition(alice).points.m).toMatchObject({ from: 'b', to: 'b' });
  expect(alice.lastPreservedGeometryElements).toBeGreaterThan(0);
  valid(alice);
});

it('rejects a cycle, referenced deletion, unknown fields and non-finite coordinates before any writes', () => {
  const { alice } = replicas(); const before = readProject(alice.doc), point = getShared(alice.doc, [...path, 'points', 'a']);
  for (const patch of [
    { points: { m: { from: 'm' } } }, { points: { a: { deleted: true } } }, { points: { a: { x: Infinity } } },
    { points: { a: { curve: 'M0 0' } } }, { vectors: { ab: { from: 'missing' } } },
  ]) expect(() => alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', geometry: patch } as never)).toThrow();
  expect(readProject(alice.doc)).toBe(before); expect(getShared(alice.doc, [...path, 'points', 'a'])).toBe(point);
});

it('interpolates free points and derives midpoints while copying and reusable motions keep independent diagram scopes', () => {
  const { alice } = replicas();
  alice.updateState('scene-1', 'comp-2', 'diagram', { geometry: { points: { a: { x: 2, y: 3 } } } });
  const scene = alice.scene('scene-1'), transition = scene.transitions['transition-1'];
  const frame = transitionFrame(scene, transition, transition.duration / 2, kernel);
  expect(frame.objects[0].state.geometry!.points.a).toMatchObject({ x: 0, y: 1 });
  const shape = shapeGeometry(frame.objects[0]); expect(shape?.kind).toBe('diagram');
  if (shape?.kind !== 'diagram') throw new Error('missing diagram');
  expect(shape.curves.find(c => c.id === 'points/m')!.path).toContain('M48 0');
  expect(frameToSvg(frame)).toContain('data-geometry-element="points/m"');
  const [copy] = alice.paste('scene-1', 'comp-1', copyObjects(scene, 'comp-1', ['diagram']), 0);
  alice.updateState('scene-1', 'comp-1', copy, { geometry: { points: { a: { x: 10 } } } });
  expect(definition(alice).points.a.x).toBe(-2);
  const motion = captureMotion(scene, ['diagram'], 'Geometry'); expect(motion.version).toBe(5);
  const inserted = alice.insertMotion('scene-1', motion);
  expect(definition(alice, inserted.compositionId, inserted.ids[0]).points.a.x).toBe(-2); valid(alice);
});

it('AI edits semantic elements with guards, preserves concurrent coordinates and rejects invalid final references', () => {
  const { alice, bob, sync } = replicas();
  const operation: ProposalOperation = { action: 'setGeometryElement', compositionId: 'comp-1', objectId: 'diagram', collection: 'angles', elementId: 'new-angle', element: { from: 'b', vertex: 'a', to: 'm', label: 'α' } };
  const proposal = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Angle', operations: [operation] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { b: { x: 4 } } } }); sync();
  applyProposal(alice.doc, proposal); expect(definition(alice).angles['new-angle']).toMatchObject(operation.element!); valid(alice);
  expect(() => compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Bad', operations: [{ ...operation, element: { from: 'missing', vertex: 'a', to: 'm', label: 'bad' } }] })).toThrow();
  const pending = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Rewire', operations: [{ ...operation, element: { from: 'c', vertex: 'a', to: 'm', label: 'rewire' } }] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { m: { from: 'b' } } } }); sync();
  expect(() => applyProposal(alice.doc, pending)).toThrow(/提案後/); valid(alice);
});

it('AI converts a midpoint to a free point using coordinate/reference leaves and preserves a peer label', () => {
  const { alice, bob, sync } = replicas();
  const parent = getShared(alice.doc, [...path, 'points', 'm']);
  const operation: ProposalOperation = { action: 'setGeometryElement', compositionId: 'comp-1', objectId: 'diagram', collection: 'points', elementId: 'm', element: { kind: 'free', x: 1, y: 2, label: 'M' } };
  const proposal = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Free point', operations: [operation] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { geometry: { points: { m: { label: 'Peer M' } } } }); sync();
  applyProposal(alice.doc, proposal);
  expect(definition(alice).points.m).toMatchObject({ kind: 'free', x: 1, y: 2, label: 'Peer M', from: null, to: null });
  expect(getShared(alice.doc, [...path, 'points', 'm'])).toBe(parent); valid(alice);
  alice.undo(); sync(); expect(definition(alice).points.m).toMatchObject({ kind: 'midpoint', from: 'a', to: 'b', label: 'Peer M' }); valid(alice);
});

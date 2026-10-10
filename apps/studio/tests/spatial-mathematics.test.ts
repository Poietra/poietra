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
import { spatialMathProject } from './spatial-math-fixture';

const docs: Y.Doc[] = [];
afterEach(() => { for (const doc of docs.splice(0)) doc.destroy(); });
function replicas(project = spatialMathProject('network')) {
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
const state = (store: EditorStore, cid = 'comp-1', id = 'diagram') => store.scene('scene-1').compositions[cid].states[id];
const path = ['scenes', 'scene-1', 'compositions', 'comp-1', 'states', 'diagram'];
const node = { x: 3, y: 2, label: 'P' };
const edge = { from: 'p', to: 'b', label: 'edge', directed: true, weight: 2, bend: 0 };
const valid = (store: EditorStore) => expect(parseProjectFile(JSON.stringify(readProject(store.doc)))).toEqual(readProject(store.doc));

for (const kind of ['network', 'surface'] as const) it(`creates ${kind} as a semantic object, upgrades v1 monotonically and preserves Composition independence`, () => {
  const { alice } = replicas(makeDemoProject());
  const id = alice.addObject('scene-1', 'comp-1', kind);
  expect(readProject(alice.doc)!.version).toBe(6);
  if (kind === 'network') {
    alice.updateState('scene-1', 'comp-2', id, { network: { nodes: { a: { x: 5 } } } });
    expect(state(alice, 'comp-1', id).network!.nodes.a.x).toBe(-2);
  } else {
    alice.updateState('scene-1', 'comp-2', id, { surface: { yaw: 95 } });
    expect(state(alice, 'comp-1', id).surface!.yaw).toBe(35);
  }
  alice.undo(); alice.undo(); expect(alice.scene('scene-1').objects[id]).toBeUndefined();
  expect(readProject(alice.doc)!.version).toBe(6); alice.redo(); valid(alice);
});

it('merges network coordinates, labels and edge weights offline, retaining Yjs parents through Undo/Redo', () => {
  const { alice, bob, sync } = replicas();
  const a = getShared(alice.doc, [...path, 'network', 'nodes', 'a']);
  const ab = getShared(alice.doc, [...path, 'network', 'edges', 'ab']);
  const snapshot = state(alice);
  alice.updateState('scene-1', 'comp-1', 'diagram', { network: { nodes: { a: { x: 1 } }, edges: { ab: { weight: null } } } });
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { nodes: { a: { y: 3, label: 'Peer A' } }, edges: { ab: { label: 'peer edge' } } } });
  sync(); expect(state(alice).network!.nodes.a).toMatchObject({ x: 1, y: 3, label: 'Peer A' });
  expect(snapshot.network!.nodes.a).toMatchObject({ x: -2, y: -1, label: 'A' });
  alice.undo(); sync(); expect(state(alice).network!.nodes.a).toMatchObject({ x: -2, y: 3, label: 'Peer A' });
  expect(state(alice).network!.edges.ab).toMatchObject({ weight: 1, label: 'peer edge' });
  alice.redo(); sync(); expect(state(alice).network!.edges.ab.weight).toBeNull();
  expect(getShared(alice.doc, [...path, 'network', 'nodes', 'a'])).toBe(a);
  expect(getShared(alice.doc, [...path, 'network', 'edges', 'ab'])).toBe(ab); valid(alice);
});

it('retains a new node used by a peer edge while unrelated coordinates undo without consuming an earlier action', () => {
  const { alice, bob, sync } = replicas(); alice.setProjectName('Earlier');
  alice.updateState('scene-1', 'comp-1', 'diagram', { network: { nodes: { p: node, q: node, a: { x: -4 } } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { peer: edge } } }); sync();
  alice.undo(); sync();
  expect(state(alice).network!.nodes.p).toMatchObject(node);
  expect(state(alice).network!.nodes.q).toBeUndefined();
  expect(state(alice).network!.nodes.a.x).toBe(-2);
  expect(alice.lastPreservedGeometryElements).toBe(1);
  expect(readProject(alice.doc)!.name).toBe('Earlier'); valid(alice);
  alice.redo(); sync(); valid(alice);
});

it('retains a peer-labelled new edge and its endpoints while removing unrelated new nodes', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'diagram', { network: { nodes: { p: node, q: node }, edges: { local: edge } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { local: { label: 'Peer edge' } } } }); sync();
  alice.undo(); sync(); expect(state(alice).network!.edges.local.label).toBe('Peer edge');
  expect(state(alice).network!.nodes.p).toBeDefined(); expect(state(alice).network!.nodes.q).toBeUndefined(); valid(alice);
});

it('retains a restored node used by a peer loop through Undo and Redo', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { ab: { deleted: true }, ca: { deleted: true } }, nodes: { a: { deleted: true } } } }); sync();
  alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', network: { nodes: { a: { deleted: false } } } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { loop: { ...edge, from: 'a', to: 'a' } } } }); sync();
  alice.undo(); sync(); expect(state(alice).network!.nodes.a.deleted).toBe(false); valid(alice);
  alice.redo(); sync(); valid(alice);
});

it('rejects invalid endpoints, referenced deletion, unsafe IDs and non-finite network values before any writes', () => {
  const { alice } = replicas(), before = readProject(alice.doc);
  for (const network of [
    { nodes: { a: { deleted: true } } }, { nodes: { a: { x: Infinity } } },
    { edges: { ab: { from: 'missing' } } }, { edges: { ab: { bend: 11 } } },
    { edges: { ab: { weight: NaN } } }, { nodes: { constructor: node } },
    { nodes: { a: { unknown: 'field' } } },
  ]) expect(() => alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', network } as never)).toThrow();
  expect(readProject(alice.doc)).toBe(before);
  alice.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { loop: { ...edge, from: 'a', to: 'a' }, parallel: { ...edge, from: 'a', bend: 1 } } } }); valid(alice);
});

it('merges surface expressions and camera leaves offline without replacing definitions or peer settings', () => {
  const { alice, bob, sync } = replicas(spatialMathProject('surface'));
  const surface = getShared(alice.doc, [...path, 'surface']);
  alice.updateState('scene-1', 'comp-1', 'diagram', { surface: { zExpression: 'a*(x^2-y^2)', a: 2 } });
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { yaw: 95, wireframe: false } }); sync();
  expect(state(alice).surface).toMatchObject({ zExpression: 'a*(x^2-y^2)', a: 2, yaw: 95, wireframe: false });
  alice.undo(); sync(); expect(state(alice).surface).toMatchObject({ zExpression: 'a*sin(x)*cos(y)', a: 1, yaw: 95, wireframe: false });
  alice.redo(); sync(); expect(getShared(alice.doc, [...path, 'surface'])).toBe(surface); valid(alice);
});

it('keeps peer-dependent surface ranges and visible modes valid when unrelated camera/style edits undo', () => {
  const { alice, bob, sync } = replicas(spatialMathProject('surface'));
  alice.setProjectName('Earlier');
  alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', surface: { uMax: 10, filled: true, wireframe: false, yaw: 80 } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { uMin: 5 } }); sync();
  alice.undo(); sync(); expect(state(alice).surface).toMatchObject({ uMin: 5, uMax: 10, yaw: 35 });
  expect(readProject(alice.doc)!.name).toBe('Earlier'); expect(alice.lastPreservedGeometryElements).toBeGreaterThan(0); valid(alice);
  alice.redo(); sync(); valid(alice);
  alice.updateState('scene-1', 'comp-1', 'diagram', { surface: { wireframe: true } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { filled: false } }); sync();
  alice.undo(); sync(); expect(state(alice).surface!.wireframe).toBe(true); valid(alice);
});

it('does not restore a parametric mode incompatible with an unused expression edited by a peer', () => {
  const p = spatialMathProject('surface');
  for (const c of Object.values(p.scenes['scene-1'].compositions)) c.states.diagram.surface!.kind = 'parametric';
  const { alice, bob, sync } = replicas(p);
  alice.updateState('scene-1', 'comp-1', 'diagram', { surface: { kind: 'heightfield', yaw: 70 } }); sync();
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { xExpression: 'unused invalid(' } }); sync();
  alice.undo(); sync(); expect(state(alice).surface).toMatchObject({ kind: 'heightfield', xExpression: 'unused invalid(', yaw: 35 }); valid(alice);
});

it('rejects invalid surface programs, camera, ranges, subdivision counts and modes before any writes', () => {
  const { alice } = replicas(spatialMathProject('surface')), before = readProject(alice.doc);
  for (const surface of [
    { zExpression: 'globalThis.alert(1)' }, { zExpression: 'z=x+y' }, { yaw: Infinity },
    { zoom: 0 }, { pitch: 90 }, { steps: 3 }, { steps: 49 }, { steps: 8.5 },
    { uMin: 3 }, { filled: false, wireframe: false }, { unknown: 1 },
  ]) expect(() => alice.updateState('scene-1', 'comp-1', 'diagram', { fill: '#ffffff', surface } as never)).toThrow();
  expect(readProject(alice.doc)).toBe(before);
  expect(() => parseProjectFile(JSON.stringify({ ...before, version: 5 }))).toThrow();
  expect(() => parseProjectFile(JSON.stringify({ ...before, version: 7 }))).toThrow();
});

for (const kind of ['network', 'surface'] as const) it(`${kind} animation, clipboard and reusable motions preserve semantic scopes and derive render paths`, () => {
  const { alice } = replicas(spatialMathProject(kind));
  alice.updateState('scene-1', 'comp-2', 'diagram', kind === 'network'
    ? { network: { nodes: { a: { x: 2, y: 3 } } } }
    : { surface: { a: 3, yaw: 95, zExpression: 'a*(x^2-y^2)' } });
  const scene = alice.scene('scene-1'), transition = scene.transitions['transition-1'];
  const frame = transitionFrame(scene, transition, transition.duration / 2, kernel);
  if (kind === 'network') expect(frame.objects[0].state.network!.nodes.a).toMatchObject({ x: 0, y: 1 });
  else expect(frame.objects[0].state.surface).toMatchObject({ a: 2, yaw: 65, zExpression: 'a*(x^2-y^2)' });
  expect(shapeGeometry(frame.objects[0])!.kind).toBe('diagram');
  expect(frameToSvg(frame)).toContain(`data-geometry-element="${kind === 'network' ? 'nodes/a' : 'faces/'}`);
  const [copy] = alice.paste('scene-1', 'comp-1', copyObjects(scene, 'comp-1', ['diagram']), 0);
  alice.updateState('scene-1', 'comp-1', copy, kind === 'network' ? { network: { nodes: { a: { x: 10 } } } } : { surface: { yaw: 120 } });
  expect(state(alice)[kind]).toEqual(scene.compositions['comp-1'].states.diagram[kind]);
  const motion = captureMotion(scene, ['diagram'], 'Mathematics'); expect(motion.version).toBe(6);
  const inserted = alice.insertMotion('scene-1', motion); expect(state(alice, inserted.compositionId, inserted.ids[0])[kind]).toEqual(state(alice)[kind]); valid(alice);
});

it('AI writes network leaves, preserves peer coordinates/labels and guards endpoint deletion', () => {
  const { alice, bob, sync } = replicas();
  const operation: ProposalOperation = { action: 'setNetworkElement', compositionId: 'comp-1', objectId: 'diagram', collection: 'edges', elementId: 'ab', element: { ...state(alice).network!.edges.ab, directed: true, weight: null } };
  const proposal = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Directed edge', operations: [operation] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { nodes: { b: { x: 4 } }, edges: { ab: { label: 'Peer label' } } } }); sync();
  applyProposal(alice.doc, proposal); expect(state(alice).network!.edges.ab).toMatchObject({ directed: true, weight: null, label: 'Peer label' }); valid(alice);
  const pending = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Loop', operations: [{ ...operation, elementId: 'loop', element: { ...edge, from: 'c', to: 'c' } }] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { network: { edges: { bc: { deleted: true }, ca: { deleted: true } }, nodes: { c: { deleted: true } } } }); sync();
  expect(() => applyProposal(alice.doc, pending)).toThrow(/提案後/); valid(alice);
});

it('AI validates final network references and creates endpoints and edges atomically from a v1 project', () => {
  const { alice } = replicas(makeDemoProject());
  const operations: ProposalOperation[] = [
    { action: 'createObject', ref: '@network', compositionId: 'comp-1', kind: 'network', name: 'Graph theory', x: 640, y: 360, width: 560, height: 360, fill: '#ffffff', text: '', fontSize: 32 },
    { action: 'setNetworkElement', compositionId: 'comp-1', objectId: '@network', collection: 'edges', elementId: 'loop', element: { ...edge, from: 'p', to: 'p' } },
    { action: 'setNetworkElement', compositionId: 'comp-1', objectId: '@network', collection: 'nodes', elementId: 'p', element: node },
  ];
  applyProposal(alice.doc, compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Graph', operations }));
  expect(readProject(alice.doc)!.version).toBe(6); valid(alice);
  const id = Object.values(alice.scene('scene-1').objects).find(o => o.kind === 'network')!.id;
  expect(() => compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Orphan', operations: [{ action: 'setNetworkElement', compositionId: 'comp-1', objectId: id, collection: 'nodes', elementId: 'p', element: null }] })).toThrow();
});

it('AI edits a surface formula without clobbering camera/style changes and guards coupled range changes', () => {
  const { alice, bob, sync } = replicas(spatialMathProject('surface'));
  const surface = { ...state(alice).surface!, zExpression: 'a*(x^2-y^2)', a: 2 };
  const operation: ProposalOperation = { action: 'setSurface', compositionId: 'comp-1', objectId: 'diagram', surface };
  const proposal = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Saddle', operations: [operation] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { yaw: 100, axes: false }, fill: '#ff0000' }); sync();
  applyProposal(alice.doc, proposal); expect(state(alice).surface).toMatchObject({ zExpression: 'a*(x^2-y^2)', a: 2, yaw: 100, axes: false });
  expect(state(alice).fill).toBe('#ff0000'); valid(alice);
  const pending = compileProposal(alice.doc, readProject(alice.doc)!, 'scene-1', { message: 'Range', operations: [{ ...operation, surface: { ...state(alice).surface!, uMin: 1 } }] });
  bob.updateState('scene-1', 'comp-1', 'diagram', { surface: { uMax: 2 } }); sync();
  expect(() => applyProposal(alice.doc, pending)).toThrow(/提案後/); valid(alice);
});

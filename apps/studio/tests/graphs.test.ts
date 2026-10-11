import { afterEach, expect, it } from 'vitest';
import * as Y from 'yjs';
import * as kernel from '../../../_build/js/release/build/motion/motion.js';
import { initializeDocument, readProject, getShared, applyChanges } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { defaultTrack } from '../shared/model';
import { parseProjectFile } from '../shared/project-file';
import { copyObjects, serializeObjects, parseObjects } from '../shared/clipboard';
import { captureMotion } from '../shared/motion-template';
import { compileProposal, applyProposal, type ProposalOperation } from '../shared/ai';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { compositionFrame, transitionFrame, compileScene, type RenderObject } from '../src/engine/evaluate';
import { frameToSvg } from '../src/engine/renderer';
import { shapeGeometry } from '../src/engine/rendering/shape-geometry';
import { graphProject } from './graph-fixture';

const docs: Y.Doc[] = [];
afterEach(() => { for (const doc of docs.splice(0)) doc.destroy(); });
function replicas(project = graphProject()) {
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
const graph = (store: EditorStore, cid = 'comp-1', id = 'graph') => store.scene('scene-1').compositions[cid].states[id].graph!;
const path = ['scenes', 'scene-1', 'compositions', 'comp-1', 'states', 'graph', 'graph'];
const operation = (property: Extract<ProposalOperation, { action: 'setState' }>['property'], value: number | string | boolean): Extract<ProposalOperation, { action: 'setState' }> => ({ action: 'setState', compositionId: 'comp-1', objectId: 'graph', property, value });
const proposal = (store: EditorStore, operations: ProposalOperation[]) => compileProposal(store.doc, readProject(store.doc)!, 'scene-1', { message: 'Function graph', operations });
const curve = (item: RenderObject) => {
  const shape = shapeGeometry(item); expect(shape?.kind).toBe('graph');
  if (shape?.kind !== 'graph') throw new Error('Missing graph geometry');
  return shape;
};

it('creates one mathematical object, owns independent Composition states, and upgrades without Undo downgrades', () => {
  const { alice } = replicas(makeDemoProject());
  const id = alice.addObject('scene-1', 'comp-1', 'graph', { graph: { expression: 'x^3-3x', a: 0 } });
  expect(Object.keys(alice.scene('scene-1').objects)).toHaveLength(4);
  expect(graph(alice, 'comp-1', id)).toMatchObject({ expression: 'x^3-3x', a: 0, syntaxVersion: 1 });
  expect(alice.scene('scene-1').compositions['comp-2'].states[id].visible).toBe(false);
  expect(readProject(alice.doc)!.version).toBe(4);
  alice.updateState('scene-1', 'comp-2', id, { graph: { a: 8 } });
  expect(graph(alice, 'comp-1', id).a).toBe(0);
  alice.undo(); expect(graph(alice, 'comp-2', id).a).toBe(0);
  alice.undo(); expect(alice.scene('scene-1').objects[id]).toBeUndefined();
  expect(readProject(alice.doc)!.version).toBe(4);
  alice.redo(); expect(graph(alice, 'comp-1', id).expression).toBe('x^3-3x');
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('merges offline expression and coefficient edits in the same map and selectively undoes local leaves', () => {
  const { alice, bob, sync } = replicas();
  const map = getShared(alice.doc, path);
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'a*sin(x)+b' } });
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { a: 5, b: 2 } });
  sync();
  expect(graph(alice)).toMatchObject({ expression: 'a*sin(x)+b', a: 5, b: 2 });
  expect(getShared(alice.doc, path)).toBe(map);
  alice.undo(); sync();
  expect(graph(alice)).toMatchObject({ expression: 'x^3 - a*x', a: 5, b: 2 });
  expect(getShared(alice.doc, path)).toBe(map);
  expect(graph(alice, 'comp-2').a).toBe(3);
});

it('switches equations atomically, accepts immutable patches and preserves offline coefficients through Undo', () => {
  const { alice, bob, sync } = replicas();
  const map = getShared(alice.doc, path);
  const patch = Object.freeze({ expression: 'x^2+y^2=a^2' });
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: patch });
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { a: 1.5 } });
  sync();
  expect(patch).toEqual({ expression: 'x^2+y^2=a^2' });
  expect(graph(alice)).toMatchObject({ expression: 'x^2+y^2=a^2', syntaxVersion: 2, a: 1.5 });
  expect(getShared(alice.doc, path)).toBe(map);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
  alice.undo(); sync();
  expect(graph(alice)).toMatchObject({ expression: 'x^3 - a*x', syntaxVersion: 1, a: 1.5 });
  alice.redo(); sync();
  expect(graph(alice)).toMatchObject({ expression: 'x^2+y^2=a^2', syntaxVersion: 2, a: 1.5 });
  expect(getShared(alice.doc, path)).toBe(map);
});

it('keeps a peer equation and its grammar when undoing the switch that introduced equations', () => {
  const { alice, bob, sync } = replicas();
  alice.setProjectName('Earlier edit');
  alice.updateState('scene-1', 'comp-1', 'graph', { fill: '#ffffff', graph: { expression: 'x^2+y^2=1' } }); sync();
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'x*y=1' } }); sync();
  alice.undo(); sync();
  expect(graph(alice)).toMatchObject({ expression: 'x*y=1', syntaxVersion: 2 });
  expect(alice.lastPreservedGraphDefinitions).toBe(1);
  expect(readProject(alice.doc)!.name).toBe('Earlier edit');
  expect(alice.scene('scene-1').compositions['comp-1'].states.graph.fill).not.toBe('#ffffff');
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
  alice.redo(); sync();
  expect(graph(alice)).toMatchObject({ expression: 'x*y=1', syntaxVersion: 2 });
  alice.undo(); alice.undo();
  expect(readProject(alice.doc)!.name).not.toBe('Earlier edit');
});

it('merges offline equation/function switches with a compatible additive grammar', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'x^2+y^2=1' } });
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'sin(x)' } });
  sync();
  expect(graph(alice).syntaxVersion).toBe(2);
  expect(['x^2+y^2=1', 'sin(x)']).toContain(graph(alice).expression);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'cos(x)' } });
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'x*y=1' } });
  sync();
  expect(graph(alice).syntaxVersion).toBe(2);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('creates, copies and reuses animated equations as mathematical objects', () => {
  const { alice } = replicas(makeDemoProject());
  const id = alice.addObject('scene-1', 'comp-1', 'graph', { graph: { expression: 'x^2+y^2=a^2', a: 1 } });
  alice.updateState('scene-1', 'comp-2', id, { visible: true, graph: { a: 1.5 } });
  alice.setKeyframe('scene-1', 'transition-1', id, 'radius', { property: 'graphA', at: .5, value: .75, easing: 'linear' });
  const scene = alice.scene('scene-1');
  const mid = transitionFrame(scene, scene.transitions['transition-1'], scene.transitions['transition-1'].duration / 2, kernel).objects.find(item => item.object.id === id)!;
  expect(mid.state.graph).toMatchObject({ expression: 'x^2+y^2=a^2', syntaxVersion: 2, a: .75 });
  expect(curve(mid).curve).not.toBe('');
  expect(curve(mid).curve).not.toMatch(/NaN|Infinity/);
  const clipboard = copyObjects(scene, 'comp-1', [id]);
  const [copy] = alice.paste('scene-1', 'comp-1', clipboard, 0);
  expect(graph(alice, 'comp-1', copy)).toEqual(graph(alice, 'comp-1', id));
  const motion = captureMotion(scene, [id], 'Circle radius');
  const inserted = alice.insertMotion('scene-1', motion);
  expect(graph(alice, inserted.compositionId, inserted.ids[0])).toMatchObject({ expression: 'x^2+y^2=a^2', syntaxVersion: 2 });
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('AI authors equations and paired grammar leaves while guarding a later peer mode change', () => {
  const { alice, bob, sync } = replicas();
  const edits = proposal(alice, [operation('graphExpression', 'x^2+y^2=a^2'), operation('graphA', 1)]);
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { b: 5 } }); sync();
  applyProposal(alice.doc, edits);
  expect(graph(alice)).toMatchObject({ expression: 'x^2+y^2=a^2', syntaxVersion: 2, a: 1, b: 5 });
  alice.undo(); expect(graph(alice)).toMatchObject({ expression: 'x^3 - a*x', syntaxVersion: 1, a: 3, b: 5 }); sync();
  const guarded = proposal(alice, [operation('graphA', 2)]);
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'x*y=1' } }); sync();
  expect(() => applyProposal(alice.doc, guarded)).toThrow('提案後');
});

it('keeps a newly created graph used by a collaborator and preserves its peer coefficient edits', () => {
  const { alice, bob, sync } = replicas(makeDemoProject());
  const id = alice.addObject('scene-1', 'comp-1', 'graph'); sync();
  bob.updateState('scene-1', 'comp-1', id, { graph: { a: 7 } }); sync();
  alice.undo(); sync();
  expect(alice.scene('scene-1').objects[id].kind).toBe('graph');
  expect(graph(alice, 'comp-1', id).a).toBe(7);
  expect(alice.lastUndoPreservedObjects).toBe(1);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('retains only the axis bounds needed by a peer when Undo would invert a valid range', () => {
  const { alice, bob, sync } = replicas();
  alice.setProjectName('Earlier edit');
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { xMin: 10, xMax: 20 }, fill: '#ffffff' }); sync();
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { xMin: 15 } }); sync();
  alice.undo(); sync();
  expect(graph(alice)).toMatchObject({ xMin: 15, xMax: 20 });
  expect(alice.scene('scene-1').compositions['comp-1'].states.graph.fill).not.toBe('#ffffff');
  expect(alice.lastPreservedGraphRanges).toBe(1);
  expect(readProject(alice.doc)!.name).toBe('Earlier edit');
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
  alice.redo(); expect(graph(alice)).toMatchObject({ xMin: 15, xMax: 20 });
  alice.undo(); alice.undo(); expect(readProject(alice.doc)!.name).not.toBe('Earlier edit');
});

it('retains the current axis bounds when Redo would conflict with a later peer edit', () => {
  const { alice, bob, sync } = replicas();
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { xMin: -2 } });
  alice.undo(); sync();
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { xMax: -2.5 } }); sync();
  alice.redo(); sync();
  expect(graph(alice)).toMatchObject({ xMin: -3, xMax: -2.5 });
  expect(alice.lastPreservedGraphRanges).toBe(1);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('rejects invalid math edits and creation before publishing other fields or format changes', () => {
  const { alice } = replicas();
  const clock = Y.encodeStateVector(alice.doc);
  for (const patch of [{ expression: 'x +' }, { expression: 'globalThis.alert(1)' }, { xMin: 3 }, { yMax: -4 }, { a: NaN }, { breaks: [Infinity] }, { syntaxVersion: 3 }]) {
    expect(() => alice.updateState('scene-1', 'comp-1', 'graph', { x: 90, graph: patch })).toThrow();
  }
  expect(Y.encodeStateVector(alice.doc)).toEqual(clock);
  expect(() => alice.addObject('scene-1', 'comp-1', 'graph', { graph: { expression: 'x+' } })).toThrow();
  expect(Y.encodeStateVector(alice.doc)).toEqual(clock);
});

it('animates coefficients, stretches intermediate keys and shares the evaluated curve with SVG', () => {
  const { alice } = replicas();
  alice.updateState('scene-1', 'comp-2', 'graph', { graph: { a: 7 } });
  alice.setPropertyTiming('scene-1', 'transition-1', 'graph', 'graph', { start: 100, duration: 400, easing: 'linear' });
  alice.setKeyframe('scene-1', 'transition-1', 'graph', 'middle', { property: 'graphA', at: .5, value: 9, easing: 'linear' });
  let scene = alice.scene('scene-1');
  for (const [time, expected] of [[100, 3], [200, 6], [300, 9], [400, 8], [500, 7]]) {
    const frame = transitionFrame(scene, scene.transitions['transition-1'], time, kernel);
    expect(frame.objects[0].state.graph!.a).toBe(expected);
    expect(compileScene(scene, kernel).transition('transition-1', time)).toEqual(frame);
    expect(frameToSvg(frame)).toContain(`data-graph-curve="true" d="${curve(frame.objects[0]).curve}"`);
  }
  alice.setPropertyTiming('scene-1', 'transition-1', 'graph', 'graph', { start: 100, duration: 600, easing: 'linear' });
  scene = alice.scene('scene-1');
  expect(transitionFrame(scene, scene.transitions['transition-1'], 400, kernel).objects[0].state.graph!.a).toBe(9);
  expect(scene.transitions['transition-1'].tracks.graph.keyframes!.middle.at).toBe(.5);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('AI applies mathematical definitions and paired ranges atomically and guards peer range changes', () => {
  const { alice, bob, sync } = replicas();
  const edits = proposal(alice, [operation('graphExpression', 'a*sin(x)+b'), operation('graphXMin', 10), operation('graphXMax', 20), operation('graphBreaks', '12, 15')]);
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { a: 5 } }); sync();
  applyProposal(alice.doc, edits);
  expect(graph(alice)).toMatchObject({ expression: 'a*sin(x)+b', xMin: 10, xMax: 20, breaks: [12, 15], a: 5 });
  alice.undo(); expect(graph(alice)).toMatchObject({ expression: 'x^3 - a*x', xMin: -3, xMax: 3, breaks: [], a: 5 }); sync();
  const guarded = proposal(alice, [operation('graphXMin', 1)]);
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { xMax: .5 } }); sync();
  expect(() => applyProposal(alice.doc, guarded)).toThrow('提案後');
  expect(() => proposal(alice, [operation('graphExpression', 'x+'), operation('graphA', 7)])).toThrow();
  expect(() => proposal(alice, [operation('graphXMin', 8)])).toThrow();
});

it('AI creates graphs with editable definitions in one Undo action and uses version 4', () => {
  const { alice } = replicas(makeDemoProject());
  const operations: ProposalOperation[] = [
    { action: 'createObject', ref: '@function', compositionId: 'comp-1', name: 'Cubic', kind: 'graph', x: 640, y: 360, width: 560, height: 360, fill: '#d7d8e4', text: '', fontSize: 32 },
    { ...operation('graphExpression', 'x^3 - a*x'), objectId: '@function' },
    { ...operation('graphA', 3), objectId: '@function' },
  ];
  applyProposal(alice.doc, proposal(alice, operations));
  const id = Object.values(alice.scene('scene-1').objects).find(o => o.kind === 'graph')!.id;
  expect(graph(alice, 'comp-1', id).expression).toBe('x^3 - a*x');
  expect(readProject(alice.doc)!.version).toBe(4);
  alice.undo(); expect(alice.scene('scene-1').objects[id]).toBeUndefined();
  expect(readProject(alice.doc)!.version).toBe(4);
});

it('portable files and reused motions preserve definitions and timings without serialized geometry', () => {
  const { alice } = replicas();
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: '1/(x-0.123)', breaks: [.123] } });
  alice.setPropertyTiming('scene-1', 'transition-1', 'graph', 'graph', { start: 50, duration: 500, easing: 'linear' });
  const text = JSON.stringify(readProject(alice.doc));
  expect(text).not.toMatch(/"(?:curve|segments|world)":/);
  const loaded = parseProjectFile(text); expect(loaded).toEqual(readProject(alice.doc));
  for (const corrupt of [
    (p: typeof loaded) => { p.version = 3; },
    (p: typeof loaded) => { p.scenes['scene-1'].compositions['comp-1'].states.graph.graph!.syntaxVersion = 3; },
    (p: typeof loaded) => { p.scenes['scene-1'].compositions['comp-1'].states.graph.graph!.expression = 'x+'; },
  ]) { const p = structuredClone(loaded); corrupt(p); expect(() => parseProjectFile(JSON.stringify(p))).toThrow(); }
  const clipboard = copyObjects(alice.scene('scene-1'), 'comp-1', ['graph']);
  const [copy] = alice.paste('scene-1', 'comp-1', clipboard, 0);
  alice.updateState('scene-1', 'comp-1', copy, { graph: { a: 99 } });
  expect(graph(alice).a).toBe(3);
  const template = captureMotion(loaded.scenes['scene-1'], ['graph'], 'Function motion');
  expect(template.version).toBe(4);
  const inserted = alice.insertMotion('scene-1', template);
  expect(graph(alice, inserted.compositionId, inserted.ids[0]).expression).toBe('1/(x-0.123)');
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('keeps version 4 data when reusing a non-graph object with a graph channel or retained definition', () => {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  const id = Object.values(scene.objects)[0].id;
  scene.transitions['transition-1'].tracks[id] = defaultTrack(id, { duration: scene.transitions['transition-1'].duration, easing: 'linear' });
  const { alice } = replicas(project);
  alice.setPropertyTiming('scene-1', 'transition-1', id, 'graph', { start: 100, duration: 500, easing: 'linear' });
  const motion = captureMotion(alice.scene('scene-1'), [id], 'Timing');
  expect(motion.version).toBe(4);
  expect(parseProjectFile(JSON.stringify(motion))).toEqual(motion);
  const clipboard = copyObjects(alice.scene('scene-1'), 'comp-1', [id]);
  clipboard.states[id].graph = { ...graphProject().scenes['scene-1'].compositions['comp-1'].states.graph.graph!, breaks: [] };
  const text = serializeObjects(clipboard);
  expect(JSON.parse(text.split('\n').slice(1).join('\n')).version).toBe(4);
  expect(parseObjects(text)).toEqual(clipboard);
});

it('Write trims the same curve in both hosts and the cache never changes saved definitions', () => {
  const { alice } = replicas(); const scene = alice.scene('scene-1');
  const item = compositionFrame(scene, scene.compositions['comp-1']).objects[0];
  const before = JSON.stringify(readProject(alice.doc));
  const full = curve(item), partial = curve({ ...item, writeProgress: .5 });
  expect(full.curve.length).toBeGreaterThan(partial.curve.length);
  expect(curve({ ...item, writeProgress: 0 }).curve).toBe('');
  expect(full.curve).not.toMatch(/NaN|Infinity/);
  const svg = frameToSvg({ width: 1280, height: 720, background: '#000000', objects: [{ ...item, writeProgress: .5 }] });
  expect(svg).toContain(`data-graph-curve="true" d="${partial.curve}"`);
  expect(svg).not.toContain('stroke-dashoffset');
  full.labels.length = 0;
  expect(curve(item).labels.length).toBeGreaterThan(0);
  expect(JSON.stringify(readProject(alice.doc))).toBe(before);
});

it('restores a missing Composition state with a complete, validated mathematical definition', () => {
  const { alice } = replicas();
  applyChanges(alice.doc, [{ path: ['scenes', 'scene-1', 'compositions', 'comp-2', 'states', 'graph'], value: undefined }], 'peer');
  alice.updateState('scene-1', 'comp-2', 'graph', { graph: { a: 4 } });
  expect(graph(alice, 'comp-2')).toMatchObject({ expression: 'x^3 - a*x', a: 4, xMin: -3 });
  expect(graph(alice).a).toBe(3);
  expect(parseProjectFile(JSON.stringify(readProject(alice.doc)))).toEqual(readProject(alice.doc));
});

it('shades the region under a function as a derived path, upgrades to version 7 only when shaded, and reveals it with Write', () => {
  const { alice, bob, sync } = replicas();
  const map = getShared(alice.doc, path);
  expect(readProject(alice.doc)!.version).toBe(4);
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { filled: false } });
  expect(readProject(alice.doc)!.version).toBe(4);
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { filled: true } });
  bob.updateState('scene-1', 'comp-1', 'graph', { graph: { a: 1 } });
  sync();
  expect(graph(alice)).toMatchObject({ filled: true, a: 1 });
  expect(getShared(alice.doc, path)).toBe(map);
  expect(readProject(alice.doc)!.version).toBe(7);
  const scene = alice.scene('scene-1');
  const item = compositionFrame(scene, scene.compositions['comp-1']).objects[0];
  const full = curve(item), half = curve({ ...item, writeProgress: .5 });
  expect(full.area).toMatch(/^M.*Z$/);
  expect(full.area.length).toBeGreaterThan(half.area.length);
  expect(half.area.length).toBeGreaterThan(0);
  expect(curve({ ...item, writeProgress: 0 }).area).toBe('');
  const svg = frameToSvg(compositionFrame(scene, scene.compositions['comp-1']));
  expect(svg.indexOf('data-graph-area="true"')).toBeGreaterThan(0);
  expect(svg.indexOf('data-graph-area="true"')).toBeLessThan(svg.indexOf('data-graph-curve="true"'));
  expect(svg).toContain(`fill="${scene.compositions['comp-1'].states.graph.stroke}" fill-opacity="0.25" stroke="none"`);
  expect(JSON.stringify(readProject(alice.doc))).not.toMatch(/"area":/);
  alice.undo(); sync();
  expect(graph(alice)).toMatchObject({ filled: false, a: 1 });
  expect(readProject(alice.doc)!.version).toBe(7);
  expect(curve(compositionFrame(alice.scene('scene-1'), alice.scene('scene-1').compositions['comp-1']).objects[0]).area).toBe('');
  alice.redo(); sync();
  expect(graph(alice).filled).toBe(true);
  const loaded = parseProjectFile(JSON.stringify(readProject(alice.doc)));
  expect(loaded).toEqual(readProject(alice.doc));
  for (const version of [6, 8]) expect(() => parseProjectFile(JSON.stringify({ ...loaded, version }))).toThrow();
  const unshaded = structuredClone(loaded); unshaded.version = 6;
  unshaded.scenes['scene-1'].compositions['comp-1'].states.graph.graph!.filled = false;
  expect(parseProjectFile(JSON.stringify(unshaded))).toEqual(unshaded);
  expect(() => alice.updateState('scene-1', 'comp-1', 'graph', { graph: { shaded: true } as never })).toThrow();
  expect(() => proposal(alice, [operation('graphFilled', 1)])).toThrow();
  applyProposal(alice.doc, proposal(alice, [operation('graphFilled', false), { ...operation('graphFilled', true), compositionId: 'comp-2' }]));
  expect(graph(alice).filled).toBe(false);
  expect(graph(alice, 'comp-2').filled).toBe(true);
  alice.updateState('scene-1', 'comp-1', 'graph', { graph: { expression: 'x^2+y^2=a^2', filled: true } });
  expect(curve(compositionFrame(alice.scene('scene-1'), alice.scene('scene-1').compositions['comp-1']).objects[0]).area).toBe('');
});

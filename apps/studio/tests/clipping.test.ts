import { expect, it } from 'vitest';
import * as Y from 'yjs';
import * as kernel from '../../../_build/js/release/build/motion/motion.js';
import { initializeDocument, readProject } from '../shared/document';
import { parseProjectFile } from '../shared/project-file';
import { EditorStore } from '../src/editor/store';
import { EditorUndoManager } from '../src/editor/undo';
import { compositionFrame, transitionFrame, compileScene } from '../src/engine/evaluate';
import { frameToSvg, frameToSvgView } from '../src/engine/renderer';
import { clippingProject } from './clipping-fixture';

it('evaluates hidden animated clipping parents consistently for editing and compiled playback', () => {
  const s = clippingProject().scenes['scene-1'];
  const first = compositionFrame(s, s.compositions['comp-1']);
  expect(first.objects.map(x => x.object.id)).toEqual(['child']);
  expect(first.objects[0].clips).toEqual([{ width: 80, height: 80, world: { a: 1, b: 0, c: 0, d: 1, e: 100, f: 80 } }]);
  Object.assign(s.compositions['comp-2'].states.frame, { width: 40, x: 120, rotation: 45, scaleX: 2, shear: .3 });
  const t = s.transitions['transition-1'];
  const program = compileScene(s, kernel);
  for (const time of [0, t.duration / 2, t.duration]) {
    const frame = transitionFrame(s, t, time, kernel);
    expect(program.transition(t.id, time)).toEqual(frame);
    expect(frame.objects[0].clips).toHaveLength(1);
  }
  expect(program.transition(t.id, t.duration).objects[0].clips![0].width).toBe(40);
  const svg = frameToSvg(first, { idPrefix: 'clip' });
  expect(svg).toContain('clipPathUnits="userSpaceOnUse"');
  expect(svg).toContain('transform="matrix(1 0 0 1 100 80)"');
  expect(frameToSvgView(first).objects[0].clipPaths).toHaveLength(1);
});

it('intersects nested clips and keeps runtime geometry out of portable files', () => {
  const p = clippingProject(), s = p.scenes['scene-1'];
  s.objects.inner = { ...s.objects.frame, id: 'inner', parentId: 'frame' };
  s.objects.child.parentId = 'inner';
  for (const c of Object.values(s.compositions)) c.states.inner = { ...c.states.frame, x: 10, y: 0, width: 30, height: 40 };
  expect(compositionFrame(s, s.compositions['comp-1']).objects[0].clips).toHaveLength(2);
  const saved = JSON.stringify(p);
  expect(saved).not.toContain('"clips"');
  expect(parseProjectFile(saved)).toEqual(p);
  p.version = 2;
  expect(() => parseProjectFile(JSON.stringify(p))).toThrow();
  p.version = 3; s.objects.frame.kind = 'circle';
  expect(() => parseProjectFile(JSON.stringify(p))).toThrow();
});

it('publishes only the clipping leaf, preserves peer poses through Undo and keeps format upgrades monotonic', () => {
  const p = clippingProject(); p.version = 2; delete p.scenes['scene-1'].objects.frame.clipChildren;
  const a = new Y.Doc(), b = new Y.Doc();
  try {
    initializeDocument(a, p); Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    const stores = [a, b].map(doc => Object.assign(Object.create(EditorStore.prototype), { doc, undoManager: new EditorUndoManager(doc) }) as EditorStore);
    stores[0].setObject('scene-1', 'frame', { clipChildren: true });
    stores[1].updateState('scene-1', 'comp-1', 'child', { x: 17 });
    Y.applyUpdate(a, Y.encodeStateAsUpdate(b));
    stores[0].undo();
    expect(readProject(a)!.version).toBe(3);
    expect(stores[0].scene('scene-1').objects.frame.clipChildren).not.toBe(true);
    expect(stores[0].scene('scene-1').compositions['comp-1'].states.child.x).toBe(17);
    stores[0].redo();
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    expect(readProject(a)).toEqual(readProject(b));
    stores[0].setParent('scene-1', 'child', null);
    expect(readProject(a)!.version).toBe(3);
  } finally { a.destroy(); b.destroy(); }
});

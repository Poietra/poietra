import { expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import { compileProposal, applyProposal, type ProposalOperation } from '../shared/ai';
import { initializeDocument, readProject } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { defaultState, type Project } from '../shared/model';
import { compileProposal as original } from './oracle/ai-compiler';

test('a one-property proposal does not read unrelated state payloads or mutate its input', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  try {
    const project = readProject(doc)!;
    const scene = project.scenes['scene-1'];
    const composition = scene.compositions['comp-1'];
    const states = { ...composition.states };
    Object.defineProperty(states, 'equation', { enumerable: true, get() { throw new Error('Unrelated state was read'); } });
    const source: Project = { ...project, scenes: { ...project.scenes, 'scene-1': { ...scene, compositions: { ...scene.compositions, 'comp-1': { ...composition, states } } } } };
    const before = Y.encodeStateVector(doc);
    const proposal = compileProposal(doc, source, 'scene-1', { message: 'Move one object', operations: [{ action: 'setState', compositionId: 'comp-1', objectId: 'circle', property: 'x', value: 600 }] });
    expect(Y.encodeStateVector(doc)).toEqual(before);
    expect(composition.states.circle.x).toBe(245);
    applyProposal(doc, proposal);
    expect(readProject(doc)!.scenes['scene-1'].compositions['comp-1'].states.circle.x).toBe(600);
    expect(readProject(doc)!.scenes['scene-1'].compositions['comp-1'].states.equation).toEqual(composition.states.equation);
  } finally { doc.destroy(); }
});

test('AI creation respects the portable object limit before any shared write', () => {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  for (let i = Object.keys(scene.objects).length; i < 500; i++) {
    const id = `object-${i}`;
    scene.objects[id] = { id, name: id, kind: 'circle', order: i, locked: false, groupId: null };
    for (const composition of Object.values(scene.compositions)) composition.states[id] = defaultState('circle');
  }
  const doc = new Y.Doc(); initializeDocument(doc, project);
  try {
    const before = Y.encodeStateVector(doc);
    const operation: ProposalOperation = { action: 'createObject', ref: '@extra', compositionId: 'comp-1', kind: 'circle', name: 'Extra', x: 10, y: 10, width: 10, height: 10, fill: '#ffffff', text: '', fontSize: 36 };
    expect(() => compileProposal(doc, readProject(doc)!, 'scene-1', { message: 'Add', operations: [operation] })).toThrow('500');
    expect(Y.encodeStateVector(doc)).toEqual(before);
    expect(Object.keys(readProject(doc)!.scenes['scene-1'].objects)).toHaveLength(500);
  } finally { doc.destroy(); }
});

test('mixed proposal plans match the previous compiler with deterministic identities', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  let sequence = 0, random = 17, accepted = 0;
  const uuid = vi.spyOn(crypto, 'randomUUID').mockImplementation(() => `${(++sequence).toString(16).padStart(8, '0')}-0000-4000-8000-000000000000`);
  const next = (limit: number) => { random = (Math.imul(random, 1664525) + 1013904223) >>> 0; return random % limit; };
  const normalize = (result: ReturnType<typeof compileProposal>) => ({ ...result,
    changes: [...result.changes].sort((a, b) => JSON.stringify(a.path).localeCompare(JSON.stringify(b.path))),
    guards: [...result.guards ?? []].sort((a, b) => JSON.stringify(a.path).localeCompare(JSON.stringify(b.path))),
  });
  try {
    const project = readProject(doc)!;
    const before = Y.encodeStateVector(doc);
    for (let index = 0; index < 100; index++) {
      const operations: ProposalOperation[] = [];
      if (index % 2 === 0) operations.push({ action: 'createObject', ref: '@new', compositionId: 'comp-1', name: 'New', kind: 'circle', x: next(1000), y: 200, width: 60, height: 60, fill: '#abcdef', text: '', fontSize: 36 });
      for (let i = 0; i < 5; i++) {
        const objectId = index % 2 === 0 && next(2) ? '@new' : 'circle';
        switch (next(4)) {
          case 0: operations.push({ action: 'setState', compositionId: 'comp-2', objectId, property: 'x', value: next(1000) }); break;
          case 1: operations.push({ action: 'setTrack', transitionId: 'transition-1', objectId, property: 'duration', value: next(900) }); break;
          case 2: operations.push({ action: 'setPropertyTiming', transitionId: 'transition-1', objectId, channel: 'opacity', timing: index % 5 === 0 ? null : { start: 0, duration: next(900), easing: 'easeOut' } }); break;
          case 3: operations.push({ action: 'setState', compositionId: 'comp-1', objectId, property: 'fill', value: '#123456' }); break;
        }
      }
      if (index % 3 === 0) operations.push({ action: 'appendComposition', ref: '@end', transitionRef: '@travel', name: 'End', duration: 1000, transitionDuration: 800 }, { action: 'setState', compositionId: '@end', objectId: 'circle', property: 'x', value: next(1000) });
      if (index % 3 === 0 && index % 5 === 0) operations.push({ action: 'setPropertyTiming', transitionId: '@travel', objectId: 'circle', channel: 'size', timing: null });
      const raw = { message: 'Mixed plan', operations };
      const run = (compiler: typeof compileProposal) => { sequence = 0; try { return { result: normalize(compiler(doc, project, 'scene-1', raw)) }; } catch { return { rejected: true }; } };
      const actual = run(compileProposal);
      if (actual.result) accepted++;
      expect(actual, `scenario ${index}`).toEqual(run(original));
      expect(Y.encodeStateVector(doc)).toEqual(before);
    }
    expect(accepted).toBeGreaterThan(10);
    expect(accepted).toBeLessThan(100);
  } finally { uuid.mockRestore(); doc.destroy(); }
});

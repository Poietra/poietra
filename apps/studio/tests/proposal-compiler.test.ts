import { expect, test } from 'vitest';
import * as Y from 'yjs';
import { compileProposal, applyProposal, type ProposalOperation } from '../shared/ai';
import { initializeDocument, readProject } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { defaultState, type Project } from '../shared/model';

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

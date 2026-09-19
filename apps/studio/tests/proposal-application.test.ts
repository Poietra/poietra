import { expect, test } from 'vitest';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { getValue, initializeDocument, readProject } from '../shared/document';
import { applyProposal, validateProposalForApply, type EditProposal, type GuardedChange } from '../shared/ai';

function write(doc: Y.Doc, path: string[], value: unknown): GuardedChange {
  const expected = getValue(doc, path);
  return { path, value, expected: expected ?? null, existed: expected !== undefined };
}
function proposal(changes: GuardedChange[]): EditProposal { return { id: 'test-proposal', message: 'Test', count: changes.length, changes }; }

test('preparing a later shared value can fail without publishing any earlier write', () => {
  const doc = new Y.Doc();
  try {
    initializeDocument(doc, makeDemoProject());
    const snapshot = readProject(doc), clocks = Y.encodeStateVector(doc), failure = new Error('Late payload failure');
    const payload = Object.defineProperty({}, 'field', { enumerable: true, get() { throw failure; } });
    const input = proposal([write(doc, ['name'], 'Earlier write'), write(doc, ['extra'], payload)]);
    let updates = 0; doc.on('update', () => { updates++; });
    expect(() => applyProposal(doc, input)).toThrow(failure);
    expect(updates).toBe(0); expect(Y.encodeStateVector(doc)).toEqual(clocks); expect(readProject(doc)).toEqual(snapshot);
  } finally { doc.destroy(); }
});

test('a parent replacement mixed with a child edit fails before either write reaches the document', () => {
  const doc = new Y.Doc();
  try {
    initializeDocument(doc, makeDemoProject());
    const base = ['scenes', 'scene-1', 'transitions', 'transition-1', 'tracks', 'circle'];
    const track = { ...(getValue(doc, base) as Record<string, unknown>), duration: 700 };
    const input = proposal([write(doc, base, track), write(doc, [...base, 'duration'], 500)]);
    const before = JSON.stringify(input), clocks = Y.encodeStateVector(doc);
    expect(() => validateProposalForApply(doc, input)).toThrow('重複');
    expect(track.duration).toBe(700); expect(JSON.stringify(input)).toBe(before); expect(Y.encodeStateVector(doc)).toEqual(clocks);
    expect(() => applyProposal(doc, input)).toThrow('重複');
    expect(Y.encodeStateVector(doc)).toEqual(clocks);
    expect(getValue(doc, [...base, 'duration'])).toBe(600);
    expect(JSON.stringify(input)).toBe(before);
  } finally { doc.destroy(); }
});

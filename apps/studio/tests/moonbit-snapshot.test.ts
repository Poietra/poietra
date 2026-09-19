import { describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { applyChanges, getShared, initializeDocument, readProject, toShared } from '../shared/document';
import { makeDemoProject } from '../shared/demo';
import { projectStructureView } from '../shared/structure-view';
import type { Project } from '../shared/model';

function fixture() {
  const doc = new Y.Doc(), project = makeDemoProject();
  project.scenes.other = { ...structuredClone(project.scenes['scene-1']), id: 'other' };
  project.sceneOrder.push('other');
  initializeDocument(doc, project);
  return doc;
}
const statePath = ['scenes', 'scene-1', 'compositions', 'comp-1', 'states', 'circle'];
const x = (doc: Y.Doc) => readProject(doc)!.scenes['scene-1'].compositions['comp-1'].states.circle.x;
const fullRead = (doc: Y.Doc) => projectStructureView(doc.getMap('project').toJSON() as Project);

describe('MoonBit incremental shared snapshots', () => {
  it('reuses unchanged branches and keeps previous snapshots immutable', () => {
    const doc = fixture(), before = readProject(doc)!;
    expect(readProject(doc)).toBe(before);
    applyChanges(doc, [{ path: [...statePath, 'x'], value: 700 }]);
    const after = readProject(doc)!;
    expect(after).toEqual(fullRead(doc));
    expect(after).not.toBe(before);
    expect(after.scenes.other).toBe(before.scenes.other);
    expect(after.scenes['scene-1'].objects).toBe(before.scenes['scene-1'].objects);
    expect(after.scenes['scene-1'].compositions['comp-2'].states).toBe(before.scenes['scene-1'].compositions['comp-2'].states);
    expect(before.scenes['scene-1'].compositions['comp-1'].states.circle.x).not.toBe(700);
    expect(() => { after.scenes.other.name = 'mutated'; }).toThrow(TypeError);
    expect(() => { after.scenes['scene-1'].compositions['comp-1'].states.circle.x = -1; }).toThrow(TypeError);
    expect(x(doc)).toBe(700);
    doc.destroy();
  });

  it('reads preceding writes inside nested transactions, even on the first read', () => {
    const doc = fixture(), state = getShared(doc, statePath) as Y.Map<unknown>;
    doc.transact(() => {
      state.set('x', 10);
      expect(x(doc)).toBe(10);
      doc.transact(() => { state.set('x', 20); expect(x(doc)).toBe(20); });
      state.set('x', 30);
      expect(x(doc)).toBe(30);
    });
    expect(x(doc)).toBe(30);
    expect(readProject(doc)).toEqual(fullRead(doc));
    doc.destroy();
  });

  it('invalidates before deep observers and handles transactions queued by observers', () => {
    const doc = fixture(), state = getShared(doc, statePath) as Y.Map<unknown>;
    readProject(doc);
    const seen: number[] = [];
    doc.getMap('project').observeDeep(() => {
      seen.push(x(doc));
      if (x(doc) === 10) {
        state.set('x', 20);
        seen.push(x(doc));
      }
    });
    state.set('x', 10);
    expect(seen).toEqual([10, 20, 20]);
    expect(x(doc)).toBe(20);
    doc.destroy();
  });

  it('does not confuse pending transactions from an earlier lifecycle observer', () => {
    const doc = fixture(), state = getShared(doc, statePath) as Y.Map<unknown>;
    let nest = false;
    doc.on('beforeObserverCalls', () => {
      if (nest) { nest = false; state.set('x', 99); }
    });
    readProject(doc);
    const seen: number[] = [];
    doc.getMap('project').observeDeep(() => seen.push(x(doc)));
    nest = true;
    state.set('x', 12);
    expect(seen.every(value => value === 99)).toBe(true);
    expect(x(doc)).toBe(99);
    doc.destroy();
  });

  it('recovers from an exception before cache invalidation', () => {
    const doc = fixture(), state = getShared(doc, statePath) as Y.Map<unknown>;
    let fail = false;
    doc.on('beforeObserverCalls', () => { if (fail) { fail = false; throw new Error('observer failed'); } });
    readProject(doc);
    fail = true;
    expect(() => state.set('x', 42)).toThrow('observer failed');
    expect(x(doc)).toBe(42);
    expect(readProject(doc)).toEqual(fullRead(doc));
    doc.destroy();
  });

  it('invalidates replaced maps, deletes, order edits, Undo and remote updates', () => {
    const doc = fixture(), peer = new Y.Doc();
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(doc));
    const undo = new Y.UndoManager(doc.getMap('project'));
    readProject(doc); readProject(peer);
    const scenes = getShared(doc, ['scenes']) as Y.Map<unknown>;
    const replacement = structuredClone(makeDemoProject().scenes['scene-1']);
    replacement.name = 'replacement';
    scenes.set('scene-1', toShared(replacement));
    expect(readProject(doc)).toEqual(fullRead(doc));
    Y.applyUpdate(peer, Y.encodeStateAsUpdate(doc));
    expect(readProject(peer)).toEqual(readProject(doc));
    undo.stopCapturing();
    scenes.delete('other');
    expect(readProject(doc)!.sceneOrder).toEqual(['scene-1']);
    undo.undo();
    expect(readProject(doc)!.sceneOrder).toEqual(['scene-1', 'other']);
    const order = getShared(doc, ['sceneOrder']) as Y.Array<string>;
    doc.transact(() => { order.delete(0, 2); order.insert(0, ['other', 'scene-1', 'other']); });
    expect(readProject(doc)!.sceneOrder).toEqual(['other', 'scene-1']);
    expect(readProject(doc)).toEqual(fullRead(doc));
    doc.destroy(); peer.destroy();
  });
});

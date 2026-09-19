import { expect, it } from 'vitest';
import * as Y from 'yjs';
import { makeDemoProject } from '../shared/demo';
import { initializeDocument, getShared } from '../shared/document';
import { duplicateComposition, deleteComposition } from '../src/editor/structure';
import { renameScene } from '../src/editor/scenes';

it('prepares the bridge parent before a Composition deletion can mutate shared data', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  const middle = duplicateComposition(doc, 'scene-1', 'comp-1');
  const compositions = getShared(doc, ['scenes', 'scene-1', 'compositions']) as Y.Map<unknown>;
  const next = compositions.get('comp-2') as Y.Map<unknown>;
  // Simulate an imported/remote plain record where the operation needs a shared parent.
  compositions.set('comp-2', next.toJSON());
  const before = doc.getMap('project').toJSON(), vector = Y.encodeStateVector(doc);
  expect(() => deleteComposition(doc, 'scene-1', middle)).toThrow('Composition');
  expect(doc.getMap('project').toJSON()).toEqual(before);
  expect(Y.encodeStateVector(doc)).toEqual(vector);
  doc.destroy();
});

it('keeps JavaScript-compatible UTF-16 name limits and Unicode whitespace handling', () => {
  const doc = new Y.Doc(); initializeDocument(doc, makeDemoProject());
  for (const name of ['  日本語の Scene  ', '\u3000名前\u3000', '\ufeff名前\ufeff', '😀'.repeat(150), '\u0085Name\u0085']) {
    renameScene(doc, 'scene-1', name);
    expect((getShared(doc, ['scenes', 'scene-1']) as Y.Map<unknown>).get('name')).toBe(name.trim().slice(0, 200));
  }
  doc.destroy();
});

import * as Y from 'yjs';
import * as moonbit from '../../../../_build/js/release/build/boundary/boundary.js';

export const renameScene = (doc: Y.Doc, sceneId: string, name: string): void => moonbit.renameScene(doc, sceneId, name, Y);
export const duplicateScene = (doc: Y.Doc, sceneId: string): string => moonbit.duplicateScene(doc, sceneId, Y);
export const deleteScene = (doc: Y.Doc, sceneId: string): { selectedId: string } => moonbit.deleteScene(doc, sceneId, Y);
export const moveScene = (doc: Y.Doc, sceneId: string, direction: -1 | 1): void => moonbit.moveScene(doc, sceneId, direction, Y);

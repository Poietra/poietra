import * as Y from 'yjs';
import * as moonbit from '../../../../_build/js/release/build/boundary/boundary.js';

export const duplicateComposition = (doc: Y.Doc, sceneId: string, compositionId: string): string => moonbit.duplicateComposition(doc, sceneId, compositionId, Y);
export const deleteComposition = (doc: Y.Doc, sceneId: string, compositionId: string): { selectedId: string; removedTransitionIds: string[] } => moonbit.deleteComposition(doc, sceneId, compositionId, Y);

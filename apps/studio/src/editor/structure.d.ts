import * as Y from 'yjs';
export declare const duplicateComposition: (doc: Y.Doc, sceneId: string, compositionId: string) => string;
export declare const deleteComposition: (doc: Y.Doc, sceneId: string, compositionId: string) => {
    selectedId: string;
    removedTransitionIds: string[];
};

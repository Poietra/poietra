import * as Y from 'yjs';
export declare const renameScene: (doc: Y.Doc, sceneId: string, name: string) => void;
export declare const duplicateScene: (doc: Y.Doc, sceneId: string) => string;
export declare const deleteScene: (doc: Y.Doc, sceneId: string) => {
    selectedId: string;
};
export declare const moveScene: (doc: Y.Doc, sceneId: string, direction: -1 | 1) => void;

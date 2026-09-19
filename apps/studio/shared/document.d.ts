import * as Y from 'yjs';
import type { Project } from './model';
export type Path = (string | number)[];
export type Change = {
    path: string[];
    value: unknown;
};
export declare const LOCAL_ORIGIN = "poietra-local";
export declare const toShared: (value: unknown) => unknown;
export declare const initializeDocument: (doc: Y.Doc, project: Project) => void;
export declare const ensureSceneAudioTracks: (doc: Y.Doc) => boolean;
export declare const ensureSceneAnimationTracks: (doc: Y.Doc) => boolean;
/** Immutable snapshot. Clone before editing outside the shared command API. */
export declare const readProject: (doc: Y.Doc) => Project | null;
export declare const getShared: (doc: Y.Doc, path: string[]) => unknown;
export declare const getValue: (doc: Y.Doc, path: string[]) => unknown;
export declare const applyChanges: (doc: Y.Doc, changes: Change[], origin?: unknown) => void;
export declare const changesFor: (base: string[], values: object) => Change[];

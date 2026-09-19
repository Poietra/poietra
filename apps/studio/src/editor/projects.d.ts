import * as Y from 'yjs';
import type { Project } from '../../shared/model';
export declare const createProjectMessages: (source: Y.Doc, project: Project) => {
    updateMessage: Uint8Array;
    syncMessage: Uint8Array;
};
export declare const createProjectRoom: (project: Project, signal?: AbortSignal) => Promise<URL>;

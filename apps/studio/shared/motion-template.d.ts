import type { Project, Scene } from './model';
/** Capture selected subtrees and required hidden ancestors as one portable Scene. */
export declare function captureMotion(scene: Scene, ids: string[], name: string): Project;

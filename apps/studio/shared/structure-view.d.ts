import type { Project, Scene } from './model';
/** Typed MoonBit projects retained CRDT tombstones without repair transactions. */
export declare const sceneStructureView: (scene: Scene) => Scene;
export declare const projectStructureView: (project: Project) => Project;

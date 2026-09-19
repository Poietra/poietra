import type { Project, Scene } from './model';
import { sceneStructureView as sceneView, projectStructureView as projectView } from '../../../_build/js/release/build/boundary/boundary.js';

/** Typed MoonBit projects retained CRDT tombstones without repair transactions. */
export const sceneStructureView: (scene: Scene) => Scene = sceneView;
export const projectStructureView: (project: Project) => Project = projectView;

import { compositionFrame as composition, transitionFrame as transition, evaluateScene as evaluate, preparePlayback, playbackFrame, playbackComposition, playbackTransition } from '../../../../_build/js/release/build/boundary/boundary.js';
import type { Composition, ObjectState, Scene, SceneObject, Transition } from '../../shared/model';
import type { MotionKernel } from './kernel';

export interface RenderObject { object: SceneObject; state: ObjectState; writeProgress: number; order: 'together' | 'sequential'; videoTimeMs?: number; videoFrame?: string }
export interface Frame { objects: RenderObject[]; background: string; width: number; height: number }

export function compositionFrame(scene: Scene, value: Composition, sceneTime?: number): Frame {
  return composition(scene, value, sceneTime);
}
export function transitionFrame(scene: Scene, value: Transition, time: number, kernel: MotionKernel, sceneTime?: number): Frame {
  return transition(scene, value, time, kernel, sceneTime);
}
export function evaluateScene(scene: Scene, time: number, kernel: MotionKernel): Frame {
  return evaluate(scene, time, kernel);
}

/** Owns a snapshot. Rebuild on document changes, reuse for every seek and frame. */
export function compileScene(scene: Scene, kernel: MotionKernel) {
  const program = preparePlayback(scene, kernel);
  return {
    evaluate: (time: number): Frame => playbackFrame(program, time),
    composition: (id: string, time?: number): Frame => playbackComposition(program, id, time),
    transition: (id: string, time: number, sceneTime?: number): Frame => playbackTransition(program, id, time, sceneTime),
  };
}

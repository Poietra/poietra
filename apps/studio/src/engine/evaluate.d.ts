import type { RenderObject, Frame } from "../../shared/scene-types";
export type { RenderObject, Frame } from "../../shared/scene-types";
import type { Composition, ObjectState, Scene, SceneObject, Transition } from '../../shared/model';
import type { MotionKernel } from './kernel';
export declare function compositionFrame(scene: Scene, value: Composition, sceneTime?: number): Frame;
export declare function transitionFrame(scene: Scene, value: Transition, time: number, kernel: MotionKernel, sceneTime?: number): Frame;
export declare function evaluateScene(scene: Scene, time: number, kernel: MotionKernel): Frame;
/** Owns a snapshot. Rebuild on document changes, reuse for every seek and frame. */
export declare function compileScene(scene: Scene, kernel: MotionKernel): {
    evaluate: (time: number) => Frame;
    composition: (id: string, time?: number) => Frame;
    transition: (id: string, time: number, sceneTime?: number) => Frame;
};

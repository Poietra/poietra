import type { AnimationTrack, Scene, SceneObject, Transition } from '../../shared/model';
export type AnimationPresence = 'enter' | 'exit' | 'both';
export interface VisibleAnimation {
    object: SceneObject;
    track: AnimationTrack;
    existing: boolean;
    presence: AnimationPresence;
}
export declare const visibleAnimation: (scene: Scene, transition: Transition, objectId: string) => VisibleAnimation | null;
export declare const visibleAnimations: (scene: Scene, transition: Transition) => VisibleAnimation[];

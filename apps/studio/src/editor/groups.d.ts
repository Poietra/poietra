import type { AnimationKind, AnimationTrack, Easing, Scene, SceneObject } from '../../shared/model';
import type { Change } from '../../shared/document';
import type { VisibleAnimation } from './animation-tracks';
export type AnimationTarget = VisibleAnimation;
export interface ExcludedTarget {
    object: SceneObject;
    reason: 'locked' | 'hidden';
}
export type GroupAnimationPatch = {
    type?: AnimationKind;
    start?: number;
    duration?: number;
    easing?: Easing;
    order?: AnimationTrack['order'];
};
export declare const groupMembers: (scene: Scene, groupId: string) => SceneObject[];
export declare const editableGroupMembers: (scene: Scene, selectedIds: string[]) => SceneObject[];
export declare const groupAnimationTargets: (scene: Scene, transitionId: string, selectedIds: string[]) => {
    targets: AnimationTarget[];
    excluded: ExcludedTarget[];
};
export declare const groupAnimationChanges: (scene: Scene, transitionId: string, selectedIds: string[], patch: GroupAnimationPatch) => Change[];
export declare function commonTrackValue<K extends keyof AnimationTrack>(targets: AnimationTarget[], property: K): AnimationTrack[K] | undefined;

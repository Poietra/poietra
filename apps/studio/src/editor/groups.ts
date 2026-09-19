import type { AnimationKind, AnimationTrack, Easing, Scene, SceneObject } from '../../shared/model';
import type { Change } from '../../shared/document';
import type { VisibleAnimation } from './animation-tracks';
import * as moonbit from '../../../../_build/js/release/build/boundary/boundary.js';

export type AnimationTarget = VisibleAnimation;
export interface ExcludedTarget { object: SceneObject; reason: 'locked' | 'hidden' }
export type GroupAnimationPatch = { type?: AnimationKind; start?: number; duration?: number; easing?: Easing; order?: AnimationTrack['order'] };
export const groupMembers: (scene: Scene, groupId: string) => SceneObject[] = moonbit.groupMembers;
export const editableGroupMembers: (scene: Scene, selectedIds: string[]) => SceneObject[] = moonbit.editableGroupMembers;
export const groupAnimationTargets: (scene: Scene, transitionId: string, selectedIds: string[]) => { targets: AnimationTarget[]; excluded: ExcludedTarget[] } = moonbit.groupAnimationTargets;
export const groupAnimationChanges: (scene: Scene, transitionId: string, selectedIds: string[], patch: GroupAnimationPatch) => Change[] = moonbit.groupAnimationChanges;
export function commonTrackValue<K extends keyof AnimationTrack>(targets: AnimationTarget[], property: K): AnimationTrack[K] | undefined { return moonbit.commonTrackValue(targets, property); }

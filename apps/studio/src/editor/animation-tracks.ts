import type { AnimationTrack, Scene, SceneObject, Transition } from '../../shared/model';
import * as moonbit from '../../../../_build/js/release/build/boundary/boundary.js';

export type AnimationPresence = 'enter' | 'exit' | 'both';
export interface VisibleAnimation { object: SceneObject; track: AnimationTrack; existing: boolean; presence: AnimationPresence }
export const visibleAnimation: (scene: Scene, transition: Transition, objectId: string) => VisibleAnimation | null = moonbit.visibleAnimation;
export const visibleAnimations: (scene: Scene, transition: Transition) => VisibleAnimation[] = moonbit.visibleAnimations;

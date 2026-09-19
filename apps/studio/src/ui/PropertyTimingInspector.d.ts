import type { ComponentType } from 'react';
import type { AnimationTrack, SceneObject, Transition } from '../../shared/model';
import './PropertyAnimation.css';
export declare const PropertyTimingInspector: ComponentType<{
    object: SceneObject;
    transition: Transition;
    track: AnimationTrack;
}>;

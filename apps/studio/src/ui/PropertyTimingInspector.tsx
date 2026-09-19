import type { ComponentType } from 'react';
import type { AnimationTrack, SceneObject, Transition } from '../../shared/model';
import { PropertyTimingInspector as MoonPropertyTimingInspector } from '../../../../_build/js/release/build/ui/ui.js';
import './PropertyAnimation.css';

export const PropertyTimingInspector: ComponentType<{ object: SceneObject; transition: Transition; track: AnimationTrack }> = MoonPropertyTimingInspector;

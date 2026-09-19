import type { ComponentType } from 'react';
import type { Frame } from '../engine/evaluate';
import { Stage as MoonStage } from '../../../../_build/js/release/build/ui/ui.js';
import './Stage.css';
import './OperationFeedback.css';

export const Stage: ComponentType<{ frame: Frame; compositionId: string; interactive?: boolean; stateEditing?: boolean; prefix?: string; zoom?: number }> = MoonStage;

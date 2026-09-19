import type { ComponentType } from 'react';
import type { Frame } from '../engine/evaluate';
import './Stage.css';
import './OperationFeedback.css';
export declare const Stage: ComponentType<{
    frame: Frame;
    compositionId: string;
    interactive?: boolean;
    stateEditing?: boolean;
    prefix?: string;
    zoom?: number;
}>;

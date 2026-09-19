import type { ReactElement } from 'react';
import type { Scene, Segment } from '../../shared/model';
export declare const PlaybackPanel: (props: {
    scene: Scene;
    segment: Segment | undefined;
    playhead: number;
    onEdit: () => void;
}) => ReactElement;

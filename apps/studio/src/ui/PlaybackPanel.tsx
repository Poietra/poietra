import type { ReactElement } from 'react';
import type { Scene, Segment } from '../../shared/model';
import { PlaybackPanel as MoonPlaybackPanel } from '../../../../_build/js/release/build/ui/ui.js';
export const PlaybackPanel = MoonPlaybackPanel as (props: { scene: Scene; segment: Segment | undefined; playhead: number; onEdit: () => void }) => ReactElement;

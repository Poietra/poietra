import type { ComponentType, ReactNode } from 'react';
import { Timeline as MoonTimeline } from '../../../../_build/js/release/build/ui/ui.js';
import './TimelineSeek.css';
import './TimelineFeedback.css';
import './PropertyAnimation.css';

export const Timeline: ComponentType<{ zoom: number; setZoom: (value: number) => void; children?: ReactNode }> = MoonTimeline;

import type { ComponentType, ReactNode } from 'react';
import './TimelineSeek.css';
import './TimelineFeedback.css';
import './PropertyAnimation.css';
export declare const Timeline: ComponentType<{
    zoom: number;
    setZoom: (value: number) => void;
    children?: ReactNode;
}>;

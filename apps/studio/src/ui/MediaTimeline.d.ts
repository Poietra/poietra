import type { ComponentType } from 'react';
import './MediaTimeline.css';
export declare const MediaTimeline: ComponentType<{
    onAdd: (kind: 'audio' | 'video') => void;
    disabled?: boolean;
}>;

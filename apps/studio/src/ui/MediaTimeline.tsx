import type { ComponentType } from 'react';
import { MediaTimeline as MoonMediaTimeline } from '../../../../_build/js/release/build/ui/ui.js';
import './MediaTimeline.css';

export const MediaTimeline: ComponentType<{ onAdd: (kind: 'audio' | 'video') => void; disabled?: boolean }> = MoonMediaTimeline;

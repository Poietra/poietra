import type { ComponentType } from 'react';
import './AssistantPanel.css';
export declare const AssistantPanel: ComponentType<{
    isActive: boolean;
    onOpenScene: (sceneId: string) => void;
    onEditMoment: () => void;
}>;

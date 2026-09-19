import type { ComponentType } from 'react';
import { AssistantPanel as MoonAssistantPanel } from '../../../../_build/js/release/build/ui/ui.js';
import './AssistantPanel.css';
export const AssistantPanel: ComponentType<{ isActive: boolean; onOpenScene: (sceneId: string) => void; onEditMoment: () => void }> = MoonAssistantPanel;

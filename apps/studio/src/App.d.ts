import { type ComponentType } from 'react';
import type { EditorStore } from './editor/store';
import type { MotionKernel } from './engine/kernel';
import type { ExporterContract, RendererContract } from './engine/render-contract';
import type { PainterContract } from './engine/painter-contract';
import './ui/AssistantPanel.css';
import './ui/ConnectionStatus.css';
import './ui/EasingEditor.css';
import './ui/export-dialog.css';
import './ui/groups.css';
import './ui/MediaTimeline.css';
import './ui/OperationFeedback.css';
import './ui/ProjectDialog.css';
import './ui/ProjectPreview.css';
import './ui/PropertyAnimation.css';
import './ui/SceneTabs.css';
import './ui/Stage.css';
import './ui/TexInput.css';
import './ui/TimelineFeedback.css';
import './ui/TimelineSeek.css';
interface Props {
    store: EditorStore;
    kernel: MotionKernel;
    renderer: RendererContract;
    exporter: ExporterContract | null;
    createFramePainter?: PainterContract['createFramePainter'];
}
export declare const App: ComponentType<Props>;
export {};

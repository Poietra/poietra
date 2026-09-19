import { createElement, type ComponentType } from 'react';
import type { EditorStore } from './editor/store';
import type { MotionKernel } from './engine/kernel';
import type { ExporterContract, RendererContract } from './engine/render-contract';
import type { PainterContract } from './engine/painter-contract';
import { portableProject, rehostImageAssets } from './editor/images';
import { createProjectRoom } from './editor/projects';
import { App as MoonApp } from '../../../_build/js/release/build/ui/ui.js';
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
const services = { portableProject, rehostImageAssets, createProjectRoom };
export const App: ComponentType<Props> = props => createElement(MoonApp, { ...props, services });

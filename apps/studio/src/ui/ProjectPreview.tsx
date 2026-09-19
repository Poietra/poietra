import type { ComponentType } from 'react';
import type { Project, Selection } from '../../shared/model';
import type { MotionKernel } from '../engine/kernel';
import type { RendererContract } from '../engine/render-contract';
import type { PainterContract } from '../engine/painter-contract';
import { ProjectPreview as MoonProjectPreview } from '../../../../_build/js/release/build/ui/ui.js';
import './ProjectPreview.css';

interface Props {
  open: boolean; onOpenChange: (open: boolean) => void; project: Project;
  renderer: RendererContract; kernel: MotionKernel; createFramePainter?: PainterContract['createFramePainter'];
  onEdit: (sceneId: string, selection: Selection) => void;
}
export const ProjectPreview: ComponentType<Props> = MoonProjectPreview;

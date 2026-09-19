import type { ComponentType } from 'react';
import type { Project, Scene } from '../../shared/model';
import type { MotionKernel } from '../engine/kernel';
import type { ExporterContract } from '../engine/render-contract';
import { ExportDialog as MoonExportDialog } from '../../../../_build/js/release/build/ui/ui.js';
import './export-dialog.css';

export interface ExportDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  exporter: ExporterContract;
  scene: Scene;
  project?: Project;
  kernel: MotionKernel;
  name: string;
}
export const ExportDialog: ComponentType<ExportDialogProps> = MoonExportDialog;

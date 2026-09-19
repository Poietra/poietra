import type { ComponentType } from 'react';
import type { Project, Scene } from '../../shared/model';
import type { MotionKernel } from '../engine/kernel';
import type { ExporterContract } from '../engine/render-contract';
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
export declare const ExportDialog: ComponentType<ExportDialogProps>;

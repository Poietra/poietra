import { type ComponentType } from 'react';
import type { Project } from '../../shared/model';
import './ProjectDialog.css';
interface ProjectDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    project: Project;
    roomId: string;
    synced: boolean;
}
export declare const ProjectDialog: ComponentType<ProjectDialogProps>;
export {};

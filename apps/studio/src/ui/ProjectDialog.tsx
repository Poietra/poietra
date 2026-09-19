import { createElement, type ComponentType } from 'react';
import type { Project } from '../../shared/model';
import { portableProject } from '../editor/images';
import { createProjectRoom } from '../editor/projects';
import { ProjectDialog as MoonProjectDialog } from '../../../../_build/js/release/build/ui/ui.js';
import './ProjectDialog.css';

interface ProjectDialogProps { open: boolean; onOpenChange: (open: boolean) => void; project: Project; roomId: string; synced: boolean }
const services = { portableProject, createProjectRoom };
export const ProjectDialog: ComponentType<ProjectDialogProps> = props => createElement(MoonProjectDialog, { ...props, services });

import type { Project, Scene } from './model';
import * as moonbit from '../../../_build/js/release/build/boundary/boundary.js';

export interface ProjectSegment { scene: Scene; start: number; duration: number }
export const projectSegments: (project: Project) => ProjectSegment[] = moonbit.projectSegments;
export const projectDuration: (project: Project) => number = moonbit.projectDuration;
export const projectSegmentAt: (segments: ProjectSegment[], time: number) => ProjectSegment | undefined = moonbit.projectSegmentAt;

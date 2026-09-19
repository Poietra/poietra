import type { Project, Scene } from './model';
export interface ProjectSegment {
    scene: Scene;
    start: number;
    duration: number;
}
export declare const projectSegments: (project: Project) => ProjectSegment[];
export declare const projectDuration: (project: Project) => number;
export declare const projectSegmentAt: (segments: ProjectSegment[], time: number) => ProjectSegment | undefined;

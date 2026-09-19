import type { Project, Scene } from '../../shared/model';
import type { MotionKernel } from './kernel';
import type { ExportOptions, ExportResult } from './render-contract';
export { getExportCapabilities } from './exporting/codecs';
export declare function exportScene(scene: Scene, kernel: MotionKernel, options: ExportOptions): Promise<ExportResult>;
export declare function exportProject(project: Project, kernel: MotionKernel, options: ExportOptions): Promise<ExportResult>;

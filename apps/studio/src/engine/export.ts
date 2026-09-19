import type { Project, Scene } from '../../shared/model';
import type { MotionKernel } from './kernel';
import type { ExportOptions, ExportResult } from './render-contract';
import { createFramePainter } from './painter';
import { prepareScene } from './renderer';
import * as moonbit from '../../../../_build/js/release/build/browser_export/browser_export.js';

export { getExportCapabilities } from './exporting/codecs';
const host = { createFramePainter, prepareScene };
export function exportScene(scene: Scene, kernel: MotionKernel, options: ExportOptions): Promise<ExportResult> {
  return moonbit.exportScene(scene, kernel, options, host);
}
export function exportProject(project: Project, kernel: MotionKernel, options: ExportOptions): Promise<ExportResult> {
  return moonbit.exportProject(project, kernel, options, host);
}

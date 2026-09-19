import type { ExportCapabilities } from '../render-contract';
import * as moonbit from '../../../../../_build/js/release/build/browser_export/browser_export.js';
export const environmentReason: () => string | undefined = moonbit.environmentReason;
export const bitrateFor: (width: number, height: number, fps: number) => number = moonbit.bitrateFor;
export const getExportCapabilities: () => Promise<ExportCapabilities> = moonbit.getExportCapabilities;
export const findExportCodec: (format: 'mp4' | 'webm', width: number, height: number, bitrate: number, signal?: AbortSignal) => Promise<'avc' | 'vp9' | 'vp8' | undefined> = moonbit.findExportCodec;

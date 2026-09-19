import type { ExportCapabilities } from '../render-contract';
export declare const environmentReason: () => string | undefined;
export declare const bitrateFor: (width: number, height: number, fps: number) => number;
export declare const getExportCapabilities: () => Promise<ExportCapabilities>;
export declare const findExportCodec: (format: 'mp4' | 'webm', width: number, height: number, bitrate: number, signal?: AbortSignal) => Promise<'avc' | 'vp9' | 'vp8' | undefined>;

export type RenderFormat = 'svg' | 'png' | 'mp4';
export interface RenderOptions {
  format?: RenderFormat;
  width?: number;
  height?: number;
  fps?: 24 | 30 | 60;
  timeMs?: number;
  signal?: AbortSignal;
  onProgress?: (fraction: number) => void;
  timeoutMs?: number;
}
export interface RenderResult {
  bytes: Uint8Array;
  format: RenderFormat;
  mimeType: 'image/svg+xml' | 'image/png' | 'video/mp4';
  width: number;
  height: number;
  durationMs: number;
  frames: number;
  rasterizedFrames: number;
  audioCodec: 'mp3' | null;
  elapsedMs: number;
  /** Process high-water RSS; includes parent and thread memory, not an isolated Worker heap. */
  peakRssBytes: number;
}
export interface Capabilities {
  formats: RenderFormat[];
  videoCodec: 'avc';
  audioCodec: 'mp3';
  imageInputs: string[];
  audioInputs: string[];
  videoInputs: false;
  maxInputBytes: number;
  maxPixels: number;
  maxVideoDurationMs: number;
  maxVideoFrames: number;
  externalAssets: false;
}
export function capabilities(): Capabilities;
export function inspectProjectFile(text: string): {
  name: string; scenes: number; durationMs: number; width: number; height: number;
  audibleTracks: number; issues: string[]; capabilities: Capabilities;
};
export function renderProjectFile(text: string, options?: RenderOptions): Promise<RenderResult>;

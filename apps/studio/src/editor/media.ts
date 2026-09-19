import type { MediaAsset } from '../../shared/media';
import * as moon from '../../../../_build/js/release/build/browser_media/browser_media.js';

export type ImportProgress = { phase: 'reading' | 'waveform' | 'uploading' | 'saving'; progress: number };
export const prepareMedia: (file: File, signal: AbortSignal, progress?: (value: ImportProgress) => void) => Promise<{ asset: Omit<MediaAsset, 'src'>; blob: Blob; kind: 'audio' | 'video' }> = moon.prepareMedia;
export const uploadMedia: (room: string, blob: Blob, signal?: AbortSignal, progress?: (value: ImportProgress) => void) => Promise<string> = moon.uploadMedia;
export const mediaBlob: (src: string, signal?: AbortSignal) => Promise<Blob> = moon.mediaBlob;

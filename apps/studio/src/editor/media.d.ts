import type { MediaAsset } from '../../shared/media';
export type ImportProgress = {
    phase: 'reading' | 'waveform' | 'uploading' | 'saving';
    progress: number;
};
export declare const prepareMedia: (file: File, signal: AbortSignal, progress?: (value: ImportProgress) => void) => Promise<{
    asset: Omit<MediaAsset, 'src'>;
    blob: Blob;
    kind: 'audio' | 'video';
}>;
export declare const uploadMedia: (room: string, blob: Blob, signal?: AbortSignal, progress?: (value: ImportProgress) => void) => Promise<string>;
export declare const mediaBlob: (src: string, signal?: AbortSignal) => Promise<Blob>;

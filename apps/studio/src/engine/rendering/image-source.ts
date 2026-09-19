import * as moonbit from '../../../../../_build/js/release/build/browser_media/browser_media.js';
export const imageBlob: (src: string, signal?: AbortSignal) => Promise<Blob> = moonbit.imageBlob;
export const blobDataUrl: (blob: Blob) => Promise<string> = moonbit.blobDataUrl;

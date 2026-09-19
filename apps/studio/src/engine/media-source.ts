import type { Input } from 'mediabunny';
import { openMedia as moonOpenMedia } from '../../../../_build/js/release/build/browser_media/browser_media.js';
export const openMedia: (src: string, signal: AbortSignal) => Promise<Input> = moonOpenMedia;

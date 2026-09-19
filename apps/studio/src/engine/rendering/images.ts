import type { Scene } from '../../../shared/model';
import * as moonbit from '../../../../../_build/js/release/build/browser_media/browser_media.js';
export const preparedImage: (src: string | undefined) => string | null = moonbit.preparedImage;
export const prepareImages: (scene: Scene) => Promise<void> = moonbit.prepareImages;

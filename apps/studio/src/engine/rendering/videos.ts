import type { Frame } from '../evaluate';
import * as moonbit from '../../../../../_build/js/release/build/browser_media/browser_media.js';
export class VideoFrames {
  private readonly core = moonbit.createVideoFrames();
  prepare(frame: Frame, signal?: AbortSignal): Promise<void> { return this.core.prepare(frame, signal); }
  dispose(): void { this.core.dispose(); }
}
export const prepareVideoFrame: (frame: Frame, signal?: AbortSignal) => Promise<void> = moonbit.prepareVideoFrame;

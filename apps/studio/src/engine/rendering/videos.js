import * as moonbit from "../../../../../_build/js/release/build/browser_media/browser_media.js";
export class VideoFrames {
    core = moonbit.createVideoFrames();
    prepare(frame, signal) { return this.core.prepare(frame, signal); }
    dispose() { this.core.dispose(); }
}
export const prepareVideoFrame = moonbit.prepareVideoFrame;

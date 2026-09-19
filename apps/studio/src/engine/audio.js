import * as moonbit from "../../../../_build/js/release/build/browser_media/browser_media.js";
export const AUDIO_SAMPLE_RATE = 48000;
export const audibleTracks = moonbit.audibleTracks;
export class AudioMixer {
    core;
    constructor(tracks, signal) { this.core = moonbit.createAudioMixer(tracks, signal); }
    prepare() { return this.core.prepare(); }
    mix(start, frames) { return this.core.mix(start, frames); }
    dispose() { this.core.dispose(); }
}

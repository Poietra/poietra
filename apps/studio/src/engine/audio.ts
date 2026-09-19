import type { AudioTrack } from '../../shared/media';
import * as moonbit from '../../../../_build/js/release/build/browser_media/browser_media.js';
export const AUDIO_SAMPLE_RATE = 48000;
export const audibleTracks: (tracks: Record<string, AudioTrack> | undefined) => AudioTrack[] = moonbit.audibleTracks;
export class AudioMixer {
  private readonly core;
  constructor(tracks: AudioTrack[], signal?: AbortSignal) { this.core = moonbit.createAudioMixer(tracks, signal); }
  prepare(): Promise<void> { return this.core.prepare(); }
  mix(start: number, frames: number): Promise<AudioBuffer> { return this.core.mix(start, frames); }
  dispose(): void { this.core.dispose(); }
}

import type { AudioTrack } from '../../shared/media';
export declare const AUDIO_SAMPLE_RATE = 48000;
export declare const audibleTracks: (tracks: Record<string, AudioTrack> | undefined) => AudioTrack[];
export declare class AudioMixer {
    private readonly core;
    constructor(tracks: AudioTrack[], signal?: AbortSignal);
    prepare(): Promise<void>;
    mix(start: number, frames: number): Promise<AudioBuffer>;
    dispose(): void;
}

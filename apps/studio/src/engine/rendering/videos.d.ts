import type { Frame } from '../evaluate';
export declare class VideoFrames {
    private readonly core;
    prepare(frame: Frame, signal?: AbortSignal): Promise<void>;
    dispose(): void;
}
export declare const prepareVideoFrame: (frame: Frame, signal?: AbortSignal) => Promise<void>;

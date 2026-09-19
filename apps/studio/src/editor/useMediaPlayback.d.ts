import type { Scene } from '../../shared/model';
export declare const useMediaPlayback: (scene: Scene | null, time: number, playing: boolean, onError?: (error: Error) => void) => {
    cancel(): void;
    unlock(): Promise<void>;
};

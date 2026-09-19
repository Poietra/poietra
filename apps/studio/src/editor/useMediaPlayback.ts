import type { Scene } from '../../shared/model';
import { useMediaPlayback as moonUseMediaPlayback } from '../../../../_build/js/release/build/ui/ui.js';
export const useMediaPlayback: (scene: Scene | null, time: number, playing: boolean, onError?: (error: Error) => void) => {
  cancel(): void; unlock(): Promise<void>;
} = moonUseMediaPlayback;

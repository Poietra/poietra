import type { Easing } from '../../shared/easing';
export interface MotionKernel {
    ease(value: number, kind: number): number;
    track_progress(time: number, start: number, duration: number, easing: number): number;
    interpolate(from: number, to: number, progress: number): number;
    cubic_bezier(p0: number, p1: number, p2: number, p3: number, progress: number): number;
    cubic_bezier_ease(value: number, x1: number, y1: number, x2: number, y2: number): number;
}
export declare const trackProgress: (kernel: MotionKernel, time: number, start: number, duration: number, easing: Easing) => number;
export declare const loadKernel: () => Promise<MotionKernel>;

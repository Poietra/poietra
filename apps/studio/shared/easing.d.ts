import type { PresetEasing, CubicBezierEasing, Easing } from "./scene-types";
export type { PresetEasing, CubicBezierEasing, Easing } from "./scene-types";
/** Unit-square control points for a time (x) → progress (y) curve. */
export declare const DEFAULT_CUSTOM_EASING: CubicBezierEasing;
export declare function isValidEasing(value: unknown): value is Easing;
export declare const easingsEqual: (a: Easing | null | undefined, b: Easing | null | undefined) => boolean;

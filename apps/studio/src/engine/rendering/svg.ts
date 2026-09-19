import * as moonbit from '../../../../../_build/js/release/build/boundary/boundary.js';
export const color: (value: string, fallback?: string) => string = moonbit.svgColor;
export const escapeXml: (value: string) => string = moonbit.svgEscape;
export const finite: (value: number, fallback?: number) => number = moonbit.svgFinite;
export const unit: (value: number) => number = moonbit.svgUnit;
export const number: (value: number) => string = moonbit.svgNumber;
export const safeId: (value: string) => string = moonbit.svgId;

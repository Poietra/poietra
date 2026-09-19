import * as moonbit from '../../../../../_build/js/release/build/browser_export/browser_export.js';
export const exportAbortError: () => DOMException = moonbit.exportAbortError;
export const checkAbort: (signal?: AbortSignal) => void = moonbit.checkAbort;
export const abortable: <T>(promise: Promise<T>, signal?: AbortSignal) => Promise<T> = moonbit.abortable;

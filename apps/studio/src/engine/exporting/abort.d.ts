export declare const exportAbortError: () => DOMException;
export declare const checkAbort: (signal?: AbortSignal) => void;
export declare const abortable: <T>(promise: Promise<T>, signal?: AbortSignal) => Promise<T>;

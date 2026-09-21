import { Worker } from 'node:worker_threads';
export { capabilities, inspectProjectFile } from '../../_build/js/release/build/headless_render/headless_render.js';

// Each request owns a fresh WASM instance. A timeout, disconnect or AbortSignal
// terminates the thread, including synchronous raster/codec work and its caches.
export function renderProjectFile(text, { signal, onProgress, timeoutMs = 120000, ...options } = {}) {
  if (signal?.aborted) return Promise.reject(signal.reason ?? new DOMException('Rendering cancelled.', 'AbortError'));
  if (typeof text !== 'string') return Promise.reject(new TypeError('Pass portable project JSON as a string.'));
  if (Buffer.byteLength(text) > 32 * 1024 * 1024) return Promise.reject(new RangeError('Project files must be 32 MiB or smaller.'));
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 300000) return Promise.reject(new RangeError('timeoutMs must be between 1 and 300000.'));
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./worker.mjs', import.meta.url), {
      workerData: { text, options },
      // The test runner expands process.execArgv with process-only V8 flags.
      // Forward loaders/preloads, never those flags or --input-type/--test.
      execArgv: process.execArgv.flatMap((arg, index, args) =>
        ['--import', '--require', '-r'].includes(arg) ? [arg, args[index + 1]]
          : /^(--import|--require)=/.test(arg) ? [arg] : []),
      resourceLimits: { maxOldGenerationSizeMb: 512 },
    });
    let settled = false;
    const finish = async (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      await worker.terminate();
      if (error) reject(error); else resolve(result);
    };
    const abort = () => void finish(signal.reason ?? new DOMException('Rendering cancelled.', 'AbortError'));
    const timer = setTimeout(() => void finish(new DOMException('Rendering exceeded its time limit.', 'TimeoutError')), timeoutMs);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    worker.on('message', message => {
      if (settled) return;
      if ('progress' in message) {
        try { onProgress?.(message.progress); } catch (error) { void finish(error); }
      } else if (message.error) {
        const error = new Error(message.error.message); error.name = message.error.name;
        void finish(error);
      } else if (message.result) {
        if (message.result.bytes.byteLength > 64 * 1024 * 1024) void finish(new RangeError('Output exceeds 64 MiB.'));
        else void finish(null, message.result);
      }
    });
    worker.on('error', error => void finish(error));
    worker.on('exit', code => { if (!settled) void finish(new Error(`Render worker exited before returning a result (${code}).`)); });
  });
}

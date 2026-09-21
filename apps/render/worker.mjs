import { parentPort, workerData } from 'node:worker_threads';
import { renderProjectFile } from '../../_build/js/release/build/headless_render/headless_render.js';
import { createHost } from './runtime-host.mjs';

let host;
try {
  host = await createHost({ ...workerData.options, onProgress: value => parentPort.postMessage({ progress: value }) });
  const started = performance.now();
  const result = await renderProjectFile(workerData.text, workerData.options, host);
  result.elapsedMs = performance.now() - started;
  result.peakRssBytes = process.resourceUsage().maxRSS * 1024;
  parentPort.postMessage({ result }, [result.bytes.buffer]);
} catch (error) {
  parentPort.postMessage({ error: { name: error.name ?? 'Error', message: error.message ?? String(error) } });
} finally {
  host?.dispose();
  parentPort.close();
}

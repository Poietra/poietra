import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
for (const name of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
  childProcess[name] = () => { throw new Error(`Subprocess execution is forbidden: ${name}`); };
}
syncBuiltinESMExports();
globalThis.fetch = input => {
  // Emscripten may ask fetch to decode its inline WASM data URI. Decode it
  // locally; every URL that could perform network I/O remains forbidden.
  if (typeof input === 'string' && input.startsWith('data:application/octet-stream;base64,')) {
    return Promise.resolve(new Response(Buffer.from(input.slice(input.indexOf(',') + 1), 'base64')));
  }
  throw new Error('Network fetch is forbidden in headless rendering.');
};
for (const name of ['window', 'document', 'VideoEncoder', 'AudioEncoder', 'VideoFrame', 'AudioData']) {
  if (globalThis[name] !== undefined) throw new Error(`Unexpected browser API: ${name}`);
}

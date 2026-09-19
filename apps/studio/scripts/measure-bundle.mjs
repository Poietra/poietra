// Static sizes, not transfer measurements. Build first.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { gzipSync, brotliCompressSync } from 'node:zlib';
import { dirname, resolve } from 'node:path';
import { environment } from './benchmark-environment.mjs';

const output = resolve(process.env.POIETRA_PERF_OUTPUT || 'test-results/bundle-performance.json');
const manifest = JSON.parse(await readFile(new URL('../dist/.vite/manifest.json', import.meta.url), 'utf8'));
const files = [];
for (const file of [...new Set(Object.values(manifest).map(entry => entry.file).filter(file => file.endsWith('.js'))), 'wasm/poietra_core.wasm']) {
  const bytes = await readFile(new URL(`../dist/${file}`, import.meta.url));
  files.push({ file, rawBytes: bytes.length, gzipBytes: gzipSync(bytes, { level: 9 }).length, brotliBytes: brotliCompressSync(bytes).length });
}
function closure(keys) {
  const seen = new Set();
  function visit(key) {
    if (seen.has(key)) return;
    if (!manifest[key]) throw new Error(`Missing manifest entry ${key}`);
    seen.add(key); for (const dependency of manifest[key].imports || []) visit(dependency);
  }
  keys.forEach(visit);
  const selected = files.filter(file => [...seen].some(key => manifest[key].file === file.file));
  return { files: selected.map(file => file.file), ...Object.fromEntries(['rawBytes', 'gzipBytes', 'brotliBytes'].map(key => [key, selected.reduce((sum, file) => sum + file[key], 0)])) };
}
const result = {
  measuredAt: new Date().toISOString(), environment: environment(),
  method: 'Vite production output. JS groups include static imports, exclude dynamic imports/CSS/fonts/media. Home includes its dynamically selected entry. Compression computed per file: gzip level 9, Brotli Node defaults; server may serve identity.',
  groups: { homeJavascript: closure(['index.html', 'src/home.js']), editorStaticJavascript: closure(['src/editor/bootstrap.js']) },
  files: files.sort((a, b) => b.rawBytes - a.rawBytes),
};
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result.groups, null, 2));

// Native build I/O and Vite SSR loading; page policy and assembly live in MoonBit.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { createServer } from 'vite';
import { renderFiles } from '../../../_build/js/release/build/site_build/site_build.js';

const vite = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
try {
  const { renderHome, renderMarkdown } = await vite.ssrLoadModule('/src/prerender.js');
  const shell = await readFile('dist/index.html', 'utf8');
  const manifest = JSON.parse(await readFile('dist/.vite/manifest.json', 'utf8'));
  for (const file of renderFiles(shell, manifest, renderHome, renderMarkdown)) {
    const target = join('dist', file.path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, file.content);
  }
  console.log('Prerendered English/Japanese home and developer pages, Markdown, OpenAPI, project schema, example, and editor shell.');
} finally { await vite.close(); }

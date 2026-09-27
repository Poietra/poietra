import { readdir } from 'node:fs/promises';
import { suites } from '../apps/studio/tests/e2e/suites.ts';

const root = new URL('../apps/studio/tests/e2e/', import.meta.url);
async function specs(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true });
  const found = [];
  for (const entry of entries) {
    const name = prefix + entry.name;
    if (entry.isDirectory()) found.push(...await specs(new URL(`${entry.name}/`, directory), `${name}/`));
    else if (name.endsWith('.spec.ts')) found.push(name);
  }
  return found;
}
const actual = new Set(await specs(root));
const registered = new Set();
const errors = [];
for (const [suite, files] of Object.entries(suites)) {
  for (const file of files) {
    if (registered.has(file)) errors.push(`Duplicate browser spec: ${file} (${suite})`);
    if (!actual.has(file)) errors.push(`Missing browser spec: ${file} (${suite})`);
    registered.add(file);
  }
}
for (const file of actual) {
  if (!registered.has(file)) errors.push(`Unclassified browser spec: ${file}; add it to tests/e2e/suites.ts`);
}
if (errors.length) throw new Error(errors.join('\n'));
console.log(`Browser suites: ${actual.size} specs classified in ${Object.keys(suites).length} suites.`);

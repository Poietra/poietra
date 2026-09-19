// Count source by purpose, rather than treating repository bytes as runtime dependencies.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const root = fileURLToPath(new URL('../', import.meta.url));
const { values } = parseArgs({ options: { json: { type: 'boolean' }, check: { type: 'boolean' } } });
const categories = [
  'MoonBit application', 'MoonBit tests', 'JavaScript runtime adapters',
  'JavaScript tooling/tests', 'TypeScript runtime', 'TypeScript declarations',
  'TypeScript tests', 'TypeScript tooling',
];
const totals = new Map(categories.map(category => [category, { category, files: 0, lines: 0, bytes: 0 }]));
const runtimeTypeScript = [];
const files = new Set(execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], {
  cwd: root, encoding: 'utf8',
}).split('\0').filter(Boolean));
for (const name of [...files].sort()) {
  const path = join(root, name);
  if (!existsSync(path)) continue;
  const runtime = /^apps\/studio\/(src|shared|server|worker)\//.test(name);
  let category;
  if (name.endsWith('.mbt')) category = /_(wb)?test\.mbt$/.test(name) ? 'MoonBit tests' : 'MoonBit application';
  else if (/\.d\.[cm]?ts$/.test(name)) category = 'TypeScript declarations';
  else if (/\.[cm]?tsx?$/.test(name)) {
    if (runtime) { category = 'TypeScript runtime'; runtimeTypeScript.push(name); }
    else if (name.includes('/tests/') || /\.(test|spec)\./.test(name)) category = 'TypeScript tests';
    else category = 'TypeScript tooling';
  } else if (/\.[cm]?jsx?$/.test(name)) category = runtime ? 'JavaScript runtime adapters' : 'JavaScript tooling/tests';
  else continue;
  const bytes = readFileSync(path);
  const count = totals.get(category);
  count.files++;
  count.bytes += bytes.length;
  count.lines += bytes.reduce((lines, byte) => lines + Number(byte === 10), 0)
    + Number(bytes.length > 0 && bytes.at(-1) !== 10);
}
const report = {
  basis: 'Tracked and unignored working-tree source; raw bytes include declarations and tests. This is not GitHub Linguist classification.',
  totals: [...totals.values()], runtimeTypeScript,
};
if (values.json) console.log(JSON.stringify(report, null, 2));
else { console.log(report.basis); console.table(report.totals); }
if (values.check && runtimeTypeScript.length) {
  console.error(`Executable TypeScript belongs outside src/shared/server/worker:\n${runtimeTypeScript.join('\n')}`);
  process.exitCode = 1;
}

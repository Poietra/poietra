// Compile both directions against the captured public API. No runtime imports,
// browser globals or native Cloudflare objects are evaluated by this check.
import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const app = resolve(root, 'apps/studio');
const directory = resolve(app, '.contracts');
const snapshot = JSON.parse(readFileSync(new URL('./contracts/6220679.json', import.meta.url), 'utf8'));
const files = Object.keys(snapshot.modules);
mkdirSync(directory, { recursive: true });
const checks = [];
try {
  for (const [index, name] of files.entries()) {
    const declaration = name.replace(/\.js$/, '.d.ts');
    const current = readFileSync(resolve(app, declaration), 'utf8');
    for (const [version, source] of [['previous', snapshot.modules[name]], ['current', current]]) {
      const target = resolve(directory, version, declaration);
      mkdirSync(dirname(target), { recursive: true });
      const normalized = source
        // Private host storage is not part of a consumer's structural API.
        .replace(/^\s*(?:private .*|#private);\s*$/gm, '')
        .replace(/(['"])(\.[^'"\n]+)\1/g, (match, quote, specifier) => {
          const original = resolve(app, dirname(name), specifier);
          const local = relative(app, original).replace(/\.(?:js|ts|tsx)$/, '') + '.js';
          const resolved = Object.hasOwn(snapshot.modules, local)
            ? resolve(directory, version, local.replace(/\.js$/, '')) : original;
          return quote + resolved + quote;
        });
      writeFileSync(target, normalized);
    }
    const oldModule = JSON.stringify('./previous/' + name);
    const newModule = JSON.stringify('./current/' + name);
    checks.push(`declare let old${index}: typeof import(${oldModule});`,
      `declare let next${index}: typeof import(${newModule});`,
      `old${index} = next${index};`,
      `const compatible${index}: Pick<typeof next${index}, keyof typeof old${index}> = old${index};`);
    for (const match of snapshot.modules[name].matchAll(/export (?:declare )?(?:interface|type) (\w+)(?![\w<])/g)) {
      const type = match[1];
      checks.push(`declare let old${index}_${type}: import(${oldModule}).${type};`,
        `declare let next${index}_${type}: import(${newModule}).${type};`,
        `old${index}_${type} = next${index}_${type}; next${index}_${type} = old${index}_${type};`);
    }
  }
  writeFileSync(resolve(directory, 'check.ts'), checks.join('\n'));
  writeFileSync(resolve(directory, 'tsconfig.json'), JSON.stringify({
    compilerOptions: { target: 'ES2023', module: 'ESNext', moduleResolution: 'Bundler',
      strict: true, skipLibCheck: true, noEmit: true, lib: ['ES2023', 'DOM', 'DOM.Iterable'],
      types: ['node', '../.wrangler/worker-configuration.d.ts', 'vite/client'] },
    files: ['check.ts', '../worker/auth-secrets.d.ts'],
  }));
  execFileSync('pnpm', ['exec', 'tsc', '-p', resolve(directory, 'tsconfig.json')], { cwd: app, stdio: 'inherit' });
  console.log(`Public API contracts: ${files.length} modules compatible with ${snapshot.revision.slice(0, 7)}.`);
} finally {
  rmSync(directory, { recursive: true, force: true });
}

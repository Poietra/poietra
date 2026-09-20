import { normalizePath } from 'vite';
import { join } from 'node:path';
import { readClientExports, workspace } from '../../../scripts/client-runtime.mjs';

const prefix = '\0poietra-client:';

export function moonbitClient() {
  const packages = readClientExports();
  const artifact = name => normalizePath(join(workspace, '_build/js/release/build', name, `${name}.js`));
  let ssrBuild = false;
  return {
    name: 'poietra-moonbit-client',
    enforce: 'pre',
    configResolved(config) { ssrBuild = Boolean(config.build.ssr); },
    async resolveId(source, importer, options) {
      // Prerender/Vitest SSR, Node and Worker imports retain standalone modules.
      if (options?.ssr || !importer) return null;
      const match = source.match(/(?:^|\/)_build\/js\/release\/build\/([^/]+)\/\1\.js$/);
      if (!match || !packages.has(match[1])) return null;
      const resolved = await this.resolve(source, importer, { ...options, skipSelf: true });
      if (!resolved || normalizePath(resolved.id) !== artifact(match[1])) return null;
      return prefix + match[1];
    },
    load(id) {
      if (!id.startsWith(prefix)) return null;
      const name = id.slice(prefix.length);
      if (!packages.has(name)) throw new Error(`Unknown MoonBit client package ${name}`);
      this.addWatchFile(join(workspace, 'moonbit', name, 'moon.pkg'));
      const bindings = readClientExports().get(name);
      return `import { ${name} as load } from ${JSON.stringify(artifact('client_runtime'))};\n`
        + 'const api = load();\n'
        + bindings.map(({ exported }) => `export const ${exported} = api.${exported};`).join('\n');
    },
    generateBundle(_options, bundle) {
      if (ssrBuild) return;
      // Fail the build if a new import path bypasses the shared linker.
      const standalone = new Set([...packages.keys()].map(artifact));
      for (const chunk of Object.values(bundle)) {
        if (chunk.type !== 'chunk') continue;
        for (const id of Object.keys(chunk.modules)) {
          if (standalone.has(normalizePath(id))) this.error(`Duplicate MoonBit browser artifact: ${id}`);
        }
      }
    },
  };
}

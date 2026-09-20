import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { readClientExports, workspace } from './client-runtime.mjs';
import { moonbitClient } from '../apps/studio/scripts/moonbit-client.mjs';
import * as runtime from '../_build/js/release/build/client_runtime/client_runtime.js';

test('the shared client preserves every standalone export and callable arity', async () => {
  const packages = readClientExports();
  assert.deepEqual(Object.keys(runtime).sort(), [...packages.keys()].sort());
  for (const [name, bindings] of packages) {
    const standalone = await import(join(workspace, '_build/js/release/build', name, `${name}.js`));
    const shared = runtime[name]();
    assert.deepEqual(Object.keys(shared).sort(), Object.keys(standalone).sort(), name);
    assert.deepEqual(Object.keys(shared).sort(), bindings.map(({ exported }) => exported).sort(), name);
    for (const key of Object.keys(shared)) {
      assert.equal(typeof shared[key], 'function', `${name}.${key}`);
      assert.equal(shared[key].length, standalone[key].length, `${name}.${key} arity`);
    }
  }
});

test('the labelled-argument bridge preserves video preparation for each foreign Bool value', async () => {
  const standalone = await import('../_build/js/release/build/ui/ui.js');
  const source = { objects: [{ object: { id: 'video', kind: 'video' } }] };
  const renderer = { prepareFrame() { throw new Error('Effects should not run during server rendering'); } };
  function evaluate(hook, enabled) {
    let result;
    renderToStaticMarkup(createElement(function Probe() {
      result = hook(source, renderer, 'scope', enabled);
      return null;
    }));
    return result;
  }
  for (const enabled of [-1, true, false, undefined]) {
    const shared = evaluate(runtime.ui().usePreparedStageFrame, enabled);
    assert.deepEqual(shared, evaluate(standalone.usePreparedStageFrame, enabled));
    assert.equal(shared.frame.objects.length, enabled === -1 || enabled === true ? 0 : 1);
  }
});

test('only this workspace browser artifacts are redirected; SSR and lazy packages retain their imports', async () => {
  const plugin = moonbitClient();
  const importer = join(workspace, 'apps/studio/src/App.js');
  const artifact = name => join(workspace, '_build/js/release/build', name, `${name}.js`);
  const context = { async resolve(source) { return { id: source }; }, addWatchFile() {} };
  const browser = await plugin.resolveId.call(context, artifact('ui'), importer, { ssr: false });
  assert.match(plugin.load.call(context, browser), /client_runtime\/client_runtime\.js/);
  assert.equal(await plugin.resolveId.call(context, artifact('ui'), importer, { ssr: true }), null);
  for (const name of ['browser_export', 'browser_projects', 'site', 'site_shell']) {
    assert.equal(await plugin.resolveId.call(context, artifact(name), importer, {}), null);
  }
  assert.equal(await plugin.resolveId.call(context, '/another/_build/js/release/build/ui/ui.js', importer, {}), null);
});

test('browser builds reject duplicate artifacts without constraining SSR builds', () => {
  const plugin = moonbitClient();
  const chunk = { type: 'chunk', modules: { [join(workspace, '_build/js/release/build/ui/ui.js')]: {} } };
  const context = { error(message) { throw new Error(message); } };
  assert.throws(() => plugin.generateBundle.call(context, {}, { editor: chunk }), /Duplicate MoonBit browser artifact/);
  plugin.configResolved({ build: { ssr: true } });
  assert.doesNotThrow(() => plugin.generateBundle.call(context, {}, { server: chunk }));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import Ajv2020 from 'ajv/dist/2020.js';
import { openapiJson, projectSchemaJson, exampleJson } from '../../../_build/js/release/build/render_api/render_api.js';
import { inspectProjectFile, capabilities } from '../index.mjs';
import { startServer } from '../server.mjs';
import { project } from './fixtures.mjs';

test('generated project schema accepts current and legacy projects and rejects invalid structural edits', () => {
  const ajv = new Ajv2020({ allErrors: true });
  const validate = ajv.compile(JSON.parse(projectSchemaJson()));
  const legacy = project(); legacy.version = 1;
  for (const value of [project(), legacy, JSON.parse(exampleJson())]) {
    assert.equal(validate(value), true, JSON.stringify(validate.errors));
    assert.equal(inspectProjectFile(JSON.stringify(value)).issues.length, 0);
  }
  for (const change of [
    value => { value.version = 3; },
    value => { value.scenes.scene.compositions.a.states.box.x = '100'; },
    value => { value.scenes.scene.objects.box.kind = 'unknown'; },
    value => { delete value.sceneOrder; },
    value => { value.sceneOrder = ['constructor']; },
    value => { value.scenes.scene.transitions.transition.tracks.box.easing = { type: 'cubicBezier', x1: 2, y1: 0, x2: 1, y2: 1 }; },
  ]) {
    const value = project(); change(value);
    assert.equal(validate(value), false);
    assert.throws(() => inspectProjectFile(JSON.stringify(value)));
  }
});

test('published OpenAPI resolves its schemas and describes actual authenticated HTTP responses', async () => {
  const server = await startServer({ port: 0, token: 'contract-test' });
  const origin = 'http://127.0.0.1:' + server.address().port;
  const headers = { authorization: 'Bearer contract-test', 'content-type': 'application/json' };
  try {
    const response = await fetch(origin + '/openapi.json', { headers: { origin: 'https://agent.example' } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    const spec = await response.json();
    assert.deepEqual(spec, JSON.parse(openapiJson(origin)));
    assert.equal(spec.openapi, '3.1.1');
    assert.deepEqual(spec.servers.map(server => server.url), [origin]);
    assert.deepEqual(Object.keys(spec.paths).sort(), ['/capabilities', '/inspect', '/render']);
    const ajv = new Ajv2020({ strict: false, allErrors: true });
    ajv.addSchema(spec, 'poietra-openapi');
    const valid = (name, value) => {
      const check = ajv.compile({ $ref: 'poietra-openapi#/components/schemas/' + name });
      assert.equal(check(value), true, JSON.stringify(check.errors));
    };
    const sampleResponse = await fetch(origin + '/examples/hello.poietra.json');
    const sample = await sampleResponse.text();
    valid('Project', JSON.parse(sample));
    assert.deepEqual(await (await fetch(origin + '/schemas/project.json')).json(), JSON.parse(projectSchemaJson()));
    const head = await fetch(origin + '/openapi.json', { method: 'HEAD' });
    assert.equal(head.status, 200); assert.equal(await head.text(), '');
    assert.equal((await fetch(origin + '/capabilities')).status, 401);
    const caps = await (await fetch(origin + '/capabilities', { headers })).json();
    valid('Capabilities', caps); assert.deepEqual(caps, capabilities());
    const inspect = await fetch(origin + '/inspect', { method: 'POST', headers, body: sample });
    assert.equal(inspect.status, 200); valid('Inspection', await inspect.json());
    const render = await fetch(origin + '/render?format=mp4&width=320&fps=30', { method: 'POST', headers, body: sample });
    assert.equal(render.status, 200);
    assert.ok(Object.hasOwn(spec.paths['/render'].post.responses['200'].content, render.headers.get('content-type')));
    assert.equal(render.headers.get('x-poietra-frames'), '30');
    assert.equal(Buffer.from(await render.arrayBuffer()).toString('ascii', 4, 8), 'ftyp');
    const error = await fetch(origin + '/render?fps=25', { method: 'POST', headers, body: sample });
    assert.equal(error.status, 422); valid('Error', await error.json());
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { request as httpRequest } from 'node:http';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { startServer } from '../server.mjs';
import { project } from './fixtures.mjs';
import { openapiJson, projectSchemaJson, exampleJson } from '../../../_build/js/release/build/render_api/render_api.js';

const run = promisify(execFile);
const root = fileURLToPath(new URL('../../../', import.meta.url));

test('HTTP accepts a portable file and returns PNG/MP4 with validation, auth and cancellation', async () => {
  const server = await startServer({ port: 0, token: 'test-render-token' });
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = { authorization: 'Bearer test-render-token', 'content-type': 'application/json' };
  const post = (path, body, extra = {}) => fetch(base + path, { method: 'POST', headers, body, ...extra });
  try {
    assert.equal((await fetch(base + '/capabilities')).status, 401);
    const capabilities = await fetch(base + '/capabilities', { headers });
    assert.deepEqual((await capabilities.json()).formats, ['svg', 'png', 'mp4']);
    assert.equal((await post('/render', '{}', { headers: { ...headers, origin: 'https://example.com' } })).status, 403);
    const invalidHost = await new Promise((resolve, reject) => {
      const req = httpRequest(base + '/capabilities', { headers: { ...headers, host: 'evil.test' } }, response => { response.resume(); resolve(response.statusCode); });
      req.on('error', reject); req.end();
    });
    assert.equal(invalidHost, 403);
    assert.equal((await post('/render', '{}', { headers: { authorization: headers.authorization, 'content-type': 'text/plain' } })).status, 415);
    assert.equal((await post('/render?width=NaN', JSON.stringify(project()))).status, 422);
    assert.equal((await post('/render?format=png&format=mp4', '{}')).status, 400);
    assert.equal((await post('/render?token=oops', '{}')).status, 400);
    assert.equal((await post('/render', '{')).status, 422);
    const info = await post('/inspect', JSON.stringify(project()));
    assert.equal((await info.json()).durationMs, 820);
    const png = await post('/render?width=160', JSON.stringify(project()));
    assert.equal(png.status, 200); assert.equal(png.headers.get('content-type'), 'image/png');
    assert.equal(png.headers.get('x-content-type-options'), 'nosniff');
    assert.deepEqual([...new Uint8Array(await png.arrayBuffer()).subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
    const mp4 = await post('/render?format=mp4&width=160', JSON.stringify(project()));
    assert.equal(mp4.status, 200); assert.equal(mp4.headers.get('x-poietra-frames'), '25');
    assert.equal(Buffer.from(await mp4.arrayBuffer()).toString('ascii', 4, 8), 'ftyp');
    // Hold a streaming upload to establish ownership deterministically.
    const { promise, resolve } = Promise.withResolvers();
    let upload;
    const stream = new ReadableStream({ start(controller) { upload = controller; controller.enqueue(new TextEncoder().encode('{')); } });
    const controller = new AbortController();
    const pending = post('/render', stream, { duplex: 'half', signal: controller.signal }).catch(() => null).finally(resolve);
    let busy = false;
    for (let i = 0; i < 30 && !busy; i++) {
      const response = await post('/render', '{}'); busy = response.status === 429;
    }
    assert.equal(busy, true);
    controller.abort(); await promise; await pending;
    try { upload.close(); } catch { /* stream cancelled */ }
    let restored;
    for (let i = 0; i < 30; i++) {
      restored = await post('/inspect', JSON.stringify(project()));
      if (restored.status !== 429) break;
    }
    assert.equal(restored.status, 200);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('HTTP returns 413 for declared and chunked oversized files without losing the response', async () => {
  const server = await startServer({ port: 0 });
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const declared of [true, false]) {
      const status = await new Promise((resolve, reject) => {
        const req = httpRequest(base + '/render', {
          method: 'POST', headers: { 'content-type': 'application/json', ...(declared ? { 'content-length': 33554433 } : {}) },
        }, response => { response.resume(); response.on('end', () => resolve(response.statusCode)); });
        req.on('error', reject);
        req.write('{');
        if (!declared) req.end(Buffer.alloc(33554432, 32));
      });
      assert.equal(status, 413);
    }
    const recovery = await fetch(base + '/inspect', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(project()) });
    assert.equal(recovery.status, 200);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('HTTP wildcard binding requires a token and accepts requests through a real interface', async () => {
  assert.throws(() => startServer({ host: '0.0.0.0', port: 0, token: '' }), /POIETRA_RENDER_TOKEN/);
  const server = await startServer({ host: '0.0.0.0', port: 0, token: 'public-test-token' });
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(base + '/capabilities')).status, 401);
    assert.equal((await fetch(base + '/capabilities', { headers: { authorization: 'Bearer public-test-token' } })).status, 200);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('MCP stdio discovers tools, inspects and renders a file without overwriting output', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'poietra-mcp-'));
  const inputPath = join(dir, 'input.poietra.json'), outputPath = join(dir, 'output.png');
  await writeFile(inputPath, JSON.stringify(project()));
  const transport = new StdioClientTransport({ command: process.execPath, args: [fileURLToPath(new URL('../mcp.mjs', import.meta.url))], stderr: 'pipe' });
  const client = new Client({ name: 'poietra-render-test', version: '1.0.0' });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    assert.deepEqual(tools.map(tool => tool.name).sort(), ['poietra_capabilities', 'poietra_inspect', 'poietra_render']);
    const resources = await client.listResources();
    assert.deepEqual(resources.resources.map(resource => resource.uri).sort(), [
      'poietra://docs/openapi', 'poietra://docs/project-schema', 'poietra://examples/hello',
    ]);
    for (const [uri, expected] of [
      ['poietra://docs/openapi', openapiJson('http://127.0.0.1:8799')],
      ['poietra://docs/project-schema', projectSchemaJson()],
      ['poietra://examples/hello', exampleJson()],
    ]) {
      const { contents } = await client.readResource({ uri });
      assert.equal(contents[0].mimeType, 'application/json');
      assert.deepEqual(JSON.parse(contents[0].text), JSON.parse(expected));
    }
    const inspect = await client.callTool({ name: 'poietra_inspect', arguments: { inputPath } });
    assert.equal(JSON.parse(inspect.content[0].text).name, 'Headless fixture');
    const result = await client.callTool({ name: 'poietra_render', arguments: { inputPath, outputPath, format: 'png', width: 160 } });
    assert.ok(!result.isError, JSON.stringify(result));
    assert.equal(JSON.parse(result.content[0].text).width, 160);
    const original = await readFile(outputPath); assert.ok(original.length > 100);
    const duplicate = await client.callTool({ name: 'poietra_render', arguments: { inputPath, outputPath } });
    assert.equal(duplicate.isError, true); assert.deepEqual(await readFile(outputPath), original);
  } finally { await client.close(); await transport.close(); await rm(dir, { recursive: true, force: true }); }
});

test('render works with subprocess launches and network fetch disabled, and no browser globals', async () => {
  const { stdout } = await run(process.execPath, ['--import', fileURLToPath(new URL('./offline-guard.mjs', import.meta.url)), fileURLToPath(new URL('./offline-proof.mjs', import.meta.url))], {
    cwd: root, env: { ...process.env, PATH: '' }, timeout: 20000, maxBuffer: 1024 * 1024,
  });
  assert.deepEqual(JSON.parse(stdout), { format: 'mp4', frames: 25, audioCodec: 'mp3', decodedFrames: 25 });
});

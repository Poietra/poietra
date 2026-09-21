import { resolve } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { renderProjectFile, inspectProjectFile, capabilities } from './index.mjs';
import { readProjectFile, writeResultFile } from './io.mjs';
import { openapiJson, projectSchemaJson, exampleJson } from '../../_build/js/release/build/render_api/render_api.js';

const server = new McpServer({ name: 'poietra-render', version: '0.1.0' });
let rendering = false;
const textResult = value => ({ content: [{ type: 'text', text: JSON.stringify(value, null, 2) }] });
for (const [name, path, description, read] of [
  ['poietra_openapi', 'docs/openapi', 'OpenAPI for the separately started local HTTP service.', () => openapiJson('http://127.0.0.1:8799')],
  ['poietra_project_schema', 'docs/project-schema', 'Structural schema for portable projects; inspect also checks references and compatibility.', projectSchemaJson],
  ['poietra_example', 'examples/hello', 'A complete one-second project ready to save, inspect and render.', exampleJson],
]) {
  const uri = 'poietra://' + path;
  server.registerResource(name, uri, { mimeType: 'application/json', description }, async () => ({
    contents: [{ uri, mimeType: 'application/json', text: read() }],
  }));
}
server.registerTool('poietra_capabilities', {
  description: 'List supported headless rendering formats, codecs and limits. No Chromium or FFmpeg is used.',
  inputSchema: {}, annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
}, async () => textResult(capabilities()));
server.registerTool('poietra_inspect', {
  description: 'Validate a local portable .poietra.json file and report rendering compatibility.',
  inputSchema: { inputPath: z.string().min(1) },
  annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
}, async ({ inputPath }) => {
  try { return textResult(inspectProjectFile(await readProjectFile(inputPath))); }
  catch (error) { return { ...textResult({ error: error.message }), isError: true }; }
});
server.registerTool('poietra_render', {
  description: 'Render a portable Poietra file to SVG, PNG or H.264 MP4 using standalone WASM. Embedded PNG/JPEG and PCM WAV are supported; imported video is not. Writes a new output file and never overwrites one.',
  inputSchema: {
    inputPath: z.string().min(1), outputPath: z.string().min(1),
    format: z.enum(['svg', 'png', 'mp4']).default('png'),
    width: z.number().int().positive().max(1920).optional(), height: z.number().int().positive().max(1920).optional(),
    fps: z.union([z.literal(24), z.literal(30), z.literal(60)]).optional(), timeMs: z.number().nonnegative().optional(),
  },
  annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
}, async ({ inputPath, outputPath, ...options }, extra) => {
  if (rendering) return { ...textResult({ error: 'A render is already running. Retry after it finishes.' }), isError: true };
  rendering = true;
  try {
    const result = await renderProjectFile(await readProjectFile(inputPath), { ...options, signal: extra.signal });
    extra.signal.throwIfAborted();
    await writeResultFile(outputPath, result.bytes, extra.signal);
    const { bytes, ...metadata } = result;
    return textResult({ outputPath: resolve(outputPath), bytes: bytes.byteLength, ...metadata });
  } catch (error) { return { ...textResult({ error: error.message }), isError: true }; }
  finally { rendering = false; }
});
await server.connect(new StdioServerTransport());

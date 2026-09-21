import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { createHash, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createHttpHandler } from '../../_build/js/release/build/render_http/render_http.js';
import { renderProjectFile } from './index.mjs';

export function startServer({ host = '127.0.0.1', port = 8799, token = process.env.POIETRA_RENDER_TOKEN } = {}) {
  if (!['127.0.0.1', '::1', 'localhost'].includes(host) && !token) throw new Error('Set POIETRA_RENDER_TOKEN before binding outside loopback.');
  const expected = token && createHash('sha256').update(`Bearer ${token}`).digest();
  const controllers = new Set();
  const handle = createHttpHandler({
    authorized: request => !expected || timingSafeEqual(expected, createHash('sha256').update(request.headers.get('authorization') ?? '').digest()),
    sameOrigin: request => !request.headers.has('origin') || request.headers.get('origin') === new URL(request.url).origin,
    async readBody(request, limit) {
      const chunks = []; let size = 0;
      const oversized = () => { const error = new Error('Project files must be 32 MiB or smaller.'); error.status = 413; return error; };
      if (Number(request.headers.get('content-length')) > limit) throw oversized();
      if (!request.body) throw new Error('Request body is missing.');
      // Cancelling the Node request stream here also destroys its response socket.
      // Leave it open long enough to deliver the 413 response, then close it below.
      for await (const chunk of request.body.values({ preventCancel: true })) {
        size += chunk.byteLength;
        if (size > limit) throw oversized();
        chunks.push(chunk);
      }
      return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, size));
    },
    render: renderProjectFile,
  });
  const server = createServer(async (req, res) => {
    const controller = new AbortController(); controllers.add(controller);
    const abort = () => { if (!res.writableEnded) controller.abort(); };
    req.on('aborted', abort); res.on('close', abort);
    try {
      const address = server.address();
      let origin = `http://${host.includes(':') ? `[${host}]` : host}:${address.port}`;
      const actualHost = req.headers.host;
      if (['0.0.0.0', '::'].includes(host)) {
        // A wildcard listener has no public authority. It always requires a
        // bearer token; accept a well-formed authority supplied by its client.
        const client = actualHost && URL.parse(`http://${actualHost}`);
        if (!client || client.host !== actualHost || client.username || client.password) {
          res.writeHead(400); res.end(); return;
        }
        origin = client.origin;
      } else if (actualHost !== new URL(origin).host && !(host === '127.0.0.1' && actualHost === `localhost:${address.port}`)) {
        // Pin loopback/explicit hosts to protect unauthenticated local use from
        // DNS rebinding. Host is not an authentication mechanism for public use.
        res.writeHead(403, { 'Content-Type': 'application/json' }); res.end('{"error":"Invalid Host header."}'); return;
      }
      const url = new URL(req.url, origin);
      if (url.origin !== origin) { res.writeHead(403); res.end(); return; }
      const request = new Request(url, {
        method: req.method, headers: req.headers, signal: controller.signal,
        ...(['GET', 'HEAD'].includes(req.method) ? {} : { body: Readable.toWeb(req), duplex: 'half' }),
      });
      const response = await handle(request);
      if (res.destroyed) return;
      if (response.status === 413) res.setHeader('Connection', 'close');
      res.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) {
        const stream = Readable.fromWeb(response.body);
        stream.on('error', () => res.destroy()); stream.pipe(res);
      } else res.end();
    } catch (error) {
      if (!res.destroyed && !res.headersSent) { res.writeHead(500, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ error: error.message })); }
    } finally {
      controllers.delete(controller); req.off('aborted', abort);
      if (!req.complete) req.resume();
    }
  });
  server.requestTimeout = 30000; server.headersTimeout = 15000;
  server.on('close', () => { for (const controller of controllers) controller.abort(); });
  return new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, () => { server.off('error', reject); resolve(server); }); });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = await startServer({ host: process.env.POIETRA_RENDER_HOST ?? '127.0.0.1', port: Number(process.env.POIETRA_RENDER_PORT ?? 8799) });
  console.error(`Poietra render API listening on http://${server.address().address}:${server.address().port}`);
  const stop = () => { server.closeAllConnections(); server.close(); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
}

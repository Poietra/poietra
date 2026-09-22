import assert from 'node:assert/strict';
import { once } from 'node:events';
import { WebSocket } from 'ws';

/** Local-only workerd inspector. Profiling runs are not latency comparisons. */
export async function startWorkerProfile(inspector) {
  const url = new URL(inspector); url.protocol = 'http:'; url.pathname = '/json/list';
  assert(['127.0.0.1', 'localhost'].includes(url.hostname));
  const targets = await (await fetch(url)).json();
  const target = targets.find(target => target.id.endsWith('poietra-collaboration-integration'));
  assert(target, 'workerd inspector target not found');
  const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map();
  let serial = 0;
  ws.on('message', bytes => {
    const message = JSON.parse(String(bytes)), entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id); clearTimeout(entry.timer);
    message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
  });
  await once(ws, 'open');
  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++serial;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Inspector timeout: ${method}`)); }, 15000);
      pending.set(id, { resolve, reject, timer }); ws.send(JSON.stringify({ id, method, params }));
    });
  }
  try {
    await send('Profiler.enable'); await send('Profiler.setSamplingInterval', { interval: 1000 }); await send('Profiler.start');
  } catch (error) { ws.close(); throw error; }
  return async () => {
    try { return (await send('Profiler.stop')).profile; }
    finally { ws.close(); }
  };
}

/** Local-only, one-room load test: real workerd plus partitioned Yjs clients.
 * Run a frozen wrangler dry-run bundle. No production load and no browser FPS claim.
 */
import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { Worker } from 'node:worker_threads';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir, cpus, totalmem } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';

const { values: args } = parseArgs({ options: {
  'source-revision': { type: 'string' },
  bundle: { type: 'string' }, output: { type: 'string' }, clients: { type: 'string', default: '32' },
  seconds: { type: 'string', default: '10' }, 'edit-hz': { type: 'string', default: '1' },
  'presence-hz': { type: 'string', default: '1' }, port: { type: 'string', default: '8796' },
  browser: { type: 'boolean' },
  'owned-presence': { type: 'boolean' }, generators: { type: 'string', default: '8' }, 'legacy-client': { type: 'boolean' },
} });
assert(args.bundle, '--bundle <frozen wrangler dry-run index.js> required');
const count = Number(args.clients), seconds = Number(args.seconds), editHz = Number(args['edit-hz']), presenceHz = Number(args['presence-hz']), generators = Math.min(count, Number(args.generators));
assert(count > 1 && count <= 500 && seconds >= 2 && editHz > 0 && presenceHz > 0 && generators > 0);
const port = Number(args.port), origin = `http://127.0.0.1:${port}`, room = crypto.randomUUID(); assert(![5173, 8787].includes(port));
const studio = fileURLToPath(new URL('..', import.meta.url)), temporary = await mkdtemp(resolve(tmpdir(), 'poietra-load-'));
let child, browser, page, id = 0;
const browserErrors = [];
const protocolCount = count - (args.browser ? 1 : 0);
const actors = [];
const require = createRequire(import.meta.url);
const wranglerRequire = createRequire(require.resolve('wrangler/package.json'));
const miniflareRequire = createRequire(wranglerRequire.resolve('miniflare/package.json'));
const digest = data => createHash('sha256').update(data).digest('hex');
const stats = values => { values.sort((a, b) => a - b); return { samples: values.length, p50: values[Math.floor(values.length * .5)] ?? null, p95: values[Math.floor(values.length * .95)] ?? null, p99: values[Math.floor(values.length * .99)] ?? null, max: values.at(-1) ?? null }; };
function command(target, name, value, timeout = 90000) {
  const request = ++id;
  return new Promise((done, reject) => {
    const timer = setTimeout(() => { target.off('message', receive); reject(new Error(`${name} timed out`)); }, timeout);
    function receive(message) { if (message.id !== request) return; clearTimeout(timer); target.off('message', receive); message.error ? reject(new Error(message.error)) : done(message.result); }
    target.on('message', receive);
    const message = { id: request, command: name, value, room };
    target.postMessage ? target.postMessage(message) : target.send(message);
  });
}
try {
  assert.equal(await fetch(`${origin}/api/health`).catch(() => null), null, 'Port is in use');
  let logs = '';
  child = spawn(process.execPath, [fileURLToPath(new URL('./collaboration-worker.integration.mjs', import.meta.url)), '--child', '--port', String(port), '--persist-to', resolve(temporary, 'state'), '--bundle', resolve(args.bundle)], { cwd: studio, detached: true, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
  for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { logs = (logs + data).slice(-10000); });
  await new Promise((done, reject) => {
    const timer = setTimeout(() => reject(new Error(`workerd startup timeout: ${logs}`)), 30000);
    child.once('error', reject); child.once('exit', code => reject(new Error(`workerd exited ${code}: ${logs}`)));
    child.on('message', message => { if (message.ready) { clearTimeout(timer); done(); } });
  });
  for (let i = 0; i < generators; i++) {
    const start = Math.floor(i * protocolCount / generators), end = Math.floor((i + 1) * protocolCount / generators);
    const actor = new Worker(new URL('./helpers/collaboration-load-client.mjs', import.meta.url), { workerData: { origin, room, start, length: end - start, total: count, owned: !!args['owned-presence'], legacyIndex: args['legacy-client'] ? count - 1 : -1 } });
    actors.push(actor);
  }
  await command(actors[0], 'seed');
  const joined = Date.now();
  await Promise.all(actors.map(actor => command(actor, 'join')));
  if (args.browser) {
    const { chromium, expect } = await import('@playwright/test');
    browser = await chromium.launch({ headless: true });
    page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    page.on('pageerror', error => browserErrors.push(error.message));
    await page.goto(`${origin}/?room=${room}`);
    await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 60000 });
    await expect(page.getByRole('button', { name: `参加者 ${count} 人`, exact: true })).toBeVisible({ timeout: 60000 });
    await page.getByRole('button', { name: `Object ${count - 1}`, exact: true }).click();
    await page.evaluate(() => {
      window.loadFrames = []; window.loadTasks = []; let previous = performance.now();
      window.loadMeasure = true; window.loadStart = Infinity;
      const frame = time => { if (!window.loadMeasure) return; if (Date.now() >= window.loadStart) window.loadFrames.push(time - previous); previous = time; requestAnimationFrame(frame); };
      requestAnimationFrame(frame);
      new PerformanceObserver(list => { if (window.loadMeasure && Date.now() >= window.loadStart) for (const e of list.getEntries()) window.loadTasks.push(e.duration); }).observe({ type: 'longtask' });
    });
  }
  await Promise.all(actors.map(actor => command(actor, 'presence')));
  const joinMs = Date.now() - joined, start = Date.now() + 1000;
  if (page) await page.evaluate(start => { window.loadStart = start; }, start);
  const publishers = (await Promise.all(actors.map(actor => command(actor, 'publish', { start, seconds, editHz, presenceHz })))).flat();
  const results = await Promise.all(actors.map(actor => command(actor, 'verify', publishers)));
  const latencies = results.flatMap(result => result.latencies), sum = key => results.reduce((total, result) => total + result[key], 0);
  let browserResult;
  if (page) {
    const { expect } = await import('@playwright/test');
    const timing = await page.evaluate(() => { window.loadMeasure = false; return { frames: window.loadFrames, longTasks: window.loadTasks }; });
    const editStart = Date.now();
    const input = page.getByRole('spinbutton', { name: 'Position X', exact: true });
    await input.fill('777'); await input.press('Tab');
    await Promise.all(actors.map(actor => command(actor, 'pose', { index: count - 1, x: 777 })));
    await expect(input).toHaveValue('777');
    browserResult = { editAndPeerConvergenceMs: Date.now() - editStart, frameIntervalMs: stats(timing.frames), longTasksMs: stats(timing.longTasks), pageErrors: browserErrors, browser: browser.version(), renderer: 'headless Chromium on local machine, not real-device FPS' };
    assert.equal(browserErrors.length, 0);
  }
  await command(child, 'hibernate');
  await command(actors[0], 'edit'); await Promise.all(actors.map(actor => command(actor, 'check')));
  const result = {
    ...(browserResult ? { browser: browserResult } : {}),
    measuredAt: new Date().toISOString(), sourceRevision: args['source-revision'] ?? execFileSync('git', ['rev-parse', 'HEAD'], { cwd: studio, encoding: 'utf8' }).trim(),
    harnessRevision: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: studio, encoding: 'utf8' }).trim(),
    versions: { moon: (await readFile(resolve(studio, '../../.moon-version'), 'utf8')).trim(), wrangler: require('wrangler/package.json').version, miniflare: wranglerRequire('miniflare/package.json').version, workerd: miniflareRequire('workerd/package.json').version, yjs: require('yjs/package.json').version, yWebsocket: require('y-websocket/package.json').version },
    browserManifestSha256: args.browser ? digest(await readFile(resolve(studio, 'dist/.vite/manifest.json'))) : null,
    bundleSha256: digest(await readFile(args.bundle)), harnessSha256: digest(await readFile(fileURLToPath(import.meta.url))),
    actorSha256: digest(await readFile(new URL('./helpers/collaboration-load-client.mjs', import.meta.url))),
    clientPresenceSha256: args['owned-presence'] ? digest(await readFile(resolve(studio, '../../_build/js/release/build/client_presence/client_presence.js'))) : null,
    machine: { platform: process.platform, node: process.version, cpu: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem(), affinity: (await readFile('/proc/self/status', 'utf8')).match(/Cpus_allowed_list:\s*(.*)/)?.[1] },
    workload: { clients: count, objects: count, seconds, editHz, presenceHz, ownedPresence: !!args['owned-presence'], legacyClient: !!args['legacy-client'], browserClient: !!args.browser, generators, warmup: 'all peers synchronized, then 1s idle', host: 'local workerd, one room; protocol clients across worker threads; optional browser reported separately; no WAN' },
    joinMs, convergenceMs: Math.max(...results.map(result => result.convergedAt)) - start, measuredUpdates: publishers.reduce((n, p) => n + p.edits, 0),
    wire: { compression: [...new Set(results.flatMap(r => r.compression))], receivedBytes: sum('wireReceivedBytes'), transmittedBytes: sum('wireTransmittedBytes') },
    received: sum('received'), receivedBytes: sum('receivedBytes'), transmitted: sum('transmitted'), transmittedBytes: sum('transmittedBytes'), disconnects: sum('disconnects'),
    peerEditLatencyMs: stats(latencies), generator: { uvThreadpoolSize: process.env.UV_THREADPOOL_SIZE ?? 'default', schedulerMaxDelayMs: Math.max(...results.map(r => r.schedulerMaxDelayMs)), eventLoopP99Ms: Math.max(...results.map(r => r.eventLoopP99Ms)), heapsBytes: sum('heapBytes'), rssBytes: process.memoryUsage().rss },
    checks: { allFinalPoses: true, hibernationEditAndPresence: true },
  };
  if (args.output) await writeFile(args.output, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser?.close();
  await Promise.allSettled(actors.map(async actor => { try { await command(actor, 'close', undefined, 2000); } finally { await actor.terminate(); } }));
  if (child && child.exitCode === null && child.signalCode === null) { const exited = once(child, 'exit'); process.kill(-child.pid, 'SIGKILL'); await exited; }
  await rm(temporary, { recursive: true, force: true });
}

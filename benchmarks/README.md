# Performance

[Project overview](../README.md) · [Development and checks](../docs/development.md)

[CI](#ci-latency--2026-09-27) ·
[Rendering and memory](#rendering-import-and-retained-memory--2026-09-27) ·
[Collaboration](#same-room-collaboration--2026-09-22) ·
[Headless export](#headless-export--2026-09-21) ·
[Browser linking](#shared-browser-linking--2026-09-20) ·
[Earlier evidence](#earlier-measurement-evidence) · [Reproduction](#reproduce-the-measurements)

Measurements are stored in [benchmarks/](.) with source/artifact hashes,
environment, workloads and raw samples. The following results describe specific
local fixtures. Production CDN delivery, real mobile hardware, WAN collaboration
and long source-media projects need separate measurement.

## CI latency — 2026-09-27

[Run 36308337905](https://github.com/Poietra/poietra/actions/runs/36308337905) completed in **4m29s**, compared with **12m17s** for
[the preceding serial run](https://github.com/Poietra/poietra/actions/runs/36306079950)
at `4e2e07b`: 63.5% less elapsed time. The tradeoff is more runner time:

| CI measurement | Serial | Split |
| --- | ---: | ---: |
| Workflow creation to completion, including setup and queueing | 12m17s | 4m29s |
| Sum of job durations (not billing-rounded minutes) | 12m13s | 22m26s |
| Browser cases included in CI | 233 | 248 |

This is one successful sample per layout, with the same application, pinned
MoonBit/Node/Playwright and Ubuntu runner image. Restored pnpm caches were used;
no dedicated warmup or CPU affinity was applied. GitHub hosts and load can differ,
and the split includes 18 previously omitted cases while consolidating three
browser cases. It measures CI latency, not application speed or per-test CPU
savings. Raw job/step timestamps and environment details are retained in
[before.json](2026-09-27-ci/before.json) and
[after.json](2026-09-27-ci/after.json).

<a id="rendering-and-playback--2026-09-27"></a>

## Rendering, import and retained memory — 2026-09-27

These are **incremental comparisons at different source revisions**, not one
cumulative speedup. Node **24.13.0**, MoonBit **0.10.13+cbb11c36f**, Intel Core
Ultra 7 255H, 32 GB WSL2, CPU affinity **0–15**; browser runs use Chromium
**153.0.8010.12** and SwiftShader. Workloads run sequentially with frozen
application sources/artifacts. Raw reports identify builds, inputs, warmup,
samples and exclusions. CPU work and SwiftShader publication do not measure
hardware FPS, field INP, WAN latency or complete encoding time.

The tables retain representative results and material tradeoffs. The
[complete per-change measurements and methods](https://github.com/Poietra/poietra/blob/0ef67abbcf445aad72b7a26cfd67af1f742b2cfe/README.md#rendering-and-playback--2026-09-27)
preserve smaller workloads, controls, batch sizes and the development sequence.
All raw evidence remains in [benchmarks/](.).

**Production browser behavior.** Values are milliseconds. Brackets are the range
of process medians, except the initial circle-drag row, which reports one
process's event median and min–max. These measure different intervals; do not
compare rows as equivalent frame times.

| 500-object workload / observed interval | Before | After | Evidence |
| --- | ---: | ---: | --- |
| Circle drag, input delivery → DOM mutation | 19.3 [15.4–30.9] | 12.4 [11.3–16.8] | [Typed frame capture](2026-09-27-typed-frames) |
| Project preview, browser tasks per Canvas publication | 13.931 [13.913–13.999] | 6.496 [6.443–6.688] | [One active rendering path](2026-09-27-project-preview) |
| Editor playback, browser tasks per Canvas publication | 11.871 [11.814–11.893] | 8.125 [8.090–8.158] | [Retained hit geometry](2026-09-27-playback-hit-surface) |
| Static project hold, total browser tasks per 3.5-second pass | 1,343 [1,340–1,348] | 787 [782–789] | [Static frame reuse](2026-09-27-project-holds) |
| Prepared image drag, input delivery → DOM mutation | 13.7 [13.6–13.7] | 12.2 [12.1–12.2] | [Span-based SVG escaping](2026-09-27-svg-image-drag) |
| File opening, six Compositions, input change → destination ready | 872 [841–889] | 839 [805–874] | [Production import](2026-09-27-project-import) |

Preview/hold/playback cases each use three fresh processes, one warmup and three
3.5-second measured passes per size, a 1440×900 viewport and isolated loopback
production storage. Preview eliminated 27 million hidden SVG characters per pass;
editor playback reduced about 108,000 SVG mutations to 500 when pausing. Static
holds make no display copies after the initial frame; transitions and visible
video remain dynamic. Publication/rAF medians stayed around **16.7 ms**: these
results show less work, not higher display FPS.

Drag cases use one warmup and three 60-move drags; the image case repeats this in
three fresh processes after preparing the same 104,443-byte PNG. Its two-rAF
presentation-opportunity median was **40.1 → 40.5 ms**, with no improvement.
Circle-drag input spacing changed from 50.0 to 33.3 ms; pre-delivery waiting is
excluded. Neither result measures physical paint completion or field INP.

Import uses three fresh processes, one warmup and three measured file openings
per case. It compares the three codec files from `db01142` with the new codec,
on the same `fad7e69` Node host with bounded writes and saved ordered replies.
Input JSON is identical; random Yjs IDs vary binary packet sizes. Timing includes
file reading, validation, Yjs conversion, legacy migration, persistence, navigation,
Live status, object nodes, visible Canvas and two animation-frame opportunities.
Final Composition geometry is checked after timing. Pre-navigation time was
376 [353–385] → 353 [347–376] ms; 100-object/two-Composition readiness was
234 [233–235] → 235 [233–235] ms. **Ranges overlap: an end-to-end import speedup
is not established.** Test-observer scheduling is included; WAN and media are not.

**CPU operations.** Values below are milliseconds per operation, median [range
of process medians], from five fresh Node processes. Each report records its
specific warmup and batch size; these exclude browser work, media decoding and
encoding. Editing includes Yjs, selective Undo and immutable snapshot reads;
public evaluation/rendering includes native record conversion.

| Change / representative workload | Before | After |
| --- | ---: | ---: |
| [Native SVG view](2026-09-27-render-view), 500 circles | 0.522 [0.510–0.536] | 0.302 [0.287–0.313] |
| [Indexed hierarchy](2026-09-27-indexed-hierarchy), 500 objects, parents + six keys/frame | 0.6136 [0.5950–0.6261] | 0.5140 [0.5136–0.5265] |
| [Authored curve preparation](2026-09-27-curve-preparation), same parent/key fixture | 3.571 [3.421–3.766] | 2.114 [2.060–2.238] |
| [Editing layout reuse](2026-09-27-shared-state-view), 500-object parent edit + frame | 1.363 [1.330–1.394] | 0.979 [0.966–1.002] |
| [Immutable pose reuse](2026-09-27-immutable-poses), 500-object flat edit + frame | 0.606 [0.578–0.636] | 0.517 [0.502–0.547] |
| [Indexed Composition](2026-09-27-indexed-compositions), 500-object parent edit + frame | 0.924 [0.918–0.929] | 0.868 [0.852–0.923] |
| [Audio source validation reuse](2026-09-27-media-editing), steady volume edit, embedded 1 MiB | 8.4788 [7.5578–8.5987] | 0.0199 [0.0189–0.0321] |
| [Export capture](2026-09-27-export-capture), one Scene, 500 objects × 12 Compositions | 21.512 [21.359–21.903] | 13.267 [12.429–13.853] |
| [Repeated asset validation](2026-09-27-asset-validation), parse 16 references to one 1 MiB image | 76.71 [76.20–79.60] | 21.61 [20.64–22.87] |
| [SVG span escaping](2026-09-27-svg-escaping), one embedded 1 MiB image | 20.150 [19.644–20.576] | 1.931 [1.922–2.003] |
| [Timeline projection](2026-09-27-timeline-projection), 500 objects × 12 Compositions, 50 videos | 0.05633 [0.05395–0.05684] | 0.00202 [0.00196–0.00207] |
| [Owned normalization](2026-09-27-project-parsing), parse 500 objects × 12 Compositions | 51.642 [49.782–54.362] | 40.193 [38.564–41.523] |
| [Iterative reserved-key guard](2026-09-27-json-key-scan), same 500 × 12 parse | 40.193 [38.564–41.523] | 15.173 [14.582–15.675] |
| [Owned normalization](2026-09-27-project-parsing), parse 500 × 100 | 458.777 [450.752–478.909] | 345.026 [340.642–356.969] |
| [Iterative reserved-key guard](2026-09-27-json-key-scan), same 500 × 100 parse | 345.026 [340.642–356.969] | 127.734 [126.214–132.062] |

Limits and controls matter:

- Immutable pose reuse costs about **0.16 MB** extra retained JS heap per
  500-object document. Indexed Composition evaluation of uncached mutable inputs
  changed **0.906 → 0.930 ms**. These CPU changes did not establish faster dragging.
- Normal browser media uses room URLs: the audio row's 1 MiB counts Base64
  characters, not decoded audio. A room-URL volume edit was **0.0309 → 0.0239 ms**;
  the first embedded edit still validates the source.
- Export capture stops at the missing-WebCodecs check after capture/preparation;
  snapshots fell from two to one. It excludes actual export/encoding duration.
- Repeated-asset parsing still creates independent output records. SVG escaping
  retains XML control/surrogate rules; its replacement-heavy control did not improve.
- Timeline generation is a metadata query; duration still inspects visible media
  and its **0.05406 → 0.05218 ms** ranges overlap. No frame evaluation is timed.
- Parsing uses two warmup and seven measured batches, three parses per batch
  except one at 100 Compositions. The largest JSON is 13,343,340 UTF-8 bytes;
  final JSON-only control **33.480 → 33.555 ms** did not improve. Full validation,
  unknown-subtree reserved keys and independent results remain intact. The
  [CPU profile](2026-09-27-json-key-scan/before.cpuprofile.gz) identified
  the old per-value reviver cost; parsing gains alone do not establish UI latency.

**Prepared ownership and memory.** Playback preparation uses five fresh processes,
three compile warmups, seven timed compilations with GC outside timing, and eight
retained programs while the caller's Scene stays alive. Values are medians;
playback heap is decimal MB per program. These are separate incremental changes.

| Change / 500 objects × 12 Compositions | Prepare before → after, ms | Retained before → after, MB |
| --- | ---: | ---: |
| [Remove duplicate native Scene](2026-09-27-playback-ownership) | 24.828 → 12.012 | 11.464 → 7.093 |
| [Share order and parent graph](2026-09-27-shared-scene-layout), parents | 19.651 → 12.827 | 8.040 → 7.591 |
| [Release source containers](2026-09-27-compiled-ownership), explicit tracks | 11.530 → 11.941 | 7.092 → 4.972 |
| [Release source/key containers](2026-09-27-compiled-ownership), parents + six keys | 25.896 → 28.981 | 23.311 → 15.118 |

The last row trades more setup work for less retained memory: process medians
25.490–26.678 → 28.101–29.153 ms; heap 23.308–23.313 → 15.117–15.118 MB.
Authored keys and retained deleted poses remain intact, with independent evaluated
frames. Native/WASM memory, transient allocation and media decoding are excluded.

The separate [headless retained-ownership comparison](2026-09-27-headless-ownership)
starts from `e521995`. Each of five fresh processes completes two warmup renders,
then prepares three jobs sequentially and pauses them at the native resource port.
The input string is already allocated; GC-retained JS heap is divided by three.
Values are median [process range], in **MiB per job**, not the playback MB above.

| Headless timeline | Before, MiB | After, MiB |
| --- | ---: | ---: |
| 500 objects × 12 Compositions | 5.138 [5.134–5.144] | 4.576 [4.576–4.578] |
| 500 × 60 | 25.754 [25.740–25.762] | 23.128 [23.122–23.137] |
| 500 × 12, including 50 text objects | 5.447 [5.437–5.454] | 4.892 [4.886–4.899] |

Every released job completes SVG rendering with identical output bytes. Preparation
(parse/compile/resource-port arrival) was 31.132 [28.657–32.421] →
30.663 [30.361–31.864] ms at 12 Compositions and 97.469 [96.768–99.750] →
94.639 [93.323–96.261] ms at 60. The 100-object/two-Composition heap ranges overlap.
The text follow-up uses 600 distinct strings and deterministic mock metrics,
with the same baseline headless artifact verified by hash. Its preparation time
was 32.821 [30.476–33.375] → 32.670 [29.404–33.616] ms: no speedup established.
This measures retained timelines and suspended orchestration, excluding peak RSS,
input strings, native/WASM buffers, fonts, codecs and real resource preparation.

**Canvas publication and inconclusive experiments.** These measurements use
release MoonBit through Vite, a 1280×720 Canvas and SwiftShader; asynchronous
paint/publication time is distinct from editor input latency or GPU completion.

| Change / 500 circles | Before, ms | After, ms | Method / interpretation |
| --- | ---: | ---: | --- |
| [Typed frame capture](2026-09-27-typed-frames) | 9.43 [17.70 p95] | 6.55 [13.30 p95] | One warmup, 30 paints; mean [p95]; caller clone remains |
| [Direct draft publication](2026-09-27-preview-drafts) | 4.737 [4.648–4.923] | 4.132 [4.060–4.190] | Five fresh processes; alternate modes, two warmup/seven 15-frame batches; constructor canvas retained in both |
| [Cache-hit ticket ownership](2026-09-27-raster-tickets), half opacity | 4.227 [4.171–4.313] | 4.206 [4.129–4.385] | Three-process publication comparison; no speedup established |
| [Typed raster bounds](2026-09-27-typed-raster), half opacity | 4.206 [4.129–4.385] | 4.266 [4.239–4.319] | Same publication method; no speedup established |

Publication comparisons check full pixel equality outside timing. Cache hits
already finish synchronously in MoonBit's async lowering; the ticket change does
not remove a Promise/microtask per object. Layout/pose caches, retained React
SVG elements and the draft path did not establish faster editor dragging.
A [native props-factory trial](2026-09-27-stage-props/exploratory)
was rejected (**12.0 → 12.3 ms** drag median). The
[typed cubic experiment](2026-09-27-cubic-geometry), also rejected,
changed publication **4.295 → 4.272 ms** while its unchanged circle control moved
**4.269 → 4.120 ms**; the proposed patch and raw variation remain available.

[Current checks](../docs/development.md#checks) cover mutable public inputs, queued/nested observers,
metadata invalidation, cancellation, video timing, peer edits, Undo/Redo and
preview/export agreement. See [reproduction commands](#reproduce-the-measurements),
[production import harness](../apps/studio/scripts/measure-project-import.mjs) and
[headless heap harness](../scripts/benchmark-headless-heap.mjs). No production
deployment was made for these changes.

## Same-room collaboration — 2026-09-22

Real local workerd, one room and one object per participant, on the same Intel
Core Ultra 7 255H / 32 GB WSL2 host as eight Node client-generator threads; CPU
affinity 0–15. Node 24.13.0, MoonBit 0.10.13+cbb11c36f, Wrangler 4.131.2,
workerd 1.20260911.1, Yjs 13.6.32 and y-websocket 3.1.0. Every run synchronized
all clients, waited one second, then staggered periodic property/presence edits.
Builds, tests and encoders did not run concurrently. These are local end-to-end
delivery measurements, including client scheduling and Yjs application.

The 32-client comparison used two edits and ten presence updates per second per
client for ten seconds, with three samples at each revision. Incoming room
messages fell from **103,008–103,040 to 3,839–3,840: about 96.3% fewer**, principally
by stopping remote-awareness echoes. Peer-edit p95 was **9–14 ms** afterward;
the preceding implementation varied from **43–1,129 ms**, so a fixed latency
speedup is not claimed. All final states converged, with no disconnected clients.
The [raw results](2026-09-22-collaboration) named
`delivery-before-32-*` and `delivery-after-32-*` use the same harness `3a04bf8`,
comparing application `115ed1e` with `72f05a2`.

Longer runs used one edit and one presence update per second per protocol client:

| One-room workload | Duration / edits | Peer delivery p50 / p95 | Final convergence / disconnects |
| --- | --- | --- | --- |
| [500 protocol clients](2026-09-22-collaboration/soak-500.json) | 60 s / 29,998 | 526 / 1,750 ms | 60.422 s / 0 |
| [499 protocol clients + one browser](2026-09-22-collaboration/soak-browser-500.json) | 60 s / 29,940 | 318 / 539 ms | 60.259 s / 0 |

Both runs checked every client's final poses and edits/presence after forced
hibernation. The browser run used headless Chromium 153.0.8010.12: no page errors
or long tasks were observed during the measured load; rAF intervals were
16.7 ms at p95. Its own edit, made **after** the load, reached all protocol clients
in 196 ms. This is one browser on a local machine, not 500 rendered browsers or
real-device FPS. Protocol clients received about 439 MB on the wire during that
run with `permessage-deflate`; logical decoded traffic was about 2.83 GB.

Raw files record frozen artifact hashes and harness revisions (`3a04bf8` /
`29a8366`). Both long runs measured application `72f05a2`, before the final
socket-retirement fix. Generator process RSS reached 15–16 GB; those hundreds of
client documents are not the Worker heap. Intermediate, high-rate, legacy-client
and rejected generator experiments remain under
[exploratory/](2026-09-22-collaboration/exploratory).

Latency still varies at 500 participants. This verifies the stated one-minute
workloads and final convergence, not 500 people continuously dragging at high
frequency, long-duration endurance or WAN performance. The room remains a single
authoritative Durable Object; Cloudflare documents a workload-dependent
[soft limit of 1,000 requests/s per object](https://developers.cloudflare.com/durable-objects/platform/limits/).
Batching reduces persistence/fan-out overhead but does not remove that inbound
event limit or the cost of delivering everyone's edits to everyone else.

The client follow-up on 2026-09-22 fixes a gap in the earlier cursor tests: the
canvas includes unchanged Scene/Composition IDs in every move, while the old
throttle recognized only single-field cursor patches. The real workerd regression
now opens 500 sockets (one browser, one document observer and 498 idle roster
connections) and drives the actual canvas. With controlled browser time, 20 moves
at 41 ms intervals plus a 180 ms trailing drain produce one presence publication.
A burst of 90 drag moves without advancing the browser clock changes the local
inspector immediately and flushes one document update on pointer release. The peer
receives the final position, and Undo retains its independent color edit. A separate
transport test advances time by 16 ms between 90 edits: it produces 23 packets
with a 50 ms window and final flush, demonstrating delivery during continuous input.
These are deterministic message-count and ordering checks, not latency or FPS
measurements. They do not establish 500 continuously dragging browsers. See
[the real-browser regression](../apps/studio/tests/collaboration-worker.integration.mjs)
and [transport checks](../apps/studio/tests/client-sync.test.ts).

To repeat the current implementation, build once, freeze the bundle and run
these commands sequentially from `apps/studio` (port 8796 must be unused):

```sh
pnpm build:web
pnpm exec wrangler deploy --dry-run --outdir /tmp/poietra-collaboration-bundle
node tests/collaboration-load.integration.mjs \
  --bundle /tmp/poietra-collaboration-bundle/index.js --owned-presence \
  --clients 500 --generators 8 --seconds 60 --edit-hz 1 --presence-hz 1 \
  --output /tmp/poietra-collaboration-500.json
# Repeat with --browser to include one real browser among the 500 participants.
```

The `79531b9` follow-up removes duplicate presence serialization and intermediate
host-record allocations. The decoder transfers its freshly owned selection array
instead of copying it again. Existing mizchi WebSocket bindings avoid a dynamic
method lookup and argument array on every send.

| Independently decoded fixture | Packets before | Packets after |
| --- | ---: | ---: |
| 64 ordinary cursor updates | 2 | 1 |
| 500-person ordinary roster | 10 | 6 |
| 500-person roster with long Unicode selections | 100 | 100 |

All entries, safe-integer clocks, null removals and UTF-8 data are preserved;
packets stay within 100 entries and 16,000 bytes for older clients. The unchanged
Unicode packet count reflects the byte limit. See the
[raw follow-up results and conditions](2026-09-22-collaboration/encoding).
The three 15-second 500-client runs at each revision converged without disconnects
and passed hibernation checks. Separate 500-client checks with an old client and
a real browser passed too.

Unrelated C++ compilation was observed on this shared host during these follow-up
runs. **Their wall times are exploratory, not evidence of an end-to-end latency
or encoding-time speedup.** The earlier `72f05a2` timing records above describe
their own runs. A new isolated timing comparison is still required. The harness
now separates document/presence traffic and supports local workerd CPU profiling
with `--profile-worker /tmp/room.cpuprofile`; profiling results are separate from
latency comparisons. Stop other builds before timing. To repeat the encoder check
from the repository root after building:

```sh
node apps/studio/scripts/benchmark-presence.mjs \
  --module _build/js/release/build/server_presence/server_presence.js \
  --output /tmp/poietra-presence.json
```

## Headless export — 2026-09-21

Local Node 24.13.0 on an Intel Core Ultra 7 255H, WSL2 Linux, CPU affinity 0–15.
Each workload received one warmup and three sequential samples in fresh processes
and worker threads, with frozen sources and no concurrent builds/tests/encoders.
The fixture is **1280×720, 30 fps, 3.4 seconds / 102 frames**, with Japanese/Latin
text, MathJax, Glow and an embedded PNG. Audio adds trimmed stereo WAV at half gain
and a muted track. [Before typed boundaries](2026-09-21-headless/render.json)
and [after the refactor](2026-09-21-headless/typed-render.json) record raw
samples, source/artifact hashes and dependency versions for the working trees on
top of `4a68767`. Both use the same harness and input hashes.

| Workload | Before, median | Typed, median [min–max] | Rasterized / encoded frames | MP4 bytes |
| --- | ---: | ---: | ---: | ---: |
| Static hold | 1,125 ms | 1,117 [1,112–1,135] ms | 1 / 102 | 26,232 |
| Animated intermediate value | 1,461 ms | 1,421 [1,410–1,423] ms | 26 / 102 | 31,798 |
| Animation with audio | 1,507 ms | 1,506 [1,505–1,526] ms | 26 / 102 | 115,260 |

Wall time includes worker startup, module/WASM/font loading, MathJax, rendering,
encoding, muxing and thread teardown; it excludes parent-process startup,
file/network transfer and independent decoding. Whole-process peak RSS ranged
from **229–269 MiB** after the refactor; this is not a Cloudflare Worker heap
measurement. The short, unpaired samples show no material slowdown in this fixture;
they do not establish a general speedup, a browser comparison or a long-video SLA.

```sh
pnpm build:moonbit
# Freeze sources/artifacts; run with no other build, test or encoder in progress.
node scripts/benchmark-headless.mjs test-results/headless-benchmark.json
```

## Shared browser linking — 2026-09-20

Application `0cda0c5` links the six browser packages once. Its baseline is
`2c00643` (application `99a349d`); standalone boundary/editor and WASM artifacts
remained identical. [Bundle before](2026-09-20-client-linking/bundle-before.json)
and [after](2026-09-20-client-linking/bundle-after.json) record all files
and hashes.

| Static JS group | Before | After |
| --- | ---: | ---: |
| Editor, raw | 1,883,417 B | 1,610,705 B (−14.5%) |
| Editor, gzip level 9 | 524,141 B | 457,443 B (−12.7%) |
| Editor, Brotli | 401,036 B | 371,942 B (−7.3%) |
| Homepage, gzip level 9 | 91,072 B | 91,134 B (+62 B) |

Groups include static imports; the homepage also includes its selected entry.
Dynamic editor modules, CSS, fonts and media are excluded. Compression is computed
per file, using Node's default Brotli settings, rather than measured on the wire.

Cold startup used three fresh contexts per build, no warmup, one pre-seeded
circle, a 412 × 823 viewport, disabled cache, 4× CPU slowdown, 150 ms HTTP latency,
200,000 B/s download and 93,750 B/s upload. Hardware: Core Ultra 7 255H, 32 GiB,
WSL2, CPUs 0–15; Node 24.13.0, MoonBit 0.10.13+cbb11c36f and Chromium 153.0.8010.12.
Runs were sequential with frozen artifacts and no concurrent local builds,
tests or encoders.

| Cold startup, median [min–max] | Before | After |
| --- | ---: | ---: |
| FCP | 1,680 [1,668–1,684] ms | 1,676 [1,668–1,676] ms |
| LCP | 11,340 [11,288–11,376] ms | 10,152 [10,148–10,172] ms |
| Circle in DOM + two animation frames | 11,903.9 [11,811.2–11,963.9] ms | 10,651.2 [10,648.7–10,651.7] ms |
| Observed long-task blocking sum | 354 [304–476] ms | 347 [338–354] ms |

Stage readiness improved **10.5%** in this fixture. The local Node server sends
uncompressed assets and uses local WebSockets; these are not production load
times. The stage metric is a presentation opportunity, not physical display or a
Web Vital, and the blocking sum is not Lighthouse TBT. Full samples:
[startup before](2026-09-20-client-linking/startup-before.json),
[startup after](2026-09-20-client-linking/startup-after.json).

A separate warm interaction run used 100/500 circles at 1440 × 900, one drag
warmup and three sets of 60 pointer moves, with a 1 ms CPU sampler. For 500 circles,
median delivery-to-DOM was **14.4 ms**, delivery-to-DOM plus two animation frames
was **33.4 ms**, and actual input spacing was **50.0 ms**. The three-second Scene
(two one-second holds and one-second transition) had rAF intervals of 16.7 ms
median, 49.9 ms p95 and 83.4 ms maximum. Long frames remain. This final run does
not establish an interaction speedup; it excludes pre-delivery input waiting,
media, WAN and hardware GPU behavior. [Samples and profiles](2026-09-20-client-linking)
retain the full observations.

## Earlier measurement evidence

These datasets belong to earlier revisions; do not combine their speedups or
report them as fresh measurements of the current release. Previous explanations,
including unsuccessful/intermediate runs and old deployment records, remain in
[the README at 5468c56](https://github.com/Poietra/poietra/blob/5468c56/README.md#performance).

| Investigation | Retained evidence |
| --- | --- |
| Panel/resource invalidation | [Document updates](2026-09-20-document-updates) |
| Clock, presence and chat subscriptions | [UI subscriptions](2026-09-20-ui-subscriptions), including synchronous-clock regressions |
| Retained SVG and direct Canvas shapes | [Rendering, interaction, startup and WebCodecs](2026-09-20-retained-rendering) |
| Parenting and value curves | [Primitives](2026-09-20-primitives) |
| Lazy loading, static holds and export | [Startup](2026-09-20-startup) and [interaction/export](2026-09-20-interaction) |
| Typed editing plans | [Object edits](2026-09-20-editing), [Transition timing](2026-09-20-timing), [track timing](2026-09-20-tracks) and [creation](2026-09-20-creation) |
| Initial migration and video pipeline | [2026-09-19](2026-09-19) and [optimized](2026-09-19-optimized) |

The latest recorded export timing comparison is the retained-rendering experiment
(`4b2ae74` → `8357a35`). Its warmed 500-shape MP4 fixture, 90 frames at 720p/30 fps,
fell from **387.7 [382.5–395.2] ms to 342.0 [336.6–342.6] ms** (median [min–max]).
It used one warmup and three measured runs, fresh painter/encoder resources,
Chromium/SwiftShader on the same WSL2 machine with CPUs 0–15, and CDP profiling.
Other host activity was not isolated. It excludes source audio/video, module
loading and download handling; every
output's packet count and first decoded frame were checked. This is an engine
fixture, not a prediction for a user's video. See [export before](2026-09-20-retained-rendering/export-before.json)
and [after](2026-09-20-retained-rendering/export-after.json).

## Reproduce the measurements

Build once, then freeze sources and generated artifacts. Run workloads
sequentially, without other builds/tests/encoders. Default outputs go to ignored
`test-results/`; use distinct files for repeated runs. Historical comparisons
require the matching source revision and harness, not just today's scripts.

```sh
# Repository root: current MoonBit CPU suites in three fresh processes each
pnpm build
pnpm bench --runs 3 --output test-results/benchmarks/cpu.json

# Terminal 1, from the repository root: isolated production host
cd apps/studio
PORT=5188 NODE_ENV=production OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-perf \
  node server/index.js
```

```sh
# Terminal 2, from apps/studio; run each command to completion
pnpm exec playwright install chromium
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-home.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-editor.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-startup.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-interaction.mjs
node scripts/measure-bundle.mjs
```

`POIETRA_PERF_OUTPUT` selects a browser measurement's JSON file.
`measure-home` defaults to five runs per locale, `measure-startup` to three cold
runs (`POIETRA_PERF_RUNS`); `measure-editor` uses 30 inputs per scenario
(`POIETRA_PERF_SAMPLES`). Match affinity explicitly when comparing historical
runs: latest shared-linking results used CPUs 0–15; some earlier experiments used
measurement CPUs 0–3 and server CPUs 4–5.

Renderer/export harnesses import source modules through a **development** host
using the same release MoonBit artifacts. Keep this separate from startup runs:

```sh
# Terminal 1, apps/studio: stop the production measurement host first
PORT=5189 OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-render node server/index.js
```

```sh
# Terminal 2, apps/studio
node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5189 --frames 60 \
  --output test-results/benchmarks/rendering-1.json
POIETRA_BENCH_URL=http://127.0.0.1:5189 node scripts/benchmark-export.mjs
POIETRA_PERF_URL=http://127.0.0.1:5189 node scripts/measure-subscriptions.mjs
POIETRA_PERF_URL=http://127.0.0.1:5189 node scripts/measure-document-updates.mjs
```

Rendering video fixtures require FFmpeg/libx264 (`--skip-video` omits them).
Export uses `POIETRA_BENCH_RUNS` and `POIETRA_BENCH_OUTPUT`. Subscription/document
probes count development StrictMode invocations, including retries and diagnostic
overhead; they are not production timing or FPS measurements.

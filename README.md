# Poietra

**Make motion together, with friends and AI.**

Poietra is a collaborative motion editor that runs in the browser. Arrange shapes,
text, equations, images and video; animate their properties; mix audio; and export
MP4 or WebM. Everyone edits the same structured project, including the AI assistant.
Its changes remain editable and can be undone.

![Poietra's studio, with a canvas, timeline, properties and shared chat](apps/studio/docs/assets/studio.png)

[日本語の使い方・設定](apps/studio/README.md) · [Performance](#performance) ·
[Checks](#checks) · [Issues](https://github.com/Poietra/poietra/issues)

This is the **MoonBit implementation** of the original
[Poietra hackathon application](https://github.com/Poietra/poietra-hackathon).
Application logic—including the UI, collaboration, rendering, media, AI and
servers—is written in typed MoonBit. The numerical motion kernel targets
WebAssembly; browser and server packages target JavaScript. Native adapters retain
React/Base UI, Yjs, MathJax, Mediabunny, OpenAI and platform APIs. Rust is needed
only to rebuild the historical comparison oracle, not to run or build this app.
There are no executable `.ts` or `.tsx` files in `src`, `shared`, `server` or
`worker`. Public `.d.ts` contracts and TypeScript tests/tooling remain; native JS
entry points run without a TypeScript loader.

The rewrite is verified locally and in CI. **It has not been deployed to
poietra.com**; that domain belongs to the original service.

## What you can make

- Share a room link and edit together, with presence, offline reconnection and
  Undo scoped to your own edits.
- Compose circles, rectangles, text, LaTeX, Bézier paths, arrows, number lines,
  images and video. Align or group objects and edit their geometry.
- Set a separate start, duration and easing for position, opacity and other
  properties. Use Move, Write, Fade, Grow and Cut, including custom Bézier easing.
- Import audio/video, trim clips, adjust volume and preview the same timeline
  used for export. Save a portable project file with its media embedded.
- Ask `@codex` in shared chat for structured edits or generated image assets.
  Apply a proposal manually or send with Ctrl/⌘+Enter to apply after validation.
- Optionally sign in with Google or GitHub to keep a private project list.
  Guest editing through a shared link still works.

A **Scene** owns the canvas and object identities. A **Composition** is a still
state with a hold duration. A **Transition** animates between adjacent
Compositions; changing a state in one Composition does not change another.

## Run locally

Use Node.js **24+** (tested: 24.13.0), pnpm **10.23.0**, Python **3.12+** for
adapter generation, and the exact MoonBit version in [.moon-version](.moon-version)
(`moonc v0.10.13+cbb11c36f`).

```sh
git clone https://github.com/Poietra/poietra.git
cd poietra
pnpm install --frozen-lockfile

curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moonbit.sh
bash /tmp/install-moonbit.sh "$(cat .moon-version)"
export PATH="$HOME/.moon/bin:$PATH"
node scripts/moon.mjs update

pnpm dev
```

Open **http://localhost:5173**. Editing, collaboration, media and export work
without an API key. Optional AI/OAuth settings belong in `apps/studio/.env`;
see the [configuration guide](apps/studio/README.md#設定).
The Node host saves data under `apps/studio/.data` by default.

```sh
pnpm build                     # MoonBit JS/WASM, types, Vite, localized HTML/Markdown
pnpm --dir apps/studio start    # serve the production build locally
pnpm test                      # build, extension test, regression/differential tests
pnpm typecheck
node scripts/moon.mjs check --target js --deny-warn
```

`node scripts/moon.mjs` selects `POIETRA_MOON`, then `.tools/moon/bin/moon`, then
`moon` on PATH. Rebuild with `pnpm build:moonbit` after editing `.mbt` files;
Vite's native source watching does not compile MoonBit.

## How it is built

| Layer | MoonBit packages | Responsibility |
| --- | --- | --- |
| Pure model and engine | `scene`, `motion`, `geometry`, `render`, `audio`, `exporting`, `editor`, `proposal_plan` | Typed documents, prepared playback, geometry, SVG, PCM mixing, edit/export plans |
| Collaboration | `collaboration`, `boundary`, `browser_editor`, `browser_undo`, `browser_chat` | Field-level Yjs edits, immutable snapshots, selective Undo and chat |
| Browser | `ui`, `browser_render`, `browser_media`, `browser_export`, `browser_projects`, `browser_kernel` | React components, resource ownership, Canvas/WebGL2, decoding, export and file transfer |
| Services | `schemas`, `proposals`, `ai_service`, `auth_policy`, `auth_service` | Validated AI operations, bounded requests, OAuth and private project indexes |
| Hosts and storage | `node_server`, `node_rooms`, `node_assets`, `node_auth`, `worker_server`, `worker_room`, `worker_assets`, `worker_accounts`, `room_assets`, `r2_upload`, `http_policy`, `http_runtime` | HTTP/WebSockets, persistence, quotas, streaming uploads and atomic publication |
| Public site | `site`, `site_shell`, `site_boundary`, `browser_site`, `site_build` | English/Japanese content, lazy editor entry, prerendering and content negotiation |

The implementation lives in [moonbit/](moonbit/). [apps/studio/](apps/studio/)
contains native adapters, styles, assets and regression tests. Generated release
modules go to `_build/`; `scripts/generate-adapters.py` generates representation
adapters and public record types from the typed model. `scripts/bindings.json`
generates 32 simple JS facades. Wrangler environment types are generated under
ignored `.wrangler/`, rather than committed as 15,408 lines of application source.
Historical TypeScript/Rust implementations in
[tests/oracle/](apps/studio/tests/oracle/) are used only for comparison.

The rewrite changes the data flow as well as the language:

- **Prepare once, evaluate repeatedly.** Typed `Hold`/`Change` programs resolve
  tracks, object matches, layer order and colors before playback. Seeking uses a
  binary search. Preview and export share the evaluator.
- **Share unchanged data.** Yjs reads reuse immutable branches and invalidate
  touched branches before observers run. Presence/chat updates retain unchanged
  Scene identities; a one-field proposal reads only the state it needs.
- **Own asynchronous work.** Renderers, decoders, imports and AI requests have
  explicit lifetimes. Stale completions cannot publish into a replacement view;
  cancellation releases resources. Uploads use bounded buffers and backpressure.
- **Keep video frames as pixels.** A bounded decoder cursor follows actual
  source timestamps, including variable frame intervals. Canvas painting bypasses
  PNG/SVG conversion; shared-source objects retain independent owned frames.
  Seeking resets the cursor and GPU failure retains the portable SVG path.
  Media parsers/codecs load on demand, outside the editor's static entry graph.
  This uses Mediabunny 1.56.2's
  [sequential canvas iterator](https://mediabunny.dev/guide/reading-media-files),
  with explicit ownership and cancellation around the host binding.
- **Preserve edit intent.** Commands write only changed fields. Guarded proposals
  validate the complete batch before publication. Pending Yjs dependencies are
  persisted even when they have not yet produced a visible document change.

Upstream packages were selected by source review and compatibility tests:
[mizchi/js.mbt](https://github.com/mizchi/js.mbt) **0.13.0** supplies host bindings;
[mizchi/npm_typed.mbt](https://github.com/mizchi/npm_typed.mbt) **0.1.16** supplies
React/Zod bindings; [mizchi/cloudflare.mbt](https://github.com/mizchi/cloudflare.mbt/tree/575da27df27e0342813143ed17cce470960fbf73)
**0.1.12** supplies selected SQLite and R2 types. Native Promise bindings bridge
R2 into the application's request lifetimes, and alarm timestamps use `Double`.

Other reviewed libraries—including Luna, gfx, converge, audio-mbt and MoonBit
OpenAI clients—are not dependencies. Yjs retains the nested-map/selective-Undo
contract; the official OpenAI SDK retains Responses and Images support. The
[gfx source](https://github.com/mizchi/gfx-mbt/tree/1aec97a83ab1e7d0c924c400f0e5494f8ac3c1ca)
informed the separation between the pure Glow program and its browser driver.

## Add a feature

1. Define data and behavior in the appropriate typed MoonBit package. Document
   fields belong in `moonbit/scene/model.mbt`; kind variants and names belong in
   `moonbit/scene/kinds.mbt`. `pnpm build:moonbit` regenerates JS marshalling and
   `apps/studio/shared/scene-types.d.ts`. Unknown representations fail generation.
2. Implement validation, commands, evaluation/rendering and UI where the feature
   needs them. A generated record does not automatically gain UI, persistence
   validation or animation semantics. Use compiler errors and regression tests
   to find affected constructors and exhaustive matches; keep old files readable.
3. Export host-facing operations in the package's `moon.pkg`. Add a precise
   adjacent `.d.ts` contract and, for direct forwarding, a `scripts/bindings.json`
   entry. Native JS should only register platform objects, import assets or wire
   dependencies. Editor components and orchestration belong in `moonbit/ui`.
4. Run `pnpm test`, `pnpm typecheck` and the relevant browser/runtime checks.
   `pnpm test:extensions` actually adds a nested optional record and callable API
   in an isolated copy, builds it, round-trips values through generated JS and
   compiles a consumer that rejects incorrect field types. The API gate checks
   108 captured modules in both directions while permitting additional exports.

Rebuild `.mbt` changes while the dev server is running with `pnpm build:moonbit`.
Performance runs require a completed build and frozen sources. For a new external
API, check existing mizchi bindings before adding a narrow native boundary.

## Performance

Remeasured **2026-09-19**. The new video pipeline reduced the median 720p/30 Hz
painting time from **53.0 to 12.8 ms (4.1×)** in the software-GPU workload below.
Deferring media libraries reduced the editor's static JavaScript by **19.7% raw**
and **18.2% gzip**. Shape-only editing did not show an improvement in this run.

Application changes are at
[`b29ee2a`](https://github.com/Poietra/poietra/commit/b29ee2a21caa399b3f2b7fd8bf85c27f32d9b4af).
[All new results](benchmarks/2026-09-19-optimized/) record the exact checkout,
samples, toolchain, machine and WASM hashes. The renderer uses the sample-capture
fix at [`2c71303`](https://github.com/Poietra/poietra/commit/2c7130310336ce08f3f0d45cc8ef1e9170f73fd3);
the application artifacts are unchanged. [Previous results](benchmarks/2026-09-19/)
from `0602d6b` are retained for the video/payload comparison.

Measurements ran sequentially with frozen sources and artifacts, without local
builds, tests or other encoders. Hardware: Intel Core Ultra 7 255H, 16 logical
CPUs, 31.1 GiB RAM, Linux x64 under WSL2. Benchmark processes used CPUs `0-3`;
servers used `4-5`. Other host activity was not isolated. Node was 24.13.0;
headless Chromium was 153.0.8010.12.

### CPU comparisons

These compare the original TypeScript/Rust algorithms against prepared MoonBit
implementations, including architectural changes. Each suite ran in **three fresh
Node processes**, each warming up and alternating old/new for seven batches.
Tables use the median of process medians; speedup is their ratio. Units are ms.

**Scene evaluation** — 240 frames/batch, two Compositions and a Transition.
Baseline: pinned TypeScript evaluator and Rust WASM. Rewrite: prepared MoonBit
playback and MoonBit WASM. Preparation is measured separately with seven compile
calls/process; it is not first-use browser startup latency.

| Objects | Easing | Baseline / frame | MoonBit / frame | Speedup | Preparation |
| ---: | --- | ---: | ---: | ---: | ---: |
| 10 | Preset | 0.02753 | 0.00471 | 5.8× | 0.229 |
| 100 | Preset | 0.20739 | 0.02242 | 9.2× | 0.986 |
| 500 | Preset | 1.11129 | 0.13249 | 8.4× | 2.429 |
| 10 | Custom Bézier | 0.02391 | 0.00404 | 5.9× | 0.066 |
| 100 | Custom Bézier | 0.23300 | 0.03830 | 6.1× | 0.506 |
| 500 | Custom Bézier | 1.18585 | 0.20165 | 5.9× | 2.512 |

At 500 objects/preset easing, MoonBit process medians ranged from
**0.13101–0.14502 ms/frame**. This excludes drawing,
decoding, encoding, UI and networking; these are not browser FPS.

**Snapshots** — one Yjs leaf edit plus a complete project read; three Scenes,
five Compositions/Scene, 50 edits/batch. Baseline: `toJSON()` and the pinned
structural projection. MoonBit: immutable snapshots with branch reuse.

| Objects / Scene | Baseline / edit + read | MoonBit / edit + read | Speedup |
| ---: | ---: | ---: | ---: |
| 100 | 1.6438 | 0.06565 | 25.0× |
| 500 | 9.8254 | 0.21039 | 46.7× |

**AI proposal compilation** — one existing object's `x` edit, including guards
and preflight, from an already-read snapshot; ten compilations/batch. Baseline:
retained TypeScript compiler from `afbd6b3`, using current shared bindings. This
excludes model calls, image generation, networking and applying edits.

| Objects | Compositions | Baseline / proposal | MoonBit / proposal | Speedup |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 10 | 1.9389 | 0.24037 | 8.1× |
| 500 | 10 | 8.3654 | 0.27324 | 30.6× |
| 500 | 40 | 37.0487 | 0.60375 | 61.4× |

### Browser editing and loading

The **production UI** used 2/4 isolated contexts sharing one local Node room,
with one Composition and 100/500 circles. After three warmup nudges, 30 trusted
ArrowRight inputs were timed from `keydown` to the matching stage transform plus
two animation-frame callbacks. The peer column selects the slowest peer per input.
[Raw editor results](benchmarks/2026-09-19-optimized/editor.json).

| Objects | Participants | Local p50 / p95 | Slowest peer p50 / p95 |
| ---: | ---: | ---: | ---: |
| 100 | 2 | 27.9 / 39.4 ms | 29.5 / 45.6 ms |
| 100 | 4 | 38.2 / 45.1 ms | 42.7 / 57.3 ms |
| 500 | 2 | 70.9 / 98.9 ms | 71.2 / 92.5 ms |
| 500 | 4 | 87.0 / 149.1 ms | 91.6 / 130.3 ms |

This is a **presentation opportunity**, not physical display latency or field INP.
All participants share one machine/browser process, without artificial network
or CPU slowdown. The 500-object/four-participant local p95 rose from **95.2 to
149.1 ms** compared with the previous run. Shape-only drawing was also slower
in the table below. These measurements do not establish the cause; this update
has not demonstrated faster editing of large shape-only scenes. WAN latency,
workerd performance and long-session memory growth remain unmeasured.

The **production homepage** was loaded five times/locale in new contexts with
cache disabled, a 390×844 viewport, CDP CPU slowdown ×4, configured latency
150 ms and download throughput 200,000 bytes/s. Medians, with LCP min–max in
parentheses; [raw page results](benchmarks/2026-09-19-optimized/home.json).

| Locale | FCP | LCP | CLS | Observed long-task blocking |
| --- | ---: | ---: | ---: | ---: |
| English | 788 ms | 1,724 ms (1,724–1,724) | 0.00019 | 39 ms |
| Japanese | 884 ms | 1,792 ms (1,784–1,800) | 0.00097 | 135 ms |

Observation ends after network idle, font readiness and two animation frames.
Blocking sums `max(0, duration − 50 ms)` across observed long tasks; it is **not
Lighthouse TBT**. The local server served uncompressed assets. Homepage visits
loaded no editor/WASM and opened no collaboration socket. These are local lab
measurements, not production field data or evidence of a homepage speedup.

### Rendering and payload

Three fresh Chromium runs used **SwiftShader** (software GPU), release MoonBit
modules served by Vite, and a 1280×720 canvas. Shape workloads move one object
and include cloning plus `painter.render` (30 samples/run). Video workloads call
the real painter, including its owned media preparation, for 60 timestamps/run
after warmup. These are **unpaced component measurements**, without a GPU
completion fence or physical-display measurement. Previous/current p50 columns
are the medians of the three run p50s.

| Scenario | Previous p50 | Current p50 | Current run p50 range | Current run p95 range |
| --- | ---: | ---: | ---: | ---: |
| Move/paint, 100 circles | 3.1 ms | 3.7 ms | 3.6–4.2 ms | 11.2–13.3 ms |
| Move/paint, 500 circles | 7.0 ms | 8.1 ms | 7.9–8.6 ms | 17.3–19.4 ms |
| 720p video, timestamps at 30 Hz | 53.0 ms | 12.8 ms | 12.7–13.7 ms | 18.1–22.3 ms |
| Same 30 fps source, timestamps at 60 Hz | 48.1 ms | 9.1 ms | 5.8–10.6 ms | 15.2–18.2 ms |
| Video, alternating two still timestamps | 47.5 ms | 43.6 ms | 41.8–44.2 ms | 56.0–63.9 ms |

All final runs are retained: [run 1](benchmarks/2026-09-19-optimized/rendering-1.json),
[run 2](benchmarks/2026-09-19-optimized/rendering-2.json),
[run 3](benchmarks/2026-09-19-optimized/rendering-3.json). The 60 Hz scenario mixes
reused source frames with newly decoded frames, so its p50 varies across that
boundary. These results do not predict playback FPS on a hardware GPU.

The previous sequential scenarios made 60 `CanvasSink.getCanvas` calls and
60 PNG conversions per 60 timestamps. The new WebGL2 painting path made **zero**
random-frame requests and **zero PNG conversions**; it used 59 iterator reads at
30 Hz and 29 at 60 Hz after warmup. Iterator reads include lookahead/EOF, not just
new pictures. `marks.decode` times complete `getCanvas` calls and
`marks.sequentialDecode` times complete iterator `next()` calls; neither isolates
the codec. Seeking still resets the cursor, explaining the smaller gain for
alternating still frames. Canvas pixels are copied into owned surfaces before a
shared source advances, and the portable SVG fallback remains available.

The old recorder retained references to mutable decoder-mark sample arrays;
some old arrays include later work after the first `n` samples. Its captured
counts/summaries and painter samples were unaffected. The new recorder snapshots
arrays before proceeding, and retained sample counts/sums have been checked.

Production JavaScript sizes, including static imports:

| Entry | Raw | gzip level 9 | Brotli |
| --- | ---: | ---: | ---: |
| Homepage, including its selected entry | 290,332 B | 91,053 B | 78,434 B |
| Editor bootstrap | 2,027,223 B | 560,586 B | 424,495 B |

Editor static JS fell from **2,524,629 to 2,027,223 B**; gzip fell from **685,047
to 560,586 B**. Mediabunny loads when media/export needs it and remains part of the
full application. The static group excludes dynamic media/MathJax/font modules,
CSS, fonts and user media. Compression is calculated per file, not measured
network transfer. [Bundle inventory](benchmarks/2026-09-19-optimized/bundle.json)
records every emitted JS file and the motion WASM.

### Reproduce the measurements

Build once. Stop other builds, tests and encoders before measuring; keep source
and generated artifacts unchanged for the whole run. Results normally go under
ignored `test-results/` so a local run does not overwrite published evidence.

```sh
# Repository root: CPU comparison, three fresh processes per suite
pnpm build
pnpm bench --runs 3 --output test-results/benchmarks/cpu.json

# Terminal 1: isolated production host, no real API calls
cd apps/studio
PORT=5188 NODE_ENV=production OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-perf \
  node server/index.js
```

```sh
# Terminal 2, apps/studio; run each command to completion
pnpm exec playwright install chromium
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-home.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-editor.mjs
node scripts/measure-bundle.mjs
```

`measure-home` defaults to five runs/locale (`POIETRA_PERF_RUNS`);
`measure-editor` defaults to 30 inputs/scenario (`POIETRA_PERF_SAMPLES`) and creates
fresh local rooms. `POIETRA_PERF_OUTPUT` selects each output file. On Linux, prefix
measurement commands with `taskset -c 0-3` and the host with `taskset -c 4-5` to
match the recorded CPU affinity; choose CPUs available on your machine.

The renderer harness imports source modules from a separate Vite development
host, backed by the same release MoonBit artifacts. It requires FFmpeg/libx264
for its generated 720p clip; `--skip-video` omits those scenarios.

```sh
# apps/studio, separate terminal
PORT=5189 OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-render node server/index.js
# apps/studio, measurement terminal; repeat three times with distinct outputs
node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5189 --frames 60 \
  --output test-results/benchmarks/rendering-1.json
```

## Checks

The [completed implementation CI run](https://github.com/Poietra/poietra/actions/runs/35416192419)
passed 642 Vitest regression/differential tests, 15 MoonBit JS tests, four MoonBit
WASM tests, 154 main browser checks, six media/export checks and 25 production-page
checks. It also verified a newly generated feature/API, 108 captured public API
contracts, and actual Node/workerd persistence, hibernation, restart, R2
migration/fault/quota and account/TTL integrations. The
[workflow](.github/workflows/check.yml) is the authoritative command selection.

```sh
# Repository root
pnpm test
node scripts/moon.mjs test --target js
node scripts/moon.mjs test --target wasm moonbit/motion moonbit/proposal_plan
pnpm build

# apps/studio: browser and local runtime checks
cd apps/studio
pnpm exec playwright install chromium
pnpm test:e2e
pnpm exec playwright test --config tests/e2e/media-export.config.ts
pnpm exec playwright test --config tests/e2e/site-production.config.ts
node tests/collaboration-worker.integration.mjs --port 8796
node tests/media-storage.integration.mjs node
node tests/r2-assets-worker.integration.mjs
node tests/accounts-worker.integration.mjs
```

Video checks need FFmpeg/ffprobe. Set `POIETRA_TEST_URL` to test an existing isolated
server; otherwise Playwright starts its configured host. API/OAuth responses are
simulated in automated tests. Live Google/GitHub registration and paid OpenAI
requests have **not** been validated for this rewrite.

## Deployment and limits

The Node host uses local persistence. The Cloudflare host uses Static Assets,
room/account SQLite Durable Objects and a private R2 media bucket. Try it locally
with `pnpm --dir apps/studio dev:worker` after building.
`pnpm --dir apps/studio run deploy` currently performs **only a dry-run bundle**.

Before any real deployment, choose an account/origin, review the copied account ID,
OAuth settings, generated canonical URLs and storage names. The configuration has
independent `poietra-moonbit` Worker/bucket names and no production domain route;
its SEO origin still points at the original service. Do not reuse production
storage to validate the rewrite.

Desktop Chromium is the primary tested browser. Codec availability depends on
the browser/device; MP4 audio requires AAC encoding, while WebM uses Opus. The
portable format permits 500 objects and 100 Compositions per Scene. Images are
normalized to at most 2,048 px on the long edge and 1 MiB; room image storage is
64 MiB. Audio/video limits are 32 MiB/file, ten minutes/source and 128 MiB/room.
See the [user guide](apps/studio/README.md) for editing, export and other limits.

The public rewrite started from `poietra-hackathon` commit
`3f49040ee4bcf06bfcf02e269712833f3729c536`, at the founder's request on 2026-09-18.
The separate private design archive was not imported. The original
[hackathon application](apps/studio/docs/hackathon-application.md) is retained as
historical material; current implementation details live in these READMEs.

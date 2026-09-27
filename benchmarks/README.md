# Measurements

[Project overview](../README.md) · [Development and checks](../docs/development.md)

This is an index of raw evidence and the commands used to collect new samples.
Each dataset records its revision, environment and workload. Historical tables,
analysis and rejected experiments remain in the
[guide at 99c2dbd](https://github.com/Poietra/poietra/blob/99c2dbdb5c35361eec5b505bd369bd81b43fe430/benchmarks/README.md).
Use its matching source and harness revisions when reproducing an old comparison.

## Reproduce the measurements

Build once, then freeze source and generated artifacts. Run each workload to
completion without concurrent builds, tests or encoders. Record compiler/runtime,
browser, hardware, affinity, warmup, samples and exclusions with raw results.
Compare like workloads and report variation. Local CPU, SwiftShader and protocol
client results do not establish device FPS or WAN performance.

```sh
# Repository root; --help lists suites, --suite selects one
pnpm build
pnpm bench --runs 3 --output test-results/benchmarks/cpu.json

# Terminal 1: isolated production host
cd apps/studio
PORT=5188 NODE_ENV=production OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-perf \
  node server/index.js
```

From `apps/studio` in another terminal, run one probe at a time:

```sh
pnpm exec playwright install chromium
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-editor.mjs
```

| Question | Probe in `apps/studio/scripts/` |
| --- | --- |
| Delivered bundle / home / startup | `measure-bundle.mjs`, `measure-home.mjs`, `measure-startup.mjs` |
| Editor input, dragging, import, project playback | `measure-editor.mjs`, `measure-interaction.mjs`, `measure-project-import.mjs`, `measure-project-preview.mjs` |
| Prepared playback and retained editing heap (no server) | `benchmark-playback.mjs`, `benchmark-edit-heap.mjs` |
| Rendering and export through a development host | `benchmark-rendering.mjs`, `benchmark-export.mjs` |
| React subscription/document invalidation through a development host | `measure-subscriptions.mjs`, `measure-document-updates.mjs` |

`POIETRA_PERF_OUTPUT` selects the browser JSON output. Home defaults to five runs
per locale; startup uses three (`POIETRA_PERF_RUNS`). Editor uses 30 inputs per
scenario (`POIETRA_PERF_SAMPLES`). Use distinct files for repeat runs.

Renderer/export and subscription probes need a **development** host to import
source modules. Stop the production measurement host first, keep release MoonBit
artifacts frozen, then run from `apps/studio` in separate terminals:

```sh
PORT=5189 OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-render node server/index.js
# Another terminal, after the host is ready:
node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5189 --frames 60 \
  --output test-results/benchmarks/rendering-1.json
POIETRA_BENCH_URL=http://127.0.0.1:5189 node scripts/benchmark-export.mjs
```

Video fixtures require FFmpeg/libx264 (`--skip-video` omits them). Export accepts
`POIETRA_BENCH_RUNS` and `POIETRA_BENCH_OUTPUT`. Subscription/document probes use
`POIETRA_PERF_URL`; their StrictMode invocation counts are not production timings.
Headless probes run without a server from the root:
`node scripts/benchmark-headless.mjs` and `node scripts/benchmark-headless-heap.mjs`.

## CI latency — 2026-09-27

| Recorded sample | Serial | Split |
| --- | ---: | ---: |
| Creation to completion, including setup/queueing | 12m17s | 4m29s |
| Sum of job durations, before billing rounding | 12m13s | 22m26s |
| Browser cases included | 233 | 248 |

Evidence: [before](2026-09-27-ci/before.json), [after](2026-09-27-ci/after.json).
One successful sample per layout; same application and pinned toolchain/runner
image, restored caches, no dedicated warmup/affinity. Split CI adds 18 previously
omitted cases and consolidates three. This trades more runner time for less wait;
it does not measure application speed or per-test CPU savings.

## Rendering, import and retained memory — 2026-09-27

These datasets contain workload-specific comparisons, including exploratory and
rejected changes. Directory dates alone do not identify a common baseline;
consult each report's revision and the archived analysis before comparing values.

| Raw dataset | Focus |
| --- | --- |
| [asset-validation](2026-09-27-asset-validation/) | Media validation |
| [compiled-ownership](2026-09-27-compiled-ownership/) | Compiled program retention |
| [cubic-geometry](2026-09-27-cubic-geometry/) | Rejected geometry experiment |
| [curve-preparation](2026-09-27-curve-preparation/) | Animation curves |
| [evaluated-pose](2026-09-27-evaluated-pose/) | Pose evaluation |
| [export-capture](2026-09-27-export-capture/) | Export input ownership |
| [headless-ownership](2026-09-27-headless-ownership/) | Headless retained memory |
| [immutable-poses](2026-09-27-immutable-poses/) | Shared immutable poses |
| [indexed-compositions](2026-09-27-indexed-compositions/) | Composition lookup |
| [indexed-hierarchy](2026-09-27-indexed-hierarchy/) | Parent lookup |
| [json-key-scan](2026-09-27-json-key-scan/) | Portable-file key scanning |
| [media-editing](2026-09-27-media-editing/) | Media command plans |
| [parent-interaction](2026-09-27-parent-interaction/) | Parented dragging |
| [playback-hit-surface](2026-09-27-playback-hit-surface/) | Playback SVG updates |
| [playback-ownership](2026-09-27-playback-ownership/) | Preparation memory |
| [preview-drafts](2026-09-27-preview-drafts/) | Drag previews |
| [project-holds](2026-09-27-project-holds/) | Static hold reuse |
| [project-import](2026-09-27-project-import/) | Browser import |
| [project-parsing](2026-09-27-project-parsing/) | Portable-file parsing |
| [project-preview](2026-09-27-project-preview/) | Whole-project playback |
| [raster-tickets](2026-09-27-raster-tickets/) | Prepared raster ownership |
| [render-view](2026-09-27-render-view/) | Typed render views |
| [shared-scene-layout](2026-09-27-shared-scene-layout/) | Shared scene structure |
| [shared-state-view](2026-09-27-shared-state-view/) | Shared editing snapshots |
| [stage-props](2026-09-27-stage-props/) | Stage properties, including rejected trial |
| [svg-escaping](2026-09-27-svg-escaping/) | SVG serialization |
| [svg-image-drag](2026-09-27-svg-image-drag/) | Image drag rendering |
| [timeline-projection](2026-09-27-timeline-projection/) | Timeline preparation |
| [typed-frames](2026-09-27-typed-frames/) | Typed evaluated frames |
| [typed-raster](2026-09-27-typed-raster/) | Raster boundary |

## Same-room collaboration — 2026-09-22

[Raw collaboration results](2026-09-22-collaboration/) include local workerd,
protocol clients and a one-browser variant. These are not 500 active browsers;
generator saturation and WAN/production limits are discussed in the archived guide.
To repeat the workload, build/freeze first and run from `apps/studio` with port
8796 unused:

```sh
pnpm exec wrangler deploy --dry-run --outdir /tmp/poietra-collaboration-bundle
node tests/collaboration-load.integration.mjs \
  --bundle /tmp/poietra-collaboration-bundle/index.js --owned-presence \
  --clients 500 --generators 8 --seconds 60 --edit-hz 1 --presence-hz 1 \
  --output /tmp/poietra-collaboration-500.json
```

Add `--browser` to include one real browser among the participants.

## Headless export — 2026-09-21

[Raw export results](2026-09-21-headless/) cover the standalone WASM backend.
New runs use `scripts/benchmark-headless.mjs` after building, without Chromium or
FFmpeg. Do not compare its throughput directly with browser hardware encoders.

## Earlier measurement evidence

| Raw dataset | Focus |
| --- | --- |
| [Initial](2026-09-19/), [optimized](2026-09-19-optimized/) | Early implementation baseline |
| [Client linking](2026-09-20-client-linking/), [startup](2026-09-20-startup/) | Bundle loading and startup |
| [Creation](2026-09-20-creation/), [editing](2026-09-20-editing/), [primitives](2026-09-20-primitives/) | Pure plans and evaluation |
| [Timing](2026-09-20-timing/), [tracks](2026-09-20-tracks/) | Animation commands |
| [Document updates](2026-09-20-document-updates/), [subscriptions](2026-09-20-ui-subscriptions/) | UI invalidation |
| [Interaction](2026-09-20-interaction/), [retained rendering](2026-09-20-retained-rendering/) | Dragging, drawing and export |

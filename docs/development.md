# Development and verification

[Project overview and setup](../README.md#run-locally) · [Architecture](architecture.md) · [Measurements](../benchmarks/README.md)

[Commands](#commands) · [Add a feature](#add-a-feature) ·
[Checks](#checks) · [Deployment and limits](#deployment-and-limits)

## Commands

Run these commands from the **repository root**:

| Command | Purpose |
| --- | --- |
| `pnpm dev` | Build MoonBit and start the Node/Vite development host on port 5173 |
| `pnpm build:moonbit` | Regenerate adapters and facades; build release JS and motion WASM |
| `pnpm build` | Build MoonBit, check types, bundle the editor and prerender EN/JA HTML/Markdown |
| `pnpm --dir apps/studio start` | Serve the completed production build with Node |
| `pnpm test` | Audit sources, build, run extension/API build tests and Vitest |
| `pnpm test:render` | Check headless rendering, independent decoding, HTTP and MCP after building |
| `pnpm render INPUT --format mp4 -o OUTPUT` | Render a portable file without a browser or FFmpeg |
| `pnpm render:api` / `pnpm render:mcp` | Start the local HTTP API / stdio MCP server |
| `pnpm typecheck` | Check declarations and captured public API contracts |
| `pnpm audit:source` | Report source inventory and reject executable application TS/TSX |

After editing `.mbt`, run `pnpm build:moonbit`: Vite does not compile MoonBit.
Restart the Node host after server-side changes. The wrapper
`node scripts/moon.mjs` selects `POIETRA_MOON`, then `.tools/moon/bin/moon`, then
`moon` on PATH. Use it for `update`, `check`, `test` and `version --all` so local
commands use the same toolchain as the build.

## Add a feature

1. Define domain data in `moonbit/scene/model.mbt` and kinds in
   `moonbit/scene/kinds.mbt`. Put pure edit decisions in `editor` and shared
   evaluation in `scene`/`motion`; keep React, Yjs and platform objects at the host
   boundary. Read the applicable [implementation](../AGENTS.md) and
   [product rules](../apps/studio/AGENTS.md).
2. Implement validation, persistence compatibility, commands, evaluation,
   rendering and UI as needed. Generated record types do not implement these
   behaviors. Object creation, clipboard and media imports share
   `editor.ObjectInsertion`; Scene/Composition defaults use `scene/creation`, with
   limits and creation decisions in `editor/structure_commands`.
3. Preserve collaboration intent. Property channels share enumeration/lookup in
   `scene/editing`; typed plans identify changed leaves. Retain existing Yjs
   timing parents. Validate all targets and encode detached values before any
   write: a Yjs transaction cannot roll back earlier writes when conversion fails.
4. Export host-facing functions in the package's `moon.pkg`, with a precise
   adjacent `.d.ts` contract and a `scripts/bindings.json` entry for direct
   forwarding. Run `pnpm build:moonbit` to regenerate adapters/facades/shared
   exports. Check existing mizchi bindings before adding a native API boundary.
5. Run `pnpm test`, `pnpm typecheck`, pure-core tests on JS/WASM, and the
   [relevant browser/runtime checks](#checks). Verify preview/export agreement,
   offline edits and selective Undo for changes that affect those behaviors.

`pnpm test:extensions` adds a nested optional record and callable API in an
isolated copy, regenerates and compiles them, checks standalone/shared-runtime
calls and rejects incorrect TypeScript consumer fields. The contract gate checks
108 captured public modules while allowing new exports; shared-runtime tests
compare 221 function exports and their arity.

For a headless backend, implement `render_job.Backend` using the contracts in
`media_pipeline`; keep native conversions in its adapter. New formats belong in
`render_job.Format` and its exhaustive matches. Add media contracts only when a
consumer needs them, and preserve the standalone JS/WASM compilation test.

## Checks

Test layout revision `a26550d` passed the complete
[CI run 36308337905](https://github.com/Poietra/poietra/actions/runs/36308337905)
on **2026-09-27**: 818 Vitest checks, 66 MoonBit JS checks, 63 WASM checks,
five extension/linking checks, 20 headless API/MCP checks and 248 browser cases.
Generated bindings, warning-free MoonBit types, public TypeScript contracts,
the production build and real Node/workerd persistence, collaboration and account
restart checks passed. This verifies the application at `db4865f` with revised
tests/CI; it is not a production deployment.

The test design review on **2026-09-27** found
18 cases selected locally but omitted by CI's command-line filename list. Browser
configs now share [suites.ts](../apps/studio/tests/e2e/suites.ts); `pnpm check:test-suites`
rejects missing, duplicate and unclassified specs, including nested files.
[check.yml](../.github/workflows/check.yml) runs these configs without a second list.

| Boundary being checked | Execution |
| --- | --- |
| Pure plans, parsing, history budgets, Yjs leaf semantics and host contracts | Vitest, MoonBit JS/WASM, extension/linking and headless tests in `core` |
| Real editor gestures, peer edits, offline/Undo and browser lifecycle contracts | `test:e2e`: 196 cases across four CI shards, two workers each |
| Media import, project playback/download, encoded MP4/WebM and browser audio | `test:media-editor`, `test:export`, `test:media`: 8 + 10 + 6 cases, sequential in `media` |
| Built public pages and real persistence/restart behavior | `test:site`: 28 cases, then Node/workerd integration checks in `production` |
| Extended WebGL/Canvas/Write pixel matrices | Opt-in `effects.config.ts`, `effects-write.config.ts`, `glow.config.ts`; retained outside PR CI |
| Rendering timings and SVG source profiles | Separate opt-in measurement specs; run alone on an otherwise idle machine |

The redesign removes duplicate scenarios only where their assertions are retained:
AI Scene cancellation is folded into the stronger return-to-Scene/history case;
synthetic single-object cut/paste is covered by real keyboard group cut/paste,
including Undo/Redo and peer edits. History entry/content limits moved from 19 UI
request/reply cycles to a direct `chatHistory` contract test; browser multi-turn,
retry and proposal-status wiring remain. Composition inheritance and peer Undo
run once through the timeline, with a short sidebar entry/selection check.
The sync-watchdog and held-key tests advance the browser clock instead of waiting
for wall time. Audio-device timing tests still use the real audio clock.

JS/WASM conformance, immutable snapshot identity, independent video decoding and
real process restart tests intentionally remain: they detect failures at different
boundaries. Timing-only rendering cases have separate files/config selection and
do not masquerade as correctness checks. No new retry policy hides failures.
Every CI browser job retains JSON case durations and failure traces for seven
days. The final `check` job retains the existing required-check name and fails
if any suite fails, is cancelled or is unexpectedly skipped.

CI timing and runner-time tradeoffs are recorded in the
[measurement index](../benchmarks/README.md#ci-latency--2026-09-27).

Regressions cover independent parsing, reserved/escaped keys in ignored subtrees,
strict easing, borrowed inputs, raster identity/cancellation and preview/export
agreement. Pure JS/WASM cases preserve retained/hidden text resources, first
ordered Scene dimensions and independent lists when a timeline is reused.
Browser cases include 500-object/six-Composition imports with and without legacy
track initialization, reload and reconnect.

The Node transport tests exercise bounded stalled peers, failed sends, late
callbacks, saved ordered replies (including unresolved Yjs dependencies), malformed
vectors and actual filesystem failures before broadcast/reply. A real Node process
is killed immediately after an ordered reply and restarted from the same isolated
directory: ordinary and unresolved-dependency updates both survive. Those two
regressions fail against the pre-fix `1548c6c` host; no graceful close/dispose or
checkpoint delay is allowed before the kill.

Actual workerd verified offline edits, selective Undo, ordered durable replies,
compaction, hibernation, late closes, process restart and pending dependencies.
The 500-connection regression uses one real editing browser, a protocol observer
and 498 idle sockets. With controlled browser time, 20 actual canvas cursor moves
within one second publish once; 90 pointer moves before advancing the timer update
the local view immediately and flush one document packet at pointer release.
Separate deterministic checks verify timed continuous editing, queue bounds,
page lifecycle writes and chat cancellation on reload. These are packet-count and
correctness checks, not measurements of 500 active browsers or WAN latency.
The [load-test results and generator limitations](../benchmarks/README.md#same-room-collaboration--2026-09-22) are recorded separately.

Node/workerd integrations also passed media persistence, R2 migration and failure
recovery, account isolation, callback races and expiry across Worker restarts.
Account UI tests use mocked authentication responses; the Worker tests exercise
persistent accounts with mocked provider HTTP. They do not verify live OAuth
completion or paid AI calls.

Earlier provider/page verification and targeted regression records remain in
[the previous README](https://github.com/Poietra/poietra/blob/8b95885ce59a9682b19770c7a37f7c55dc4f4375/README.md#checks).
The headless checks decode all
H.264 frames and MP3 samples with independent WASM
decoders, verify timing/trim/gain/mute, exercise HTTP/MCP, oversized requests and
cancellation, and render with subprocess launches and network fetch disabled.
They also verify typed-package isolation, invalid consumer rejection, native
buffer validation, encoder backpressure, single cleanup and error preservation.
CI runs them in a job that does not install Chromium or FFmpeg.

The account/project browser checks cover search/order, failed reads, restoration
retries, identity changes, delayed replies and guest project operations. Sources
and generated output stay frozen during browser verification.

```sh
# Repository root
pnpm test
pnpm test:render
pnpm typecheck
node scripts/moon.mjs check --target js --deny-warn
node scripts/moon.mjs test --target js
node scripts/moon.mjs test --target wasm moonbit/motion moonbit/proposal_plan moonbit/editor moonbit/scene
node scripts/moon.mjs test --target wasm moonbit/render moonbit/exporting moonbit/audio moonbit/media_pipeline moonbit/render_job
pnpm build

# apps/studio
cd apps/studio
pnpm exec playwright install chromium
pnpm test:e2e
pnpm test:media-editor
pnpm test:export
pnpm test:media
pnpm test:site
node tests/collaboration-worker.integration.mjs --port 8796
node tests/media-storage.integration.mjs node
node tests/r2-assets-worker.integration.mjs
node tests/accounts-worker.integration.mjs
```

Browser video checks require FFmpeg/ffprobe; `pnpm test:render` does not.
On Linux, Playwright may also need browser
system dependencies (`pnpm exec playwright install --with-deps chromium`).
Use an isolated local test host: browser tests create and edit rooms. The default
E2E configuration uses port 5173 and may reuse an existing server; set
`POIETRA_TEST_URL` to a dedicated host if that port belongs to your development
session. The production-page configuration serves the completed build separately.

The extended rendering configs remain opt-in as before; they are not counted as
PR CI coverage. `effects.config.ts` now runs correctness only; use
`effects-benchmark.config.ts` for its timings. For the prebuilt Write/Glow fixtures,
`RUN_WRITE_BENCHMARK=1` and `GLOW_BENCHMARK=1` select only measurement specs in their
respective configs; `RUN_SVG_PROFILE=1` selects only the Write source profiler.
Do not run these measurements alongside builds, tests or encoders.

Automated provider HTTP is simulated. Production smoke verified GitHub's
authorization redirect and flow storage; full Google/GitHub login completion and
paid OpenAI calls were not part of this release's verification.

## Deployment and limits

Node persists locally. Cloudflare serves Static Assets, stores room/account state
in SQLite Durable Objects and keeps media bytes in private R2. Default Wrangler
configuration is for isolated `poietra-moonbit` validation. The explicit
`production` environment updates the existing `poietra-hackathon` Worker in
Yumaboda's account, preserving `poietra.com`, old workers.dev links, three Durable
Object namespaces, migration tag `v2-accounts`, secrets and `poietra-assets-prod`.

**Last recorded deployment: 2026-09-22 12:58 JST.** Application `2d76eed`
served at 100% as Worker version `dcd24d3d-45b7-4abe-b4eb-3a274955c841`.
Storage namespaces, secret bindings, variables, rate limits and runtime settings
matched the preceding release, including Static Assets routing and headers.
There was no document/storage migration. The recorded predecessor is
`ed47add7-6904-425e-8eb3-171315450e9e` (application `79531b9`). Confirm the active
version before the next deployment instead of assuming this record is live state.

Verification used a dedicated room: release JS/WASM hashes, existing room/R2
restoration, upload deduplication, two-browser edits, selective Undo and reload
recovery, guest/account UI, GitHub authorization start, playback and seeking.
A downloaded 720p MP4 decoded all 102 expected frames. Full provider login and paid AI calls
were outside this smoke check. The 500-client tests ran against isolated local
workerd, not the production domain. Reload existing editor tabs to use corrected
canvas cursor throttling, bounded document batching and lifecycle/chat flushing.

Use the [studio deployment procedure](../apps/studio/README.md#実行と配置) for local
workerd, version upload, activation and rollback. `pnpm --dir apps/studio run deploy`
only builds a **dry run**. A Worker rollback changes code/assets; it does not
restore room data. Any rollback must understand version 3 documents and persistent
account dismissals.

The [limits table](../apps/studio/README.md#現在の制限) covers project structure, media,
keyframes and AI. Long projects, large media workloads and many WAN collaborators
still need performance evaluation; optional provider integrations need live
verification in the target environment.

The rewrite originated from public hackathon commit
`3f49040ee4bcf06bfcf02e269712833f3729c536`. The original
[hackathon application](../apps/studio/docs/hackathon-application.md) remains a
historical record. Current behavior belongs in the linked guides and the product
rules; the separate private design archive was not imported.

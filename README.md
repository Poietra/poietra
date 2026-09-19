# Poietra

MoonBit rewrite of [Poietra's collaborative browser motion editor](https://github.com/Poietra/poietra-hackathon).

**Migration in progress.** The running editor currently uses MoonBit for its
motion kernel, scene evaluation, canvas geometry, shared-document operations and
CRDT structure projection, model defaults/validation, project timelines, shared UI
controls, connection status, operation feedback, group animation commands and inspectors,
property timing controls, collaborative easing gestures, object/property inspectors,
audio/video track editing, the animation timeline, canvas interaction and global keyboard/clipboard handling,
optional login/project bookmarks, sample project generation, portable-file validation, asset embedding/rehoming and object clipboard plans,
Scene/Composition management, Scene tabs, layer/group browsing and TeX completion, shared room chat, AI request/apply controls and SVG
rendering, font preparation, MathJax conversion, Canvas drawing, frame composition, raster caching, GPU Glow, image normalization, media import/upload, image loading, video decoding, audio mixing, MP4/WebM export, live preview scheduling and the complete editor screen/controller,
AI/image schemas and proposal compilation. Landing/bootstrap and services still contain
TypeScript implementations. Keeping those running preserves the original regression suite
while each implementation is replaced; this is not yet a complete rewrite.

## Run locally

Requires Node.js 24+, pnpm 10.23.0, Python 3.12+, and MoonBit v0.10.13 (the compiler
used here is `moonc v0.10.13+cbb11c36f`, released 2026-09-15).

```sh
pnpm install --frozen-lockfile
curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moonbit.sh
bash /tmp/install-moonbit.sh "$(cat .moon-version)"
moon update
pnpm dev
```

Open `http://localhost:5173`. AI and OAuth require your own local configuration;
the repository contains no credentials. `POIETRA_MOON` can select a particular
MoonBit executable. Local tooling under `.tools/moon` is also detected.

```sh
pnpm test       # builds MoonBit JS/WASM, then runs the original regression suite
pnpm build     # typecheck, production assets, English/Japanese prerendering
node scripts/moon.mjs check --target js
```

## Layout and migration

- `moonbit/motion`: pure numerical kernel, compiled to JS and WebAssembly.
- `moonbit/scene`: typed document, defaults, easing/timing validation, structural
  projection, timelines and frame evaluation; no JS types. Timeline queries pass
  only structural metadata and media endpoints, not object state payloads.
- Playback compiles an owned snapshot into `Hold` / `Change` programs. Preparation
  resolves implicit tracks, matches objects, sorts layers and parses colors once.
  Seeking uses binary search; preview and export share this same evaluator.
  Object/animation/effect kinds are enums, not arbitrary strings in the core.
- `moonbit/samples`: immutable scene builders for the blank canvas and both editable
  examples. Every state, track and metadata field matches the original examples.
- `moonbit/geometry`: selection, rotation and constrained corner resizing.
- `moonbit/render`: typed shape geometry, exact cubic bounds, text/equation Write,
  and self-contained SVG generation. Prepared MathJax trees are decoded once per
  resource lifetime. The pure renderer receives explicit font/image resources.
- `moonbit/browser_render`: font subset selection/loading and measurements,
  MathJax conversion, Canvas paths/glyphs/text atlases, SVG image decoding,
  and atomic frame publication. Raster cache keys compare typed
  appearance without serializing embedded images; pending replacements lease their
  text masks, and invalidated requests cannot resurrect cleared entries.
  Atlas allocation is bounded before integer conversion; each text line is measured
  once for all masks. Native Canvas state and image URLs are released on failure,
  cancellation and disposal. Concurrent requests share
  preparation; failed font/chunk loads remain retryable. Host failures preserve
  the JavaScript `Error` contract across the async boundary.
- Glow uses a typed, pure render program validated against device limits before
  allocation. The browser driver owns textures, framebuffers and programs; partial
  initialization releases every acquired handle. Lost GPU contexts fall back to SVG.
- `moonbit/browser_media`: bounded asset downloads, retryable shared image loads,
  and serialized video decoders with explicit ownership during track discovery.
  Inactive decoders are released on Scene changes, including Scenes without video.
  Native `JsMap` bindings avoid rehashing large embedded sources in MoonBit; inline
  image validation has a bounded memo. The actual codecs remain Mediabunny/WebCodecs.
  Import owns each decoder and waveform iterator, probes only 32 container bytes,
  and scans native Float32 audio channels directly. Cancellation and synchronous
  host failures release acquired inputs; upload handlers are detached on completion.
  Image normalization releases its canvas and object URL even when encoding fails.
- `moonbit/audio`: pure planar PCM mixing with shared stereo phase calculations.
  The browser mixer owns one decoded packet per track, shares each source input,
  serializes chunk requests, and releases partial preparation on failure or abort.
  Differential tests compare Float32 bits with the original at 16/44.1/48 kHz,
  including packet gaps, trims, overlaps and one-hour timeline positions.
- `moonbit/exporting` and `moonbit/browser_export`: validated frame schedules,
  captured project timelines, codec probes and owned encoder sessions. Preparation
  can be canceled promptly; in-flight encoding/finalization settles before cleanup.
  Native failures retain their cause, and cleanup failures cannot suppress it.
- `moonbit/editor`: typed connection/persistence states, operation feedback,
  group membership, animation edit plans, and Scene/Composition copy/delete plans. Complete batches are validated
  before writing; existing tracks change only intended leaves. A delayed
  completion cannot clear a newer gesture or another Scene.
  File decoding strips unknown fields and checks references before import.
  UTF-8 size checks use a bounded scratch buffer; clipboard operations read only
  selected payloads and destination metadata, preserving unrelated shared states.
- `moonbit/ui`: MoonBit components using mizchi's typed React bindings. Shared
  controls, Scene tabs, project/export dialogs, project preview, easing editor, playback information and status displays retain the existing CSS and accessible Base UI
  primitives. Canvas/video previews serialize work and retain one pending frame;
  lifetime checks prevent publication after switching views. Audio playback owns
  its timer, scheduled nodes and decoder together. Stable typed track identities
  replace per-tick JSON serialization, and waveform-only changes do not restart audio.
  Canvas gestures use typed modes and own their Undo entry; cancellation preserves
  earlier edits and peer changes. Hit testing uses the published painted frame.
  Ruler presses seek precisely even when the wide moving playhead overlaps them.
  Global keyboard/clipboard handlers keep stable subscriptions and read current
  state. Typed shortcut actions preserve IME/text selection and one-gesture nudge
  Undo. Asset paste checks its destination again after asynchronous transfers.
  Imports own their progress, cancellation and target. Mixed image/audio/video
  batches prepare every asset and validate all limits before one shared command,
  so failures leave no partial document edits and one Undo restores the batch.
  The studio controller uses typed selections, cursor modes and stopped/preparing/
  playing states. Scene segments and compiled frames stay cached across presence,
  chat and local panel updates; an obsolete audio-resume request cannot start
  playback or dismiss a newer request. Notifications and saves belong to the
  mounted controller and release their timers/requests on exit.
  Account sessions own their list/save requests; switching identity aborts old
  work and rejects its late responses, including already received JSON.
  `src/platform/ui-host.mjs` only exposes npm runtime values.
- `moonbit/browser_projects`: typed asset metadata, deduplicated transfers and
  staged reference publication. Contradictory metadata fails before I/O, and a
  failed/canceled clipboard batch leaves all source references intact. Fresh rooms
  stage and bound their Yjs update before sending it; an owned publication session
  waits for the ordered server acknowledgment and closes all acquired resources.
  The project dialog drops canceled requests immediately, so reopening can start
  a new operation while an old file read finishes harmlessly.
- `moonbit/browser_chat`: validated room messages, per-entry snapshot caching and
  owned Yjs subscriptions. Typed request sessions suppress canceled or stale AI
  replies; history limits and proposal-target labels live in the pure editor model.
- `moonbit/collaboration`: typed edit batches, full target validation before a
  transaction, and structural invalidation rules. Yjs remains the CRDT runtime.
- `moonbit/browser_editor`: the complete editor Store, field-level commands and
  owned connection/persistence lifecycle. Immutable snapshots feed new shared maps
  without a redundant Composition clone. Media commands use the same validated
  insertion plan as file imports. Presence is read only on awareness changes;
  project edits keep the peer array's identity. Destroy releases subscriptions,
  timers and the WebSocket provider and ignores late IndexedDB completions.
  Preference-storage failures do not prevent editing. Manual creation checks the
  portable format's 500-object/100-Composition limits before writing.
- `moonbit/browser_undo`: typed preservation plans for shared creations, promoted
  tracks, independent timing maps and their duration dependencies. Native Yjs
  identities use mizchi's weak collections. Clock subtraction groups by client
  and sweeps sorted intervals instead of repeatedly copying every range; clock
  values retain JS safe-integer precision. Invalid restoration fails before
  touching either history stack, and native failures restore temporary filters.
- `moonbit/schemas`: AI operations, easing, media and bounded chat-history schemas
  built with mizchi’s typed Zod bindings. Native schema/error identity preserves
  OpenAI structured output and the existing API error/repair contract.
- `moonbit/proposal_plan`: pure typed AI commands, identity kinds and guarded edit
  plans. Metadata and lazy state reads replace whole-Scene cloning. Appends copy
  the effective state at their declaration; later edits cannot change earlier
  copies. Generated creations respect the same 500-object portable-file limit.
- `moonbit/proposals`: schema decoding, generated-image preparation, compilation
  and atomic application of AI edits. It verifies
  values, parent identities, append dependencies and projected timing before any
  write. Only touched tracks are copied for projection. Parent/child replacement
  conflicts are rejected, and all new shared values are prepared before the Yjs
  transaction so a conversion failure cannot publish an earlier partial edit.
- Shared snapshots invalidate only changed branches before observers run.
  Unchanged Scenes retain identity, avoiding needless playback compilation.
  Cached snapshots are immutable; clone before editing outside the command API.
  Nested/observer-queued transactions read live data until their writes settle.
- `moonbit/boundary`: representation-only adapters for existing JS consumers.
  `scripts/generate-adapters.py` generates field marshalling from the MoonBit model.
  Frames do not serialize embedded media to JSON.
- `apps/studio`: the running editor and original regression tests, imported from
  public `poietra-hackathon` commit `3f49040ee4bcf06bfcf02e269712833f3729c536`.
- `apps/studio/tests/oracle`: the pinned original evaluator, SVG renderer and Rust WASM used for
  differential testing, not runtime imports.

Remaining migration areas include landing/bootstrap and Workers/Node services.
Unmigrated TypeScript remains visible until its replacement passes the same tests.
Rust is no longer required to build the running application.

The founder explicitly requested architectural improvements on 2026-09-18.
Compatibility adapters are temporary migration scaffolding; old internal APIs
do not constrain the MoonBit design.

## Checks and performance

Locally verified: **622 regression/differential tests**, 15 MoonBit tests on JS,
3 kernel tests and the pure proposal planner test on WASM, typechecking and the production build. The complete studio,
selective Undo and editor Store passed the **152-test CI browser selection**, covering
offline collaboration, guarded AI edits, IME/clipboard, gestures, independent timing,
portable media, seeking and actual MP4/WebM output. An additional 15 chat/structure
checks passed with both the dev server and browsers restricted to two CPU cores;
initial editor loading uses a 15 s budget for those simultaneous fresh sessions.

Separate rendering/production checks cover SVG/Canvas agreement, Japanese text,
equation Write, GPU limits, decoder cancellation and actual 399-frame MP4/WebM
export and decoding. Media checks exercise stereo mixing and real AudioContext
cleanup. Account behavior is tested with simulated authentication, not a live
OAuth registration. Homepage checks verify that simply visiting loads no editor
engine. Native-failure and delayed-completion tests cover Undo history restoration,
audio resume, canceled imports, account switches and persistence after disposal.
Clock subtraction matches an independent point-set model in 500 randomized cases.
The proposal compiler/schema migration also passed 53 AI/chat/image/media browser
checks, including actual MP4/WebM exports.
The new compiler matches the pinned TypeScript implementation in 100 mixed-operation
scenarios, including rejected timing and valid creation/append sequences. A poisoned
unrelated state proves one-field edits do not read or clone its payload.
CI checks generated adapters and runs the core/editor/media suites with the pinned
compiler. These checks do not constitute a production migration or deployment.

```sh
pnpm --dir apps/studio exec node --import tsx scripts/benchmark-moonbit.ts
```

This measures **CPU scene evaluation only**, excluding rendering, media decoding,
encoding and display. Node 24.13.0 on Linux x64; medians of seven alternating
240-frame batches after warmup. Local 2026-09-18 results:

| Objects | Easing | Original ms/frame | MoonBit ms/frame | Speedup | Preparation ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 10 | Preset | 0.0253 | 0.00434 | 5.8× | 0.262 |
| 100 | Preset | 0.193 | 0.0226 | 8.5× | 0.770 |
| 500 | Preset | 0.995 | 0.129 | 7.7× | 2.572 |
| 10 | Custom cubic | 0.0202 | 0.00403 | 5.0× | 0.100 |
| 100 | Custom cubic | 0.204 | 0.0349 | 5.8× | 0.516 |
| 500 | Custom cubic | 1.061 | 0.188 | 5.6× | 2.464 |

These are synthetic evaluator measurements, not a claim about end-to-end browser
fps. The main savings come from preparing reusable typed playback data, parsing
colors once, and avoiding temporary arrays when returning frames to JavaScript.

A separate 2026-09-19 benchmark measures one Yjs leaf edit plus a full project
snapshot (three Scenes, five Compositions each). It excludes UI, drawing and
networking. Seven alternating batches of 50 edits after warmup:

| Objects per Scene | Original ms/edit + read | MoonBit ms/edit + read | Speedup |
| ---: | ---: | ---: | ---: |
| 100 | 1.130 | 0.0593 | 19.0× |
| 500 | 7.839 | 0.1747 | 44.9× |

```sh
pnpm --dir apps/studio exec node --import tsx scripts/benchmark-snapshots.ts
```

A separate 2026-09-19 benchmark compiles a one-field AI edit with guards and
preflight, starting from an existing immutable snapshot. Seven alternating batches
of 10 compilations after warmup; Node 24.13.0 on Linux x64:

| Objects | Compositions | Original ms | MoonBit ms |
| ---: | ---: | ---: | ---: |
| 100 | 10 | 1.701 | 0.226 |
| 500 | 10 | 7.472 | 0.236 |
| 500 | 40 | 32.454 | 0.508 |

```sh
pnpm --dir apps/studio exec node --import tsx scripts/benchmark-proposals.ts
```

This measures compilation only, excluding model calls, network, UI and applying
changes. The old compiler at `afbd6b3` is retained only as a test/benchmark oracle.

The migration follows mizchi's [TypeScript-to-MoonBit workflow](https://github.com/mizchi/skills/tree/main/ts2moonbit-migration): typed MoonBit domain code, a small JS boundary, and comparison with the original behavior. It uses [mizchi/js_core](https://github.com/mizchi/js.mbt) for interoperability and [mizchi/npm_typed](https://github.com/mizchi/npm_typed.mbt) for typed React hooks/elements and Zod schemas. [Luna](https://github.com/mizchi/luna.mbt) and [vite-plugin-moonbit](https://github.com/mizchi/vite-plugin-moonbit) were also investigated; they are not active dependencies. The initial UI migration keeps the existing React/Base UI runtime and replaces application components with MoonBit.

On 2026-09-19, source review of [gfx](https://github.com/mizchi/gfx-mbt/tree/1aec97a83ab1e7d0c924c400f0e5494f8ac3c1ca)
informed the separation of the pure Glow program from its browser driver; gfx's
WebGL driver is currently a stub, so it is not a runtime dependency.
[canvas](https://github.com/mizchi/canvas-mbt), [image](https://github.com/mizchi/image-mbt),
[mayo](https://github.com/mizchi/mayo) and [converge](https://github.com/mizchi/converge)
were also inspected. Canvas uses its own TTF rasterizer; image does not decode WebP;
Mayo requires cross-origin isolation and explicit shared Int32 layouts. Converge's
column-level CRDT passed all 75 upstream JS tests with the pinned compiler, but
needs a separate compatibility evaluation for selective Undo.
[valtio](https://github.com/dowdiness/valtio/tree/9cdf37fa61ef656db2925035f1b42a31ec922d73)
was reviewed too; its text-sequence synchronization does not replace the editor's
nested-map document and selective Undo contract. Yjs remains the shared runtime.
The [audio mixer/resampler](https://github.com/mizchi/audio-mbt/tree/f57bffe7dea9d41173784ea6abba13fd5a8454a2)
was also reviewed. It uses interleaved PCM and a Float playback cursor; this editor
keeps planar Web Audio buffers and absolute Double timestamps to preserve its
sample-level trim/export contract.
These remain candidates, not adopted or production-verified replacements.
The MIT-licensed [jsonschema v0.8.1](https://github.com/mizchi/moonbit_jsonschema/tree/c58c2433df573960e432c5f9061dfe57b40169a1)
passed its 47 upstream JS tests with the pinned compiler, but compatibility probes
found that string `pattern` and `propertyNames` constraints were not enforced.
The MIT-licensed `mizchi/npm_typed` 0.1.16 Zod bindings passed all 48 upstream tests
and two additional compatibility probes with Zod 4.6.5. They are adopted for
discriminated operations, strict easing records, nullable timing and schema output.
Project files use a typed bounded decoder with explicit identifier,
media and cross-reference checks instead of adopting it as their validator.

## Repository and deployment

On 2026-09-18 the founder requested this new **public** `Poietra/poietra` repository.
The older private repository was renamed to `Poietra/poietra-design-archive` and
its private documents/history were not imported. The source application remains
at `Poietra/poietra-hackathon`.

The copied Worker configuration has an independent Worker/bucket name and no
production domain route. The deploy command currently bundles with `--dry-run`.
No production migration or deployment has been performed. The app guide under `apps/studio` distinguishes the source service from this
rewrite; its setup and build instructions now use MoonBit.

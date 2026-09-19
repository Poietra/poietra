# Poietra

MoonBit rewrite of [Poietra's collaborative browser motion editor](https://github.com/Poietra/poietra-hackathon).

**Migration in progress.** The running editor currently uses MoonBit for its
motion kernel, scene evaluation, canvas geometry, shared-document operations and
CRDT structure projection, model defaults/validation, project timelines, shared UI
controls, connection status, operation feedback, group animation commands and inspectors,
property timing controls, collaborative easing gestures, object/property inspectors,
audio/video track editing, the animation timeline, canvas interaction,
optional login/project bookmarks, sample project generation, portable-file validation and object clipboard plans,
Scene/Composition management, Scene tabs, layer/group browsing and TeX completion, shared room chat, AI request/apply controls and SVG
rendering, font preparation, MathJax conversion, Canvas drawing, frame composition, raster caching, GPU Glow, image normalization, media import/upload, image loading, video decoding, audio mixing, MP4/WebM export and live preview scheduling. App orchestration, remaining dialogs,
higher-level editor/Undo commands, AI proposal compilation and services still contain
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
  controls, Scene tabs, export dialog, project preview, easing editor, playback information and status displays retain the existing CSS and accessible Base UI
  primitives. Canvas/video previews serialize work and retain one pending frame;
  lifetime checks prevent publication after switching views. Audio playback owns
  its timer, scheduled nodes and decoder together. Stable typed track identities
  replace per-tick JSON serialization, and waveform-only changes do not restart audio.
  Canvas gestures use typed modes and own their Undo entry; cancellation preserves
  earlier edits and peer changes. Hit testing uses the published painted frame.
  Ruler presses seek precisely even when the wide moving playhead overlaps them.
  Account sessions own their list/save requests; switching identity aborts old
  work and rejects its late responses, including already received JSON.
  `src/platform/ui-host.mjs` only exposes npm runtime values.
- `moonbit/browser_chat`: validated room messages, per-entry snapshot caching and
  owned Yjs subscriptions. Typed request sessions suppress canceled or stale AI
  replies; history limits and proposal-target labels live in the pure editor model.
- `moonbit/collaboration`: typed edit batches, full target validation before a
  transaction, and structural invalidation rules. Yjs remains the CRDT runtime.
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

Remaining migration areas include higher-level editing and Undo, UI screens,
AI proposal compilation, and Workers/Node services.
Unmigrated TypeScript remains visible until its replacement passes the same tests.
Rust is no longer required to build the running application.

The founder explicitly requested architectural improvements on 2026-09-18.
Compatibility adapters are temporary migration scaffolding; old internal APIs
do not constrain the MoonBit design.

## Checks and performance

Locally verified: 602 regression/differential tests, 11 MoonBit tests on JS and 3 kernel tests on WASM, typechecking and the production build. A 43-test browser selection
also passed, including offline concurrent edits, deletion/Undo, custom curves, seeking, and
actual MP4/WebM export and decoding. An additional 42 browser rendering checks
passed for SVG/Canvas agreement, Japanese text, equation Write, seeks, geometry
replacement, cancellation and resource release. The Scene/chat migration passed
17 browser checks, including shared waiting state and reduced motion. CI runs
the core suite and editor selection with a pinned compiler.
The GPU and export migrations passed eight production-bundle browser checks for buffer
resizing, device-limit fallback, and actual 399-frame MP4/WebM export and decoding.
Five additional media browser checks passed after decoder, mixer and export migrations, including
seeks, mixed/trimmed audio and MP4/WebM video pixels. The preview migration also
passed 13 browser checks for Canvas scheduling, stale-frame suppression, media
import/sharing and project playback/export, plus real AudioContext cleanup and
a regression check for serialization-free ticks and metadata/gain changes. The export
dialog passed all six stale-session/cancel/retry/download checks and the three
project playback/export checks after moving to a typed state machine. The MoonBit
project preview passed those checks again, plus a real-video regression that seeks
back and forth across a Scene without video. Scene intervals are prepared once,
and frames without video skip the decode queue and its snapshot copy. The typed
easing editor passed 11 browser checks covering shared curves, one-gesture Undo,
Esc/blur cancellation, peer replacements and independent timing edits.
The canvas migration passed 35 browser checks for drawing, selection, group moves,
corner resizing, rotation, text editing and preview scheduling. The timeline passed
13 checks including a deterministic regression for clicks underneath the playhead.
Shared chat and AI controls passed 35 browser checks covering concurrent requests,
offline history, cancel/retry, automatic application, new Scenes/objects/images,
guarded peer conflicts and selective Undo. Account/project screens passed seven
browser checks, including delayed read/write responses across account switches.
File/clipboard changes passed 21 browser checks for shared paste/Undo, independent
room imports, embedded image/audio/video assets, and failed/canceled imports.
The import migration passed 15 browser checks for image normalization, audio/video
tracks, cancellation, shared assets, portable files and decoded output pixels.

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

The migration follows mizchi's [TypeScript-to-MoonBit workflow](https://github.com/mizchi/skills/tree/main/ts2moonbit-migration): typed MoonBit domain code, a small JS boundary, and comparison with the original behavior. It uses [mizchi/js_core](https://github.com/mizchi/js.mbt) for interoperability and [mizchi/npm_typed](https://github.com/mizchi/npm_typed) for typed React hooks and elements. [Luna](https://github.com/mizchi/luna.mbt) and [vite-plugin-moonbit](https://github.com/mizchi/vite-plugin-moonbit) were also investigated; they are not active dependencies. The initial UI migration keeps the existing React/Base UI runtime and replaces application components with MoonBit.

On 2026-09-19, source review of [gfx](https://github.com/mizchi/gfx-mbt/tree/1aec97a83ab1e7d0c924c400f0e5494f8ac3c1ca)
informed the separation of the pure Glow program from its browser driver; gfx's
WebGL driver is currently a stub, so it is not a runtime dependency.
[canvas](https://github.com/mizchi/canvas-mbt), [image](https://github.com/mizchi/image-mbt),
[mayo](https://github.com/mizchi/mayo) and [converge](https://github.com/mizchi/converge)
were also inspected. Canvas uses its own TTF rasterizer; image does not decode WebP;
Mayo requires cross-origin isolation and explicit shared Int32 layouts. Converge's
column-level CRDT needs a separate compatibility evaluation for selective Undo.
The [audio mixer/resampler](https://github.com/mizchi/audio-mbt/tree/f57bffe7dea9d41173784ea6abba13fd5a8454a2)
was also reviewed. It uses interleaved PCM and a Float playback cursor; this editor
keeps planar Web Audio buffers and absolute Double timestamps to preserve its
sample-level trim/export contract.
These remain candidates, not adopted or production-verified replacements.
The MIT-licensed [jsonschema v0.8.1](https://github.com/mizchi/moonbit_jsonschema/tree/c58c2433df573960e432c5f9061dfe57b40169a1)
passed its 47 upstream JS tests with the pinned compiler, but compatibility probes
found that string `pattern` and `propertyNames` constraints were not enforced.
Project files therefore use a typed bounded decoder with explicit identifier,
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

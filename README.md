# Poietra

MoonBit rewrite of [Poietra's collaborative browser motion editor](https://github.com/Poietra/poietra-hackathon).

**Migration in progress.** The running editor currently uses MoonBit for its
motion kernel, scene evaluation, canvas geometry, shared-document operations and
CRDT structure projection, model defaults/validation, project timelines, shared UI
controls, connection status, operation feedback, group animation commands,
Scene/Composition management, Scene tabs, shared AI waiting indicators and SVG
rendering. Most editor screens, higher-level editor/Undo commands, AI, Canvas/GPU
and media resource orchestration, and service orchestration still contain
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
- `moonbit/geometry`: selection, rotation and constrained corner resizing.
- `moonbit/render`: typed shape geometry, exact cubic bounds, text/equation Write,
  and self-contained SVG generation. Prepared MathJax trees are decoded once per
  resource lifetime. The pure renderer receives explicit font/image resources.
- `moonbit/editor`: typed connection/persistence states, operation feedback,
  group membership, animation edit plans, and Scene/Composition copy/delete plans. Complete batches are validated
  before writing; existing tracks change only intended leaves. A delayed
  completion cannot clear a newer gesture or another Scene.
- `moonbit/ui`: MoonBit components using mizchi's typed React bindings. Shared
  controls, Scene tabs, playback information and status displays retain the existing CSS and accessible Base UI
  primitives. `src/platform/ui-host.mjs` only exposes npm runtime values.
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
Canvas/GPU resources and media/export, shared chat/AI, and Workers/Node services.
Unmigrated TypeScript remains visible until its replacement passes the same tests.
Rust is no longer required to build the running application.

The founder explicitly requested architectural improvements on 2026-09-18.
Compatibility adapters are temporary migration scaffolding; old internal APIs
do not constrain the MoonBit design.

## Checks and performance

Locally verified: 535 regression/differential tests, 4 MoonBit tests on JS and 3 kernel tests on WASM, typechecking and the production build. A 43-test browser selection
also passed, including offline concurrent edits, deletion/Undo, custom curves, seeking, and
actual MP4/WebM export and decoding. An additional 42 browser rendering checks
passed for SVG/Canvas agreement, Japanese text, equation Write, seeks, geometry
replacement, cancellation and resource release. The Scene/chat migration passed
17 browser checks, including shared waiting state and reduced motion. CI runs
the core suite and editor selection with a pinned compiler.

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

## Repository and deployment

On 2026-09-18 the founder requested this new **public** `Poietra/poietra` repository.
The older private repository was renamed to `Poietra/poietra-design-archive` and
its private documents/history were not imported. The source application remains
at `Poietra/poietra-hackathon`.

The copied Worker configuration has an independent Worker/bucket name and no
production domain route. The deploy command currently bundles with `--dry-run`.
No production migration or deployment has been performed. The app guide under `apps/studio` distinguishes the source service from this
rewrite; its setup and build instructions now use MoonBit.

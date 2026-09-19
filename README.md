# Poietra

MoonBit rewrite of [Poietra's collaborative browser motion editor](https://github.com/Poietra/poietra-hackathon).

**Migration in progress.** The running editor currently uses MoonBit for its
motion kernel, scene evaluation, and canvas geometry. The React UI, collaboration,
AI, media renderer, and service integrations are still the original TypeScript
implementation. Keeping those running preserves the original regression suite
while each implementation is replaced; this is not yet a complete rewrite.

## Run locally

Requires Node.js 24+, pnpm 10.23.0, Python 3.12+, and MoonBit v0.10.13 (the compiler
used here is `moonc v0.10.13+cbb11c36f`, released 2026-09-15).

```sh
pnpm --dir apps/studio install --frozen-lockfile
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
- `moonbit/scene`: typed document, timeline and frame evaluation; no JS types.
- Playback compiles an owned snapshot into `Hold` / `Change` programs. Preparation
  resolves implicit tracks, matches objects, sorts layers and parses colors once.
  Seeking uses binary search; preview and export share this same evaluator.
  Object/animation/effect kinds are enums, not arbitrary strings in the core.
- `moonbit/geometry`: selection, rotation and constrained corner resizing.
- `moonbit/boundary`: representation-only adapters for existing JS consumers.
  `scripts/generate-adapters.py` generates field marshalling from the MoonBit model.
  Frames do not serialize embedded media to JSON.
- `apps/studio`: the running editor and original regression tests, imported from
  public `poietra-hackathon` commit `3f49040ee4bcf06bfcf02e269712833f3729c536`.
- `apps/studio/tests/oracle`: the pinned original evaluator and Rust WASM used for
  differential testing, not runtime imports.

Next migration areas are shared editing operations and CRDT projections, UI,
rendering/media/export, shared chat/AI, and Workers/Node service orchestration.
Unmigrated TypeScript remains visible until its replacement passes the same tests.
Rust is no longer required to build the running application.

The founder explicitly requested architectural improvements on 2026-09-18.
Compatibility adapters are temporary migration scaffolding; old internal APIs
do not constrain the MoonBit design.

## Checks and performance

Locally verified: 519 regression/differential tests, 3 kernel tests on each of
JS and WASM, typechecking and the production build. A 19-test browser selection
also passed, including collaborative editing/Undo, custom curves, seeking, and
actual MP4/WebM export and decoding. CI runs these checks with a pinned compiler.

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

The migration follows mizchi's [TypeScript-to-MoonBit workflow](https://github.com/mizchi/skills/tree/main/ts2moonbit-migration): typed MoonBit domain code, a small JS boundary, and comparison with the original behavior. It uses [mizchi/js_core](https://github.com/mizchi/js.mbt) for interoperability. [Luna](https://github.com/mizchi/luna.mbt) and [vite-plugin-moonbit](https://github.com/mizchi/vite-plugin-moonbit) are being evaluated for the UI/build migration; they are not yet the active UI.

## Repository and deployment

On 2026-09-18 the founder requested this new **public** `Poietra/poietra` repository.
The older private repository was renamed to `Poietra/poietra-design-archive` and
its private documents/history were not imported. The source application remains
at `Poietra/poietra-hackathon`.

The copied Worker configuration has an independent Worker/bucket name and no
production domain route. The deploy command currently bundles with `--dry-run`.
No production migration or deployment has been performed. Historical deployment
instructions under `apps/studio` describe the source application and must not be
used to target its production storage from this rewrite.

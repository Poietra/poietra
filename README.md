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

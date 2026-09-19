# Poietra — implementation rules

Applies to this entire repository. Product behavior is specified in
[apps/studio/AGENTS.md](apps/studio/AGENTS.md); setup, architecture, current checks
and measurements belong in [README.md](README.md).

## Scope and provenance

- 2026-09-18: The founder requested a complete MoonBit rewrite of the public
  `Poietra/poietra-hackathon` application in public `Poietra/poietra`, including
  architectural improvements for performance and reliability.
- 2026-09-19: Application logic is implemented in MoonBit. Preserve existing
  functionality, appearance, collaboration semantics, portable files and
  preview/export agreement when making further changes.
- Source provenance: public hackathon commit
  `3f49040ee4bcf06bfcf02e269712833f3729c536`. The original application is available
  in `Poietra/poietra-hackathon` and the local hackathon checkout.
- 2026-09-20: At the founder's request, remove copied historical implementations
  and migration-only comparisons. Preserve current behavioral and API checks;
  use Git history or the hackathon repository when historical code is needed.
- The separate private `poietra-design-archive` was not imported. Do not copy
  its documents or history into this public repository.
- The rewrite is not deployed to the original service. Do not deploy to its
  production domain or reuse production storage for local validation.

## Implementation

- Write application/domain logic in typed MoonBit. Runtime TS/TSX was removed on
  2026-09-19. Native JS serves browser/runtime/npm interoperability; TypeScript
  remains for public declarations and build/test tooling.
- 2026-09-20: Audit language usage with `pnpm audit:source`. GitHub's byte-based
  language ratio includes tests and does not quantify remaining host dependencies.
  Preserve behavioral tests and public declarations; CI rejects executable TS in
  the four application source directories. Benchmarks run with Node 24's native
  type stripping and explicit ESM extensions, without a `tsx` loader.
- Generate document adapters and public record types from `moonbit/scene` with
  `scripts/generate-adapters.py`. `scripts/bindings.json` generates simple public
  JS facades. Do not manually duplicate domain records or edit generated output.
  `pnpm typecheck` checks the captured public API; `pnpm test:extensions` compiles
  and runs a new MoonBit record/API in an isolated directory.
- Keep pure domain packages independent of UI/host types. Compile motion
  primitives to WASM and host integrations to JS. Use the pinned `.moon-version`
  through `node scripts/moon.mjs`; verify generated release artifacts.
- Prefer typed states/enums, prepared playback, explicit ownership and shared
  evaluators. Native adapters do not constrain internal architecture.
- Shared reads return immutable, structurally shared snapshots. Invalidate
  changed branches before Yjs observers and bypass caches during unobserved
  writes. Preserve nested/observer-queued transaction tests. Mutable consumers
  clone explicitly; commands write only intended fields.
- Preserve cancellation, late-completion suppression, backpressure and cleanup
  across async boundaries. Keep native error identity where host contracts need it.
- Inspect upstream source, license, compatibility and tests before adopting a
  dependency. Keep concise adoption decisions in README.

## Evidence and documentation

- 2026-09-19: The founder requested new measurements and a complete documentation
  refresh. Record source revision, compiler/runtime/browser, hardware, affinity,
  workloads, warmup, samples and exclusions; retain raw results for published tables.
- Run performance workloads sequentially, without concurrent builds/tests/encoders.
  Freeze source and generated output during browser runs. Report variation;
  do not present CPU microbenchmarks or SwiftShader timings as user-visible FPS.
- Use representative regression, backend-conformance and browser checks for changed behavior.
  Distinguish tests with mocked provider HTTP from live OAuth/OpenAI verification.
- Keep current documentation in the existing READMEs. Historical application text
  stays historical. Avoid new ADRs/research logs unless they are needed.
- Date decisions and state the problem they resolve. Do not label untested behavior
  verified, or describe a local build/dry-run as a production deployment.

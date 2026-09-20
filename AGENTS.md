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
- 2026-09-20: The founder authorized deploying the MoonBit rewrite to
  `https://poietra.com`. Use the explicit `production` Wrangler environment to
  update the existing `poietra-hackathon` Worker in Yumaboda's account. Preserve
  its Durable Object namespaces/classes, migration tags, `poietra-assets-prod`
  bucket, secrets, domain and old workers.dev links. Record the previous version,
  upload then deploy the new version, and verify persistence and collaboration.
  Local validation must continue to use isolated storage and the default config.

## Implementation

- 2026-09-20: The founder approved Scene-wide parent links, with local position,
  rotation, scale and anchor per Composition. Reparent/detach preserves geometry
  in all Compositions, including retained deleted ones; group selection stays
  separate. Keep full affine composition and a sparse shear coefficient so
  rotated nonuniform scale can be rebased without losing geometry. Evaluated
  world matrices are runtime data, never serialized document state.
- 2026-09-20: The founder approved intermediate actual-value keyframes with
  Composition-linked endpoints. Point time is normalized within the property's
  animation interval; resizing that interval stretches the whole curve. Use
  stable keyframe IDs, leaf edits and deletion tombstones, with authoritative
  server initialization of legacy track containers. Never replace that shared
  map during ordinary point or track edits. Format v2 upgrades are monotonic
  and excluded from editing Undo; old v1 files remain readable.
- 2026-09-20: Extending selective Undo to hierarchy and points exposed dependent
  peer edits. Retain newly created points/parents used by a peer. After received
  coordinate or motion edits use a parent relation (including a detach), retain
  that relation and compensating transform leaves when undoing it; unrelated
  appearance still undoes. Notify the user and do not consume an earlier action.

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
- 2026-09-20: Keep object/group edit decisions in pure `editor` plans, tested on
  JS and WASM. Creation/clipboard/import share `ObjectInsertion`; boundary code
  reads required metadata and encodes batches before publication. Avoid decoding
  whole Scenes for pointer edits or constructing display tracks for command plans.
- 2026-09-20: Transition resizing and single-track timing use typed plans and
  write changed timing leaves. Retain existing property-timing Yjs parents,
  including through `setTrack`: replacement erased offline peer easing/start
  edits, including through Undo/Redo. Single-track activation keeps its strict
  inherited-duration bounds; group edits have a separate remaining-duration rule.
- 2026-09-20: Scene/Composition append uses pure `editor` plans and shared
  `scene/creation` factories. Apply the same capacity checks to duplication.
  Resolve every Yjs parent and encode all detached values before writing or
  reviving a retained source; Yjs cannot roll back writes after a conversion fails.
  Keep copied states independent and preserve offline source edits through Undo.
- 2026-09-20: After reports of slow startup, playback, dragging and export, evaluate
  only the current Composition while editing; memoize unchanged layer rows. Reuse
  prepared frames only for static holds without visible video. Export must retain
  every timestamp/frame, Scene boundaries, video timing and encoder backpressure.
  Load export/file I/O on demand while capturing export inputs before any await.
- 2026-09-20: Profiling found whole-SVG DOM replacement and per-shape raster
  compositing in playback/dragging. Serialize SVG and retain keyed stage nodes
  from the same typed render view. Draw opaque, effect-free shapes directly with
  cached native geometry; preserve isolated fill/stroke compositing for opacity
  and Glow. Keep cache lifetime, fallback and preview/export checks explicit.
- Shared reads return immutable, structurally shared snapshots. Invalidate
  changed branches before Yjs observers and bypass caches during unobserved
  writes. Preserve nested/observer-queued transaction tests. Mutable consumers
  clone explicitly; commands write only intended fields.
- 2026-09-20: Profiling found clock/presence notifications rendering every editor
  panel. Keep browser-local playback position outside document/selection Context;
  subscribe only stage/audio/time indicators to it. Project, connection/history,
  presence and chat consumers select their own immutable snapshot fields. Keep
  chat read state local to its panel and preserve the public `useEditor` adapter.
  Test subscription isolation alongside seeking, cancellation and peer editing.
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

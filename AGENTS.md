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
- 2026-09-20: Independent browser foreign libraries duplicated transitive MoonBit
  definitions and slowed startup. Generate `client_runtime` export tables from
  package `moon.pkg` files and link the six editor packages once. Keep domain
  package boundaries and standalone Node/Worker/SSR artifacts; preserve lazy
  site, file/export, MathJax and Mediabunny loading. New exports must work through
  both artifacts in the extension test. Do not hand-edit generated export tables.
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
  The clock provider publishes one React state/Context snapshot; keep ordinary
  scheduling for playback ticks. An external-store clock forced synchronous
  rendering and worsened the measured 500-object playback interval.
- Preserve cancellation, late-completion suppression, backpressure and cleanup
  across async boundaries. Keep native error identity where host contracts need it.
- 2026-09-20: Pose edits were rebuilding unchanged panels and preparing the same
  resources. Keep panel presentation inputs explicit, including every displayed
  field and selection/structure dependency; command handlers read the latest
  document. Resource preparation depends on text across Compositions and visible
  image assets, not poses or timing. Preserve asset/visibility invalidation,
  cancellation and late-frame suppression, with a document-independent retry
  after preparation failure. Context wrappers still observe document changes.
- Inspect upstream source, license, compatibility and tests before adopting a
  dependency. Keep concise adoption decisions in README.
- 2026-09-21: The founder requested file-to-result API/MCP without Chromium or
  FFmpeg. The Node headless host reuses MoonBit parsing, prepared evaluation,
  SVG/equations and audio mixing; native adapters own standalone WASM codecs and
  I/O. Preserve bounded inputs, cancellation and independent decoder checks.
  Unsupported source codecs must fail explicitly. Keep this host out of browser
  bundles; it does not imply a hosted Cloudflare endpoint or Worker compatibility.
  The source audit now includes `apps/render` alongside studio application code.
- 2026-09-21: The founder requested typed render boundaries and reusable library
  extraction. Keep render orchestration in host-independent `render_job`, native
  conversion in `headless_render` and HTTP routing in `render_http`. Shared
  portable-file parsing/generated adapters live in `project_codec`, independent
  of the editing boundary. `media_pipeline` contains media values, typed ports
  and encoder ownership with no project/host dependencies; preserve its isolated
  JS/WASM consumer checks. It is reusable internally, not yet registry-published.
- 2026-09-22: The founder requested a public API/MCP page that agents can use.
  Generate bilingual developer HTML and Markdown from the same MoonBit content,
  OpenAPI/capabilities from `render_api`, and the project schema from the shared
  file validation definition. Cloudflare negotiates public pages only; schemas
  and examples are static assets. Publish accurate self-hosted HTTP/local stdio
  MCP instructions; this does not deploy a hosted render API or remote MCP.
  Keep editor, account and room routes outside public document negotiation.

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
- 2026-09-21: Repeated release/benchmark narratives obscured setup and current
  behavior. Keep architecture, extension steps, checks, measured results and the
  last verified release in the root README; keep Japanese usage, configuration
  and operations in the studio guide. Link between them instead of duplicating
  counts and release records. Keep raw benchmark evidence and link older
  explanations at a fixed Git revision. Date verification records explicitly.
- Date decisions and state the problem they resolve. Do not label untested behavior
  verified, or describe a local build/dry-run as a production deployment.

# Poietra MoonBit rewrite

- 2026-09-18: The founder requested a complete MoonBit rewrite of the public
  `Poietra/poietra-hackathon` application in this public `Poietra/poietra` repository.
- Preserve the editor's existing functionality, appearance, collaborative editing
  semantics, portable project files, and preview/export agreement during migration.
- Implement application and domain logic in typed MoonBit. JavaScript adapters are
  for browser/runtime/npm interoperability, not containers for the old implementation.
- Keep pure domain code independent of the UI and host runtime. Compile the motion
  kernel to WebAssembly; use the JS target for host integrations.
- `apps/studio` initially contains the public hackathon application's source and
  regression tests at commit `3f49040ee4bcf06bfcf02e269712833f3729c536`.
  Replace implementations incrementally and test the actual generated artifacts.
- Do not describe unported features as migrated or untested behavior as verified.
- 2026-09-18: The founder explicitly requested using MoonBit's strengths for bold
  performance and reliability improvements, not a mechanical translation. Existing
  APIs are temporary migration adapters, not constraints on the internal design.
  Prefer typed state machines, enums, compiled playback data, explicit ownership,
  and shared evaluators. Measure optimizations against the original implementation.
- Historical design work lives in the separate private `poietra-design-archive`.
  Do not copy its documents or history into this public repository.
- Keep documentation in README. Do not deploy to the existing production domain
  or reuse its production storage while validating the rewrite locally.
- 2026-09-19: Shared reads now return immutable, structurally shared snapshots.
  Invalidate changed branches before Yjs observers, and bypass caches during
  unobserved writes. Keep the tests for nested and observer-queued transactions.
  Mutable consumers must explicitly clone; commands write only intended fields.
- 2026-09-19: The founder reiterated researching existing MoonBit implementations
  as each subsystem is rewritten. Inspect upstream source, license, compatibility
  and tests before adding a dependency; record concise adoption decisions in README.

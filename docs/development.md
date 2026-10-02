# Development

[Setup](../README.md#run-locally) · [Studio operations](../apps/studio/README.md#実行と配置) · [Measurements](../benchmarks/README.md)

## Architecture

Application behavior lives in [MoonBit packages](../moonbit/). Native JavaScript
adapts browser, Node and Cloudflare APIs; TypeScript supplies public declarations
and build/test tooling. `pnpm audit:source` reports the current inventory and
rejects executable application TS/TSX. It does not measure runtime dependencies.

| Layer | Main packages | Responsibility |
| --- | --- | --- |
| Model and engine | `scene`, `motion`, `geometry`, `render`, `audio`, `exporting`, `editor`, `proposal_plan` | Documents, pure edit plans, prepared evaluation and shared rendering |
| Collaboration | `collaboration`, `boundary`, `browser_editor`, `browser_undo`, `browser_chat` | Yjs leaf edits, immutable snapshots, selective Undo and chat |
| Browser | `ui`, `browser_render`, `browser_media`, `browser_export`, `browser_projects`, `browser_kernel` | React UI, drawing, resources, media and portable files |
| Portable files | `project_codec` | Bounded parsing, validation and generated record adapters |
| Headless rendering | `render_job`, `media_pipeline`, `headless_render`, `render_http`, `render_api`, `math_render` | Typed orchestration, media contracts, host conversion and HTTP |
| Services | `schemas`, `proposals`, `ai_service`, `auth_policy`, `auth_service` | Validation, AI proposals, OAuth and private project lists |
| Hosts and storage | `node_*`, `worker_*`, `room_assets`, `r2_upload`, `http_policy`, `http_runtime` | HTTP/WebSockets, persistence, quotas and media publication |
| Public site | `site`, `site_shell`, `site_boundary`, `browser_site`, `developer_site`, `site_build` | Localized pages, developer documentation and prerendering |

The boundaries to preserve are:

- Pure domain packages are independent of React, Yjs and host types. Edit plans
  name changed leaves; boundary code validates and encodes before publishing.
- Editor components share typed MoonBit state, selection and commands through
  `ui/editor_model.mbt`; `ui/editor_native.mbt` adapts the public JS context and
  hooks. Cached panel views retain their typed props through the React adapter.
  This boundary was established on 2026-10-02 to catch internal field and callback
  mismatches at compilation. Native document snapshots retain their shared identity;
  decoding entire Scenes for UI state would lose that property and add work.
  Property timing, keyframes, easing and timeline tracks also retain typed values
  and callbacks through their inspectors and gestures (`ui/animation_model.mbt`).
  Timeline row models contain display metadata and timing values; operation
  feedback uses the domain status type through rendering. The native
  adapters translate public JS props, targeted document reads and leaf commands;
  gesture history uses opaque identities (`ui/gesture_native.mbt`). This separation
  was extended on 2026-10-03 to keep JavaScript records out of editing logic.
  Property timing commands read current leaves before planning an edit, preserving
  intervening peer values under the existing timing bounds. Gesture calculations
  keep the shared document snapshots intact.
- Each room has one authoritative Yjs document. Reads share immutable snapshots;
  selective Undo preserves peer edits. Persist updates before broadcasting or
  acknowledging them, including unresolved dependencies.
- Preview and export share prepared evaluation and render geometry. Capture
  export inputs before awaiting; preserve every output timestamp, cancellation,
  backpressure and cleanup. Keep playback-clock notifications local to consumers.
- `render_job` owns host-independent orchestration; `headless_render` owns native
  conversion. `media_pipeline` has no project or host dependency: producers own
  frame/sample buffers until the awaited consumer returns. It is not published.

Detailed behavior belongs in the [product rules](../apps/studio/AGENTS.md) and
[implementation rules](../AGENTS.md). Earlier explanations are available at
[revision 99c2dbd](https://github.com/Poietra/poietra/blob/99c2dbdb5c35361eec5b505bd369bd81b43fe430/docs/architecture.md).

## Build and generated code

`pnpm build:moonbit` generates adapters, builds release JS and motion WASM under
`_build/`, copies the WASM into `apps/studio/public/wasm/`, and generates facades.
Use `node scripts/moon.mjs` for compiler commands; it selects `POIETRA_MOON`, then
`.tools/moon/bin/moon`, then `moon` on PATH. The version is pinned by `.moon-version`.

| Source of truth | Generated output |
| --- | --- |
| [Scene model](../moonbit/scene/model.mbt) via [generate-adapters.py](../scripts/generate-adapters.py) | [Record adapters](../moonbit/project_codec/adapters.mbt) and [public scene types](../apps/studio/shared/scene-types.d.ts) |
| [bindings.json](../scripts/bindings.json) | Simple native JS facades |
| Package `moon.pkg` exports via [client-runtime.mjs](../scripts/client-runtime.mjs) | Shared browser entry/export tables |

Do not edit generated output. The browser links six editor packages once through
`client_runtime`; the [Vite adapter](../apps/studio/scripts/moonbit-client.mjs)
rejects duplicate standalone copies. Node, Worker and SSR use standalone artifacts.
Preserve lazy site, file/export, MathJax and Mediabunny loading.

## Commands

Run from the repository root:

| Command | Purpose |
| --- | --- |
| `pnpm dev` | Build MoonBit and start Node/Vite on port 5173 |
| `pnpm build:moonbit` | Regenerate adapters/facades and build release JS/WASM |
| `pnpm build` | Build MoonBit, check types, bundle and prerender public pages |
| `pnpm --dir apps/studio start` | Serve the completed production build |
| `pnpm test` | Source/suite audit, build, extension checks and Vitest |
| `pnpm typecheck` | TypeScript declarations and captured public API contracts |
| `pnpm test:render` | Headless rendering, decoding, HTTP and MCP after building |

After editing `.mbt`, run `pnpm build:moonbit`; Vite does not compile MoonBit.
Restart Node after changing server code. See [configuration](../apps/studio/README.md#設定)
for optional AI/OAuth settings and [operations](../apps/studio/README.md#実行と配置)
for Node/Worker storage and deployment commands.

## Add a feature

1. Read the product and implementation rules. Define domain records in
   `scene/model.mbt`, kinds in `scene/kinds.mbt`, pure decisions in `editor`, and
   shared evaluation in `scene`/`motion`.
2. Implement validation, persistence compatibility, commands, evaluation and UI
   as needed. Creation/clipboard/import share `editor.ObjectInsertion`; Scene
   and Composition defaults use `scene/creation`.
3. Write only intended leaves and retain existing Yjs parents. Resolve all targets
   and encode detached values before writing; a Yjs transaction cannot roll back
   writes when conversion fails.
4. Export host APIs in `moon.pkg`, provide adjacent `.d.ts` contracts and add
   simple forwarding to `scripts/bindings.json`. Rebuild generated output.
5. Run the checks for the affected boundaries below. Changes to animation,
   collaboration or persistence also need preview/export, peer/Undo or restart
   checks, respectively.

`pnpm test:extensions` compiles a new record/API in isolation, checks standalone
and shared-runtime exports, and rejects invalid TypeScript consumers. For a new
headless backend, implement `render_job.Backend`; add formats through
`render_job.Format` and preserve the isolated JS/WASM `media_pipeline` checks.

## Checks

[CI](../.github/workflows/check.yml) defines the required suites. Browser selection
comes from [suites.ts](../apps/studio/tests/e2e/suites.ts);
`pnpm check:test-suites` rejects missing, duplicate and unclassified specs.

| Boundary | Checks |
| --- | --- |
| Pure plans and host contracts | `pnpm test`, MoonBit JS/WASM, `pnpm test:render` |
| Gestures, peer edits, offline/Undo and lifecycle | `pnpm --dir apps/studio test:e2e` (four CI shards) |
| Media import, encoded export and browser audio | Studio `test:media-editor`, `test:export`, `test:media`, sequentially |
| Built pages and persistence | Studio `test:site`, then Node/workerd integrations listed in CI |
| Extended pixel matrices | Opt-in `effects.config.ts`, `effects-write.config.ts`, `glow.config.ts` |

Run pure MoonBit tests from the root:

```sh
node scripts/moon.mjs check --target js --deny-warn
node scripts/moon.mjs test --target js
node scripts/moon.mjs test --target wasm moonbit/motion moonbit/proposal_plan moonbit/editor moonbit/scene moonbit/render moonbit/exporting moonbit/audio moonbit/media_pipeline moonbit/render_job
```

Install Chromium with `pnpm --dir apps/studio exec playwright install --with-deps chromium`.
CI's media suites require FFmpeg/ffprobe; headless checks use independent WASM
decoders without browser/FFmpeg dependencies. Browser tests
create rooms: use isolated storage and `POIETRA_TEST_URL` if port 5173 belongs to
another session. Production-page tests serve the completed build separately.

JS/WASM conformance, snapshot identity, independent decoding and real process
restart checks cover different failure boundaries. Keep them when removing
redundant scenarios. Provider HTTP is mocked; these checks do not verify live
OAuth completion or paid AI calls. Timing probes are separate from correctness
checks; run them using the [measurement guide](../benchmarks/README.md).

## API documentation

The bilingual [developer pages](https://poietra.com/developers/) contain CLI,
HTTP/MCP instructions, codecs and limits. To read documentation for this checkout,
run `pnpm build` then `pnpm --dir apps/studio start` and open `/developers/` or
`/ja/developers/`. The [Node API](../apps/render/index.d.mts) supports progress and
cancellation. The renderer is a self-hosted Node service; poietra.com serves
public documentation, not a hosted rendering endpoint.

Edit [developer_site](../moonbit/developer_site/content.mbt) for both HTML and
Markdown. [render_api](../moonbit/render_api/) generates OpenAPI/capabilities;
[project_codec](../moonbit/project_codec/) generates the project schema from its
validation definitions. Avoid separate handwritten copies of API contracts.

The Node backend uses resvg WASM for SVG, minih264 for H.264, and Mediabunny with
LAME for muxing/MP3. [Dependencies](../apps/render/package.json) are pinned. Retain
upstream notices: resvg and the MP3 extension/MPL-2.0, H.264 wrapper/MIT,
minih264/public domain, libmp4v2/MPL-1.1 and LAME/LGPL. The 2026-09-21 backend
review kept SVG because canvas-mbt lacked the filters/shadows needed for Glow.
Browser-identical pixels are not promised; path-length adaptation and an
intermediate H.264 MP4 buffer remain backend constraints.

## Deployment and limits

Last recorded deployment: **2026-09-22 12:58 JST**, application `2d76eed`, Worker
version `dcd24d3d-45b7-4abe-b4eb-3a274955c841`. Smoke checks covered persistence,
two-browser edits, Undo/reload, playback and a decoded 102-frame 720p MP4. Full
provider login, paid AI calls and 500 production clients were outside that check.
[The full record](https://github.com/Poietra/poietra/blob/99c2dbdb5c35361eec5b505bd369bd81b43fe430/docs/development.md#deployment-and-limits)
includes the predecessor. Confirm the active version before deploying again.

Follow the [studio deployment procedure](../apps/studio/README.md#実行と配置).
The default Wrangler config uses isolated storage; only explicit `production`
commands target the existing service. A dry run or successful CI is not a deployment.
A Worker rollback restores code/assets, not room data; it must understand version
3 documents and persistent account dismissals. See [current limits](../apps/studio/README.md#現在の制限).

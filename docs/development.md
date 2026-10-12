# Development

[Setup](../README.md#run-locally) · [Studio operations](../apps/studio/README.md#実行と配置) · [Measurements](../benchmarks/README.md)

## Architecture

Application behavior lives in [MoonBit packages](../moonbit/). Native JavaScript
adapts browser, Node and Cloudflare APIs; TypeScript supplies public declarations
and build/test tooling. `pnpm audit:source` reports the current inventory and
rejects executable application TS/TSX. It does not measure runtime dependencies.

| Layer | Main packages | Responsibility |
| --- | --- | --- |
| Model and engine | `scene`, `motion`, `math_plot`, `math_geometry`, `math_network`, `math_surface`, `geometry`, `render`, `audio`, `exporting`, `editor`, `proposal_plan` | Documents, mathematical evaluation, pure edit plans, prepared evaluation and shared rendering |
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
  feedback uses the domain status type through rendering. Canvas gestures carry
  typed transforms, Bézier control points and positions to `ui/stage_native.mbt`, which
  reads current object metadata and encodes only the edited fields. Gesture
  bindings retain their original Scene/Composition and native Undo owner.
  Path gestures preserve the shared path/control-point maps, so Undo and
  concurrent edits retain the other control point. The native adapters translate
  public JS props, targeted document reads and leaf commands;
  gesture history uses opaque identities (`ui/gesture_native.mbt`). This separation
  was extended on 2026-10-03 to keep JavaScript records out of editing logic.
  Property timing commands read current leaves before planning an edit, preserving
  intervening peer values under the existing timing bounds. Gesture calculations
  keep the shared document snapshots intact.
- Each room has one authoritative Yjs document. Reads share immutable snapshots;
  selective Undo preserves peer edits. Persist updates before broadcasting or
  acknowledging them, including unresolved dependencies. Opening a portable
  project publishes it as ordered messages of at most 1 MiB (2026-10-12), and
  Durable Object compaction stores the document in 1 MiB SQLite rows (plus the
  legacy single row while it fits one part), so project size is bounded by the
  128 MB file limit rather than one CRDT message.
- Preview and export share prepared evaluation and render geometry. Capture
  export inputs before awaiting; preserve every output timestamp, cancellation,
  backpressure and cleanup. Keep playback-clock notifications local to consumers.
- Function graphs (2026-10-10) retain a versioned `scene.GraphDefinition` per
  Composition. The pure `math_plot` package parses a bounded numeric expression
  and samples in mathematical coordinates; `render` maps it to centered, y-down
  viewport paths, axes and labels shared by SVG, Canvas/GPU and Node export.
  Paths are derived runtime data. This preserves editable mathematical intent
  without making path editing or host JavaScript the source of the graph.
  Coefficients a/b/c share a `graph` timing channel and normalized intermediate
  keys; expressions/ranges switch at half the base animation progress. Graph edits
  write nested leaves and retain the Yjs graph map. Undo/Redo retains necessary axis
  bounds if a peer's later edit would otherwise invert a valid range.
  Concurrent conflicting bounds show an error; correct the range before export.
  Portable graph data uses monotonic, non-Undo format v4; v1/v2/v3 remain readable.
- Implicit curves (2026-10-11) extend the same graph object with one `left=right`
  equation in x/y/a/b/c. Grammar v2 adds equations to the original functions;
  authors retain v2 when returning to a function, so offline expression edits
  cannot conflict with a redundant grammar downgrade. Selective Undo/Redo retains
  only a grammar leaf needed by a surviving peer equation and reports it to the
  user. UI, public editor patches and AI operations select grammar automatically;
  files validate their declared grammar. The existing coefficient channel and
  discrete expression/range switch also apply to equations.
  The pure `math_plot` contour sampler uses up to 128 × 128 cells, with center
  samples dividing each cell into four triangles. Shared edge roots, verified by
  bounded bisection/residual checks, avoid treating a pole or jump as a solution.
  Adjacent root identities form continuous components for Write. Evaluations are
  capped at 65536, segments at 8192, and root refinement at 20 steps. Undefined,
  unresolved and zero-valued-area regions are omitted; work limits are reported.
  This is a finite sampling heuristic: narrow components, high frequencies and
  repeated roots without sign changes can be missed. It is not certified topology
  or a global error bound. Preview and Node export use the same derived geometry;
  no new host dependency or serialized path is needed.
- Shaded regions (2026-10-11) resolve the request to draw a curve thinly and
  then fill beneath it. `GraphDefinition.filled` is an optional flag; `render`
  closes each continuous explicit run to the x-axis using the sampler's
  unclipped chords and only then clips the region to the viewport, so a curve
  that leaves through the top or bottom still shades beneath it. It emits one
  derived path that SVG, Canvas and Node export paint in the curve colour at a
  fixed quarter opacity beneath the curve. Write fills up to the x reached by
  the revealed line; a wholly offscreen curve sweeps across the viewport.
  Equations never shade. The flag follows the discrete
  expression switch, writes one graph leaf and is a Composition value; the
  region is never serialized. Shading is painted content, so the hit SVG picks a
  graph by its region like a filled shape. Portable format v7 is required only
  when a graph is shaded, so a v6 reader fails explicitly instead of silently
  dropping the region; v1–v6 remain readable.
- Extensible mathematics (2026-10-11) keeps one searchable creation palette in
  `editor.math_tools`; adding a family does not add a toolbar button. Function
  plots retain their own definition/evaluator. The first diagram family stores
  a `scene.GeometryDefinition` per Composition: stable point IDs, free coordinates
  or midpoint references, vector endpoint references, angles and deletion
  tombstones. IDs belong to the diagram, so copying/reusing a diagram preserves
  its internal relationships while creating independent root identities.
  `math_geometry` is a host-independent, bounded one-way construction evaluator;
  missing/cyclic references are unresolved rather than guessed. New edits and
  portable files validate references, finite coordinates and at most 128 stored
  elements per collection. Concurrent incompatible rewiring can still leave an
  unresolved construction; the inspector reports it for correction.
  Free points interpolate using Position timing; topology switches at half base
  progress. Derived paths/labels feed the same `render.Shape.Diagram` boundary
  in SVG, Canvas/GPU and Node, with per-element Write. Point gestures invert the
  full world affine matrix and use screen-sized handles inside parent clips.
  Boundary edits retain Yjs collections and write intended leaves. Selective
  Undo/Redo preserves peer-used points, their construction ancestors and required
  reference leaves without consuming an earlier action; unrelated pose/style
  edits still undo. AI `setGeometryElement` uses typed plans and validates the
  final diagram before publication, retaining per-element guards for coordinate
  edits and topology dependencies for structural edits.
  Portable geometry uses monotonic, non-Undo format v5 with v1–v4 reads.
  This family avoids turning each point into a Scene object or adding point
  fields to every global animation channel. Internal-point keyframes, global
  constraints remain deferred; additional families join this palette and shared
  render boundary without turning derived paths into document source.
- Networks and 3D surfaces (2026-10-11) extend the same palette and render adapter.
  `scene.NetworkDefinition` retains diagram-local nodes, labelled directed/undirected
  edges, optional weights, bends and tombstones; `math_network` supplies degree
  and deterministic circular arrangement. Limits are 128 stored nodes/256 edges,
  including tombstones. Self-loops and parallel edges are valid; endpoint
  references must resolve. Nodes use the existing affine-aware point gestures.
  `scene.SurfaceDefinition` retains heightfield or parametric expressions,
  ranges, a/b/c, yaw/pitch/zoom, subdivision count and display modes.
  `math_surface` reuses the bounded parser with u/v aliases and triangulates a
  4–48 square grid: at most 14115 expression evaluations and 4608 triangles.
  Invalid vertices and cell-center probes omit undefined/pole-spanning cells;
  this finite heuristic can miss narrow/high-frequency features and is not
  certified topology. `render` uses orthographic projection, viewport clipping,
  face shading and stable mean-depth sorting. Per-triangle antialiasing can leave
  fine seams; intersecting/folded triangles can have occlusion artifacts. This
  object-local surface renderer does not provide a general 3D scene, perspective,
  mesh imports or implicit isosurfaces.
  Per-curve fills/strokes share ordering and Write behavior across SVG,
  Canvas/GPU and Node, with bounded source/geometry caches outside documents.
  Node coordinates and surface a/b/c/yaw/pitch/zoom use Position timing;
  topology, weights, formulas and grid settings switch at half base progress.
  Internal element keyframes and force layout are deferred. Typed AI operations
  `setNetworkElement`/`setSurface` validate the final definitions, emit only changed
  leaves and guard structural/coupled constraints while permitting unrelated peer
  edits. Selective Undo retains peer-used nodes/edges, valid surface ranges,
  display modes and necessary formula/mode dependencies. Concurrent incompatible
  endpoint/range edits report errors for correction, as existing mathematical
  families do. Both families use monotonic, non-Undo format v6 with v1–v5 reads;
  clipboard and reusable motions keep semantic scopes with fresh root identities.
  No new runtime dependency or global animation-property enumeration is needed.
- Graph and diagram picking (2026-10-11) use the presented SVG curves with a 12 CSS-pixel
  interaction stroke, independent of zoom and affine transforms. Selected graphs
  also accept dragging within their transformed bounds. Both supplemental hits
  follow existing painted-object/bounds hits and intersect every evaluated parent
  clip, so they cannot capture another object's painted area or clipped content.
  `ui/stage_hit.mbt` uses a native Canvas `isPointInStroke` adapter and a WeakMap
  of the current path/transform; reusing displayed geometry avoids sampling the
  expression again or adding invisible hit paths to preview/export. This runtime
  geometry is never serialized.
- Numeric graph syntax supports x/a/b/c, pi/e, arithmetic and the functions
  listed in the [studio guide](../apps/studio/README.md#関数のグラフを描く).
  Grammar v2 additionally supports y and one equality for implicit curves.
  It has no host callbacks or code execution. Input is capped at 512 characters
  and 128 parser nodes; coefficients/ranges are finite within ±100000 and known
  discontinuities at most 32. For y=f(x), adaptive midpoint/quarter probes use 0.5 logical
  scene pixels as a subdivision threshold, with depth 10, 16384 evaluations and
  4096 chords per plot. Lines are clipped before generating paths, and the
  unclipped chords are kept so shaded regions can close before clipping;
  undefined samples and unresolved jumps split branches. Reaching a bound omits unresolved
  portions and reports it in the inspector. This is a drawing heuristic, not a
  certified global error bound or proof of continuity; extreme oscillation and
  narrow features can be missed. `render` owns bounded expression/geometry caches,
  which are never serialized into documents. Symbolic algebra is deferred;
  additional mathematical kinds can use the same boundary.
- Canvas and export sizing are separate (2026-10-03): canvas controls edit only
  Scene width/height leaves, preserving poses, motion and peer edits through Undo.
  A size change cancels gestures using the old coordinate mapping. Export's pure
  `exporting.Resolution` derives an aspect-preserving output size from the current
  source before capture; `exporting.plan` validates it and the browser probes codec
  support at that size. This permits custom/4K output without scaling document
  objects or changing the Node renderer's published resource limits.
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
node scripts/moon.mjs test --target wasm moonbit/motion moonbit/math_plot moonbit/math_geometry moonbit/math_network moonbit/math_surface moonbit/proposal_plan moonbit/editor moonbit/scene moonbit/render moonbit/exporting moonbit/audio moonbit/media_pipeline moonbit/render_job
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

Function graph verification (2026-10-10, working tree based on `e19bc49`) used
the pinned MoonBit compiler, Node 24.13.0 and Chromium 153.0.8010.12 with isolated
Node room storage. Type/API checks, production web build and source/suite audits
passed, alongside 78 MoonBit JS tests, 75 WASM tests, 834 studio tests, 21 headless
tests and 5 extension checks. The browser selection below passed 41 tests,
including graph authoring, peer edits, Undo, legacy imports, clipping and
SVG/Canvas/GPU pixel comparisons with Write and coefficient cache invalidation.
A fresh Chromium context after an actual Node process restart recovered the
expression, coefficient, identical SVG curve and saved version 4 project.
Headless checks independently decoded graph PNG/MP4 outputs. These checks ran
locally without live provider calls; production deployment is recorded below.
Production export verification on 2026-10-10 downloaded a 320 × 180 H.264 graph
MP4 with 24 frames over 0.8 seconds. FFmpeg independently decoded every frame
and confirmed changing graph geometry.

```sh
POIETRA_TEST_URL=http://127.0.0.1:5442 pnpm --dir apps/studio exec playwright test graphs.spec.ts primitives.spec.ts clipping.spec.ts undo-objects.spec.ts painter-preview.spec.ts ai-create.spec.ts --workers=2
```

Graph pointer verification (2026-10-11) reproduced difficult picking on
production Chromium at 1440 × 900, using an isolated 1280 × 720 graph-only room.
The default curve's 2-unit stroke occupied 1.19 screen pixels: normal offsets
of 0.5 px selected the graph, while 0.75 px did not. Axes and grid lines also
selected it, but the selection outline and empty interior did not; dragging
the selected empty interior cleared selection without moving the graph.
The new pointer regression failed on the previous release and passed with
supplemental graph picking: a 4 px offset selects, 8 px does not, and selected
empty-viewport drags move the graph. Local Chromium checks passed 45 representative
tests covering graph gestures, nested rotated clips, overlapping objects,
selection, Undo and SVG/Canvas/GPU rendering. The final 8-test graph suite also
passed after adding zero-width-stroke exclusion, including screen-pixel picking
at 50%/150% zoom with rotated nonuniform scale, coefficient changes, peer sync,
Undo and Escape cancellation. The production build, type/API checks, source/suite
audits and 5 isolated extension checks passed; source audit found no executable
application TypeScript. These are correctness checks, not performance measurements.

```sh
POIETRA_TEST_URL=http://127.0.0.1:5442 pnpm --dir apps/studio exec playwright test graphs.spec.ts clipping.spec.ts primitives.spec.ts marquee.spec.ts undo-objects.spec.ts painter-preview.spec.ts --workers=2
```

Implicit curve verification (2026-10-11, working tree based on `9644064`) used
the pinned MoonBit compiler, Node 24.13.0 and Chromium 153.0.8010.12 with isolated
Node/workerd storage. The release web build, captured API/type checks,
source/suite audits and production dry run passed. Targeted pure-package tests
passed 41 cases on both JS and WASM; studio passed 840 tests, headless rendering
22 tests and isolated extension checks 5 tests. Contour cases include connected
circles, an elliptic curve's separate oval/open branch, saddles, poles, undefined
regions, coefficient scaling and bounded work. Headless checks independently
decoded animated equation PNG/MP4 outputs and checked SVG geometry.
The 46-test browser selection above passed, including equation authoring,
invalid drafts, picking/dragging, peer edits, Undo, portable-file reload,
clipping and SVG/Canvas/GPU agreement. The isolated workerd integration passed
real process restart, dependency persistence, offline peer edits and 500 local
sockets. These correctness checks do not establish production capacity or
verify live provider calls. Equations remain numerically sampled as described
above; verification does not establish complete topology for arbitrary inputs.

Mathematical diagram verification (2026-10-11, working tree based on `05c57c1`)
used the pinned MoonBit 2026-09-15 compiler, Node 24.13.0 and Chromium
153.0.8010.12 with isolated Node/workerd storage. The release build, captured
API/type checks, source/suite audits, production dry run and 5 isolated extension
checks passed. MoonBit JS passed 90 cases; targeted `math_geometry`, `scene`,
`render`, `proposal_plan` and `render_job` WASM checks passed 32. Studio passed
849 tests and the complete headless suite passed 23. The final rendering/API
selection passed 14, including Japanese diagram glyphs and independently
decoded moving-vector/midpoint MP4 output.
The 59-test browser selection below passed, covering the mathematics palette,
point gestures, reference validation, peer edits, Undo/cancellation, save/import,
affine parents/clipping, existing graphs/text/selection, and SVG/Canvas/GPU
agreement during Write. The isolated workerd integration passed offline edits,
selective Undo, hibernation, dependency persistence, forced process restart and
500 local sockets. These are correctness checks; they do not establish faster
rendering or production capacity, and live provider calls were not exercised.

```sh
POIETRA_TEST_URL=http://127.0.0.1:5442 pnpm --dir apps/studio exec playwright test math-geometry.spec.ts graphs.spec.ts primitives.spec.ts clipping.spec.ts text-editing.spec.ts marquee.spec.ts painter-preview.spec.ts undo-objects.spec.ts ai-create.spec.ts --workers=2
```

Network and 3D surface verification (2026-10-11, working tree based on `fe72e65`)
used the pinned MoonBit 2026-09-15 compiler, Node 24.13.0 and Chromium
153.0.8010.12 with isolated Node/workerd storage. The release build, captured
API/type checks, source/suite audits and 5 isolated extension checks passed.
MoonBit JS passed 104 cases; the targeted math, scene, editor, render and proposal
packages passed 93 WASM cases. Studio passed 865 tests and headless rendering
passed 26, including independently decoded animated network/surface MP4 output,
Japanese labels, sphere/torus meshes and undefined-cell omission.
The browser selection below passed 63 tests, covering both palette entries,
node gestures, self-loops/parallel edges/weights, surface formulas and view edits,
invalid drafts, peer edits, selective Undo/cancellation, portable v6 save/import,
affine parents/clipping, reusable motions, existing graphs/text/AI proposals and
SVG/Canvas/GPU agreement with Write, opacity and sphere/torus occlusion.
The isolated workerd integration passed offline editing, hibernation, pending
dependencies, forced process restart and 500 local sockets. New v6 node/edge
leaves, deletion tombstones, formulas and camera settings restored without any
previous client repopulating the server. These are correctness checks, not
performance or production-capacity measurements; provider HTTP was mocked.

```sh
POIETRA_TEST_URL=http://127.0.0.1:5442 pnpm --dir apps/studio exec playwright test spatial-math.spec.ts math-geometry.spec.ts graphs.spec.ts clipping.spec.ts canvas.spec.ts motion-template.spec.ts text-editing.spec.ts undo-objects.spec.ts undo-tracks.spec.ts ai-create.spec.ts ai.spec.ts ai-dogfood.spec.ts --workers=2
node apps/studio/tests/collaboration-worker.integration.mjs --port 8790
```

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

The 2026-10-12 output-limit decision removes headless-only resolution, duration
and frame quotas that blocked local exports. `exporting` owns the shared
dimension and frame-index bounds used by validation and published capabilities;
`maxVideoDurationMs: null` means there is no fixed duration quota. Local deadlines
are opt-in; the HTTP adapter owns its existing deadline. Cancellation still
terminates synchronous WASM work. Input/media validation and the output byte
bound remain in place; larger jobs still need memory for intermediate and final
encoded buffers.

Validated on 2026-10-12 with MoonBit `0.10.13+cbb11c36f`, Node `26.11.1` and
Python `3.14`: shared JS/WASM validation, independent decoding of 4K and
61.6-second MP4s, CLI/MCP/HTTP contracts, cancellation/deadlines, Studio tests,
public API types and the built bilingual developer pages. Logs are retained in
ignored `test-results/headless-limits-2026-10-12/`. This was local validation,
not a production deployment.

## Deployment and limits

Last recorded deployment: **2026-10-12 00:07 JST**, Worker version
`540e5b71-7ba4-4b09-8c01-590de1746e69` at 100% on `poietra.com`.
The application source was clean commit `dc1ae0b91b59c60d35f2c5fb679745a14d5b732b`,
tagged `prs-dc1ae0b`, with all eight checks passing in
[CI run 38148724104](https://github.com/Poietra/poietra/actions/runs/38148724104).
Its predecessor was `9a901272-73fa-4f75-91a3-61369a0c5409`.
The production build and dry run passed with the pinned MoonBit compiler and
Node 24.13.0. Before promotion, version metadata confirmed identical bindings,
Durable Object namespaces/classes, migration tags, runtime settings and asset
routing. R2, secret bindings, domain and existing workers.dev links were preserved.

Production Chromium 153.0.8010.12 checks covered ten browser cases: graph area
picking, shared shading, selective Undo and portable v7 save/reload; network
gestures and surface editing; figure paste, file selection/drop, shared stored
images, preparation guards, cancellation, distinct requests and restoration.
The seven figure cases passed after the test helper waited for its initial
attachment before typing; the initial run and rerun are retained as evidence.
AI HTTP was mocked in those cases; room storage, image bytes, collaboration and
proposal application used the real production service.

Six dedicated rooms retained their full v1/v4/v5/v6 project snapshots across
the deployment, and the earlier image retained its SHA-256. A new v7 graph with
an equation survived reload and retrieval by a fresh browser without IndexedDB.
Playback and seeking passed. Its exported 320 × 180 H.264 MP4 contained 25 frames
over 0.82 seconds; FFmpeg decoded every frame, and pixel samples confirmed
quarter-opacity shading for wholly offscreen curves, changing coefficients and
visible equation output. English/Japanese pages and health passed; served
bootstrap, client runtime, kernel, schema and OpenAPI hashes matched the build.
No browser errors occurred in the export canary. Live provider login, paid AI
calls and 500 production clients were outside these correctness checks.
Raw logs, version metadata, initial failure trace, screenshots, portable file,
MP4 and manifests are retained in ignored
`apps/studio/test-results/production-prs-2026-10-12-thi44wsz/`.

[Previous deployment record](https://github.com/Poietra/poietra/blob/dc1ae0b91b59c60d35f2c5fb679745a14d5b732b/docs/development.md#deployment-and-limits).
Confirm the active version before deploying again.

Follow the [studio deployment procedure](../apps/studio/README.md#実行と配置).
The default Wrangler config uses isolated storage; only explicit `production`
commands target the existing service. A dry run or successful CI is not a deployment.
A Worker rollback restores code/assets, not room data; it must understand version
7 graph shading, version 6 networks/surfaces, version 5 diagrams and graph grammar v2 equations,
as well as persistent account dismissals. See [current limits](../apps/studio/README.md#現在の制限).

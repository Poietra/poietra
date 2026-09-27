# Poietra

**Make motion together, with friends and AI.**

Poietra is a collaborative motion editor that runs in the browser. Arrange shapes,
text, equations, images and video; animate their properties; mix audio; and export
MP4 or WebM. Friends and the AI assistant edit the same structured objects, so
individual positions, colors and timings remain editable.

[Open Poietra](https://poietra.com) · [日本語の使い方・設定](apps/studio/README.md) ·
[Run locally](#run-locally) · [API / MCP](https://poietra.com/developers/) · [Architecture](#how-it-is-built) ·
[Performance](#performance) · [Issues](https://github.com/Poietra/poietra/issues)

![Poietra's studio, with a canvas, timeline, properties and shared chat](apps/studio/docs/assets/studio.png)

This repository contains the **MoonBit implementation** of
[poietra-hackathon](https://github.com/Poietra/poietra-hackathon). Application logic
runs as MoonBit-generated JavaScript, with a WebAssembly motion kernel and native
adapters for browser APIs and JavaScript libraries. Executable application TS/TSX
has been removed; internal refactoring and performance work continue.

Documentation reviewed **2026-09-22**. The browser/developer-page release is
[`396c26b`](https://github.com/Poietra/poietra/commit/396c26b879bc528ca2066ac2b68675216a9e4e4a).
Cloudflare hosts the editor, documentation and schemas. The headless renderer
runs as a self-hosted Node service or local MCP process, with no hosted render endpoint.
The MoonBit service was last verified in production on **2026-09-22**;
see [deployment status and operations](#deployment-and-limits).

## What you can make

- Share a room link and edit together, with presence, offline reconnection and
  Undo scoped to your own edits. Guests can create and edit projects.
- Compose circles, rectangles, text, LaTeX, Bézier paths, arrows, number lines,
  images and video. Align, group or parent objects and edit their anchors.
- Animate properties with separate start times, durations and easing. Add actual
  intermediate values for returns, pauses and color changes; use Move, Write,
  Fade, Grow or Cut, including custom Bézier easing.
- Import and trim audio/video, adjust volume and export the project or a Scene.
  Save a portable project file containing its media.
- Ask `@codex` in shared chat for structured edits or generated image assets.
  Apply a proposal manually, or send with Ctrl/⌘+Enter to apply after validation.
- Optionally sign in with Google or GitHub to keep a private list of project
  shortcuts. Search by name, sort the list and undo its most recent removal.
  Shared-link editing remains available without login.

The [studio guide](apps/studio/README.md) covers editing, accounts, media,
shortcuts, AI configuration and export. Desktop Chromium is the primary tested
browser; codec support depends on the browser and device.

## Run locally

Use Node.js **24+** (tested: 24.13.0), pnpm **10.23.0**, Python **3.12+** for
adapter generation, and the compiler pinned in [.moon-version](.moon-version)
(`moonc v0.10.13+cbb11c36f`). The following commands use a POSIX shell.

```sh
git clone https://github.com/Poietra/poietra.git
cd poietra
pnpm install --frozen-lockfile

curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moonbit.sh
bash /tmp/install-moonbit.sh "$(cat .moon-version)"
export PATH="$HOME/.moon/bin:$PATH"
node scripts/moon.mjs update

pnpm dev
```

Open **http://localhost:5173**. The homepage opens a new project or an editable
sample; viewing it alone does not create a room or load the editor. Node stores
local data in `apps/studio/.data`. Editing, collaboration, ordinary chat and export
work without an API key. Optional AI/OAuth settings go in `apps/studio/.env`;
see [configuration](apps/studio/README.md#設定).

Run these commands from the **repository root**:

| Command | Purpose |
| --- | --- |
| `pnpm dev` | Build MoonBit and start the Node/Vite development host on port 5173 |
| `pnpm build:moonbit` | Regenerate adapters and facades; build release JS and motion WASM |
| `pnpm build` | Build MoonBit, check types, bundle the editor and prerender EN/JA HTML/Markdown |
| `pnpm --dir apps/studio start` | Serve the completed production build with Node |
| `pnpm test` | Audit sources, build, run extension/API build tests and Vitest |
| `pnpm test:render` | Check headless rendering, independent decoding, HTTP and MCP after building |
| `pnpm render INPUT --format mp4 -o OUTPUT` | Render a portable file without a browser or FFmpeg |
| `pnpm render:api` / `pnpm render:mcp` | Start the local HTTP API / stdio MCP server |
| `pnpm typecheck` | Check declarations and captured public API contracts |
| `pnpm audit:source` | Report source inventory and reject executable application TS/TSX |

After editing `.mbt`, run `pnpm build:moonbit`: Vite does not compile MoonBit.
Restart the Node host after server-side changes. The wrapper
`node scripts/moon.mjs` selects `POIETRA_MOON`, then `.tools/moon/bin/moon`, then
`moon` on PATH. Use it for `update`, `check`, `test` and `version --all` so local
commands use the same toolchain as the build.

## Headless rendering, API and MCP

[apps/render](apps/render/) accepts saved `.poietra.json` files and returns SVG,
PNG or H.264 MP4. It runs in Node 24+ without Chromium, FFmpeg, WebCodecs, native
codec executables or runtime network access. Install the workspace dependencies
and build MoonBit first; fonts and codec WASM come from pinned local packages.

```sh
pnpm build:moonbit
pnpm render project.poietra.json --inspect
pnpm render project.poietra.json --format mp4 --width 1280 --fps 30 -o result.mp4
pnpm render:api
```

HTTP accepts the portable JSON body at `POST /render` and returns the binary
result. `POST /inspect` reports structural compatibility; `GET /capabilities`
lists supported formats and limits. Stdio MCP exposes `poietra_capabilities`,
`poietra_inspect` and `poietra_render`; the latter two use local file paths.
The [Node API](apps/render/index.d.mts) also supports progress and AbortSignal.
See the [Japanese setup and request examples](apps/studio/README.md#ファイルから描画する-api--mcp).

The [developer page](https://poietra.com/developers/) and
[Japanese page](https://poietra.com/ja/developers/) include a working quickstart,
MCP configuration and an editable sample. Agents can discover the
[OpenAPI 3.1.1 specification](https://poietra.com/openapi.json),
[project JSON Schema](https://poietra.com/schemas/project.json) and
[starter file](https://poietra.com/examples/hello.poietra.json) through
[llms.txt](https://poietra.com/llms.txt). The public specification targets
`http://127.0.0.1:8799`; the local service's `/openapi.json` uses its actual origin.
MCP resources expose `poietra://docs/openapi`, `poietra://docs/project-schema`
and `poietra://examples/hello`. Documentation endpoints are public even when
render/inspect/capabilities require a configured bearer token.

Cloudflare serves prerendered HTML or Markdown at `/developers/` and
`/ja/developers/`, selected by `Accept` and `Accept-Language` with matching `Vary`
headers. Explicit `index.md` paths also work. Pages need no application JavaScript;
OpenAPI, schema and examples are Static Assets with cross-origin read headers.
`developer_site` generates both page representations; `render_api` generates
the contract and sample; `project_codec` derives structural JSON Schema from its
file-validation definitions. Runtime validation additionally checks references,
timing and renderer support. Preview these pages with `pnpm build` followed by
`pnpm --dir apps/studio start`.

| Area | Headless support |
| --- | --- |
| Drawing | Shared shapes, text, Japanese fonts, MathJax, Write and Glow |
| Animation | Composition/Transition timing, parent transforms, intermediate values and multiple Scenes |
| Images | Embedded PNG/JPEG; WebP and external URLs are rejected |
| Audio | Embedded mono/stereo PCM WAV, trimming, resampling, gain and mute; MP4 contains MP3 audio |
| Not yet supported | Imported video, compressed source audio, WebM output and AAC encoding |
| Limits | 32 MiB input, 64 MiB output, 1920 px per side and 2,073,600 pixels; MP4 ≤60 seconds and ≤1800 frames |

The HTTP server binds to loopback by default and requires a bearer token when
binding elsewhere. HTTP/MCP each serialize renders; every render owns a worker
thread, terminated on cancellation or timeout (120 seconds by default).
CLI/MCP publish complete files without overwriting existing paths. Unsupported
content fails explicitly. Inspection does not decode assets; malformed media can
still fail during rendering. This is a Node service; compatibility with Cloudflare
Workers and deployment of a hosted render endpoint remain unverified.

## How it is built

The [MoonBit packages](moonbit/) hold application behavior.
[apps/studio/](apps/studio/) holds native facades, styles, assets and integration
tests. The pure editing/evaluation core is independent of React and host APIs.

| Layer | Main packages | Responsibility |
| --- | --- | --- |
| Model and engine | `scene`, `motion`, `geometry`, `render`, `audio`, `exporting`, `editor`, `proposal_plan` | Typed documents, edit plans, prepared evaluation, geometry and audio mixing |
| Collaboration | `collaboration`, `boundary`, `browser_editor`, `browser_undo`, `browser_chat` | Yjs leaf edits, immutable snapshots, selective Undo and shared chat |
| Browser | `ui`, `browser_render`, `browser_media`, `browser_export`, `browser_projects`, `browser_kernel` | React UI, drawing, resource lifetimes, decoding, export and portable files |
| Portable files | `project_codec` | Shared generated record adapters, bounded parsing and document validation |
| Headless rendering | `render_job`, `media_pipeline`, `headless_render`, `render_http`, `render_api`, `math_render` and `apps/render` | Typed render orchestration, media contracts, JS/HTTP boundaries, OpenAPI, WASM codecs and MCP |
| Services | `schemas`, `proposals`, `ai_service`, `auth_policy`, `auth_service` | Input validation, guarded AI proposals, OAuth and private project lists |
| Hosts and storage | `node_*`, `worker_*`, `room_assets`, `r2_upload`, `http_policy`, `http_runtime` | HTTP/WebSockets, persistence, quotas and atomic media publication |
| Public site | `site`, `site_shell`, `site_boundary`, `browser_site`, `developer_site`, `site_build` | Localized content, lazy editor entry, developer documentation and prerendering |
| Browser linking | `client_runtime` | Generated shared entry for six browser packages |

### Document and collaboration contracts

| Concept | Scope |
| --- | --- |
| Project | Ordered Scenes; portable saves include media, excluding account data and chat |
| Scene | Canvas, object identities, parent links and independent audio tracks |
| Composition | A still state, its hold duration and each object's independent appearance/transform |
| Transition | Animation between adjacent Compositions, with object and property timing |
| Account | Private sessions and room shortcuts, separate from room editing access |

Parent transforms compose as affine matrices. Reparenting preserves geometry in
all Compositions, including retained states; anchor edits compensate position in
the edited state. Sparse shear preserves rotated, nonuniform scales. Evaluated
world matrices are runtime data.
Visibility, opacity, paint order and selection groups remain independent of
parenting. Intermediate keyframes hold actual values at normalized times within
a property's interval, with Composition-linked endpoints and outgoing-segment
easing. Reparenting preserves Composition poses; intermediate keys and paths stay
in parent coordinates and may need adjustment. These features use document
version 2; version 1 files remain readable.

Yjs stores changes at individual fields. Readers receive immutable, structurally
shared snapshots; writers invalidate touched branches before observers run.
Structural deletion and keyframe deletion retain CRDT records. Selective Undo
preserves received peer edits, including dependent parent/point changes, and may
retain a shared creation with a notice. Unreceived offline work cannot be known.
Pending Yjs dependencies are persisted even before they affect the visible view.

Room transport now targets 500 participants, with a 512-socket admission cap to
leave reconnect headroom. `client_presence` sends only the local awareness clock;
remote changes still notify the UI. Browser cursor emission adapts from 50 ms to
1 second as the room grows, and received presence packets publish one UI snapshot
per 16 ms while reusing unchanged peers. Selection and local editing stay immediate.
Cursor throttling compares context values: repeating the same Scene/Composition
IDs does not bypass it. Actual context changes, selection and pointer exit flush
pending presence immediately.

`client_sync` uses y-websocket's public `WebSocketPolyfill` option to losslessly
merge outgoing document updates. The local document, rendering, IndexedDB and Undo
still update immediately. The first queued update starts a bounded timer: 16 ms
up to 32 peers, 50 ms above that; further edits do not postpone it. Queues hold at
most 128 updates / 256 KiB and flush before sync/control frames and close, on
gesture end or Undo/Redo, and when the page is hidden. While hidden or leaving,
subsequent lifecycle writes also send immediately; this preserves chat cancellation
performed by a later page-exit handler. Returning to the page restores batching.
Chat transactions flush immediately; active AI requests cancel on navigation
before the browser aborts their HTTP fetch, with that listener removed on settlement.
A disconnected socket discards its queue;
the existing document and IndexedDB participate in the normal reconnect handshake.
Each socket owns its timer, so an old connection cannot publish on its replacement.

`server_sync` shares bounded output batching between Node and Workers. Worker
input batches are losslessly merged with Yjs, journaled in one SQLite transaction,
then applied and published. Ordered sync replies flush pending input first, so
portable-file creation still waits for durable acknowledgment. Up to 32 sockets,
document batching uses the next timer turn without an added delay; larger rooms
use nominal 10 ms input / 50 ms output windows. Both queues retain at most 128
small updates or 256 KiB before flushing; a larger individually valid update
flushes immediately. The journal compacts at 256 batches or 4 MiB. Unresolved Yjs
dependencies remain in both merged journal entries and snapshots.

Presence coalesces over 100 ms and keeps the latest clock per client. Socket and
owner indexes rebuild from attachments after hibernation; stale closes cannot
remove a replacement. A replacement retires the old socket and releases its
admission slot immediately. Full rosters are split into packets accepted by older
clients: at most 100 entries and 16,000 bytes. Each entry is encoded once, and its
actual UTF-8 bytes determine the packet boundary. Native socket sends use the
existing typed mizchi binding. Node disconnects clients with more than 1 MiB of
queued output; the
Workers WebSocket API does not expose Node's `bufferedAmount`, so that guard is
Node-specific. This transport keeps the existing room authority and storage
schema; it does not introduce a new namespace or document format.

[Product rules](apps/studio/AGENTS.md) define these contracts, and
[root implementation rules](AGENTS.md) describe the editing boundaries to preserve.

### UI, rendering and resource ownership

```mermaid
flowchart LR
  document[Immutable project] --> session[Edit session and selection]
  session --> panels[Document panels]
  document --> prepared[Prepared scene evaluation]
  prepared --> preview[Stage and audio]
  prepared --> export[Export from captured project]
  clock[Local playback time] --> preview
  clock --> indicators[Time labels and seek markers]
  presence[Presence] --> people[Peer overlays and participants]
  chat[Room chat] --> aside[Chat and unread count]
  status[Connection and Undo status] --> controls[Status and history controls]
```

Playback preparation resolves segments, tracks, hierarchy, layer order and curves
once; repeated evaluation uses the shared engine for preview and export. Editing
reads the current Composition. Static holds without visible video can reuse a
prepared frame while export still encodes every timestamp.
The editor and project preview share the same hold key. Its owning playback
program is also a memo dependency, so edits and Scene changes cannot reuse an
old frame. Holding the visual frame leaves the clock and audio running normally.
Project preview selects Canvas or SVG fallback before preparing a frame. Canvas
receives the source frame directly; it neither serializes a hidden SVG nor
converts video to PNG before the painter decodes it. If Canvas fails, preview
uses the stage's typed preparation state and retained SVG nodes. Legacy renderers
with only `frameToSvg` remain supported. Cancellation prevents prepared video
from crossing Scene boundaries or publishing after the preview closes.
During active Scene playback with a visible Canvas, the editor retains its hidden
SVG hit surface without updating it. Pause, seek while paused, and Canvas failure
restore current SVG geometry; selection and editing still use that hit surface.
As of **2026-09-27**, preparation decodes directly into its owned typed snapshot;
it retains a separate native copy only of object metadata required by public
frames. It no longer clones or retains a second set of Composition states,
tracks or audio data. Native object extensions, nulls and stable references
within one program remain available to JS consumers.
After compilation, the program retains frame dimensions and the required poses,
tracks and curves. It releases the source Scene containers and original key maps;
editing data and deletion tombstones remain untouched in the document.
One typed `ObjectLayout` also shares layer order and the lazily prepared parent
graph across all holds/transitions. Composition matrices remain independent;
reusing structure never reuses evaluated world transforms or serializes them.
Editing also retains that typed layout while an immutable snapshot's object map
is unchanged. Only `readProject` registers trusted snapshots: public caller-owned
objects, even shallow-frozen ones, and in-transaction reads use fresh conversion.
Weak keys follow snapshot lifetime; metadata, order and parent edits invalidate
the layout, while pose edits still evaluate current world matrices.
The reader likewise registers immutable Composition snapshots so editing can
share decoded `ObjectState` leaves. The generated Composition adapter accepts a
typed leaf decoder; it does not decide ownership or cache caller-owned inputs.
State maps remain private to each decode, and public frames receive fresh native
state/path records. Old snapshots, nested writes and accessor-based inputs keep
their respective value semantics.
Audio edits likewise reuse a validated typed media leaf from the current immutable
Scene. Clip values and source bounds are checked on every command. Changed media,
caller-owned patches and in-transaction inputs validate afresh; a shallow freeze
does not establish ownership. The weak cache retains neither documents nor extra
source bytes. The portable codec shares the same field schema and validates media
once before checking clip values, instead of rescanning it inside the audio record.
Portable parsing and project asset capture use an operation-owned typed
`AssetValidation` table. A repeated immutable source string shares its format
check; dimensions, MIME, duration, waveform and clip fields remain independently
validated. The table is released with the operation and never trusts a mutable
native record. Conflicting references still fail before asset transfer.
The layout resolves parent and paint indices once. Composition and transition
evaluation share one traversal over current pose arrays; neither rebuilds an
ID-keyed world-matrix map. Authored paint order, hidden ancestors and missing
poses remain independent of that traversal order. The temporary parent-ID map
is released after indexing, and evaluated arrays belong to each individual frame.
Transition evaluation resolves path travel, presence opacity and growth before
constructing the base immutable pose, avoiding successive whole-state copies.
Intermediate value keys still override that pose after those animation rules.
Curve preparation validates and groups authored points by typed property once,
constructing endpoints only for nonempty groups. The inspector prepares just
its selected curve with the same endpoint and equal-time-key rules.
Write order is one `scene.WriteOrder` enum across tracks, editing/proposal plans,
evaluated frames and rendering. Generated adapters and declarations preserve the
public `together` / `sequential` strings; pure packages no longer convert this
value through strings. The `editor` and `render` type aliases share that enum.
Timeline segments likewise carry `SegmentKind`; preparation and evaluation match
both cases exhaustively, while native segment records keep their existing strings.

Document panels, presence, chat and the local clock have separate subscriptions.
Scene tabs, layers, timeline structure and media rows retain presentation inputs
when their displayed fields stay unchanged. Resource preparation depends on text
across Compositions and visible image assets, so pose/timing edits reuse resources.
A failed preparation can be retried without changing the document.

One typed render view drives serialized SVG and retained stage nodes. Opaque
shapes without effects use cached native geometry for direct Canvas painting;
opacity and Glow retain isolated compositing. Sequential video decoding keeps
owned pixel surfaces and resets on seeking. Async owners suppress stale results,
release resources on cancellation and preserve encoder/upload backpressure.
The public SVG view uses fixed native records and a single output array; it does
not allocate intermediate key/value tuples or expose MoonBit record layout.
The stage memoizes the corresponding React element tree with that view, so
presence/selection updates do not rebuild unchanged SVG elements. React owns a
shallow copy of each props record; external renderers can return frozen views.

As of **2026-09-27**, the Canvas painter captures just the consumed frame values
into a typed `PaintFrame` before its first await. Shape, text and raster stages
share those records instead of cloning the native frame and repeatedly decoding
its objects. Video requests capture their metadata and publish prepared images
separately from the input; decoder surfaces retain their existing ownership.
Public JS drawing adapters remain available. Evaluation-to-UI marshalling still
exists; this change removes the painter's deep copy and internal round trips,
not every browser boundary conversion.

Preview uses a one-use completed `PaintDraft`: the painter lends its staging
surface until the next render, cancellation or disposal. After checking the
current Scene, dimensions and owner lifetime, the UI copies it directly to the
display. This removes the intermediate Canvas copy and releases that unused
pixel buffer. An enum selects draft or target-based painters once at startup;
public `render` and custom painters without draft support keep their contract.
Export still owns its target and each encoded frame. Native WebGL and SVG paths
share typed capture, cancellation and draft lifetime rules.

The lazy export facade captures input/settings before loading the encoder and
transfers that private snapshot to MoonBit without cloning it again. Direct
MoonBit export entries retain their own capture contract. The dialog keeps typed
presentation values (title, duration and sizes) apart from its Scene/Project input;
progress and completed/download-again state no longer retain document snapshots
or recompute their duration. Custom exporters still receive a UI-owned copy.

The headless path reuses `scene.PreparedScene`, `motion`, `render`, `audio` and
`exporting`; `math_render` shares equation preparation across browser and Node.
Static holds reuse rasterized pixels while every output frame remains encoded.
The document schema and public JS API remain unchanged.

`render_job` accepts a typed `RenderRequest` and `Backend` and returns a
`RenderResult`. It owns timeline evaluation, validation, audio mixing and the
render loop, with no `Any`, JS FFI or HTTP dependency. The prepared timeline hides
its mutable internals; callers must keep its source project stable until done.
`headless_render` converts native host objects through opaque FFI handles and
checks buffers before constructing typed values. `render_http` owns HTTP routing;
CLI and MCP use the same Node facade. Node adapters own worker threads, I/O and
npm codecs. `project_codec` supplies the shared portable-file parser and generated
record marshalling, so headless rendering no longer imports the editing boundary.

The reusable [media_pipeline package](moonbit/media_pipeline/model.mbt) has no
Poietra model, host or external package dependencies. It defines checked
`RgbaFrame` and stereo `StereoPcm` values, typed rasterizer/audio/encoder ports,
and `with_encoder` for cleanup. Frame/sample buffers remain owned by the producer
until each awaited consumer returns. Normal completion, failures and cancellation
release the encoder once; cleanup failure preserves the original render error.
Standalone consumer tests compile this package on JS and WASM and reject swapped
audio/video inputs, unchecked frame construction and incompatible callbacks.
It is an internal reusable package, not a published registry module. Separate
publication can follow another consumer's requirements without extracting Scene
semantics or the Node codecs into this interface.

For this backend, SVG is rasterized by [resvg WASM](https://github.com/thx/resvg-js),
H.264 is encoded by [minih264](https://github.com/TrevorSundberg/h264-mp4-encoder),
and [Mediabunny](https://mediabunny.dev/) muxes packets without a second encode.
Audio uses its [MP3 extension](https://mediabunny.dev/guide/extensions/mp3-encoder)
and [LAME](https://lame.sourceforge.io/). Dependencies are pinned in
[apps/render/package.json](apps/render/package.json). License notices include
resvg/MPL-2.0, the H.264 wrapper/MIT, minih264/public domain, libmp4v2/MPL-1.1,
the MP3 extension/MPL-2.0 and LAME/LGPL; retain their upstream notices when distributing.
After inspecting [mizchi/canvas-mbt](https://github.com/mizchi/canvas-mbt), we
kept the existing SVG representation because its current
[missing filters and shadows](https://github.com/mizchi/canvas-mbt/blob/main/TODO.md)
would leave Glow unsupported. Backend conformance tests cover SVG `pathLength`,
actual H.264 keyframes and MP3 priming; browser-identical rasterization is not claimed.
The resvg host still adapts SVG path lengths after serialization and buffers an
intermediate H.264 MP4 before final muxing. Typed boundaries do not remove those
remaining compatibility and long-video memory constraints.

### Build and host boundaries

`pnpm build:moonbit` produces release modules under `_build/` and copies the motion
WASM into `apps/studio/public/wasm/`. Generated code has three sources of truth:

| Source | Generated output |
| --- | --- |
| [scene model](moonbit/scene/model.mbt) via [generate-adapters.py](scripts/generate-adapters.py) | [Shared record marshalling](moonbit/project_codec/adapters.mbt) and public [scene types](apps/studio/shared/scene-types.d.ts) |
| [bindings.json](scripts/bindings.json) | Simple native JS facades forwarding public calls |
| Package `moon.pkg` exports via [client-runtime.mjs](scripts/client-runtime.mjs) | Shared browser entry/export tables |

The browser links `boundary`, `browser_editor`, `browser_media`, `browser_render`,
`browser_undo` and `ui` once through `client_runtime`. The
[Vite adapter](apps/studio/scripts/moonbit-client.mjs) redirects browser imports
and rejects duplicate standalone copies. Node, Worker and SSR use standalone
artifacts. The homepage, file/export operations, MathJax and Mediabunny retain
separate or lazy loading. Do not edit generated tables or duplicate domain records.

The [MoonBit dependency pins](moon.mod) include mizchi's JS bindings **0.13.0**,
`npm_typed` **0.1.16** for React/Zod and `cloudflare` **0.1.12** for selected
SQLite/R2 bindings. React/Base UI, Yjs, MathJax, Mediabunny and the OpenAI SDK remain
JavaScript runtime dependencies. Native adapters connect those APIs to MoonBit;
package versions are pinned in [package.json](apps/studio/package.json) and
[pnpm-lock.yaml](pnpm-lock.yaml).

### What the remaining TypeScript represents

Source audit rerun **2026-09-27**, including the standalone render host:

| Source purpose | Files | Physical lines |
| --- | ---: | ---: |
| MoonBit application | 310 | 61,750 |
| Native JS runtime adapters | 119 | 1,326 |
| Executable application TS/TSX (studio and render hosts) | 0 | 0 |
| TypeScript tests, fixtures and test configurations | 155 | 17,945 |
| Public/environment type declarations | 114 | 1,997 |
| TypeScript benchmark/tool configuration | 5 | 140 |

These counts include generated code, comments and blanks; they exclude external
library implementations and do not measure delivered bytes. Use `pnpm audit:source`
or `node scripts/source-inventory.mjs --json` for the full inventory, including
MoonBit tests and JS tooling. CI rejects executable TS/TSX in the four studio
application directories and the render host. Historical comparison implementations are available in Git and
[poietra-hackathon](https://github.com/Poietra/poietra-hackathon).

Internal refactoring remains: [media editing commands](moonbit/browser_editor/media_commands.mbt)
still merge native patches before validation, and some UI/host orchestration uses
`Any`. Document Context adapters still observe edits even when panel content is
reused. Further work is to move domain decisions into typed plans, narrow those
subscriptions and reduce the still-large editor entry. Zero executable TS is an
inventory result, not completion of these changes.

## Add a feature

1. Define domain data in `moonbit/scene/model.mbt` and kinds in
   `moonbit/scene/kinds.mbt`. Put pure edit decisions in `editor` and shared
   evaluation in `scene`/`motion`; keep React, Yjs and platform objects at the host
   boundary. Read the applicable [implementation](AGENTS.md) and
   [product rules](apps/studio/AGENTS.md).
2. Implement validation, persistence compatibility, commands, evaluation,
   rendering and UI as needed. Generated record types do not implement these
   behaviors. Object creation, clipboard and media imports share
   `editor.ObjectInsertion`; Scene/Composition defaults use `scene/creation`, with
   limits and creation decisions in `editor/structure_commands`.
3. Preserve collaboration intent. Property channels share enumeration/lookup in
   `scene/editing`; typed plans identify changed leaves. Retain existing Yjs
   timing parents. Validate all targets and encode detached values before any
   write: a Yjs transaction cannot roll back earlier writes when conversion fails.
4. Export host-facing functions in the package's `moon.pkg`, with a precise
   adjacent `.d.ts` contract and a `scripts/bindings.json` entry for direct
   forwarding. Run `pnpm build:moonbit` to regenerate adapters/facades/shared
   exports. Check existing mizchi bindings before adding a native API boundary.
5. Run `pnpm test`, `pnpm typecheck`, pure-core tests on JS/WASM, and the
   [relevant browser/runtime checks](#checks). Verify preview/export agreement,
   offline edits and selective Undo for changes that affect those behaviors.

`pnpm test:extensions` adds a nested optional record and callable API in an
isolated copy, regenerates and compiles them, checks standalone/shared-runtime
calls and rejects incorrect TypeScript consumer fields. The contract gate checks
108 captured public modules while allowing new exports; shared-runtime tests
compare 219 function exports and their arity.

For a headless backend, implement `render_job.Backend` using the contracts in
`media_pipeline`; keep native conversions in its adapter. New formats belong in
`render_job.Format` and its exhaustive matches. Add media contracts only when a
consumer needs them, and preserve the standalone JS/WASM compilation test.

## Checks

Application revision `cc615e0` passed the complete
[CI run 36280136534](https://github.com/Poietra/poietra/actions/runs/36280136534)
on **2026-09-27**: 757 Vitest checks, 58 MoonBit JS checks, 55 WASM checks,
177 main browser checks, ten export checks, six media checks and 28 production
page checks. Generated bindings, warning-free MoonBit types, public TypeScript
contracts, five extension/linking checks, 19 headless API/MCP checks and the
production build also passed.
[.github/workflows/check.yml](.github/workflows/check.yml) is the authoritative
selection; these counts describe that run.

The subsequent project-preview change passed 757 Vitest checks, five extension/
linking checks, public contracts and the production build locally. Its 39 selected
browser checks cover Canvas/SVG fallback, retained nodes, delayed video completion,
Scene changes, preparation failure/retry, panel subscription isolation and actual
MP4/WebM export. Native video preview performs no PNG conversion; legacy SVG-only
renderers and cancellation remain covered. This selection is narrower than CI.
The hold-key follow-up passed the build/contracts and 18 selected browser checks,
including both rendering paths, clock progression, document/Scene invalidation,
dynamic video during holds and independent MP4/WebM decoding.
The editor hit-surface follow-up passed the build/contracts and 32 selected
browser checks. Both legacy and draft painters keep visible Canvas pixels moving
without rebuilding SVG; pause restores matching positions and live painter failure
restores an animated SVG. Selection, drag, resize, curves, Glow and resource retry
remain covered.
The asset-validation change passed 773 Vitest checks, five extension/linking
checks, 58 MoonBit JS and 56 WASM checks (including `assets`), 19 headless checks,
public contracts and the production build. Its 21 browser checks cover portable
images/audio, cross-room copying, cancellation, atomic failure and real MP4/WebM
image rendering. New regressions reject changed source tails and invalid metadata
after a duplicate source, while preserving independent valid waveforms.

Actual workerd verified offline edits, selective Undo, ordered durable replies,
compaction, hibernation, late closes, process restart and pending dependencies.
The 500-connection regression uses one real editing browser, a protocol observer
and 498 idle sockets. With controlled browser time, 20 actual canvas cursor moves
within one second publish once; 90 pointer moves before advancing the timer update
the local view immediately and flush one document packet at pointer release.
Separate deterministic checks verify timed continuous editing, queue bounds,
page lifecycle writes and chat cancellation on reload. These are packet-count and
correctness checks, not measurements of 500 active browsers or WAN latency.
The load-test results and generator limitations are recorded below.

Node/workerd integrations also passed media persistence, R2 migration and failure
recovery, account isolation, callback races and expiry across Worker restarts.
Account UI tests use mocked authentication responses; the Worker tests exercise
persistent accounts with mocked provider HTTP. They do not verify live OAuth
completion or paid AI calls.

The preceding API/MCP documentation addition was verified on **2026-09-22**:
19 headless/contract tests, 701 Vitest checks, five build/API checks, 51 MoonBit
JS tests, 48 WASM checks, public type contracts and a complete production build.
All 28 production-page browser checks passed, including English/Japanese
developer pages at 1440/390 px with JavaScript disabled. The final typography
adjustment passed the two developer-page checks again. Raw HTTP checks passed
against both Node and real local workerd for HTML/Markdown negotiation, locale,
HEAD, cache validators, real 404s, OpenAPI/schema/example/configuration files;
workerd also verified Static Assets CORS headers. OpenAPI metadata was checked
against the official 3.1 schema; request and response schemas are tested against
actual API responses, including an authenticated MP4 render of the public sample.
The real-workerd collaboration suite also passed offline edits, selective Undo,
hibernation, compaction, process restart and pending update recovery. Public HTTP
and both developer-page browser checks passed again against `poietra.com` after
deployment, and its downloaded sample rendered locally to a 30-frame MP4.

Nine targeted browser regressions also passed on **2026-09-21** for portable
files/images, parenting/keyframe round trips, equation geometry, resource
invalidation/recovery and shared SVG rendering. The headless checks decode all
H.264 frames and MP3 samples with independent WASM
decoders, verify timing/trim/gain/mute, exercise HTTP/MCP, oversized requests and
cancellation, and render with subprocess launches and network fetch disabled.
They also verify typed-package isolation, invalid consumer rejection, native
buffer validation, encoder backpressure, single cleanup and error preservation.
CI runs them before installing Chromium or FFmpeg.

The account/project browser checks cover search/order, failed reads, restoration
retries, identity changes, delayed replies and guest project operations. Sources
and generated output stay frozen during browser verification.

```sh
# Repository root
pnpm test
pnpm test:render
pnpm typecheck
node scripts/moon.mjs check --target js --deny-warn
node scripts/moon.mjs test --target js
node scripts/moon.mjs test --target wasm moonbit/motion moonbit/proposal_plan moonbit/editor moonbit/scene
node scripts/moon.mjs test --target wasm moonbit/render moonbit/exporting moonbit/audio moonbit/media_pipeline moonbit/render_job
pnpm build

# apps/studio
cd apps/studio
pnpm exec playwright install chromium
pnpm test:e2e
pnpm test:export
pnpm exec playwright test --config tests/e2e/media-export.config.ts
pnpm exec playwright test --config tests/e2e/site-production.config.ts
node tests/collaboration-worker.integration.mjs --port 8796
node tests/media-storage.integration.mjs node
node tests/r2-assets-worker.integration.mjs
node tests/accounts-worker.integration.mjs
```

Browser video checks require FFmpeg/ffprobe; `pnpm test:render` does not.
On Linux, Playwright may also need browser
system dependencies (`pnpm exec playwright install --with-deps chromium`).
Use an isolated local test host: browser tests create and edit rooms. The default
E2E configuration uses port 5173 and may reuse an existing server; set
`POIETRA_TEST_URL` to a dedicated host if that port belongs to your development
session. The production-page configuration serves the completed build separately.

Automated provider HTTP is simulated. Production smoke verified GitHub's
authorization redirect and flow storage; full Google/GitHub login completion and
paid OpenAI calls were not part of this release's verification.

## Performance

Measurements are stored in [benchmarks/](benchmarks/) with source/artifact hashes,
environment, workloads and raw samples. The following results describe specific
local fixtures. Production CDN delivery, real mobile hardware, WAN collaboration
and long source-media projects need separate measurement.

### Rendering and playback — 2026-09-27

These incremental comparisons use Node **24.13.0**, MoonBit
**0.10.13+cbb11c36f**, Intel Core Ultra 7 255H, 32 GB WSL2 and affinity **0–15**.
Browser runs use headless Chromium **153.0.8010.12** with SwiftShader. Builds,
tests and benchmarks run separately, with application sources and generated
output frozen during browser runs. Raw reports contain source/artifact hashes,
samples, warmup and exclusions; CPU and SwiftShader timings are not hardware FPS.
[Earlier per-step explanations](https://github.com/Poietra/poietra/blob/dc881f56c93f75b8d68f452cd2348eb88ce170b4/README.md#performance)
retain the detailed development sequence.

**Canvas and interaction.** [Rendering before](benchmarks/2026-09-27-typed-frames/rendering-before.json)
and [after](benchmarks/2026-09-27-typed-frames/rendering-after.json) compare
`5cf56f1` with the typed-capture working tree recorded by its hashes. The fixture
uses release MoonBit through Vite, a 1280×720 Canvas, one warmup and 30 moving
paints per size. It still includes an explicit caller-side frame clone; the
painter's own whole-frame clone is gone. Asynchronous wall time, mean [p95] ms:

| Circles | Before | After |
| --- | ---: | ---: |
| 100 | 4.69 [13.20] | 3.48 [10.20] |
| 500 | 9.43 [17.70] | 6.55 [13.30] |

The production editor [before](benchmarks/2026-09-27-typed-frames/interaction-before.json)
and [after](benchmarks/2026-09-27-typed-frames/interaction-after.json) use isolated
loopback rooms, one browser, a 1440×900 viewport, one drag warmup and three runs
of 60 trusted pointer moves. Event delivery to DOM mutation, median [min–max] ms:

| Circles | Before | After |
| --- | ---: | ---: |
| 100 | 11.3 [8.4–19.8] | 7.6 [6.8–11.7] |
| 500 | 19.3 [15.4–30.9] | 12.4 [11.3–16.8] |

At 500 objects, actual input spacing changed from 50.0 to 33.3 ms median.
Pre-delivery waiting is excluded; this is not field INP. Playback rAF spacing
stayed 16.7 ms median. Reports retain event/frame samples and adjacent CPU
profiles. Each condition is one process without media or WAN; unchanged stages
also varied. Allocated bytes and GC time were not measured.

**Preview publication.** The [same-build comparison](benchmarks/2026-09-27-preview-drafts/)
uses the draft working tree based on `51e72d2`, identified by source/artifact
hashes. Five fresh browser processes each compare the target and draft paths
on the same painter at 1280×720: two warmup and seven measured batches of 15
moving frames per mode, alternating order. Pose updates, rAF waits and final
pixel readback are outside timing; paint and publication are included. The
constructor canvas remains allocated in both modes to isolate copying. Process
mean wall times, median [min–max] ms:

| Circles | Two copies through target | Direct draft copy |
| --- | ---: | ---: |
| 100 | 3.110 [3.103–3.191] | 2.549 [2.465–2.597] |
| 500 | 4.737 [4.648–4.923] | 4.132 [4.060–4.190] |

Every comparison checked full pixel equality after timing. These are SwiftShader
async wall times, not GPU completion or visible FPS. The production editor's
separate parented drag [before](benchmarks/2026-09-27-parent-interaction/before.json)
/ [after](benchmarks/2026-09-27-parent-interaction/after.json) has one root and
499 children, with world geometry matching the flat fixture. Under the same
pointer protocol above, 500-object DOM latency was **13.5 [12.1–18.1] →
13.2 [11.3–20.2] ms**; delivered input and playback rAF medians stayed 33.3 and
16.7 ms. This single-process comparison does not establish an interaction gain.

**Native SVG conversion.** The [before](benchmarks/2026-09-27-render-view/before.json)
and [after](benchmarks/2026-09-27-render-view/after.json) start from `fa0c3f6`.
Run `node scripts/benchmark.mjs --suite render-view --runs 5 --output <file>`.
Five sequential fresh processes use two warmup and seven measured batches of
100 frames. This includes native-frame decoding and typed rendering, excluding
DOM, React, resource loading, media, GPU and encoding. Median [range of process
medians], ms/view:

| 500 objects | Before | After |
| --- | ---: | ---: |
| Circles | 0.522 [0.510–0.536] | 0.302 [0.287–0.313] |
| Mixed shapes + Glow | 0.805 [0.790–0.813] | 0.586 [0.548–0.592] |

The unchanged SVG markup control was 0.521 → 0.521 ms for circles and
0.779 → 0.758 ms for mixed shapes, within variation. Retaining the React element
tree subsequently eliminated SVG-tree construction during cursor updates and
supports frozen renderer records. Its production [before](benchmarks/2026-09-27-stage-props/interaction-before.json)
/ [after](benchmarks/2026-09-27-stage-props/interaction-after.json) start from
`9d1e67d`'s application source and use the drag/playback method above: 500-object
DOM latency was 12.0 [10.8–18.1] → 11.7 [10.9–25.2] ms, with rAF medians still
16.7 ms. No clear drag/playback speedup was established. A native props-factory
[trial and patch](benchmarks/2026-09-27-stage-props/exploratory/) was rejected
because its 12.3 ms median did not improve on the 12.0 ms baseline.

**Preparation and retained ownership.** Run
`node apps/studio/scripts/benchmark-playback.mjs --output <file>` after building.
Each scenario uses five sequential fresh processes, three compile warmups,
seven timed compilations with GC outside timing, and eight retained programs.
The caller's Scene stays alive. Time is the median of process medians; heap is
incremental retained JS `heapUsed` per program, in decimal MB. Native/WASM memory,
transient allocation, media decoding and rendering are excluded.

| Earlier incremental change | 500-object fixture | Prepare, ms | Retained MB |
| --- | --- | ---: | ---: |
| [Remove duplicate native Scene](benchmarks/2026-09-27-playback-ownership/) (`d239856` baseline) | 12 Compositions | 24.828 → 12.012 | 11.464 → 7.093 |
| [Share order and parent graph](benchmarks/2026-09-27-shared-scene-layout/) (`e072667` baseline) | 12 Compositions, parents | 19.651 → 12.827 | 8.040 → 7.591 |

The latest [before](benchmarks/2026-09-27-compiled-ownership/final-before.json)
/ [after](benchmarks/2026-09-27-compiled-ownership/final-after.json) start from
`5888fae`. Compiled programs retain frame dimensions and compiled curves, releasing
source Scene containers and authored key maps after preparation. Missing tracks
avoid allocating an editing key container. Parent fixtures use groups of ten
objects with nine children per root; keys are six intermediate x values per track.

| 500 objects / 12 Compositions | Prepare, ms | Retained MB |
| --- | ---: | ---: |
| Explicit tracks, no parents or keys | 11.530 → 11.941 | 7.092 → 4.972 |
| Explicit tracks, parents, no keys | 13.475 → 14.720 | 7.604 → 5.484 |
| Explicit tracks, parents, six keys | 25.896 → 28.981 | 23.311 → 15.118 |
| Inherited tracks, parents | 11.832 → 11.797 | 7.118 → 5.484 |

This trades some preparation work for lower retained memory. In the six-key
case, process medians ranged 25.490–26.678 → 28.101–29.153 ms; heap ranged
23.308–23.313 → 15.117–15.118 MB. At 100 objects / two Compositions, preparation
was 0.595 → 0.756 ms and heap 0.221 → 0.168 MB. Earlier trials and repetitions
are retained in the same directory. Authored keys and retained deleted poses
remain intact; evaluation frames stay independent across seeks.

**CPU evaluation and curve compilation.** Run
`node scripts/benchmark.mjs --suite evaluation --runs 5 --output <file>` or
`--suite primitives`. Both use five sequential fresh processes and seven batches
of 240 frames per scenario; evaluation has one warmup batch, primitives has two.
Public JS frame conversion is included; rendering and encoding are excluded.
The following are separate incremental comparisons, median [range of process
medians], in milliseconds:

| Change / fixture at 500 objects | Before | After |
| --- | ---: | ---: |
| [Resolve base pose once](benchmarks/2026-09-27-evaluated-pose/), preset easing (`bde6294`) | 0.1247 [0.1184–0.1289] / frame | 0.1058 [0.1031–0.1114] / frame |
| [Indexed hierarchy](benchmarks/2026-09-27-indexed-hierarchy/), parents + six keys (`f3a3e43`) | 0.6136 [0.5950–0.6261] / frame | 0.5140 [0.5136–0.5265] / frame |
| [Group authored keys once](benchmarks/2026-09-27-curve-preparation/), parents + six keys (`2b23d42`) | 3.571 [3.421–3.766] to prepare | 2.114 [2.060–2.238] to prepare |

Indexed hierarchy added setup work in its hierarchy-only fixture
(1.277 → 1.384 ms). Grouping keys left frame time at 0.514 → 0.512 ms.
The latest ownership [control](benchmarks/2026-09-27-compiled-ownership/primitives-before.json)
/ [result](benchmarks/2026-09-27-compiled-ownership/primitives-final.json) also
showed no clear per-frame change: flat 0.0980 → 0.0983 ms; parents + six keys
0.5363 [0.5099–0.5440] → 0.5283 [0.5164–0.5314] ms.

**Editing layout reuse.** The [CPU before](benchmarks/2026-09-27-shared-state-view/primitives-before.json)
/ [after](benchmarks/2026-09-27-shared-state-view/primitives-after.json) start from
`88ea863`. Five fresh processes use two warmup and seven measured batches of
100 parent coordinate edits, including Yjs, selective Undo, immutable snapshots
and current Composition frame conversion. At 500 objects, edit + frame time was
1.363 [1.330–1.394] → 0.979 [0.966–1.002] ms; with six points per object it was
1.354 [1.330–1.423] → 0.977 [0.961–1.007] ms. Playback evaluation remained within
variation. The separate snapshot-only [before](benchmarks/2026-09-27-shared-state-view/snapshots-before.json)
/ [after](benchmarks/2026-09-27-shared-state-view/snapshots-after.json), with three
Scenes and five Compositions each, showed no clear registration penalty at 500
objects: 0.176 [0.162–0.185] → 0.169 [0.159–0.175] ms per edit/read.
The production drag [before](benchmarks/2026-09-27-shared-state-view/interaction-before.json)
/ [after](benchmarks/2026-09-27-shared-state-view/interaction-after.json) showed
no clear change: 500-circle DOM latency 11.8 [10.5–19.1] → 11.9 [10.6–25.4] ms,
with rAF medians still 16.7 ms. These are the same local browser conditions above,
not a demonstrated user-visible drag speedup. Retained view heap is measured in
the following comparison; transient allocation has not been measured.

**Immutable pose reuse.** Starting from `e7d14fa`, the same CPU harness now also
measures editing without parents. Its [before](benchmarks/2026-09-27-immutable-poses/primitives-before.json)
/ [after](benchmarks/2026-09-27-immutable-poses/primitives-after.json) use five
fresh processes and the edit/frame method above. At 500 objects, edit + frame
time was 0.606 [0.578–0.636] → 0.517 [0.502–0.547] ms without parents and
0.971 [0.958–1.030] → 0.919 [0.881–0.922] ms with parents. Snapshot-only
[before](benchmarks/2026-09-27-immutable-poses/snapshots-before.json) /
[after](benchmarks/2026-09-27-immutable-poses/snapshots-after.json) medians were
0.172 → 0.180 ms, with overlapping process ranges. Preparation and playback
controls showed no clear regression.

Run `node apps/studio/scripts/benchmark-edit-heap.mjs --output <file>` for the
[heap before](benchmarks/2026-09-27-immutable-poses/heap-before.json) /
[after](benchmarks/2026-09-27-immutable-poses/heap-after.json). Each of five fresh
processes warms three disposable documents, then retains eight documents and
renders one Composition. At 500 objects, GC-retained view heap per document grew
from 0.116 [0.093–0.118] to 0.273 [0.244–0.276] MB. After 100 parent edits it was
0.167 → 0.327 MB above the original native snapshots; that delta also includes
Yjs/snapshot bookkeeping. The CPU reduction costs roughly 0.16 MB of additional
retained typed poses in this fixture. Native/WASM memory, transient allocations,
DOM, media and Undo history are excluded from this heap measurement.

The production [drag result](benchmarks/2026-09-27-immutable-poses/interaction-after.json)
was 11.6 [10.3–27.0] ms at 500 circles, compared with the preceding layout build's
11.9 [10.6–25.4] ms; rAF medians stayed 16.7 ms. This single-process comparison
does not establish a user-visible drag/playback speedup.

**Indexed Composition evaluation.** Starting from `aa93bec`, still frames share
the indexed parent traversal already used by transitions. The [CPU before](benchmarks/2026-09-27-indexed-compositions/primitives-before.json)
/ [after](benchmarks/2026-09-27-indexed-compositions/primitives-after.json) use
the same five-process method and additionally measure 100 mutable-input
Composition frames per batch. At 500 objects with parents, edit + frame time was
0.924 [0.918–0.929] → 0.868 [0.852–0.923] ms. Uncached mutable-input evaluation
cost slightly more: 0.906 [0.905–0.915] → 0.930 [0.920–0.985] ms, since each call
prepares its own indices. Flat and prepared-transition controls stayed within
variation; no new browser latency improvement is claimed for this change.

The twelve-Composition playback [before](benchmarks/2026-09-27-indexed-compositions/playback-before.json)
/ [after](benchmarks/2026-09-27-indexed-compositions/playback-after.json) use the
GC-separated preparation method above. With 500 objects and parents, preparation
was 13.944 [13.842–14.561] → 12.942 [12.425–13.242] ms for explicit tracks,
28.101 → 26.638 ms with six authored points per track, and 11.399 → 9.827 ms for
inherited tracks. Retained playback heap stayed around 5.485 MB without points
and 15.115 MB with points. Editing-view [heap before](benchmarks/2026-09-27-indexed-compositions/heap-before.json)
/ [after](benchmarks/2026-09-27-indexed-compositions/heap-after.json) was
0.273 → 0.280 MB at 500 objects; after 100 edits, 0.326 → 0.334 MB.

**Audio editing.** The [before](benchmarks/2026-09-27-media-editing/before.json)
/ [after](benchmarks/2026-09-27-media-editing/after.json) start from `1455c59`.
Five fresh Node processes run two warmup and seven measured batches of volume
edits, including real Yjs, selective Undo and immutable snapshot reads. Each
source has 160 waveform values. Batches contain 500 edits for room references or
20 for embedded sources. Embedded sizes below count base64 characters; these
fixtures do not decode audio. Process medians, median [min–max] ms per edit:

| Source | Before | After |
| --- | ---: | ---: |
| Room asset URL | 0.0309 [0.0304–0.0312] | 0.0239 [0.0226–0.0244] |
| Embedded 64 KiB | 0.5035 [0.4835–0.5569] | 0.0202 [0.0197–0.0239] |
| Embedded 1 MiB | 8.4788 [7.5578–8.5987] | 0.0199 [0.0189–0.0321] |

The first edit still validates the source: its 1 MiB median was 9.07 → 6.32 ms,
including cold command/JIT effects. A mutable-input control validates every time;
removing duplicate source validation reduced its 1 MiB median from 7.59 to 4.31 ms.
Normal browser imports upload embedded bytes to a room asset URL, so the large
embedded-case reduction is not representative of ordinary browser drag latency.
DOM, audio playback, networking and allocated bytes were not measured here.

**Export capture.** The [before](benchmarks/2026-09-27-export-capture/before.json)
/ [after](benchmarks/2026-09-27-export-capture/after.json) start from `c1d24d8`.
Five fresh Node processes run two warmup and seven measured batches of five
public export calls, with 500 circles per Scene and the real WASM kernel. The
fixture deliberately stops at the missing-WebCodecs check, after capture and
compiled timeline preparation. Process medians, median [min–max] ms:

| Scenes | Compositions per Scene | Before | After |
| ---: | ---: | ---: | ---: |
| 1 | 2 | 4.321 [4.276–4.479] | 2.747 [2.561–2.926] |
| 2 | 2 | 8.134 [7.797–8.446] | 5.169 [4.807–5.309] |
| 1 | 12 | 21.512 [21.359–21.903] | 13.267 [12.429–13.853] |
| 2 | 12 | 40.390 [40.158–44.958] | 27.280 [24.548–28.217] |

Full source snapshots fell from two to one per public call. Compiled playback
still copies native object metadata separately; the reports distinguish these
copies. These CPU measurements exclude the dialog, async codec loading, painting,
encoding, media and I/O; they do not measure complete export duration or heap use.
The dialog separately captures its input for custom-exporter compatibility, but
no longer also copies the first Scene of an already captured project.

**Project preview.** The [raw before/after reports](benchmarks/2026-09-27-project-preview/)
compare `cc615e0` with the identified working-tree build. Three fresh Chromium
processes per version each run one warmup and three measured 3.5-second transition
passes per size, through the production loopback server at 1440×900 with
SwiftShader. CDP browser-task and script durations include instrumented playback
and play/pause handling. Process medians, median [min–max] ms per Canvas publication:

| Objects | Browser tasks before | Browser tasks after | Script before | Script after |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 5.182 [5.130–5.185] | 3.768 [3.719–3.776] | 1.333 [1.315–1.346] | 0.650 [0.642–0.671] |
| 500 | 13.931 [13.913–13.999] | 6.496 [6.443–6.688] | 5.212 [4.994–5.259] | 1.039 [0.951–1.058] |

For 500 objects, each measured pass previously replaced hidden SVG markup
213–217 times, writing 27.46–27.98 million characters. Both counts are now zero.
Canvas publication and rAF medians remain about 16.7 ms. These measurements show
less browser work, not increased display FPS; they exclude media, hardware GPU,
WAN and input latency. Separate browser checks exercise actual video in both paths.

**Static project holds.** The [raw hold reports](benchmarks/2026-09-27-project-holds/)
start from `6d0141b`, using the same browser/server setup and three fresh processes
per version. Each size has one warmup and three 3.5-second measured passes within
a five-second hold. The clock must advance past three seconds. Process medians,
median [min–max] total ms per pass:

| Objects | Browser tasks before | Browser tasks after | Script before | Script after |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 773 [762–776] | 558 [552–560] | 125 [125–129] | 80 [78–87] |
| 500 | 1,343 [1,340–1,348] | 787 [782–789] | 192 [188–197] | 93 [92–94] |

After the initial frame, display copies during each pass fell from 212–213 to
zero. The retained image stays visible while transport controls and audio keep
their clocks. These measurements exclude media and describe static holds only;
transitions and any hold containing visible video still evaluate changing frames.

**Editor hit surface.** The [raw Scene-playback reports](benchmarks/2026-09-27-playback-hit-surface/)
start from `cb3ff77`. The same three-process setup measures three 3.5-second moving
passes after one warmup, now in the editor, including SVG mutation observation.
Process medians, median [min–max] ms per Canvas publication:

| Objects | Browser tasks before | Browser tasks after | Script before | Script after |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 5.250 [5.186–5.302] | 4.395 [4.337–4.528] | 1.697 [1.684–1.700] | 1.292 [1.287–1.385] |
| 500 | 11.871 [11.814–11.893] | 8.125 [8.090–8.158] | 3.838 [3.770–3.851] | 1.937 [1.924–1.940] |

For 500 objects, SVG DOM mutations fell from 107,500–108,500 per pass to 500 when
pausing. Canvas publication and rAF medians remain about 16.7 ms. This measures
reduced work during active playback; interactive dragging still updates hit geometry.
It excludes media, hardware GPU, WAN and input latency and does not establish FPS.

**Repeated portable assets.** The [before](benchmarks/2026-09-27-asset-validation/before.json)
/ [after](benchmarks/2026-09-27-asset-validation/after.json) compare `b33c4e3` with
the identified build. Five fresh Node processes each use two warmup and seven
measured batches of three public calls. The table uses 16 references to one source
containing 1 MiB of Base64 characters, about 16 MiB of input JSON. Process medians,
median [min–max] ms per operation:

| Asset | Portable file parsing before | After | Save preparation before | After |
| --- | ---: | ---: | ---: | ---: |
| Image | 76.71 [76.20–79.60] | 21.61 [20.64–22.87] | 102.32 [101.78–103.91] | 46.01 [45.92–46.90] |
| Audio | 77.17 [76.51–78.58] | 21.96 [21.09–22.18] | 96.66 [96.39–98.54] | 40.52 [39.58–42.35] |

The reports also include room URLs, a single 1 MiB source, and 16 distinct 64 KiB
sources. Those controls show no large improvement; for example, room-audio save
preparation was 0.557 [0.514–0.576] → 0.592 [0.507–0.693] ms. Native string-key
hashing/comparison remains included. Parsing includes validation and independent
output records; saving includes its snapshot and size serialization. Payloads
exercise syntax checks, not decoding; room I/O is stubbed and no browser, codec,
network, file download or peak-memory measurement is included.

The [current checks](#checks) include mutable public inputs, nested and
observer-queued transactions, exception recovery, metadata changes, video timing,
remote updates, Undo/Redo and mutable frame outputs. No production deployment
was made for these changes.

### Same-room collaboration — 2026-09-22

Real local workerd, one room and one object per participant, on the same Intel
Core Ultra 7 255H / 32 GB WSL2 host as eight Node client-generator threads; CPU
affinity 0–15. Node 24.13.0, MoonBit 0.10.13+cbb11c36f, Wrangler 4.131.2,
workerd 1.20260911.1, Yjs 13.6.32 and y-websocket 3.1.0. Every run synchronized
all clients, waited one second, then staggered periodic property/presence edits.
Builds, tests and encoders did not run concurrently. These are local end-to-end
delivery measurements, including client scheduling and Yjs application.

The 32-client comparison used two edits and ten presence updates per second per
client for ten seconds, with three samples at each revision. Incoming room
messages fell from **103,008–103,040 to 3,839–3,840: about 96.3% fewer**, principally
by stopping remote-awareness echoes. Peer-edit p95 was **9–14 ms** afterward;
the preceding implementation varied from **43–1,129 ms**, so a fixed latency
speedup is not claimed. All final states converged, with no disconnected clients.
The [raw results](benchmarks/2026-09-22-collaboration/) named
`delivery-before-32-*` and `delivery-after-32-*` use the same harness `3a04bf8`,
comparing application `115ed1e` with `72f05a2`.

Longer runs used one edit and one presence update per second per protocol client:

| One-room workload | Duration / edits | Peer delivery p50 / p95 | Final convergence / disconnects |
| --- | --- | --- | --- |
| [500 protocol clients](benchmarks/2026-09-22-collaboration/soak-500.json) | 60 s / 29,998 | 526 / 1,750 ms | 60.422 s / 0 |
| [499 protocol clients + one browser](benchmarks/2026-09-22-collaboration/soak-browser-500.json) | 60 s / 29,940 | 318 / 539 ms | 60.259 s / 0 |

Both runs checked every client's final poses and edits/presence after forced
hibernation. The browser run used headless Chromium 153.0.8010.12: no page errors
or long tasks were observed during the measured load; rAF intervals were
16.7 ms at p95. Its own edit, made **after** the load, reached all protocol clients
in 196 ms. This is one browser on a local machine, not 500 rendered browsers or
real-device FPS. Protocol clients received about 439 MB on the wire during that
run with `permessage-deflate`; logical decoded traffic was about 2.83 GB.

Raw files record frozen artifact hashes and harness revisions (`3a04bf8` /
`29a8366`). Both long runs measured application `72f05a2`, before the final
socket-retirement fix. Generator process RSS reached 15–16 GB; those hundreds of
client documents are not the Worker heap. Intermediate, high-rate, legacy-client
and rejected generator experiments remain under
[exploratory/](benchmarks/2026-09-22-collaboration/exploratory/).

Latency still varies at 500 participants. This verifies the stated one-minute
workloads and final convergence, not 500 people continuously dragging at high
frequency, long-duration endurance or WAN performance. The room remains a single
authoritative Durable Object; Cloudflare documents a workload-dependent
[soft limit of 1,000 requests/s per object](https://developers.cloudflare.com/durable-objects/platform/limits/).
Batching reduces persistence/fan-out overhead but does not remove that inbound
event limit or the cost of delivering everyone's edits to everyone else.

The client follow-up on 2026-09-22 fixes a gap in the earlier cursor tests: the
canvas includes unchanged Scene/Composition IDs in every move, while the old
throttle recognized only single-field cursor patches. The real workerd regression
now opens 500 sockets (one browser, one document observer and 498 idle roster
connections) and drives the actual canvas. With controlled browser time, 20 moves
at 41 ms intervals plus a 180 ms trailing drain produce one presence publication.
A burst of 90 drag moves without advancing the browser clock changes the local
inspector immediately and flushes one document update on pointer release. The peer
receives the final position, and Undo retains its independent color edit. A separate
transport test advances time by 16 ms between 90 edits: it produces 23 packets
with a 50 ms window and final flush, demonstrating delivery during continuous input.
These are deterministic message-count and ordering checks, not latency or FPS
measurements. They do not establish 500 continuously dragging browsers. See
[the real-browser regression](apps/studio/tests/collaboration-worker.integration.mjs)
and [transport checks](apps/studio/tests/client-sync.test.ts).

To repeat the current implementation, build once, freeze the bundle and run
these commands sequentially from `apps/studio` (port 8796 must be unused):

```sh
pnpm build:web
pnpm exec wrangler deploy --dry-run --outdir /tmp/poietra-collaboration-bundle
node tests/collaboration-load.integration.mjs \
  --bundle /tmp/poietra-collaboration-bundle/index.js --owned-presence \
  --clients 500 --generators 8 --seconds 60 --edit-hz 1 --presence-hz 1 \
  --output /tmp/poietra-collaboration-500.json
# Repeat with --browser to include one real browser among the 500 participants.
```

The `79531b9` follow-up removes duplicate presence serialization and intermediate
host-record allocations. The decoder transfers its freshly owned selection array
instead of copying it again. Existing mizchi WebSocket bindings avoid a dynamic
method lookup and argument array on every send.

| Independently decoded fixture | Packets before | Packets after |
| --- | ---: | ---: |
| 64 ordinary cursor updates | 2 | 1 |
| 500-person ordinary roster | 10 | 6 |
| 500-person roster with long Unicode selections | 100 | 100 |

All entries, safe-integer clocks, null removals and UTF-8 data are preserved;
packets stay within 100 entries and 16,000 bytes for older clients. The unchanged
Unicode packet count reflects the byte limit. See the
[raw follow-up results and conditions](benchmarks/2026-09-22-collaboration/encoding/).
The three 15-second 500-client runs at each revision converged without disconnects
and passed hibernation checks. Separate 500-client checks with an old client and
a real browser passed too.

Unrelated C++ compilation was observed on this shared host during these follow-up
runs. **Their wall times are exploratory, not evidence of an end-to-end latency
or encoding-time speedup.** The earlier `72f05a2` timing records above describe
their own runs. A new isolated timing comparison is still required. The harness
now separates document/presence traffic and supports local workerd CPU profiling
with `--profile-worker /tmp/room.cpuprofile`; profiling results are separate from
latency comparisons. Stop other builds before timing. To repeat the encoder check
from the repository root after building:

```sh
node apps/studio/scripts/benchmark-presence.mjs \
  --module _build/js/release/build/server_presence/server_presence.js \
  --output /tmp/poietra-presence.json
```

### Headless export — 2026-09-21

Local Node 24.13.0 on an Intel Core Ultra 7 255H, WSL2 Linux, CPU affinity 0–15.
Each workload received one warmup and three sequential samples in fresh processes
and worker threads, with frozen sources and no concurrent builds/tests/encoders.
The fixture is **1280×720, 30 fps, 3.4 seconds / 102 frames**, with Japanese/Latin
text, MathJax, Glow and an embedded PNG. Audio adds trimmed stereo WAV at half gain
and a muted track. [Before typed boundaries](benchmarks/2026-09-21-headless/render.json)
and [after the refactor](benchmarks/2026-09-21-headless/typed-render.json) record raw
samples, source/artifact hashes and dependency versions for the working trees on
top of `4a68767`. Both use the same harness and input hashes.

| Workload | Before, median | Typed, median [min–max] | Rasterized / encoded frames | MP4 bytes |
| --- | ---: | ---: | ---: | ---: |
| Static hold | 1,125 ms | 1,117 [1,112–1,135] ms | 1 / 102 | 26,232 |
| Animated intermediate value | 1,461 ms | 1,421 [1,410–1,423] ms | 26 / 102 | 31,798 |
| Animation with audio | 1,507 ms | 1,506 [1,505–1,526] ms | 26 / 102 | 115,260 |

Wall time includes worker startup, module/WASM/font loading, MathJax, rendering,
encoding, muxing and thread teardown; it excludes parent-process startup,
file/network transfer and independent decoding. Whole-process peak RSS ranged
from **229–269 MiB** after the refactor; this is not a Cloudflare Worker heap
measurement. The short, unpaired samples show no material slowdown in this fixture;
they do not establish a general speedup, a browser comparison or a long-video SLA.

```sh
pnpm build:moonbit
# Freeze sources/artifacts; run with no other build, test or encoder in progress.
node scripts/benchmark-headless.mjs test-results/headless-benchmark.json
```

### Shared browser linking — 2026-09-20

Application `0cda0c5` links the six browser packages once. Its baseline is
`2c00643` (application `99a349d`); standalone boundary/editor and WASM artifacts
remained identical. [Bundle before](benchmarks/2026-09-20-client-linking/bundle-before.json)
and [after](benchmarks/2026-09-20-client-linking/bundle-after.json) record all files
and hashes.

| Static JS group | Before | After |
| --- | ---: | ---: |
| Editor, raw | 1,883,417 B | 1,610,705 B (−14.5%) |
| Editor, gzip level 9 | 524,141 B | 457,443 B (−12.7%) |
| Editor, Brotli | 401,036 B | 371,942 B (−7.3%) |
| Homepage, gzip level 9 | 91,072 B | 91,134 B (+62 B) |

Groups include static imports; the homepage also includes its selected entry.
Dynamic editor modules, CSS, fonts and media are excluded. Compression is computed
per file, using Node's default Brotli settings, rather than measured on the wire.

Cold startup used three fresh contexts per build, no warmup, one pre-seeded
circle, a 412 × 823 viewport, disabled cache, 4× CPU slowdown, 150 ms HTTP latency,
200,000 B/s download and 93,750 B/s upload. Hardware: Core Ultra 7 255H, 32 GiB,
WSL2, CPUs 0–15; Node 24.13.0, MoonBit 0.10.13+cbb11c36f and Chromium 153.0.8010.12.
Runs were sequential with frozen artifacts and no concurrent local builds,
tests or encoders.

| Cold startup, median [min–max] | Before | After |
| --- | ---: | ---: |
| FCP | 1,680 [1,668–1,684] ms | 1,676 [1,668–1,676] ms |
| LCP | 11,340 [11,288–11,376] ms | 10,152 [10,148–10,172] ms |
| Circle in DOM + two animation frames | 11,903.9 [11,811.2–11,963.9] ms | 10,651.2 [10,648.7–10,651.7] ms |
| Observed long-task blocking sum | 354 [304–476] ms | 347 [338–354] ms |

Stage readiness improved **10.5%** in this fixture. The local Node server sends
uncompressed assets and uses local WebSockets; these are not production load
times. The stage metric is a presentation opportunity, not physical display or a
Web Vital, and the blocking sum is not Lighthouse TBT. Full samples:
[startup before](benchmarks/2026-09-20-client-linking/startup-before.json),
[startup after](benchmarks/2026-09-20-client-linking/startup-after.json).

A separate warm interaction run used 100/500 circles at 1440 × 900, one drag
warmup and three sets of 60 pointer moves, with a 1 ms CPU sampler. For 500 circles,
median delivery-to-DOM was **14.4 ms**, delivery-to-DOM plus two animation frames
was **33.4 ms**, and actual input spacing was **50.0 ms**. The three-second Scene
(two one-second holds and one-second transition) had rAF intervals of 16.7 ms
median, 49.9 ms p95 and 83.4 ms maximum. Long frames remain. This final run does
not establish an interaction speedup; it excludes pre-delivery input waiting,
media, WAN and hardware GPU behavior. [Samples and profiles](benchmarks/2026-09-20-client-linking/)
retain the full observations.

### Earlier measurement evidence

These datasets belong to earlier revisions; do not combine their speedups or
report them as fresh measurements of the current release. Previous explanations,
including unsuccessful/intermediate runs and old deployment records, remain in
[the README at 5468c56](https://github.com/Poietra/poietra/blob/5468c56/README.md#performance).

| Investigation | Retained evidence |
| --- | --- |
| Panel/resource invalidation | [Document updates](benchmarks/2026-09-20-document-updates/) |
| Clock, presence and chat subscriptions | [UI subscriptions](benchmarks/2026-09-20-ui-subscriptions/), including synchronous-clock regressions |
| Retained SVG and direct Canvas shapes | [Rendering, interaction, startup and WebCodecs](benchmarks/2026-09-20-retained-rendering/) |
| Parenting and value curves | [Primitives](benchmarks/2026-09-20-primitives/) |
| Lazy loading, static holds and export | [Startup](benchmarks/2026-09-20-startup/) and [interaction/export](benchmarks/2026-09-20-interaction/) |
| Typed editing plans | [Object edits](benchmarks/2026-09-20-editing/), [Transition timing](benchmarks/2026-09-20-timing/), [track timing](benchmarks/2026-09-20-tracks/) and [creation](benchmarks/2026-09-20-creation/) |
| Initial migration and video pipeline | [2026-09-19](benchmarks/2026-09-19/) and [optimized](benchmarks/2026-09-19-optimized/) |

The latest recorded export timing comparison is the retained-rendering experiment
(`4b2ae74` → `8357a35`). Its warmed 500-shape MP4 fixture, 90 frames at 720p/30 fps,
fell from **387.7 [382.5–395.2] ms to 342.0 [336.6–342.6] ms** (median [min–max]).
It used one warmup and three measured runs, fresh painter/encoder resources,
Chromium/SwiftShader on the same WSL2 machine with CPUs 0–15, and CDP profiling.
Other host activity was not isolated. It excludes source audio/video, module
loading and download handling; every
output's packet count and first decoded frame were checked. This is an engine
fixture, not a prediction for a user's video. See [export before](benchmarks/2026-09-20-retained-rendering/export-before.json)
and [after](benchmarks/2026-09-20-retained-rendering/export-after.json).

### Reproduce the measurements

Build once, then freeze sources and generated artifacts. Run workloads
sequentially, without other builds/tests/encoders. Default outputs go to ignored
`test-results/`; use distinct files for repeated runs. Historical comparisons
require the matching source revision and harness, not just today's scripts.

```sh
# Repository root: current MoonBit CPU suites in three fresh processes each
pnpm build
pnpm bench --runs 3 --output test-results/benchmarks/cpu.json

# Terminal 1, from the repository root: isolated production host
cd apps/studio
PORT=5188 NODE_ENV=production OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-perf \
  node server/index.js
```

```sh
# Terminal 2, from apps/studio; run each command to completion
pnpm exec playwright install chromium
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-home.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-editor.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-startup.mjs
POIETRA_PERF_URL=http://127.0.0.1:5188 node scripts/measure-interaction.mjs
node scripts/measure-bundle.mjs
```

`POIETRA_PERF_OUTPUT` selects a browser measurement's JSON file.
`measure-home` defaults to five runs per locale, `measure-startup` to three cold
runs (`POIETRA_PERF_RUNS`); `measure-editor` uses 30 inputs per scenario
(`POIETRA_PERF_SAMPLES`). Match affinity explicitly when comparing historical
runs: latest shared-linking results used CPUs 0–15; some earlier experiments used
measurement CPUs 0–3 and server CPUs 4–5.

Renderer/export harnesses import source modules through a **development** host
using the same release MoonBit artifacts. Keep this separate from startup runs:

```sh
# Terminal 1, apps/studio: stop the production measurement host first
PORT=5189 OPENAI_API_KEY= POIETRA_DATA_DIR=/tmp/poietra-render node server/index.js
```

```sh
# Terminal 2, apps/studio
node scripts/benchmark-rendering.mjs --url http://127.0.0.1:5189 --frames 60 \
  --output test-results/benchmarks/rendering-1.json
POIETRA_BENCH_URL=http://127.0.0.1:5189 node scripts/benchmark-export.mjs
POIETRA_PERF_URL=http://127.0.0.1:5189 node scripts/measure-subscriptions.mjs
POIETRA_PERF_URL=http://127.0.0.1:5189 node scripts/measure-document-updates.mjs
```

Rendering video fixtures require FFmpeg/libx264 (`--skip-video` omits them).
Export uses `POIETRA_BENCH_RUNS` and `POIETRA_BENCH_OUTPUT`. Subscription/document
probes count development StrictMode invocations, including retries and diagnostic
overhead; they are not production timing or FPS measurements.

## Deployment and limits

Node persists locally. Cloudflare serves Static Assets, stores room/account state
in SQLite Durable Objects and keeps media bytes in private R2. Default Wrangler
configuration is for isolated `poietra-moonbit` validation. The explicit
`production` environment updates the existing `poietra-hackathon` Worker in
Yumaboda's account, preserving `poietra.com`, old workers.dev links, three Durable
Object namespaces, migration tag `v2-accounts`, secrets and `poietra-assets-prod`.

**Last recorded deployment: 2026-09-22 12:58 JST.** Application `2d76eed`
served at 100% as Worker version `dcd24d3d-45b7-4abe-b4eb-3a274955c841`.
Storage namespaces, secret bindings, variables, rate limits and runtime settings
matched the preceding release, including Static Assets routing and headers.
There was no document/storage migration. The recorded predecessor is
`ed47add7-6904-425e-8eb3-171315450e9e` (application `79531b9`). Confirm the active
version before the next deployment instead of assuming this record is live state.

Verification used a dedicated room: release JS/WASM hashes, existing room/R2
restoration, upload deduplication, two-browser edits, selective Undo and reload
recovery, guest/account UI, GitHub authorization start, playback and seeking.
A downloaded 720p MP4 decoded all 102 expected frames. Full provider login and paid AI calls
were outside this smoke check. The 500-client tests ran against isolated local
workerd, not the production domain. Reload existing editor tabs to use corrected
canvas cursor throttling, bounded document batching and lifecycle/chat flushing.

Use the [studio deployment procedure](apps/studio/README.md#実行と配置) for local
workerd, version upload, activation and rollback. `pnpm --dir apps/studio run deploy`
only builds a **dry run**. A Worker rollback changes code/assets; it does not
restore room data. Any rollback must understand version 2 documents and persistent
account dismissals.

The [limits table](apps/studio/README.md#現在の制限) covers project structure, media,
keyframes and AI. Long projects, large media workloads and many WAN collaborators
still need performance evaluation; optional provider integrations need live
verification in the target environment.

The rewrite originated from public hackathon commit
`3f49040ee4bcf06bfcf02e269712833f3729c536`. The original
[hackathon application](apps/studio/docs/hackathon-application.md) remains a
historical record. Current behavior belongs in these READMEs and the product
rules; the separate private design archive was not imported.

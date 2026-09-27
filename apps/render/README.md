# Headless rendering, API and MCP

[Project overview](../../README.md) · [Development and checks](../../docs/development.md)

The headless renderer accepts saved `.poietra.json` files and returns SVG,
PNG or H.264 MP4. It runs in Node 24+ without Chromium, FFmpeg, WebCodecs, native
codec executables or runtime network access. Install the workspace dependencies
and build MoonBit first; fonts and codec WASM come from pinned local packages.

Run these commands from the **repository root**:

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
The [Node API](index.d.mts) also supports progress and AbortSignal.
See the [Japanese setup and request examples](../studio/README.md#ファイルから描画する-api--mcp).

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

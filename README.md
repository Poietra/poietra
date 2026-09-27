# Poietra

**Make motion together, with friends and AI.**

Poietra is a collaborative motion editor in the browser. Arrange shapes, text,
equations, images and video; animate their properties; mix audio; and export MP4
or WebM. Friends and the AI assistant edit the same structured objects, so
positions, colors and timings remain editable.

[Open Poietra](https://poietra.com) · [日本語の使い方](apps/studio/README.md) ·
[API / MCP](https://poietra.com/developers/) · [Issues](https://github.com/Poietra/poietra/issues)

![Poietra's studio, with a canvas, timeline, properties and shared chat](apps/studio/docs/assets/studio.png)

## What you can make

- Edit a shared room together, with presence, offline reconnection and Undo
  scoped to your own edits. Guests can create and edit projects.
- Animate shapes, text, LaTeX, paths and media with per-property timing,
  intermediate keyframes and custom easing. Group, parent and clip objects.
- Reuse motions with editable text and colors, trim audio/video, and save
  portable project files containing their media.
- Ask `@codex` in shared chat for structured edits or generated image assets.
  Optional Google/GitHub login keeps a private list of project shortcuts.

Desktop Chromium is the primary tested browser; codec support varies by device.
See the [studio guide](apps/studio/README.md) for editing, accounts and limits.

## Run locally

Use Node.js **24+** (tested: 24.13.0), pnpm **10.23.0**, Python **3.12+** and
MoonBit pinned by [.moon-version](.moon-version). In a POSIX shell:

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

Open **http://localhost:5173**. Local data lives in `apps/studio/.data`.
Editing, collaboration, ordinary chat and export work without an API key.
Optional AI/OAuth settings go in `apps/studio/.env`;
see [configuration](apps/studio/README.md#設定).

After editing `.mbt`, run `pnpm build:moonbit`; Vite does not compile MoonBit.
Restart the Node host after server-side changes.

## Headless rendering, API and MCP

Render saved projects to SVG, PNG or H.264 MP4 in Node without Chromium or FFmpeg:

```sh
pnpm build:moonbit
pnpm render project.poietra.json --format mp4 --width 1280 --fps 30 -o result.mp4
pnpm render:api   # local HTTP API
# pnpm render:mcp # local stdio MCP server
```

See the [API quickstart](https://poietra.com/developers/) for codecs, limits and
HTTP/MCP contracts, or [preview the docs for this checkout](docs/development.md#api-documentation).
The renderer is self-hosted; poietra.com does not provide a hosted render endpoint.

## How it is built

Application logic lives in [MoonBit packages](moonbit/), with a WebAssembly motion
kernel and JavaScript adapters for browsers, Node and Cloudflare. TypeScript is
used for public declarations and build/test tooling. This is the MoonBit rewrite
of [poietra-hackathon](https://github.com/Poietra/poietra-hackathon).

| Read more | Contents |
| --- | --- |
| [Development](docs/development.md) | Architecture, commands, extension steps, checks and deployment record |
| [Measurements](benchmarks/README.md) | Performance results, conditions, raw evidence and reproduction |
| [Studio guide — 日本語](apps/studio/README.md) | Editing, configuration, deployment procedures and troubleshooting |

## Add a feature

Follow the [extension steps](docs/development.md#add-a-feature) and the
[implementation rules](AGENTS.md). Define domain records once and regenerate
adapters; preserve collaboration semantics and preview/export agreement.

## Checks

From the repository root:

```sh
pnpm test        # source audit, build, extension checks and Vitest
pnpm typecheck  # public API contracts
pnpm build      # production build
```

[CI](.github/workflows/check.yml) also runs MoonBit JS/WASM, browser, headless and
real persistence/restart checks. See [test commands and scope](docs/development.md#checks)
for choosing the suites relevant to a change.

## Performance

[Measurements and reproduction](benchmarks/README.md) include CI latency,
rendering, import/memory, collaboration and export. Each result records its
revision and conditions; local CPU or software-GPU results do not predict user FPS.

## Deployment and limits

The last recorded production deployment is **2026-09-22**, application `2d76eed`.
Later commits and successful CI runs do not imply deployment. See the
[release record and verification scope](docs/development.md#deployment-and-limits),
[deployment procedure](apps/studio/README.md#実行と配置) and
[current limits](apps/studio/README.md#現在の制限).

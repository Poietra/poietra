# Poietra Studio — product and runtime rules

Updated 2026-09-20. Applies to `apps/studio`; also follow the
[root rules](../../AGENTS.md). The current implementation, setup, checks and
measurements are in the [root README](../../README.md) and
[studio guide](README.md). Earlier Rust/TypeScript implementation decisions are
history in Git, not instructions to reintroduce that architecture.

## Product intent

Poietra lets friends make beautiful motion together in the browser, with an AI
collaborator that edits the same structured objects. Preserve the creator's
control over individual positions, appearances and timings. Keep the engine usable
without the UI. UI quality and a usable end-to-end creative workflow matter more
than architectural complexity.

The original motivation was the difficulty of sharing project files and managing
media/dependencies while collaborating. Do not reduce collaboration to exchanging
files or flatten AI edits into an uneditable generated video.

## Document and animation semantics

- Scene owns object identities. Composition owns each object's independent state
  and its hold duration. Transition owns the animation between neighboring states.
  Editing one Composition must not modify another's state.
- 2026-09-20: Parent identity is shared by the Scene; transform values belong to
  each Composition. Parenting inherits transforms only, with independent
  visibility/opacity and flat paint order. Preserve every Composition pose on
  reparent/detach, including retained states, and keep grouping separate.
  Matrix composition precedes rendering, selection, pointer projection and export.
- 2026-09-20: Intermediate keys contain actual field values and normalized time
  inside the property's interval; endpoints follow adjacent Compositions. The
  outgoing segment uses the point's easing; the first uses property timing.
  Cut retains but disables intermediate points. Preview, inspector graphs, AI
  and export use the same typed evaluator and pose-preserving editor plans.
- Object-level timing is the fallback for optional per-property timing. Preserve
  old projects' motion when adding timing features. Custom easing is a cubic
  Bézier with control coordinates in `0..1`; spatial Bézier paths are separate.
- Preview and export use the same time evaluation. Export captures its project at
  start so concurrent edits cannot change an in-progress output.
- Moving a grouped member moves its visible, unlocked peers. Preserve group
  behavior and local gesture Undo. Canceling a gesture must preserve earlier work
  and peer edits.
- Structural deletion uses retained CRDT data and an effective document view.
  Concurrent deletion must leave at least one usable Scene/Composition. Undo
  must preserve collaborators' changes to newly created or restored structures.

## Collaboration and persistence

- An unguessable shared room link grants editing access. Guest participation,
  project creation and editing remain available without login.
- Sync property-level edits through Yjs. Never rewrite untouched values while
  resizing a Transition or changing another property. CRDT convergence alone
  does not prove the user's edit intent was preserved.
- Playback time is local. Selection/cursors are presence; presence and chat changes
  must not rebuild unchanged scene playback or redraw unchanged content.
- Undo targets local edits, including the existing selective preservation rules.
  Test offline/reconnect, independent edits and nested/observer transactions.
- Persist unresolved Yjs dependencies as well as visible changes. Keep actual
  workerd hibernation, compaction, forced process restart and journal recovery tests.
- Opening a portable project creates a fresh room, waits for server acknowledgment
  and keeps the existing collaboration intact. Include media bytes in saved files;
  exclude chat and account data.

## AI and accounts

- Shared Chat is the human conversation; `@codex` requests structured AI edits.
  The requester applies a validated proposal, or Ctrl/⌘+Enter requests automatic
  application after validation. Recheck targets, locks and guards at application.
- Share pending/reply/application status. Only the requesting browser can stop its
  request. Preserve the reader's scroll position; pause decorative motion when
  hidden or reduced motion is requested.
- Repair a validation-rejected proposal once. Do not repair transport failures,
  refusal or incomplete output. Text, repair, image generation and image storage
  share the 170 s total deadline; the room lock is 180 s. Old requests cannot
  release a successor's lock. Failed parallel image work cancels its siblings.
- Generate at most two images per proposal. Validate placeholder edits before
  generation; publish stored image references afterward. Images remain objects
  with editable transforms; pixel editing is outside scope.
- API credentials stay on the server. Automated provider simulations must not be
  described as paid API or live OAuth verification.
- Google and GitHub logins are optional, independent identities. Do not merge by
  email. Private project lists and sessions are separate from rooms; removing a
  list entry does not delete the room or restrict shared-link access.
- 2026-09-20: The founder requested clearer account concepts. Distinguish account,
  login method, browser session, browser-local collaboration display name, private
  shortcut and shared room. Automatic visits respect persistent account-scoped
  dismissals; only explicit re-addition restores a shortcut. Keep removed titles
  out of dismissal records and preserve guest editing. A failed session lookup
  must not be presented as confirmed guest mode. Account linking remains separate.

## Media and hosts

- Video is a canvas object; audio is a separate Scene-time track. Extract video
  audio into its own track. Preserve trims, gain/mute, waveform feedback and
  matching preview/export behavior.
- Keep published file/room limits, deduplication and portable-file compatibility.
  For Worker storage, put bytes in private R2 and references/quotas in SQLite DOs.
  Publish references atomically only after upload completion. An interrupted
  upload's cleanup must not delete another upload's committed object.
- Keep the legacy SQLite read path during R2 migration; verify hash and size
  before switching the reference and preserve the original bytes.
- Own render/decode/encode resources through failure, cancellation and Scene
  changes. Preserve WebGL2 Glow with SVG/Canvas2D fallback and export decoding tests.
- Local Node and workerd are separate validation hosts with isolated storage.
  The founder authorized the production cutover on 2026-09-20; the explicit
  `production` environment preserves the existing Worker, storage and origin.

## UI and scope

- Keep the established dark editor layout, logo/project menu, Scene tabs, canvas,
  properties, Composition/Transition timeline and per-object animation tracks.
  [Editor reference](docs/assets/ui-editor-reference.png) and
  [Transition reference](docs/assets/ui-transition-reference.png) record the design
  baseline. Reuse the [original SVG logo](docs/assets/poietra-symbol-05b.svg).
- The Poietra logo opens project operations; the keyboard icon opens shortcuts.
  Show progress, completion, cancellation and errors for asynchronous operations.
- Homepage visits must not create a room or load the editor/media engine. Keep
  English/Japanese prerendering, language negotiation, Markdown and lazy entry.
  Shared rooms/editor pages are noindex; that is not access control.
- Billing, tenant administration, complex permissions and user-supplied shaders
  are outside the agreed scope. Do not treat examples in the original
  [hackathon application](docs/hackathon-application.md) as additional requirements.

## Decision history

- 2026-09-15: Composition/Transition semantics, shared links, Yjs, structured AI,
  browser export and the initial Cloudflare/Node host split were established.
- 2026-09-16–17: Media tracks, property timing, optional accounts, localized public
  pages, R2 storage and shared chat feedback were added to address creator needs.
- 2026-09-18: The founder requested the full MoonBit rewrite and substantial
  performance/reliability improvements while preserving those behaviors.
- 2026-09-19: Documentation was consolidated after completion and remeasurement;
  historical implementation choices and unfulfilled investigation notes no longer
  describe the current architecture. Keep future decisions concise and dated.

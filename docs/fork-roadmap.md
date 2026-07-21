# Fork Roadmap — eth0net/godot-ai

> **Scope:** this file lives on the `dev` branch of the personal fork
> (`eth0net/godot-ai`). It is the working plan for a batch of improvements to
> the Godot AI MCP server, driven by building a 2D cosy life sim
> (`shrine-guardian`). It is **not** intended to be upstreamed — features are
> contributed back to `hi-godot/godot-ai` as individual, self-contained PRs.
> Delete or `.gitignore` this before any PR branch is cut from `dev`.

## Working model

- **Remotes:** `origin` = `eth0net/godot-ai` (fork, push here), `upstream` =
  `hi-godot/godot-ai` (PR target).
- **`dev`** is a long-lived integration branch tracking work-in-progress across
  all features at once, so `shrine-guardian` can consume everything immediately.
- **Commit discipline:** keep each commit scoped to a single feature and prefix
  the subject with a tag (`[snapshot]`, `[diagnostics]`, `[gdunit]`, …). When a
  feature is settled, `git cherry-pick` its commits onto a fresh
  `feat/<name>` branch cut from `upstream/main` and open the PR from there.
- **Convergence:** rebase `dev` on `upstream/main` as PRs merge; merged commits
  drop out and `dev` shrinks toward upstream. When nothing is left over, switch
  `shrine-guardian` back to the released/upstream addon.
- **Before big features:** open a GitHub issue on `hi-godot/godot-ai` sketching
  the surface and get a maintainer's nod. Some items (navigation, font theming)
  are already on `docs/implementation-plan.md`; coordinate to avoid clashes.

### Game-side wiring (deferred — do NOT do yet)

`shrine-guardian` has ongoing work; wait for the go-ahead before touching it.
When ready:
- Symlink `shrine-guardian/addons/godot_ai` → this checkout's
  `plugin/addons/godot_ai` (same trick `script/setup-dev` uses for
  `test_project`).
- Run the fork's Python server (dock **Start Dev Server**, or
  `script/serve-this-worktree`) and point the MCP client at it.
- To switch back: remove the symlink, reinstall the released addon, repoint the
  MCP client.

## Contribution strategy — two gates, two tracks

The upstream bar is high and mechanical (AGENTS.md + CONTRIBUTING.md): 100%
coverage on **both** the Python and GDScript sides, live-editor smoke before
every commit, a 4-row OS/version CI matrix (incl. a Godot 4.5 canary),
`tool_catalog.gd` sync, self-update `class_name` safety, docs. That standard is
the real constraint. Reconcile "features now" with "contribute back" by not
treating "done" as one thing:

**Two quality gates**
- **Gate 1 — dev/personal (fast):** feature works in `shrine-guardian`.
  GDScript handler + Python handler + registration + a live smoke. Merge to
  `dev`, use it. Don't block on the full CI matrix.
- **Gate 2 — upstream PR (strict):** once a feature has *settled* (API stable,
  not churning), pay the full tax — both-sides tests, `tool_catalog.gd` sync,
  docs, ruff, live smoke — and open the PR from a clean `feat/` branch.

**Two tracks (sequence by upstreamability, not just value)**
- **Track A — upstream-first.** Fix/perf-shaped, existing fixtures, low
  API-design risk, high acceptance. Build these to Gate 2 from the start and PR
  early to build reviewer trust: the warnings-watermark **bug** fix (#4), test
  warnings bucket (#5), `node_get_properties` filter (#3),
  `scene_get_hierarchy` real pagination, the double-UTF-8-encode fix, the
  `from_node` O(n·depth) fix, the resource/instructions/docstring token trims,
  and surfacing `game_eval` (#2, mostly docs).
- **Track B — dev-now, upstream-after-an-issue.** New opinionated surface, needs
  new test fixtures (a gdUnit4 fixture project; live 4.5+4.7 tests for tile/nav
  APIs), design-sensitive. Build to Gate 1 for the game now; **open a GitHub
  issue first** to agree the shape before a PR: play-testing ops
  (#1/#6/#7/#8), `diagnostics_read` (#9), gdUnit runner (#11), TileSet/Nav/
  terrain/font authoring (#12–15). Some may live on the fork permanently — MIT,
  and that's a fine outcome.

**Two operating rules**
1. Write the GDScript live-editor test **as you build**, even on `dev` — it's
   the one thing that's expensive to retrofit and it doubles as your own
   in-editor validation.
2. Don't let upstream review latency block the game. Contributing back is
   upside, not a dependency.

Low-risk first engagement: file the four review reports as GitHub issues (the
`file:line` anchors are already here). Zero-code, and it gauges maintainer
receptiveness before you invest in PRs — especially the warnings bug and the
perf findings.

### Per-feature CI checklist (keeps upstream PRs green first try)

For each new tool/op, touch these in lockstep:
- `src/godot_ai/tools/<domain>.py` — tool/op + docstring
- `src/godot_ai/tools/domains.py` **and** `plugin/addons/godot_ai/tool_catalog.gd`
  (CI-enforced by `tests/unit/test_tool_domains.py`)
- `docs/TOOLS.md` — op map entry
- `plugin/addons/godot_ai/handlers/<domain>_handler.gd` — write handlers must
  `await require_writable_async()` (Python side)
- `read_resource_forms` for any read op (resource-form lint)
- Error codes in **both** `protocol/errors.py` and `utils/error_codes.gd`
- Telemetry allowlist in **both** `telemetry.gd` and
  `websocket.py::_PLUGIN_EVENT_NAMES` if adding plugin events
- Tests both sides — `pytest` + a GDScript suite when crossing the plugin boundary
- **Never delete a shipped `class_name`** — leave a compatibility shim
- **Benchmark any perf-motivated change.** Copy `script/bench/_template.gd`,
  prove the candidates agree, and paste the table + script into the PR (full
  method in `script/bench/README.md`). The maintainer hand-benches GDScript perf
  PRs (#743, #801); leading with our own numbers matches that bar. A complexity
  argument is not a benchmark — #743 was "2 walks → 1" yet measured 1.44–3.31×
  *slower*.

---

## Feature roadmap

Ordered roughly by (value ÷ effort), small self-contained wins first to build
reviewer trust before the large features.

### Tier 1 — small, self-contained, high value

#### 1. `game_manage(op="snapshot")` — batched multi-node runtime read
- **Problem:** validating game state means many `get_node_info` calls, one
  round-trip each.
- **Design:** `op="snapshot", params={targets:[{path, properties:[...]}],
  groups:[...], include_transform:true}` → one dict of resolved values.
- **Mechanism:** reuse `_resolve_runtime_node` (`game_helper.gd:420`),
  `_runtime_node_properties`, `_variant_to_json`. Pure read.
- **Effort:** small. **Pairs with:** #4 (its snapshot payload).

#### 2. Surface `game_eval` as `game_manage(op="eval")` + helper lib
- **Problem:** the round-trip bottleneck is already escapable — `game_eval`
  runs a coroutine *inside* the game frame loop (`game_helper.gd:657-663`) and
  can `await`. But it is buried under `editor_manage` and framed as a debug tool.
- **Design:** alias/add `game_manage(op="eval")`; preload a small helper lib into
  eval scope (`press(action, frames)`, `wait_frames(n)`, `snap(paths)`); add a
  frame-loop recipe to `docs/TOOLS.md`; document the 8s cap and focus-freeze
  constraint on the play-testing surface.
- **Effort:** small (registration + docs). Unlocks the timeline pattern today.

#### 3. `node_get_properties` `changed_only` / `fields` filter
- **Problem:** dumps every editor-visible property (50–150 entries, mostly
  defaults) on a core, always-loaded, high-traffic read
  (`node_handler.gd:890-920`).
- **Design:** add `changed_only:bool` (skip values equal to
  `ClassDB.class_get_property_default_value`) and/or `fields:[str]`. Propagate to
  the `godot://node/{path}/properties` resource form.
- **Effort:** small. Biggest single response-token win.

#### 4. Warnings in the error watermark → `new_warnings_since_last_call`
- **Problem (root cause of "warnings never surface"):** warnings ARE captured
  and returned by `logs_read`, but every promotion/watermark path filters to
  `level == "error"`, so a warning-only run reports
  `new_errors_since_last_call = 0` → the agent is told it was clean.
- **Filters to relax:** `surfaced_error_tracker.gd:92`;
  `editor_log_buffer.gd:50-51`; `game_log_buffer.gd` (the misnamed
  `watermark()["game_error_warn"]` reads errors-only); `mcp_debugger_plugin.gd:609`.
- **Design:** add parallel warn counters to both buffers, relax the tracker
  filter into a parallel warn sequence, extend
  `_sync_error_watermark_for_session` (`websocket.py:327-378`) with warn keys
  using the same `max()` overlap-dedup, deliver a **separate**
  `new_warnings_since_last_call` (don't regress error semantics), keep the
  exactly-once consume contract.
- **Effort:** small–med. **High value** — directly fixes the daily complaint.

#### 5. Test warnings bucket
- **Problem:** `script_error_capture.gd:43` captures only `ERROR_TYPE_SCRIPT`
  and early-returns for `push_warning`/`push_error`; no warnings field on the
  test result at all (`test_runner.gd:46-64`).
- **Design:** record `ERROR_TYPE_WARNING` (and `push_error`) into a non-fatal
  bucket, add `warnings:[]` to the result, expose via `test_run` /
  `test_manage(op="results_get")`.
- **Effort:** low.

### Tier 2 — medium, feature-shaped

#### 6. `game_manage(op="input_sequence")` — timed input timeline
- **Problem:** each input action is a separate AI round-trip; frame-accurate
  sequences are impossible from outside the frame loop.
- **Design:** `params={events:[{frame|ms, kind:"action"|"key"|"mouse"|"gamepad",
  action, pressed, strength, ...}], unit:"frame"|"ms"|"physics",
  settle_frames:int, snapshot:{...}}`. Game-side scheduler sorts by time, steps
  `await process_frame`, fires the existing `_game_input_*` bodies at scheduled
  ticks, gathers snapshot, replies once.
- **Constraints:** must respect the 8s game-side eval cap
  (`game_helper.gd:638`) — reject/auto-chunk longer timelines; must handle the
  **backgrounded-freeze** constraint (see #8); return `frames_advanced` so a
  frozen (0-progress) run is detectable.
- **Effort:** medium. The core play-testing fix.

#### 7. `game_manage(op="wait_until")` — game-side assert/wait
- **Design:** `params={setup_events:[...], condition:{path,property,op,value} |
  signal:{path,name}, timeout_ms, poll:"frame", snapshot:{...}}` →
  `{satisfied, elapsed_ms, frames_waited, snapshot, timed_out}`. Fire setup,
  loop `await process_frame` evaluating the compare / awaiting the signal with a
  deadline.
- **Effort:** small–med once #6's scheduler/snapshot helpers exist.

#### 8. Auto-focus / frame-pump helper for backgrounded games
- **Problem:** a backgrounded play-in-editor game has a frozen idle loop —
  `await process_frame`/timers don't advance and input isn't flushed unless the
  window is focused (`handlers/editor.py:419-421`; the whole `#490` eval-probe
  machinery exists for this). Without this, #6/#7 return flaky 0-progress results.
- **Design:** editor-side step to bring the game window foreground before a
  timeline/wait run (cheap), or pump N frames by messaging the game each frame.
- **Effort:** small–med. **Reliability prerequisite for #6/#7.**

#### 9. `diagnostics_read` — on-demand per-file diagnostics
- **Problem:** per-file diagnostics exist only as a side effect of writing a
  script and only on reload failure (errors) — no standalone tool
  (`script_handler.gd:241-288`).
- **Design:** `diagnostics_read(path="", severity="all", scope="all",
  refresh=true)` → `{files:[{path, diagnostics:[{severity, source:
  "parser"|"analyzer"|"runtime"|"debugger", code, message, line, ...}]}]}`.
  `scope="static"` lifts `_capture_gdscript_load_diagnostics` into a shared util
  run **unconditionally** (drop the reload-failed gate; `ValidationLogger` is
  already unfiltered); `scope="runtime"` reads the tracker grouped by file.
- **Effort:** med. **Verify first (see #10).**

#### 10. VERIFY: do GDScript analyzer warnings reach `OS.add_logger`?
- **Experiment (15 min):** attach a `ValidationLogger`, `ResourceLoader.load` a
  file with a known unused-variable warning under `CACHE_MODE_IGNORE`, check the
  buffer. Godot 4.5–4.7 has no public `GDScript.get_warnings()`; the analyzer
  normally keeps gutter warnings (unused var / shadowed / unsafe cast) in the
  parser, **not** the global error handler.
- **If yes:** #9's `scope="static"` covers analyzer warnings for free.
- **If no:** needs EditorLog scraping or a `godot --check-only` subprocess —
  scope as a follow-up.

#### 11. gdUnit4 runner mode — run the game's tests in-editor via MCP
- **Problem:** running `shrine-guardian`'s gdUnit4 suites means shelling out to
  a CI script — slow, disconnected from the editor.
- **Design:** extend the named `test_run` tool with `engine="native"|"gdunit"`,
  plus `mode="editor"|"headless"`, suite/test filters, `include_warnings`,
  `timeout_sec`. Return a schema parallel to the native runner
  (`test_runner.gd:210-242`) plus gdUnit fields (`errors`, `warnings`,
  `orphan_nodes`, per-test `reports:[{message,line}]`).
- **Mechanism:** new `gdunit_handler.gd`, command `run_gdunit_tests` returning
  `DEFERRED_RESPONSE`; connect `GdUnitSignals.instance().gdunit_event`, start the
  executor, frame-poll to the terminal event (pattern: `game_helper.gd:723-752`),
  then `send_deferred_response`. Add a `run_gdunit_tests` entry to
  `DEFERRED_TIMEOUT_MS_BY_COMMAND` (~300000ms) and bump the Python timeout.
  Route failures/warnings through `record_synthetic_error`
  (`surfaced_error_tracker.gd:134`) so they hit `logs_read` + the watermark —
  ties into #4/#5.
- **Implementation order:** (a) presence+version probe (guarded
  `ResourceLoader.load`, never `class_name`/`preload`, so the addon parses when
  gdUnit4 is absent); (b) discovery-only via `GdUnitTestSuiteScanner`;
  (c) headless baseline (`GdUnitCmdTool` + JUnit XML parse) to pin the result
  contract; (d) in-editor deferred run; (e) error/warning surfacing;
  (f) result caching + `results_get`.
- **Open questions:** recent gdUnit4 runs the GUI runner in a *separate* godot
  instance over TCP — inspect `shrine-guardian/addons/gdUnit4/` to confirm the
  in-process entrypoint (`GdUnitRunner`/`GdUnitTestSession`/executor) and the
  `GdUnitEvent` method names before hard-coding the mapping. Needs a fixture
  project with gdUnit4 (`test_project/` uses `McpTestSuite`, not gdUnit4).
- **Effort:** medium–large.

### Tier 3 — large features / capability gaps for the life sim

#### 12. TileSet authoring (currently read-only) — **highest genre value**
- **Gap:** `tileset_manage` only reads (`get_atlas_tiles`/`get_atlas_image`). No
  way to create a TileSet, add a `TileSetAtlasSource` from a texture, or set
  per-tile physics/navigation/custom-data layers.
- **Proposed ops:** `create`, `add_atlas_source`, `add_physics_layer`,
  `add_navigation_layer`, `add_custom_data_layer`, `set_tile_physics`,
  `set_tile_navigation`, `add_terrain_set`, `add_terrain`.
- **Why:** NPC collision, walkability, and per-tile custom data all live here.

#### 13. TileMap terrain / autotiling paint
- **Gap:** `tilemap_manage` has `set_cell`/`set_cells_rect`/`clear`/`get_cells`
  only. Missing terrain connect/path (autotiling), cell-list paint, pattern
  stamp, flip/rotate flags, per-cell nav/physics/custom-data read.
- **Proposed ops:** `set_cells_terrain` (connect + path), `set_cells` (list),
  `set_pattern`, flip/rotate on `set_cell`.

#### 14. Navigation2D baking
- **Gap:** no navigation tooling at all (already listed pending,
  `tool-taxonomy.md:171`). NavigationRegion2D is creatable but there's no bake.
- **Proposed:** `navigation` domain (or fold into tilemap/resource) —
  `bake_region_2d` (NavigationPolygon from rect/outline or TileMapLayer nav
  layers), `agent_configure_2d`.
- **Why:** NPC pathfinding around the village is a defining life-sim feature.

#### 15. Font-file theming
- **Gap:** `theme_manage` does color/constant/font-size/stylebox but not fonts
  (pending, `tool-taxonomy.md:157`; `theme_handler.gd:102`).
- **Proposed ops:** `theme_manage(op="set_font")`, `set_stylebox_texture` for
  9-patch dialogue frames. The cosy look is mostly typography + textured frames.

#### 16. Play-test scenario/replay harness (+ input recorder)
- **Design:** declarative scenario = launch → timeline segments (#6) interleaved
  with `wait_until` (#7) + `snapshot` (#1) assertions, chunked under the 8s cap,
  producing a pass/fail report. Model on `script/stormtest.py`'s worker/metrics
  scaffolding. Optional recorder: hook `_input` during a manual session and emit
  an `input_sequence` timeline for replay.
- **Effort:** large; depends on #1/#6/#7 landing first.

### Lower priority / polish
- ConfigFile save/load helper (`user://` slots) — medium; partly covered by
  custom-Resource `.tres` saves.
- Named physics/nav layer helper — low; interaction masks get tangled as ints.
- Day/night `CanvasModulate` gradient preset — low; achievable today via
  `animation_manage`.

---

## Performance & token wins (independent, isolated PRs)

From the review, beyond #3/#4 above:
- **`scene_get_hierarchy` pagination is Python-side only** — the plugin's
  `get_scene_tree` (`scene_handler.gd:17-25`) walks/serializes/ships the whole
  tree regardless of `limit`; `handlers/scene.py:16-18` slices last. Thread
  `offset`/`limit` into the plugin, stop the walk early. Also `scene.py:18`
  reads a `root` key the plugin never returns (dead code).
- **Double UTF-8 encode on every WS send** — `connection.gd:405-410` calls
  `to_utf8_buffer().size()` just to measure length, then `send_text` encodes
  again. Estimate length cheaply; only exact-encode near the 4MB limit.
- **`from_node` path build is O(n·depth)** — `scene_path.gd:15-23` runs both
  `is_ancestor_of` (redundant top-down) and `get_path_to` per node. Build paths
  incrementally during the walk → O(1)/node.
- **Sync GPU readback in `tick()`** for viewport/cinematic screenshots
  (`editor_handler.gd:598-638`) — only `source="game"` defers; route the others
  through `DEFERRED_RESPONSE`.
- **`godot://scene/hierarchy` resource is unpaginated** (`handlers/scene.py:69-70`)
  while the tool form paginates — apply a default depth/node cap.
- **`api_manage(get_class)` defaults to all 5 sections**
  (`class_introspection.gd:8`) — default to `["properties"]` or names-only.
- ~~**Server `instructions` string** — collapse to the 4 core tools + a
  tool-search pointer.~~ **REJECTED (investigated 2026-07-21).** The full
  enumeration is deliberate: `test_advertised_surface_matches_live_registration`
  asserts every registered tool (incl. `DEFER_META` ones) appears in the text,
  and the header count matches `list_tools()` — this is the #772 honesty design
  guarding against surface/registration drift. `DEFER_META` is only a client
  hint (some clients ignore it and load everything), so advertising the full
  surface is correct. The ~1,200 tokens are a chosen cost, not waste; trimming
  would break the test and contradict the maintainer's design.
- **`editor.py` docstrings** (~9,100 chars) read like manuals — trim war-stories
  to a `godot://` doc resource (~4-5k tokens, non-tool-search clients only).

---

## Suggested first PRs (in order) — Track A first

Lead with Track A (fix/perf-shaped, upstream-friendly, no new fixtures), then
Track B after issues are opened.

1. **#4 warnings-watermark fix** — the priority; a genuine bug (warning-only
   runs report "clean"). Isolated PR-ready branch + tests. *(in progress)*
2. #5 test warnings bucket (rides on #4's warn plumbing)
3. #3 `node_get_properties` `changed_only`/`fields`
4. `scene_get_hierarchy` real (plugin-side) pagination + dead `root` read
5. double-UTF-8-encode fix; `from_node` O(n·depth) fix
6. token trims: `api_manage` default sections, `godot://scene/hierarchy`
   pagination, `server.py` instructions, `editor.py` docstrings
7. #2 surface `game_eval` + helper recipe (docs-heavy)
--- Track B (issue first, dev-now) ---
8. #1 snapshot, then #6/#7/#8 input timeline + wait_until + auto-focus
9. #9 `diagnostics_read` (after #10 verification)
10. #11 gdUnit runner
11. #12 TileSet authoring, #14 Nav2D baking, #13 terrain paint, #15 fonts

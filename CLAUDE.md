# Aseprite Top-Down Layers — notes for Claude

Godot 4 `EditorImportPlugin` for `.aseprite`/`.ase`. Every frame of the source is a 3x3 grid of
facing directions (`left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down`, `right_down`;
center ignored). The file imports as a **SpriteFrames** with one animation per direction × tag
(`sprite_frames/animation_name`, default `{tag}_{direction}`), timed like in Aseprite (speed = 1 /
shortest frame, relative durations, reverse/ping-pong), looping when the tag ends with
`sprite_frames/loop_suffix` (default `_loop`, removed from the name). Cells with no pixels in a tag
give no animation. Aseprite exports strips to the OS cache only; they become lossless
`PortableCompressedTexture2D` textures embedded in the imported resource, so nothing is written to
`res://`. `layers/layer` is a dropdown filled from the file's layers (`[all]` = every layer but
`^_`); the listing is cached by the file's MD5 and shared with `_import`.

An inspector section on AnimatedSprite2D links an AnimationPlayer: each SpriteFrames animation
becomes an animation in the player's global library with discrete `animation` and `frame` tracks.
Syncs keep user tracks, run on reimport and scene change when a key stored in the sprite's metadata
changed, and can be forced with a button.

- Code: `addons/aseprite_topdown_layers/`: `plugin.gd`, `importer.gd`, `settings.gd`,
  `aseprite_cli.gd`, `export_planner.gd` (pure), `sprite_frames_builder.gd` (no editor),
  `animation_sync.gd` (no editor), `animated_sprite_inspector.gd` + `animation_player_panel.gd`
  (editor UI), and `aseprite_batch.lua` (runs inside Aseprite: `mode=list` and `mode=export`).
- Tests: `tests/test_runner.gd`. Demo: `examples/`. `tests/tools/build_grid.lua` turns a
  layer-per-direction sprite into the grid format; `tests/tools/build_cases.lua` builds sprites for
  manual tests into `examples/character/cases/`.
- Pending work: `ROADMAP.md`. Read it before proposing anything.
- Full plan and decision history: `plan/plan-aseprite-topdown-layers.md`. Section 9 ("Emendas")
  overrides the earlier sections. `plan/` is gitignored and local only.

## Environment

- Windows. Godot 4.7.1 and gdtoolkit 4.3.3 (`gdformat`, `gdlint`) are on PATH.
- Aseprite 1.3.18 is **not** on PATH. Pass its executable through the `ASEPRITE_PATH` env var for
  headless tests. Never write local machine paths into tracked files.

## Quality gates (required for every changed file)

- Fully typed GDScript (the demo sets `untyped_declaration=2`), `@tool` on every addon script,
  no global `class_name` (use `preload`).
- `gdformat --check addons tests` and `gdlint addons tests` are clean.
- `godot --headless --check-only --script <file>` on every changed `.gd`.
- `ASEPRITE_PATH=<exe> godot --headless --path . -s tests/test_runner.gd` ends with
  `PASS: 0 failure(s)`.
- **Godot's exit code is not a gate.** Always scan the output for `SCRIPT ERROR`, `ERROR:`,
  `Parse Error` and `WARNING:`. Engine errors count too (e.g. a `slice` with begin > end prints
  `ERROR:` while the check still passes).

## Known gotchas

- Performance: each Aseprite process costs ~200 ms to start (even `--version`); a strip costs a few
  ms. Never add per-strip or per-layer processes: an import is one `list` + one `export` run of
  `aseprite_batch.lua` (30 strips: ~0.3 s vs ~6 s with one CLI call per strip).
- The plain Aseprite CLI exits 0 for a nonexistent layer or tag and produces a wrong image,
  `--split-tags` does not work with `--sheet`, and `--crop` is silently ignored with `--sheet`. The
  Lua script raises an error on unknown layers, tags or directions and on cells that do not fit;
  names still come from the listing and are validated by the planner.
- Strips are built in Lua (`drawSprite` once per frame, crop each cell with
  `Image(image, Rectangle)`, `saveAs`). Create the strip `Image` from a copy of `sprite.spec`:
  `Image(w, h, colorMode)` has no color space. A crop outside the sprite raises no error, so cell
  sizes are validated in the planner and again in Lua.
- The reference strips in `tests/expected/` come from the plain CLI on the layer-per-direction
  `character.aseprite`; the tests check that the imported idle frames of
  `examples/character/character-matrix/character-matrix.aseprite` match them pixel for pixel.
- `append_import_external_resource()` cannot import files created during the same `_import`
  (`Can't find file ... during file reimport`, even after `EditorFileSystem.update_file()`), and a
  failed import leaves `valid=false` that is not retried. That is why textures are embedded.
- Hot reload of `@tool` scripts does not re-run `plugin.gd`'s `_enter_tree()`: new menu items,
  inspector plugins or signal connections only appear after disabling and re-enabling the plugin
  (or restarting the editor). Tell the user to do that before a manual test of such changes.
- Touching the `.aseprite` mtime does not reimport (Godot compares MD5). A parameter change in a
  `.import` file only applies on the next run. To force a reimport in tests, delete the matching
  `.md5` in `.godot/imported/` **and** touch the source's `.import` file: without an mtime change
  Godot does not even check the `.md5`, and nothing is reimported. The same goes for a new
  `_get_format_version()`: it reimports a file (and writes `importer_version` to its `.import`)
  only once that file is checked again, so existing projects need *Reimport all* or a touch.
- `EditorFileSystem.resources_reimported` is handled with a deferred sync, so the reimported
  SpriteFrames is reloaded before the AnimationPlayer is synced (confirmed in the editor: a
  duration changed in Aseprite reaches the AnimationPlayer and user tracks survive).
- Metadata names starting with `_` are editor-only and not saved: the sprite's link and sync key use
  `aseprite_topdown_layers_*` names.

## Publishing

- **No `git push`, GitHub repo creation or Asset Library submission without explicit user
  confirmation**.

## Git

- Conventional commits in English (`feat(importer): ...`, `docs: ...`), one per unit of work.
- **No trailers**: no `Co-Authored-By`, no `Claude-Session`.
- History rewrites only with user confirmation, and `git stash` first if there
  is uncommitted work.

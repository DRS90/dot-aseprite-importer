# Aseprite Top-Down Layers — notes for Claude

Godot 4 `EditorImportPlugin` for `.aseprite`/`.ase`. Every frame of the source is a 3x3 grid of
facing directions (`left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down`, `right_down`;
center ignored). On import it exports one horizontal PNG strip per direction × tag to
`assets/{tag}/{title}_{direction}_{tag}.png`, relative to the source file, skipping cells with no
pixels in the tag. `layers/layer` is a dropdown filled from the file's layers (`[all]` = every layer
but `^_`); the listing is cached by the file's MD5 and shared with `_import`, so the dropdown adds no
Aseprite process. A `PackedDataContainer`
manifest lets it delete stale outputs, and PNGs are copied into `res://` only when their MD5
changed (prevents cascading reimports).

- Code: `addons/aseprite_topdown_layers/{plugin,importer,aseprite_cli,export_planner,settings,fs_scan_scheduler}.gd`
  and `aseprite_batch.lua` (runs inside Aseprite: `mode=list` and `mode=export`).
- Tests: `tests/test_runner.gd`. Demo: `examples/`. `tests/tools/build_grid.lua` turns a
  layer-per-direction sprite into the grid format.
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
  `Parse Error` and `WARNING:`.

## Known gotchas

- Performance: each Aseprite process costs ~200 ms to start (even `--version`); a strip costs a few
  ms. Never add per-strip or per-layer processes: an import is one `list` + one `export` run of
  `aseprite_batch.lua` (30 strips: ~0.3 s vs ~6 s with one CLI call per strip).
- The plain Aseprite CLI exits 0 for a nonexistent layer or tag and produces a wrong image,
  `--split-tags` does not work with `--sheet`, and `--crop` is silently ignored with `--sheet`. The
  Lua script raises an error on unknown layers, tags or directions and on cells that do not fit;
  names still come from the listing and are validated by the planner.
- Strips are built in Lua (`drawSprite` once per frame, crop each cell with
  `Image(image, Rectangle)`, `saveAs`), not with `ExportSpriteSheet`. Create the strip `Image` from
  a copy of `sprite.spec`: `Image(w, h, colorMode)` has no color space, so the PNG loses its `sRGB`
  chunk and its MD5 changes although the pixels are equal. A crop outside the sprite raises no
  error, so cell sizes are validated in the planner and again in Lua.
- The reference strips in `tests/expected/` come from the plain CLI on the layer-per-direction
  `character.aseprite`; the tests check that the grid export of
  `examples/character/character-matrix/character-matrix.aseprite` matches them byte for byte.
- `.import` files written before the grid format still hold `output/filename="{title}_{layer}_{tag}"`;
  the planner rejects `{layer}`, so such a file fails to import until the parameter is changed.
- `godot --headless --import`: the first run writes the PNGs, but their `.import` files only
  appear on a second run (the deferred scan does not run before exit).
- Hot reload of `@tool` scripts does not re-run `plugin.gd`'s `_enter_tree()`: new menu items or
  registrations only appear after disabling and re-enabling the plugin (or restarting the editor).
  Tell the user to do that before a manual test of such changes.
- Touching the `.aseprite` mtime does not reimport (Godot compares MD5). A parameter change in a
  `.import` file only applies on the next run. To force a reimport in tests, delete the matching
  `.md5` in `.godot/imported/` **and** touch the source's `.import` file: without an mtime change
  Godot does not even check the `.md5`, and nothing is reimported. Keep the `.res` next to it: it *is* the manifest, and without it
  stale strips can no longer be found.

## Publishing

- **No `git push`, GitHub repo creation or Asset Library submission without explicit user
  confirmation**.

## Git

- Conventional commits in English (`feat(importer): ...`, `docs: ...`), one per unit of work.
- **No trailers**: no `Co-Authored-By`, no `Claude-Session`.
- History rewrites only with user confirmation, and `git stash` first if there
  is uncommitted work.

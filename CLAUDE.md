# Aseprite Top-Down Layers — notes for Claude

Godot 4 `EditorImportPlugin` for `.aseprite`/`.ase`. On import it exports one horizontal
PNG strip per layer (or layer group / combination) × tag to
`assets/{tag}/{title}_{layer}_{tag}.png`, relative to the source file. A `PackedDataContainer`
manifest lets it delete stale outputs, and PNGs are copied into `res://` only when their MD5
changed (prevents cascading reimports).

- Code: `addons/aseprite_topdown_layers/{plugin,importer,aseprite_cli,export_planner,settings,fs_scan_scheduler}.gd`
  and `aseprite_batch.lua` (runs inside Aseprite: `mode=list` and `mode=export`).
- Tests: `tests/test_runner.gd`. Demo: `examples/`.
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
- The plain Aseprite CLI exits 0 for a nonexistent layer or tag and produces a wrong image, and
  `--split-tags` does not work with `--sheet`. The Lua script raises an error on unknown names;
  names still come from the listing and are validated by the planner.
- `app.command.ExportSpriteSheet` without `ui` reuses the last Export Sprite Sheet dialog settings
  for unset parameters: pass every parameter that affects the image. An empty `dataFilename`
  dumps the JSON to stdout, so the script writes it to a cache file.
- The reference strips in `tests/expected/` come from the plain CLI; the tests check that the Lua
  export matches them byte for byte (and a combination against `--layer a --layer b`).
- `godot --headless --import`: the first run writes the PNGs, but their `.import` files only
  appear on a second run (the deferred scan does not run before exit).
- Touching the `.aseprite` mtime does not reimport (Godot compares MD5). A parameter change in a
  `.import` file only applies on the next run. To force a reimport in tests, delete the matching
  `.md5`/`.res` in `.godot/imported/`.

## Publishing

- **No `git push`, GitHub repo creation or Asset Library submission without explicit user
  confirmation**.

## Git

- Conventional commits in English (`feat(importer): ...`, `docs: ...`), one per unit of work.
- **No trailers**: no `Co-Authored-By`, no `Claude-Session`.
- History rewrites only with user confirmation, and `git stash` first if there
  is uncommitted work.

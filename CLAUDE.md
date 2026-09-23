# Dot Aseprite Importer — notes for Claude

Godot 4 addon with two `EditorImportPlugin`s for `.aseprite`/`.ase`. The main one (priority 1.0)
imports animations; `texture_importer.gd` (0.9, picked with *Import As*) imports any file as a
lossless `Texture2D` of the whole canvas with every frame side by side, reusing the planner with an
empty tag list. Both share `aseprite_source.gd` (executable lookup + listing cache).
For the animations importer: every frame of the source is a single nameless cell
(`grid/directions` = `none`, the default, `ExportPlanner.DEFAULT_DIRECTIONS`), or with `3x3` a grid
of facing directions (`left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down`,
`right_down`; center ignored), which top-down projects set in *Project Settings > Import Defaults*.
The file imports as a **SpriteFrames** with one animation per direction × tag
(`sprite_frames/animation_name`, default `{tag}_{direction}`), timed like in Aseprite (speed = 1 /
shortest frame, relative durations, reverse/ping-pong), looping when the tag ends with
`sprite_frames/loop_suffix` (default `_loop`, removed from the name). Cells with no pixels in a tag
give no animation. Aseprite exports strips to the OS cache only; `sheet_packer.gd` packs every frame
into one sheet per file (each frame cut to its used rect, frames with the same size and bytes
stored once, shelf-packed), embedded as a single lossless `PortableCompressedTexture2D` that every
frame's `AtlasTexture` shares, with a `margin` giving the cut space back so frames keep the cell
size and pivot. Nothing is written to `res://`. Size, layers, tags and durations are read from the
file's bytes by `aseprite_file_reader.gd` (no Aseprite process); `layers/layer` is a dropdown filled
from them (`[all]` = every layer but `^_`), cached by the file's MD5 and shared with `_import`.

An inspector section on AnimatedSprite2D links an AnimationPlayer: each SpriteFrames animation
becomes an animation in the player's global library with discrete `animation` and `frame` tracks.
Syncs keep user tracks, run on reimport and scene change when a key stored in the sprite's metadata
changed, and can be forced with a button. The library goes to its own file when
`animation_player/external_library` is on (the default), named by `animation_player/library_path`
(`{scene_dir}/{scene}_animations.tres`); off keeps it inside the scene. The resolved path is part of
the sync key, so a skipped sync never touches the disk.

- Code: `addons/dot_aseprite/`: `plugin.gd`, `importer.gd`, `settings.gd`,
  `aseprite_cli.gd`, `aseprite_source.gd`, `aseprite_file_reader.gd` + `export_planner.gd` (pure),
  `sheet_packer.gd` +
  `sprite_frames_builder.gd` (no editor),
  `animation_sync.gd` + `animation_library_store.gd` (no editor),
  `animated_sprite_inspector.gd` + `animation_player_panel.gd`
  (editor UI), and `aseprite_batch.lua` (runs inside Aseprite: `mode=export`, and `mode=list`, which
  only the tests use as the reference for the file reader).
- Tests: `tests/test_runner.gd`, plus `tests/animation_sync_tests.gd` (the AnimationPlayer sync
  checks, which build their nodes by hand and never call Aseprite), `tests/sheet_packer_tests.gd`
  (synthetic strips), `tests/importer_options_tests.gd` (the `none` default; an `EditorImportPlugin`
  cannot be instantiated headless, so it reads the importer's static `directions_option()` and
  `planner_options()`) and `tests/aseprite_file_reader_tests.gd` (reader vs Aseprite's listing, on
  sprites built by `tests/tools/build_reader_cases.lua`, plus the source). Demo: `examples/`.
  `tests/tools/build_grid.lua` turns a layer-per-direction sprite into the grid format;
  `tests/tools/build_cases.lua` builds sprites for manual tests into the folder passed as `out=`.
- Docs: `README.md` keeps only the overview, install, quick start and links; the details live in
  `docs/` (getting started, top-down characters, drawing, importing, AnimatedSprite2D,
  AnimationPlayer, limitations, development). English is the source of truth; `README.pt-BR.md` and
  `docs/pt-BR/` (same file names) mirror it, and every docs change updates both languages in the
  same commit. Menu, panel and option names stay in English in the translation. The addon folder's
  `README.md` is the English one with its links pointed back at the repository root; regenerate it
  after any edit with
  `sed -e 's#](docs/#](../../docs/#g' -e 's#](screenshots/#](../../screenshots/#g'
  -e 's#](README.pt-BR.md)#](../../README.pt-BR.md)#g' README.md`.
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

- Performance: each Aseprite process costs ~200 ms to start (even `--version`) plus the time to open
  the file (~570 ms for 320 frames of 128x128: every cel is decompressed); a strip costs a few ms.
  Never add per-strip, per-layer or listing processes: an import is one `export` run of
  `aseprite_batch.lua`, and what the file holds comes from `aseprite_file_reader.gd`.
- Never take names from Aseprite's stdout: on Windows `OS.execute()` hands non-ASCII output back
  garbled (`ação` arrives as `aÃ§Ã£o`). And the exit code cannot tell a failed start from a Lua
  error: Aseprite exits 127 on a script error, which `OS.execute()` reports as -1 on Windows, like a
  process that never started. The output tells them apart (`AsepriteCli.did_not_run()`): on Windows
  a failed start prints nothing, while elsewhere `OS.execute()` goes through `sh`, which prints
  `sh: ...` and exits 126/127 for a missing or non-executable file. A missing `--script` file also
  exits 127 with no output (e.g. the addon folder moved with the editor open), so `_run_batch`
  checks that `aseprite_batch.lua` exists before starting Aseprite.
- The nameless cell of `grid/directions` = `none` and `left_up` are both at (0, 0), so checking
  that a direction exists is not enough: `aseprite_batch.lua` requires `cells_per_axis == 1` to
  match an empty direction exactly, or a 3x3 job with no direction would export the `left_up` cell
  under a name nobody asked for.
- The plain Aseprite CLI exits 0 for a nonexistent layer or tag and produces a wrong image,
  `--split-tags` does not work with `--sheet`, and `--crop` is silently ignored with `--sheet`. The
  Lua script raises an error on unknown layers, tags or directions and on cells that do not fit;
  names still come from the listing and are validated by the planner.
- Strips are built in Lua (`drawSprite` once per frame, crop each cell with
  `Image(image, Rectangle)`, `saveAs`). Create the strip `Image` from a copy of `sprite.spec`:
  `Image(w, h, colorMode)` has no color space. A crop outside the sprite raises no error, so cell
  sizes are validated in the planner and again in Lua.
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
- Rename or move the addon folder only with the Godot editor **closed**. A running editor that loses
  the importer rewrites the `.import` files using it to `importer="keep"` (dropping params and uid)
  or leaves them with `valid=false`, and *Reimport all* then finds no file.
- `AtlasTexture.get_image()` ignores `margin`, so a trimmed frame comes back smaller than its cell:
  tests rebuild the cell with `SheetPackerTests.frame_image()`. A `region` of size 0 means "the
  whole atlas", so the packer leaves out a strip with no visible pixel instead of emitting one.
  Such strips do reach it: Lua's `Image:isEmpty()` compares raw pixels with 0, while Godot's
  `get_used_rect()` looks at alpha, so a cell of alpha-0 pixels with color under them (common in
  art pasted from PNG sheets) is exported and must give no animation, not fail the import.
- Metadata names starting with `_` are **saved** — verified headless for a node in a `.tscn` and a
  resource in both `.tres` and binary `.res`. The `_` only hides the entry from the inspector's
  Metadata list, which is what the docs mean by "editor-only". The sprite's link and sync key use
  `_dot_aseprite_*` for that reason.
- A resource built into a scene still has a `resource_path`
  (`res://scene.tscn::AnimationLibrary_abcd`), so `resource_path != ""` does **not** mean external:
  use `is_built_in()`. Getting this wrong passes headless (where nodes have no scene path, so the
  path is empty) and fails in the editor, where every saved scene looks external.
- A setting registered with `ProjectSettings.add_property_info()` only shows with *Advanced
  Settings* on, which is where nobody looks for an addon. `ProjectSettings.set_as_basic(key, true)`
  fixes it and is not persisted, so `register()` calls it on every run.

## Example asset

- The example is `examples/retro-top-down-character.aseprite`, built by
  `tests/tools/build_retro_example.lua` from the CC0 sheets in
  `examples/rpg-type-retro-top-down-playable-character-spritesheett/` (5yvalia, `LICENSE.png`
  included). Everything is tracked in git and the tests compare the imported frames with the sheets.
- Any third-party asset must allow redistribution before it is committed.
- **No `git push`, GitHub repo creation or Asset Library submission without explicit user
  confirmation.**

## Git

- Conventional commits in English (`feat(importer): ...`, `docs: ...`), one per unit of work.
- **No trailers**: no `Co-Authored-By`, no `Claude-Session`.
- History rewrites only with user confirmation, and `git stash` first if there
  is uncommitted work.

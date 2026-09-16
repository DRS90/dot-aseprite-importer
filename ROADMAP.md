# Roadmap

## v0.1.0 — first release

- [x] Repository scaffold, demo project, lint/format setup
- [x] Aseprite CLI wrapper, export planner, headless test runner
      (reproduces the reference `idle_loop` strips byte for byte)
- [x] Import plugin: one horizontal PNG strip per layer × tag, manifest,
      copy-only-if-changed, stale output cleanup
- [x] Layer combinations (`layers/always_include`, `layers/combinations`)
- [x] *Project > Tools* menu item to reimport every `.aseprite` file
- [x] README (install, settings, naming templates, AsepriteWizard coexistence), CHANGELOG
- [x] 3x3 grid format replaces one layer per direction: one strip per direction × tag,
      `grid/cell_size`, `layers/layer` dropdown, empty cells skipped
      (layer combinations removed; `tests/tools/build_grid.lua` converts old sprites)
- [x] Import as SpriteFrames with Aseprite frame timing, tag direction and a configurable loop
      suffix; strips are no longer written to the project
- [x] AnimationPlayer section in the AnimatedSprite2D inspector, synced on reimport and scene open
- [x] The player's animation library is written to a resource file of its own (*External Library*
      and *Library Path* in Project Settings, `{scene_dir}/{scene}_animations.tres`), keeping the
      generated animations out of the scene; turn it off to keep them inside

## Before publishing

- [x] Manual test in the editor: save in Aseprite, focus Godot, strips update with no cascading reimports
- [x] Manual test in the editor of the grid format (strips per direction, empty cells, `grid/cell_size`,
      `layers/layer` dropdown; sprites from `tests/tools/build_cases.lua`)
- [x] Manual test in the editor of the SpriteFrames import and the AnimationPlayer sync
- [x] Manual test in the editor of the animation library settings: they show without *Advanced
      Settings*, the library file is created and adopted, and a tag removed in Aseprite reaches the
      `.tres`
- [x] Rename the addon to Aseprite Top-Down Grid Animations ("Layers" no longer described it)
- [ ] Rename the repository to `godot-aseprite-topdown-grid-animations` when it is published
- [x] Screenshots in `screenshots/`: the Aseprite frame as a 3x3 grid with guide lines and the tags
      in the timeline, and the editor with the imported animations and the AnimationPlayer section.
      They are linked from the README at publish time, when the repository URL exists
- [ ] Square PNG icon (≥128 px) for the Asset Library listing
- [x] Confirm the license holder in `LICENSE` (MIT, Douglas Rodrigo dos Santos)
- [x] Replace the example asset with 5yvalia's CC0
      [RPG Type Retro Top-Down Playable Character Template](https://5yvalia.itch.io/rpg-type-retro-top-down-playable-character-template):
      `tests/tools/build_retro_example.lua` builds `examples/retro-top-down-character.aseprite` from
      its sheets, both are tracked in git, and the tests compare the imported frames with the sheets
- [ ] Push to GitHub, tag `v0.1.0`
- [ ] Submit to the Godot Asset Library (category Addon, Godot 4.7, MIT, commit hash of the tag)

## Next (v0.2.x)

- [ ] Custom direction name per grid cell
- [ ] Warn when the ignored center cell has pixels
- [ ] Undo/redo for AnimationPlayer syncs
- [ ] Test on Godot 4.4–4.6 and lower the declared minimum version
- [ ] CI: gdformat/gdlint and headless tests on GitHub Actions

## Ideas (undecided)

- Companion Aseprite Lua extension to export on save, without waiting for Godot to regain focus
- Grids other than 3x3 (e.g. 4 or 16 directions), or directions from named slices
- Honor the tag repeat count (play N times, then stop)
- Import without Aseprite for teammates, e.g. from a committed bake of the SpriteFrames

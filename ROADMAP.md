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
- [x] `grid/directions` = `3x3` | `none`: sprites with no direction (run dust, hit sparks) import
      with the frame as a single cell, so a top-down project needs no second Aseprite importer
- [x] Second importer *Aseprite Texture* (*Import As*, priority 0.9): any `.aseprite` as a lossless
      `Texture2D` of the whole canvas, for Sprite2D, TextureRect, shaders and TileSet source images

## Before publishing

- [x] Manual test in the editor: save in Aseprite, focus Godot, strips update with no cascading reimports
- [x] Manual test in the editor of the grid format (strips per direction, empty cells, `grid/cell_size`,
      `layers/layer` dropdown; sprites from `tests/tools/build_cases.lua`)
- [x] Manual test in the editor of the SpriteFrames import and the AnimationPlayer sync
- [x] Manual test in the editor of the animation library settings: they show without *Advanced
      Settings*, the library file is created and adopted, and a tag removed in Aseprite reaches the
      `.tres`
- [x] Rename the addon to Aseprite Top-Down Grid Animations ("Layers" no longer described it)
- [x] Rename the repository folder to `godot-aseprite-topdown-grid-animations` (the GitHub
      repository takes the same name when it is created)
- [x] Screenshots in `screenshots/`: the Aseprite frame as a 3x3 grid with guide lines and the tags
      in the timeline, and the editor with the imported animations and the AnimationPlayer section,
      linked from both READMEs
- [x] Square PNG icon (≥128 px) for the Asset Library listing: `icon.png`, 320 px pixel art (160 px drawn, doubled without smoothing)
- [x] Confirm the license holder in `LICENSE` (MIT, Douglas Rodrigo dos Santos)
- [x] Replace the example asset with 5yvalia's CC0
      [RPG Type Retro Top-Down Playable Character Template](https://5yvalia.itch.io/rpg-type-retro-top-down-playable-character-template):
      `tests/tools/build_retro_example.lua` builds `examples/retro-top-down-character.aseprite` from
      its sheets, both are tracked in git, and the tests compare the imported frames with the sheets
- [x] Create the GitHub repository, private for now
      (<https://github.com/DRS90/godot-aseprite-topdown-grid-animations>), and push `main`
- [x] Manual test in the editor of `grid/directions` = `none`: a sprite with no directions and a
      `_loop` tag imports as one looping animation with the suffix dropped from its name; a size
      that is not a multiple of 3 fails with a message naming both ways out; a method track added
      to a synced animation by hand survives the source being edited and reimported; and the grid
      files still import unchanged
- [x] Manual test in the editor of *Aseprite Texture*: `examples/shadow.aseprite` imported with
      *Import As* drives a Sprite2D, a `sampler2D` uniform of a ShaderMaterial and the texture of a
      TileSetAtlasSource painted on a TileMapLayer; editing it in Aseprite updates all of them; and
      a newly added `.aseprite` still lands on the animations importer
- [ ] Make the repository public and tag `v0.1.0`
- [ ] Submit to the Godot Asset Library (category Addon, Godot 4.7, MIT, commit hash of the tag)

## Next (v0.2.x)

- [ ] Custom direction name per grid cell
- [ ] Warn when the ignored center cell has pixels
- [ ] Undo/redo for AnimationPlayer syncs
- [ ] Test on Godot 4.4–4.6 and lower the declared minimum version
- [ ] CI: gdformat/gdlint and headless tests on GitHub Actions

## Ideas (undecided)

- Companion Aseprite Lua extension to export on save, without waiting for Godot to regain focus
- Grids other than 3x3 (e.g. 4 or 16 directions), or directions from named slices. `grid/directions`
  = `none` does not commit to this: it exists because every top-down game has directionless
  companion sprites, not as the first step of a configurable grid. The code shape (a divisor plus a
  cell list per mode) would make 1x4 a small step, but nothing has been decided
- Honor the tag repeat count (play N times, then stop)
- Import without Aseprite for teammates, e.g. from a committed bake of the SpriteFrames

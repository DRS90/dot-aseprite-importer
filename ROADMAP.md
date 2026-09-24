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
      with the frame as a single cell, so a top-down project needs no second Aseprite importer;
      `none` became the default with the rename to Dot Aseprite Importer
- [x] Second importer *Dot Aseprite Texture* (*Import As*, priority 0.9): any `.aseprite` as a
      lossless `Texture2D` of the whole canvas, for Sprite2D, TextureRect, shaders and TileSet
      source images
- [x] One sheet per file instead of one texture per strip: one animation per row, trimmed to the
      pixels the animation uses, with `AtlasTexture` margins keeping the frame size and the pivot,
      so every sprite using the file draws the same texture (the example's sheet is 132x535, 82%
      fewer pixels, and ~62 ms → ~19 ms)
- [x] One Aseprite process per import: the size, layers, tags and durations are read from the
      `.aseprite` file itself (the layer dropdown no longer needs Aseprite, and non-ASCII layer names
      work), and the sheet is packed per frame with repeated frames stored once (the example's sheet
      132x535 → 166x128 px; a 48x48 benchmark sprite imports in ~330 ms instead of ~750 ms)

## Before publishing

- [x] Manual test in the editor: save in Aseprite, focus Godot, strips update with no cascading reimports
- [x] Manual test in the editor of the grid format (strips per direction, empty cells, `grid/cell_size`,
      `layers/layer` dropdown; sprites from `tests/tools/build_cases.lua`)
- [x] Manual test in the editor of the SpriteFrames import and the AnimationPlayer sync
- [x] Manual test in the editor of the animation library settings: they show without *Advanced
      Settings*, the library file is created and adopted, and a tag removed in Aseprite reaches the
      `.tres`
- [x] Rename the addon to Dot Aseprite Importer (`addons/dot_aseprite_importer/`): it imports any
      `.aseprite`, and the 3x3 grid of directions is one of its features
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
- [x] Manual test in the editor of *Dot Aseprite Texture*: `examples/shadow.aseprite` imported with
      *Import As* drives a Sprite2D, a `sampler2D` uniform of a ShaderMaterial and the texture of a
      TileSetAtlasSource painted on a TileMapLayer; editing it in Aseprite updates all of them; and
      a newly added `.aseprite` still lands on the animations importer
- [x] Manual test in the editor of the single sheet: `examples/main.tscn` reimported after the
      format bump, the character does not move against its shadow while walking, `flip_h` on a
      `slash_*` animation does not shift it, every frame shows 48x48 in the SpriteFrames panel,
      opening the scene leaves it and `main_animations.tres` unchanged, and *Draw Calls* with both
      characters in different animations drops from 4 (one texture per strip) to 3
- [x] Manual test in the editor of the per-frame sheet: `examples/main.tscn` reimported after the
      format bump to 3, the character does not move against its shadow, `flip_h` does not shift
      it, every frame shows 48x48 in the SpriteFrames panel, *Draw Calls* as before, and the layer
      dropdown lists the layers with the executable path cleared
- [x] Manual test in the editor of the rename and of `grid/directions` = `none` by default: the
      plugin, the importers in *Import As*, the settings sections and the Tools item carry the new
      names; a new `.aseprite` imports with `none`; *Project Settings > Import Defaults* lists
      *Dot Aseprite SpriteFrames*, and `3x3` saved there makes the next new file a grid; the
      example opens without a sync and animates as before; `screenshots/godot-editor.png` retaken
      with the new names
- [ ] Rename the GitHub repository to `dot-aseprite-importer` and the local folder to match
- [ ] Icon: the Aseprite face with an element of its own, like the other Aseprite addons do
- [ ] Make the repository public and tag `v0.1.0`
- [ ] Submit to the Godot Asset Library (category Addon, Godot 4.7, MIT, commit hash of the tag)
      and to the Godot Asset Store

## Next (v0.2.x)

- [ ] Custom direction name per grid cell
- [ ] Warn when the ignored center cell has pixels
- [ ] Undo/redo for AnimationPlayer syncs
- [ ] Test on Godot 4.4–4.6 and lower the declared minimum version
- [ ] CI: gdformat/gdlint and headless tests on GitHub Actions

## Ideas (undecided)

- Companion Aseprite Lua extension to export on save, without waiting for Godot to regain focus
- Grids other than 3x3 (e.g. 4 or 16 directions), or directions from named slices. `grid/directions`
  = `none` does not commit to this: it is the whole frame, the default for any sprite, not the first
  step of a configurable grid. The code shape (a divisor plus a cell list per mode) would make 1x4 a
  small step, but nothing has been decided
- Honor the tag repeat count (play N times, then stop)
- Import without Aseprite for teammates, e.g. from a committed bake of the SpriteFrames

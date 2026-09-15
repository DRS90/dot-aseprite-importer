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
      `grid/cell_size`, `layers/include`, empty cells skipped
      (layer combinations removed; `tests/tools/build_grid.lua` converts old sprites)

## Before publishing

- [x] Manual test in the editor: save in Aseprite, focus Godot, strips update with no cascading reimports
- [ ] Manual test in the editor of the grid format (strips per direction, empty cells, `grid/cell_size`,
      `layers/include`)
- [ ] Rename the addon: "Layers" no longer describes the grid format
- [ ] Screenshots in `screenshots/`
- [ ] Square PNG icon (≥128 px) for the Asset Library listing
- [ ] Confirm the license holder in `LICENSE`
- [ ] Push to GitHub, tag `v0.1.0`
- [ ] Submit to the Godot Asset Library (category Addon, Godot 4.7, MIT, commit hash of the tag)

## Next (v0.2.x)

- [ ] Custom direction name per grid cell
- [ ] Warn when the ignored center cell has pixels
- [ ] Test on Godot 4.4–4.6 and lower the declared minimum version
- [ ] CI: gdformat/gdlint and headless tests on GitHub Actions
- [ ] Honor tag direction (reverse / ping-pong) in the exported strip

## Ideas (undecided)

- Optional SpriteFrames generation from the strips
- Companion Aseprite Lua extension to export on save, without waiting for Godot to regain focus
- Grids other than 3x3 (e.g. 4 or 16 directions), or directions from named slices

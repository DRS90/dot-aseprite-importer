# Roadmap

## v0.1.0 — first release

- [x] Repository scaffold, demo project, lint/format setup
- [x] Aseprite CLI wrapper, export planner, headless test runner
      (reproduces the reference `idle_loop` strips byte for byte)
- [x] Import plugin: one horizontal PNG strip per layer × tag, manifest,
      copy-only-if-changed, stale output cleanup
- [ ] Layer combinations (`layers/always_include`, `layers/combinations`)
- [ ] *Project > Tools* menu item to reimport every `.aseprite` file
- [ ] README (install, settings, naming templates, AsepriteWizard coexistence), CHANGELOG

## Before publishing

- [ ] Manual test in the editor: save in Aseprite, focus Godot, strips update with no cascading reimports
- [ ] Screenshots in `screenshots/`
- [ ] Square PNG icon (≥128 px) for the Asset Library listing
- [ ] Confirm the license holder in `LICENSE`
- [ ] Push to GitHub, tag `v0.1.0`
- [ ] Submit to the Godot Asset Library (category Addon, Godot 4.7, MIT, commit hash of the tag)

## Next (v0.2.x)

- [ ] `output/skip_empty` — skip strips with no cels in the tag
- [ ] Test on Godot 4.4–4.6 and lower the declared minimum version
- [ ] CI: gdformat/gdlint and headless tests on GitHub Actions
- [ ] Honor tag direction (reverse / ping-pong) in the exported strip

## Ideas (undecided)

- Optional SpriteFrames generation from the strips
- Companion Aseprite Lua extension to export on save, without waiting for Godot to regain focus

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- An AnimationPlayer library kept in its own file (the default) was saved empty: the sync wrote the
  animations only in the editor's memory, and saving the scene does not write external resources,
  so running the game failed to find them. The library file is now saved after every sync.
- Projects already synced by 0.1.0 recover on their own: every linked sprite syncs once more when
  its scene is opened, which rewrites library files left empty or stale. After that, a sync no
  longer trusts a matching key when the library lacks the sprite's tracks in one of its
  animations, which also covers sprites sharing a player and an animation name.
- A library file that fails to save no longer counts as synced: the next sync tries again and
  reports the error.
- A player whose root node does not resolve is reported on every sync, and the sync writes
  neither the library file nor the sync key.

## [0.1.0] - 2026-09-24

### Added

- `EditorImportPlugin` that imports `.aseprite` / `.ase` files as SpriteFrames, with one animation
  per tag. Aseprite runs once per import whatever the number of animations, to export every
  animation through a bundled Lua script; the size, layers, tags and frame durations are read from
  the file itself.
- Aseprite timing: the animation speed comes from the shortest frame of the tag and every frame
  keeps its relative duration; reverse, ping-pong and ping-pong reverse tags reorder the frames.
- Animation names from `sprite_frames/animation_name` (default `{tag}_{direction}`), and loops from
  a tag suffix, `sprite_frames/loop_suffix` (default `_loop`), which is left out of the name.
- `grid/directions`: `none` (the default) imports the whole frame as a single cell; `3x3` imports
  sprites drawn as a 3x3 grid of facing directions, with one animation per direction and tag, for
  top-down characters. A top-down project sets `3x3` for every new file in *Project Settings >
  Import Defaults*. Animation names drop `{direction}` with its separator when there is none, and a
  file without tags or directions names its only animation `default`.
- Cell size taken from the sprite (the whole frame, or a third on each axis in a 3x3 grid) or set
  with `grid/cell_size`. A cell with no pixels in a tag produces no animation.
- Two tags that give the same animation name fail the import instead of dropping the second one, so
  the animations that still worked are kept until the names are fixed.
- `layers/layer` dropdown, filled with the file's top-level layers and groups, to import one of them
  instead of `[all]`. The layers are read from the file, so the dropdown works before Aseprite is
  configured.
- Layer and tag exclusion patterns and `only_visible`.
- A second importer, *Dot Aseprite Texture*, picked per file with **Import As**: it exports the
  whole canvas with every frame side by side and saves a lossless `Texture2D`, so an `.aseprite` can
  be used in a Sprite2D, a TextureRect, a shader uniform or as the source image of a TileSet. Tags
  and the grid are ignored by it, and it stays at a lower priority so a new file still lands on the
  animations importer.
- One texture per file, embedded in the imported resource: every frame is packed into one sheet,
  cut to its own pixels, with repeated frames stored once, so every sprite using the file draws the
  same texture.
  Nothing is written to the project, and exported scenes carry their textures.
- AnimationPlayer section in the AnimatedSprite2D inspector: the sprite's animations are written to
  the linked player and synced again on reimport and when a scene is opened, keeping the tracks
  added to them.
- Project Settings *Animation Player > External Library* and *Library Path*: the player's animation
  library is written to a resource file named by a template
  (`{scene_dir}/{scene}_animations.tres`) instead of into the scene. On by default; turn it off to
  keep the animations in the scene.
- Executable path from Editor Settings, the `ASEPRITE_PATH` variable or the OS default.
- Project-wide defaults in Project Settings.
- *Project > Tools > Dot Aseprite Importer: Reimport all*.
- Headless test runner, demo project, `tests/tools/build_grid.lua` (turns a sprite drawn with one
  layer per direction into the grid format) and `tests/tools/build_cases.lua` (sprites for manual
  tests).

[0.1.0]: https://github.com/DRS90/dot-aseprite-importer/releases/tag/v0.1.0

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- `EditorImportPlugin` that imports `.aseprite` / `.ase` sprites drawn as a 3x3 grid of facing
  directions as SpriteFrames, with one animation per direction and tag. Aseprite runs twice per
  import whatever the number of animations: once to read the size, layers, tags and frame
  durations, once to export every animation through a bundled Lua script.
- Aseprite timing: the animation speed comes from the shortest frame of the tag and every frame
  keeps its relative duration; reverse, ping-pong and ping-pong reverse tags reorder the frames.
- Animation names from `sprite_frames/animation_name` (default `{tag}_{direction}`), and loops from
  a tag suffix, `sprite_frames/loop_suffix` (default `_loop`), which is left out of the name.
- Cell size taken from the sprite (a third on each axis) or set with `grid/cell_size`. A cell with
  no pixels in a tag produces no animation.
- `layers/layer` dropdown, filled with the file's top-level layers and groups, to import one of them
  instead of `[all]`.
- Layer and tag exclusion patterns and `only_visible`.
- Textures embedded in the imported resource: nothing is written to the project, and exported scenes
  carry their textures.
- AnimationPlayer section in the AnimatedSprite2D inspector: the sprite's animations are written to
  the linked player and synced again on reimport and when a scene is opened, keeping the tracks
  added to them.
- Project Settings *Animation Player > External Library* and *Library Path*: the player's animation
  library is written to a resource file named by a template
  (`{scene_dir}/{scene}_animations.tres`) instead of into the scene. On by default; turn it off to
  keep the animations in the scene.
- Executable path from Editor Settings, the `ASEPRITE_PATH` variable or the OS default.
- Project-wide defaults in Project Settings.
- *Project > Tools > Aseprite Top-Down Grid Animations: Reimport all*.
- Headless test runner, demo project, `tests/tools/build_grid.lua` (turns a sprite drawn with one
  layer per direction into the grid format) and `tests/tools/build_cases.lua` (sprites for manual
  tests).

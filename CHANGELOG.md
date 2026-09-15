# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- `EditorImportPlugin` for `.aseprite` / `.ase` sprites drawn as a 3x3 grid of facing directions
  that exports one PNG strip per direction and tag. Aseprite runs twice per import whatever the
  number of strips: once to read the size, layers and tags, once to export every strip through a
  bundled Lua script.
- Cell size taken from the sprite (a third on each axis) or set with `grid/cell_size`. A cell with
  no pixels in a tag produces no strip.
- `layers/layer` dropdown, filled with the file's top-level layers and groups, to export one of them
  instead of `[all]`.
- Output folder and file name templates with `{title}`, `{direction}` and `{tag}`.
- Layer and tag exclusion patterns, `only_visible`, horizontal or vertical strips.
- Anti-churn export: strips are copied into the project only when their content changed.
- Manifest-based deletion of strips that are no longer produced, and of the folders they leave
  empty. Strips kept with `output/delete_stale` off are still removed once it is turned on.
- Executable path from Editor Settings, the `ASEPRITE_PATH` variable or the OS default.
- Project-wide defaults in Project Settings.
- *Project > Tools > Aseprite Top-Down Layers: Reimport all*.
- Headless test runner, demo project and `tests/tools/build_grid.lua`, which turns a sprite drawn
  with one layer per direction into the grid format.

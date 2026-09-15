# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

### Added

- `EditorImportPlugin` for `.aseprite` / `.ase` that exports one PNG strip per top-level layer
  (or group) and tag. Aseprite runs twice per import whatever the number of strips: once to list
  layers and tags, once to export every strip through a bundled Lua script.
- Output folder and file name templates with `{title}`, `{layer}` and `{tag}`.
- Layer and tag exclusion patterns, `only_visible`, horizontal or vertical strips.
- `always_include` layers and named layer `combinations`, validated against the file's layers.
- Anti-churn export: strips are copied into the project only when their content changed.
- Manifest-based deletion of strips that are no longer produced, and of the folders they leave
  empty. Strips kept with `output/delete_stale` off are still removed once it is turned on.
- Executable path from Editor Settings, the `ASEPRITE_PATH` variable or the OS default.
- Project-wide defaults in Project Settings.
- *Project > Tools > Aseprite Top-Down Layers: Reimport all*.
- Headless test runner and demo project.

# Development

The repository root is a demo project (`examples/`). Checks used during development:

```
gdformat --check addons tests && gdlint addons tests
ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
ASEPRITE_PATH=<aseprite> godot --headless --path . --import
```

`tests/tools/build_grid.lua` turns a sprite drawn with one top-level layer per direction (layers
named like the grid cells) into the grid format:

```
<aseprite> -b --script-param src=<layers.aseprite> --script-param out=<grid.aseprite> --script tests/tools/build_grid.lua
```

`tests/tools/build_cases.lua` builds sprites for manual tests from a grid sprite: several layers and
groups (hidden, excluded, names the dropdown cannot offer), eight directions with an empty cell in
one tag, a canvas that is not a multiple of 3, and a file without tags. The comment at the top of
the script lists what each one covers:

```
<aseprite> -b --script-param src=<grid.aseprite> --script-param out=<folder> --script tests/tools/build_cases.lua
```

## Example asset

`examples/retro-top-down-character.aseprite` is built from the CC0 sheets credited in the
[README](../README.md#credits). It has 48x48 cells (the size of the sword effect) with the 16x16
character centered in each one, two layers (`character` and `weapon`) and one tag per animation of
the sheets. The cells of the diagonals are empty, and climbing is only drawn facing up and down.
`tests/tools/build_retro_example.lua` rebuilds it:

```
<aseprite> -b --script-param file=examples/retro-top-down-character.aseprite --script-param sheet=examples/rpg-type-retro-top-down-playable-character-spritesheett/16x16-rpg-topdown-playable-character-template.png --script-param attack=examples/rpg-type-retro-top-down-playable-character-spritesheett/48x48-attack.png --script tests/tools/build_retro_example.lua
```

The test runner compares every imported frame with those sheets, so the repository needs no
reference strips.

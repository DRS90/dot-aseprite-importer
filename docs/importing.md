# Importing

**English** | [Português (Brasil)](pt-BR/importing.md)

## Aseprite executable

The path is resolved in this order:

1. *Editor Settings > Aseprite Top-Down Grid Animations > General > Executable Path* (per machine).
2. The `ASEPRITE_PATH` environment variable (handy for CI and headless imports).
3. The OS default:
   - Windows: `C:\Program Files\Aseprite\Aseprite.exe`
   - macOS: `/Applications/Aseprite.app/Contents/MacOS/aseprite`
   - Linux/other: `aseprite` from `PATH`

Steam installs live elsewhere, e.g. `C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe`
or `~/.steam/steam/steamapps/common/Aseprite/aseprite`.

## How the automatic import works

The addon is a regular `EditorImportPlugin`. Godot reimports a source file when its content changes,
which it notices **when the Godot editor window regains focus** (or on a manual *Reimport*).

- Each import starts Aseprite twice, however many directions and tags the file has: once to read its
  size, layers, tags and frame durations, and once to export every animation. Starting Aseprite is
  what costs time (about 200 ms), not the animations.
- Aseprite exports one strip per animation to a cache folder outside the project. The strips become
  lossless textures embedded in the imported resource (in `.godot/imported/`), so nothing is written
  to the project, and exporting a scene that uses the file exports its textures with it.

*Project > Tools > Aseprite Top-Down Grid Animations: Reimport all* forces a reimport of every file
that uses this importer, e.g. after changing the executable path or a project default, or after
updating the addon.

## Import options

All options can be changed per file in the Import dock. The defaults of `layers/exclude_pattern`,
`tags/exclude_pattern`, `sprite_frames/animation_name` and `sprite_frames/loop_suffix` come from
*Project Settings > Aseprite Top-Down Grid Animations > Defaults*.

| Option | Default | Description |
|---|---|---|
| `grid/directions` | `3x3` | `3x3`: every frame is a 3x3 grid of facing directions. `none`: the frame is a single cell and the sprite has no direction, for the companions of a top-down character (a run dust puff, a hit spark, an item shine). |
| `grid/cell_size` | `(0, 0)` | Size of one cell in pixels. `0` on an axis means the sprite divided by the cells of the grid on that axis: a third with `grid/directions` at `3x3`, which the sprite must then be a multiple of, and the whole sprite at `none`. A smaller cell crops the top left corner and ignores the pixels left over at the right or bottom. |
| `layers/layer` | `[all]` | Dropdown with `[all]` and the file's top-level layers and groups. `[all]` composes every layer not matched by `layers/exclude_pattern`; any other choice imports only that layer or group. Put layers in a group to import them together. |
| `layers/exclude_pattern` | `^_` | Regular expression; matching layers are left out when `layers/layer` is `[all]`. |
| `layers/only_visible` | `false` | Use only layers visible in Aseprite. By default hidden layers are imported too. |
| `tags/exclude_pattern` | `^_` | Regular expression; matching tags are not imported. |
| `sprite_frames/animation_name` | `{tag}_{direction}` | Animation name. `{tag}` is the tag name without the loop suffix; `{direction}` is `left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down` or `right_down`, and nothing at all with `grid/directions` at `none`. |
| `sprite_frames/loop_suffix` | `_loop` | A tag ending with this text loops, and the text is left out of `{tag}`. Empty: no animation loops. |

A placeholder with nothing to put in it takes one neighbouring separator with it, so
`{tag}_{direction}` gives `run`, not `run_`, for a sprite without directions; the separators inside
a tag name are left alone. A file with neither tags nor directions to name its only animation after
gets `default`.

The characters `/`, `:`, `,` and `[` become `_` in animation names, because AnimationPlayer rejects
them. When two tags give the same name — `idle` and `idle_loop`, or two tags named alike in Aseprite
— the import fails and the error names both tags. It is not a partial import on purpose: dropping
the second animation would replace the ones that still worked with an incomplete resource, while a
failed import keeps the previous animations until the names are fixed.

The `layers/layer` dropdown is filled by asking Aseprite for the file's layers when the Import dock
shows the file. The listing is cached by file content and reused by the import, so it adds no
Aseprite process. A chosen layer that no longer exists (renamed or removed) fails the import with
an error and keeps the previous animations. The choice may be a layer matched by
`layers/exclude_pattern`, so a `_shadow` layer stays out of `[all]` and can still be imported alone.

## Coexistence with other Aseprite importers

Other addons (e.g. Aseprite Wizard) also register importers for `.aseprite`. Godot uses the importer
with the highest priority for new files; choose the importer per file with **Import As** in the
Import dock. Switching importers keeps the source file untouched.

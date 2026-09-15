# Aseprite Top-Down Layers

A Godot 4.7 editor addon that imports `.aseprite` / `.ase` sprites drawn as a **3x3 grid of facing
directions** as **one horizontal PNG strip per direction and tag**, re-exported automatically
whenever the source file changes.

Every frame is split into 3x3 cells. The position of a cell names its direction, the center cell
is ignored, and each tag is an animation (`idle_loop`, `walk`, ...):

```
character.aseprite (144x192)              assets/idle_loop/character_left_up_idle_loop.png
  +-----------+------+------------+       assets/idle_loop/character_up_idle_loop.png
  | left_up   | up   | right_up   |       ...
  | left      |      | right      |  ->   assets/walk/character_down_walk.png
  | left_down | down | right_down |       ...
  +-----------+------+------------+       (48x64 per frame)
  tags: idle_loop, walk, ...
```

A cell with no pixels in any frame of a tag produces no strip: a character drawn in six directions
(without plain `left` and `right`) just leaves those cells empty.

Only PNG files are produced. How you turn the strips into `SpriteFrames`, `AnimationPlayer` tracks
or shaders is up to you.

## Requirements

- Godot **4.7** (tested with 4.7.1).
- [Aseprite](https://www.aseprite.org/) 1.3 with scripting support (tested with 1.3.18). The addon runs
  it in batch mode with its bundled `aseprite_batch.lua`.

## Installation

1. Copy `addons/aseprite_topdown_layers` into your project's `addons/` folder.
2. Enable **Aseprite Top-Down Layers** in *Project > Project Settings > Plugins*.
3. Point the addon at the Aseprite executable (see below).
4. Select an `.aseprite` file in the FileSystem dock, open the **Import** dock, choose
   **Import As: Aseprite Top-Down Layers** and click **Reimport**.

For crisp pixel art, set *Project Settings > Rendering > Textures > Canvas Textures >
Default Texture Filter* to **Nearest**.

### Aseprite executable

The path is resolved in this order:

1. *Editor Settings > Aseprite Top-Down Layers > General > Executable Path* (per machine).
2. The `ASEPRITE_PATH` environment variable (handy for CI and headless imports).
3. The OS default:
   - Windows: `C:\Program Files\Aseprite\Aseprite.exe`
   - macOS: `/Applications/Aseprite.app/Contents/MacOS/aseprite`
   - Linux/other: `aseprite` from `PATH`

Steam installs live elsewhere, e.g. `C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe`
or `~/.steam/steam/steamapps/common/Aseprite/aseprite`.

## Drawing the sprite

- Make the canvas three cells wide and three cells tall, e.g. **144x192** for 48x64 characters, and
  draw each direction in its cell. Setting Aseprite's grid (*View > Grid Settings*) to the cell size
  helps to keep every pose inside its cell.
- Pixels that cross a cell border end up in the neighboring direction's strip.
- Every layer is composed into the strips by default. Prefix helper layers (guides, references)
  with `_` to leave them out, or pick a single layer or group in `layers/layer`.
- Use one tag per animation. Frames outside any tag are not exported unless the file has no tags.

## How the automatic export works

The addon is a regular `EditorImportPlugin`. Godot reimports a source file when its content changes,
which it notices **when the Godot editor window regains focus** (or on a manual *Reimport*). The
usual loop is: save in Aseprite, switch back to Godot, and the strips are updated.

- Each import starts Aseprite twice, however many directions and tags the file has: once to read its
  size, layers and tags, and once to export every strip. Starting Aseprite is what costs time (about
  200 ms), not the strips.
- Strips are exported to a cache folder first and copied into the project **only when their content
  changed**, so editing one animation does not reimport every texture.
- The imported resource is a small manifest listing the PNGs written. On the next import, strips
  that are no longer produced (renamed or removed tag, a cell left empty, new exclusion) are deleted
  together with their `.import` file, and folders left empty are removed. With `output/delete_stale`
  off they are kept but stay listed, so turning the option on later still removes them.
- After an import, a debounced file system scan makes Godot import the new PNGs as textures.

*Project > Tools > Aseprite Top-Down Layers: Reimport all* forces a reimport of every file that uses
this importer, e.g. after changing the executable path or a project default.

## Import options

All options can be changed per file in the Import dock. The defaults of `output/folder`,
`output/filename`, `layers/exclude_pattern` and `tags/exclude_pattern` come from
*Project Settings > Aseprite Top-Down Layers > Defaults*.

| Option | Default | Description |
|---|---|---|
| `output/folder` | `assets/{tag}` | Output folder, relative to the `.aseprite` file, or an absolute `res://` path. |
| `output/filename` | `{title}_{direction}_{tag}` | File name without extension. |
| `output/delete_stale` | `true` | Delete strips written by a previous import that are no longer produced. |
| `grid/cell_size` | `(0, 0)` | Size of one cell in pixels. `0` on an axis means a third of the sprite on that axis, which must then be a multiple of 3. A cell smaller than a third ignores the pixels left over at the right or bottom. |
| `layers/layer` | `[all]` | Dropdown with `[all]` and the file's top-level layers and groups. `[all]` composes every layer not matched by `layers/exclude_pattern`; any other choice exports only that layer or group. Put layers in a group to export them together. |
| `layers/exclude_pattern` | `^_` | Regular expression; matching layers are left out when `layers/layer` is `[all]`. |
| `layers/only_visible` | `false` | Use only layers visible in Aseprite. By default hidden layers are exported too. |
| `tags/exclude_pattern` | `^_` | Regular expression; matching tags are not exported. |
| `sheet/type` | `horizontal` | `horizontal` strip or `vertical` strip. |

Templates accept `{title}` (the source file name without extension), `{direction}` (`left_up`, `up`,
`right_up`, `left`, `right`, `left_down`, `down` or `right_down`) and `{tag}`. Tag names are
sanitized for file names (`/` and spaces become `_`).

The `layers/layer` dropdown is filled by asking Aseprite for the file's layers when the Import dock
shows the file. The listing is cached by file content and reused by the import, so it adds no
Aseprite process. A chosen layer that no longer exists (renamed or removed) fails the import with
an error and keeps the previous strips. The choice may be a layer matched by
`layers/exclude_pattern`, so a `_shadow` layer stays out of `[all]` and can still be exported alone.

## Naming conventions

- Tag names are copied literally into file names. A suffix such as `_loop` (`idle_loop`) is a handy
  convention to mark looping animations for your own tooling; the addon does not interpret it.
- Prefix helper layers and tags with `_` to keep them out of the export with the default patterns.

## Coexistence with other Aseprite importers

Other addons (e.g. Aseprite Wizard) also register importers for `.aseprite`. Godot uses the importer
with the highest priority for new files; choose the importer per file with **Import As** in the
Import dock. Switching importers keeps the source file untouched.

## Known limitations

- The grid is always 3x3, with fixed direction names and the center cell ignored.
- Only top-level layers and groups can be chosen. A group is exported as the composite of its
  children; hidden children inside a group may be included, because hidden layers are made visible
  for export.
- Tags with *reverse* or *ping-pong* direction are exported in timeline (forward) order.
- A file without tags exports one strip per direction with the whole timeline; `{tag}` is empty and
  the separators around it are collapsed (`assets/character_up.png`).
- Layer names containing `,` or `:` are not offered in the `layers/layer` dropdown.
- Aseprite is required to import. Without it the import fails and previously generated PNGs stay as
  they are, so committing the generated PNGs lets teammates without Aseprite use them.
- Only tested on Windows with Godot 4.7.1 and Aseprite 1.3.18.

## Development

The repository root is a demo project (`examples/character`). Checks used during development:

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

## License

[MIT](LICENSE)

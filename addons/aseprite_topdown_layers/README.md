# Aseprite Top-Down Layers

A Godot 4.7 editor addon that imports `.aseprite` / `.ase` files as **one horizontal PNG strip per
layer and tag**, re-exported automatically whenever the source file changes.

It is built for top-down characters drawn with one layer per facing direction
(`up`, `down`, `left_up`, ...) and one tag per animation (`idle_loop`, `walk`, ...):

```
character.aseprite                      assets/idle_loop/character_up_idle_loop.png
  layers: up, down, left_up, ...   ->   assets/idle_loop/character_down_idle_loop.png
  tags:   idle_loop, walk, ...          assets/walk/character_up_walk.png
                                        ...
```

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

## How the automatic export works

The addon is a regular `EditorImportPlugin`. Godot reimports a source file when its content changes,
which it notices **when the Godot editor window regains focus** (or on a manual *Reimport*). The
usual loop is: save in Aseprite, switch back to Godot, and the strips are updated.

- Each import starts Aseprite twice, however many layers and tags the file has: once to list them and
  once to export every strip. Starting Aseprite is what costs time (about 200 ms), not the strips.
- Strips are exported to a cache folder first and copied into the project **only when their content
  changed**, so saving an unrelated layer does not reimport every texture.
- The imported resource is a small manifest listing the PNGs written. On the next import, strips
  that are no longer produced (renamed layer, removed tag, new exclusion) are deleted together with
  their `.import` file. Empty folders are left in place.
- After an import, a debounced file system scan makes Godot import the new PNGs as textures.

*Project > Tools > Aseprite Top-Down Layers: Reimport all* forces a reimport of every file that uses
this importer, e.g. after changing the executable path or a project default.

## Import options

All options can be changed per file in the Import dock. The defaults of the first four come from
*Project Settings > Aseprite Top-Down Layers > Defaults*.

| Option | Default | Description |
|---|---|---|
| `output/folder` | `assets/{tag}` | Output folder, relative to the `.aseprite` file, or an absolute `res://` path. |
| `output/filename` | `{title}_{layer}_{tag}` | File name without extension. |
| `layers/exclude_pattern` | `^_` | Regular expression; matching layers are not exported alone. |
| `tags/exclude_pattern` | `^_` | Regular expression; matching tags are not exported. |
| `output/delete_stale` | `true` | Delete strips written by a previous import that are no longer produced. |
| `layers/only_visible` | `false` | Export only layers visible in Aseprite. By default hidden layers are exported too. |
| `layers/always_include` | *(empty)* | Comma-separated layers composed into **every** strip and never exported alone, e.g. `shadow`. |
| `layers/combinations` | *(empty)* | `name=layerA+layerB;other=layerC+layerD`. Each combination becomes one strip named after it; its layers are not exported alone. |
| `sheet/type` | `horizontal` | `horizontal` strip or `vertical` strip. |

Templates accept `{title}` (the source file name without extension), `{layer}` (layer, group or
combination name) and `{tag}`. Layer and tag names are sanitized for file names (`/` and spaces
become `_`).

Names typed in `always_include` and `combinations` are checked against the layers Aseprite reports;
an unknown name is reported as an error and the entry is skipped. This matters because the Aseprite
CLI silently exports the wrong image for unknown layer names. These two options may reference layers
matched by `layers/exclude_pattern`, so `_shadow` can be excluded on its own and still composed in.

## Naming conventions

- Tag names are copied literally into file names. A suffix such as `_loop` (`idle_loop`) is a handy
  convention to mark looping animations for your own tooling; the addon does not interpret it.
- Prefix helper layers and tags with `_` to keep them out of the export with the default patterns.

## Coexistence with other Aseprite importers

Other addons (e.g. Aseprite Wizard) also register importers for `.aseprite`. Godot uses the importer
with the highest priority for new files; choose the importer per file with **Import As** in the
Import dock. Switching importers keeps the source file untouched.

## Known limitations

- Only top-level layers and groups become strips. A group is exported as the composite of its
  children; hidden children inside a group may be included, because hidden layers are made visible
  for export.
- Tags with *reverse* or *ping-pong* direction are exported in timeline (forward) order.
- A file without tags exports one strip per layer with the whole timeline; `{tag}` is empty and the
  separators around it are collapsed (`assets/character_up.png`).
- Empty strips (a layer with no pixels in a tag) are exported anyway.
- Layer names containing `,`, `;`, `+` or `=` cannot be used in `always_include` / `combinations`.
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

## License

[MIT](LICENSE)

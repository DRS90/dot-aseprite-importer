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

The addon registers two `EditorImportPlugin`s, and every `.aseprite` uses one of them:

| Importer | Produces | Used for |
|---|---|---|
| **Aseprite Top-Down Grid Animations** | `SpriteFrames` | animations, on an AnimatedSprite2D |
| **Aseprite Texture** | a lossless `Texture2D` | Sprite2D, TextureRect, a shader uniform, the source image of a TileSet |

Which one a file wants comes down to two questions: is it animated, and does it face anywhere?

| The sprite | Import As | Gives |
|---|---|---|
| animated, one cell per facing direction | **Aseprite Top-Down Grid Animations** (the default) | one animation per direction and tag |
| animated, no direction, like a dust puff or a hit spark | the same importer, with [`grid/directions`](#import-options) set to `none` | one animation per tag |
| not animated, like a shadow, a prop or a tileset page | **Aseprite Texture** | a `Texture2D` of the canvas |

The first two keep Aseprite's frame durations, loops and ping-pong and can drive an
AnimationPlayer; the third is an image and carries none of that. A file nobody chose for lands on
the first one; pick the other per file with **Import As** in the Import dock.

Godot reimports a source file when its content changes, which it notices **when the Godot editor
window regains focus** (or on a manual *Reimport*).

- Each import starts Aseprite once, however many directions and tags the file has, to export every
  animation. The size, layers, tags and frame durations are read from the file itself in a few
  milliseconds. Starting Aseprite and opening the file is what costs time (about 200 ms plus the
  time the file takes to open), not the animations.
- Aseprite exports one strip per animation to a cache folder outside the project. The addon packs
  every frame into one sheet per file, each frame cut to its own pixels and repeated frames stored
  once, and embeds the sheet as a single lossless texture in the imported resource (in
  `.godot/imported/`). Every frame keeps the size of its cell, so the sprite does not move, and
  every sprite using the file draws the same texture. Nothing is written to the project, and
  exporting a scene that uses the file exports the texture with it.

*Project > Tools > Aseprite Top-Down Grid Animations: Reimport all* forces a reimport of every file
that uses either importer, e.g. after changing the executable path or a project default, or after
updating the addon.

## Import options

The options below belong to the **Aseprite Top-Down Grid Animations** importer; the texture importer
has its own, [further down](#importing-as-a-texture). All of them can be changed per file in the
Import dock. The defaults of `layers/exclude_pattern`, `tags/exclude_pattern`,
`sprite_frames/animation_name` and `sprite_frames/loop_suffix` come from
*Project Settings > Aseprite Top-Down Grid Animations > Defaults*; `layers/exclude_pattern` feeds
both importers.

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

The `layers/layer` dropdown is filled with the file's layers, read from the file itself when the
Import dock shows it, so it works before Aseprite is even configured. A chosen layer that no longer
exists (renamed or removed) fails the import with
an error and keeps the previous animations. The choice may be a layer matched by
`layers/exclude_pattern`, so a `_shadow` layer stays out of `[all]` and can still be imported alone.

## Importing as a texture

Set **Import As** to *Aseprite Texture* to get a plain `Texture2D` instead of animations. The whole
canvas is exported with every frame of the timeline side by side, so a single-frame sprite gives
exactly its image, and a multi-frame one gives the layout `Sprite2D.hframes` and animated TileSet
tiles expect. Drag the file onto any `Texture2D` property.

Tags, frame durations and the grid of directions are **ignored** here: they describe animations, and
this importer produces an image. Its options are the layer ones alone:

| Option | Default | Description |
|---|---|---|
| `layers/layer` | `[all]` | Same dropdown as above: `[all]`, or a single top-level layer or group. |
| `layers/exclude_pattern` | `^_` | Regular expression; matching layers are left out of `[all]`. |
| `layers/only_visible` | `false` | Use only layers visible in Aseprite. |

A file **keeps one importer at a time**: one `.aseprite` produces one resource, of one type.
Switching *Import As* replaces it rather than adding to it, so a scene that referenced the file as
SpriteFrames has to be pointed at something else afterwards. If you need the same art as both, keep
two `.aseprite` files.

## Coexistence with other Aseprite importers

Other addons also register importers for `.aseprite`, and Godot hands a new file to the one that
declares the highest priority. This addon declares **1.0** for its SpriteFrames importer, Godot's
default, and **0.9** for *Aseprite Texture*, so the texture one is never picked on its own. It does
not compete with other addons either: with another Aseprite importer installed, the choice is yours
to make per file.

Aseprite Wizard declares **2.0** for whichever of its importers is set as its default, and out of
the box that default is **Aseprite (No Import)**. In a project with both addons, a newly added
`.aseprite` is therefore imported by *Aseprite (No Import)* and produces nothing — with no error and
no warning, which looks like a broken addon and is not.

To import such a file with this addon:

1. Select it in the FileSystem dock; several files at once works too.
2. In the **Import** dock, set **Import As** to *Aseprite Top-Down Grid Animations*.
3. Click **Reimport**.

The choice is stored per file in its `.import` file, so it survives reimports, *Reimport all* and
the next person to open the project. Switching importers never touches the source file.

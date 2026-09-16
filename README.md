# Aseprite Top-Down Grid Animations

A Godot 4.7 editor addon that imports `.aseprite` / `.ase` sprites drawn as a **3x3 grid of facing
directions** as a **SpriteFrames** resource: one animation per direction and tag, timed like in
Aseprite. Assign the file to an AnimatedSprite2D, and optionally link an AnimationPlayer that gets
the same animations.

```
character.aseprite (144x192)              SpriteFrames (48x64 frames)
  +-----------+------+------------+         idle_left_up, idle_up, idle_right_up,
  | left_up   | up   | right_up   |         idle_left_down, idle_down, idle_right_down,
  | left      |      | right      |  ->     walk_left_up, walk_up, ...
  | left_down | down | right_down |
  +-----------+------+------------+
  tags: idle_loop, walk, ...
```

A cell with no pixels in any frame of a tag produces no animation: a character drawn in six
directions (without plain `left` and `right`) just leaves those cells empty.

## Requirements

- Godot **4.7** (tested with 4.7.1).
- [Aseprite](https://www.aseprite.org/) 1.3 with scripting support (tested with 1.3.18). The addon runs
  it in batch mode with its bundled `aseprite_batch.lua`.

## Installation

1. Copy `addons/aseprite_topdown_grid_animations` into your project's `addons/` folder.
2. Enable **Aseprite Top-Down Grid Animations** in *Project > Project Settings > Plugins*.
3. Point the addon at the Aseprite executable (see below).
4. Put an `.aseprite` file in the project. It is imported as SpriteFrames; if another importer took
   it, select the file, open the **Import** dock, choose
   **Import As: Aseprite Top-Down Grid Animations** and click **Reimport**.

For crisp pixel art, set *Project Settings > Rendering > Textures > Canvas Textures >
Default Texture Filter* to **Nearest**.

### Aseprite executable

The path is resolved in this order:

1. *Editor Settings > Aseprite Top-Down Grid Animations > General > Executable Path* (per machine).
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
- Pixels that cross a cell border end up in the neighboring direction's animation.
- Every layer is composed into the animations by default. Prefix helper layers (guides, references)
  with `_` to leave them out, or pick a single layer or group in `layers/layer`.
- Use one tag per animation. Frame durations and the tag direction (forward, reverse, ping-pong,
  ping-pong reverse) are kept. End a tag with `_loop` (`idle_loop`) to make its animations loop.
- Frames outside any tag are not imported unless the file has no tags.

## AnimatedSprite2D

Drag the `.aseprite` file from the FileSystem dock onto the **Sprite Frames** property of an
AnimatedSprite2D, then play its animations as usual: `$AnimatedSprite2D.play("walk_down")`.

- Animations are named `{tag}_{direction}` without the loop suffix: the tag `idle_loop` gives
  `idle_down`, `idle_left_up`, and so on.
- The animation speed is 1 / the shortest frame of the tag, and every frame keeps its duration
  relative to it, so a `speed_scale` of 1 plays at the Aseprite speed.
- A looping animation never emits `animation_finished`. Code can tell loops apart with
  `sprite_frames.get_animation_loop("idle_down")`.
- Saving the file in Aseprite updates the animations when Godot regains focus.
- The SpriteFrames is an imported resource: changes made in the SpriteFrames editor are lost on the
  next import. *Make Unique* gives an editable copy that no longer updates.

## AnimationPlayer

In the inspector of the AnimatedSprite2D, under **AnimatedSprite2D**, the **AnimationPlayer** section
links a player: click **Assign...** and pick an AnimationPlayer of the scene. Every animation of the
sprite's SpriteFrames becomes an animation of the same name in the player's global library, with
two tracks on the sprite, `animation` and `frame`, keyed at the Aseprite frame times and looping like
the SpriteFrames animation. Play them with `$AnimationPlayer.play("walk_down")`.

- The animations are synced again when the `.aseprite` file is reimported (in the open scene) and
  when a scene is opened, if anything changed. **Sync animations** forces a sync. A sync marks the
  scene as modified: save it.
- A sync replaces only the sprite's `animation` and `frame` tracks. Tracks you add to the same
  animations (sounds, hitboxes, method calls) are kept. When a tag or direction disappears, its
  animation loses the sprite's tracks and is deleted only if nothing else is left in it.
- Several sprites can share one AnimationPlayer (e.g. a body and a weapon from different files):
  each sprite has its own tracks.
- While an AnimationPlayer drives the sprite, don't also play the AnimatedSprite2D (`play()` or
  *Autoplay on Load*).
- The link is stored in the sprite's metadata and saved with the scene. The scene only holds
  built-in nodes and resources, so the game does not need the addon to run.
- Nodes inside an instanced scene are synced when that scene is opened. **Clear** unlinks the player
  and keeps the animations already written.
- The player's global library starts **built-in**, so the animations are written into the scene file
  and every sync rewrites them there. Save that library to a `.tres` and the sync writes into it
  instead, leaving a single `ext_resource` line in the scene: in Godot a resource with a file path is
  external, and erasing the path makes it built-in again. Nothing else changes, because a sync only
  creates a library when the player has none. The demo in `examples/` does this and is 18 lines
  instead of 1107. Only worth it for many animations, and remember that two scenes pointing at the
  same `.tres` write to the same file.

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
| `grid/cell_size` | `(0, 0)` | Size of one cell in pixels. `0` on an axis means a third of the sprite on that axis, which must then be a multiple of 3. A cell smaller than a third ignores the pixels left over at the right or bottom. |
| `layers/layer` | `[all]` | Dropdown with `[all]` and the file's top-level layers and groups. `[all]` composes every layer not matched by `layers/exclude_pattern`; any other choice imports only that layer or group. Put layers in a group to import them together. |
| `layers/exclude_pattern` | `^_` | Regular expression; matching layers are left out when `layers/layer` is `[all]`. |
| `layers/only_visible` | `false` | Use only layers visible in Aseprite. By default hidden layers are imported too. |
| `tags/exclude_pattern` | `^_` | Regular expression; matching tags are not imported. |
| `sprite_frames/animation_name` | `{tag}_{direction}` | Animation name. `{tag}` is the tag name without the loop suffix; `{direction}` is `left_up`, `up`, `right_up`, `left`, `right`, `left_down`, `down` or `right_down`. |
| `sprite_frames/loop_suffix` | `_loop` | A tag ending with this text loops, and the text is left out of `{tag}`. Empty: no animation loops. |

The characters `/`, `:`, `,` and `[` become `_` in animation names, because AnimationPlayer rejects
them. When two tags give the same name (`idle` and `idle_loop`), the second one is reported as an
error and skipped.

The `layers/layer` dropdown is filled by asking Aseprite for the file's layers when the Import dock
shows the file. The listing is cached by file content and reused by the import, so it adds no
Aseprite process. A chosen layer that no longer exists (renamed or removed) fails the import with
an error and keeps the previous animations. The choice may be a layer matched by
`layers/exclude_pattern`, so a `_shadow` layer stays out of `[all]` and can still be imported alone.

## Coexistence with other Aseprite importers

Other addons (e.g. Aseprite Wizard) also register importers for `.aseprite`. Godot uses the importer
with the highest priority for new files; choose the importer per file with **Import As** in the
Import dock. Switching importers keeps the source file untouched.

## Known limitations

- The grid is always 3x3, with fixed direction names and the center cell ignored.
- Only top-level layers and groups can be chosen. A group is imported as the composite of its
  children; hidden children inside a group may be included, because hidden layers are made visible
  for export.
- The tag repeat count set in Aseprite is ignored: only the loop suffix decides whether an animation
  loops.
- A file without tags gets one animation per direction with the whole timeline, named after the
  direction (`down`). It does not loop.
- Layer names containing `,` or `:` are not offered in the `layers/layer` dropdown.
- Aseprite is required to import. The imported resources live in `.godot/`, which is usually not
  committed, so everyone who opens the project needs Aseprite.
- Syncing an AnimationPlayer cannot be undone with *Undo*.
- Only tested on Windows with Godot 4.7.1 and Aseprite 1.3.18.

## Development

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

## Credits

The example character, `examples/retro-top-down-character.aseprite`, is built from the
["RPG Type Retro Top-Down Playable Character Template" by 5yvalia](https://5yvalia.itch.io/rpg-type-retro-top-down-playable-character-template),
released as **CC0** (public domain). Its sheets are in
`examples/rpg-type-retro-top-down-playable-character-spritesheett/`, with the `LICENSE.png` of the
download.

The example has 48x48 cells (the size of the sword effect) with the 16x16 character centered in
each one, two layers (`character` and `weapon`) and one tag per animation of the sheets. The cells
of the diagonals are empty, and climbing is only drawn facing up and down.
`tests/tools/build_retro_example.lua` rebuilds it:

```
<aseprite> -b --script-param file=examples/retro-top-down-character.aseprite --script-param sheet=examples/rpg-type-retro-top-down-playable-character-spritesheett/16x16-rpg-topdown-playable-character-template.png --script-param attack=examples/rpg-type-retro-top-down-playable-character-spritesheett/48x48-attack.png --script tests/tools/build_retro_example.lua
```

The test runner compares every imported frame with those sheets, so the repository needs no
reference strips.

## License

[MIT](LICENSE)

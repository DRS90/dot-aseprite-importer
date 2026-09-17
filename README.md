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

## Step by step

From an empty Aseprite file to a character that walks in every direction it was drawn in. The
steps assume the addon is installed and enabled and can find Aseprite. The sections after this one
cover each part in detail.

### 1. Draw the sprite in Aseprite

1. Create a sprite three cells wide and three cells tall: for a 32x32 character, *File > New* with
   **96x96**.
2. Set *View > Grid Settings* to **32x32** and turn on *View > Show > Grid*, so each cell is
   outlined.
3. Draw the character in the cell of each direction it faces:

   ```
   left_up    up     right_up
   left     (empty)  right
   left_down  down   right_down
   ```

   Leave the center empty, and leave empty the cells of directions you don't draw (the diagonals of
   a four-direction character, for example).
4. Add frames (*Frame > New Frame*) and draw every direction in each one. Set how long each frame
   lasts in *Frame > Frame Properties*.
5. Select the frames of one animation in the timeline and tag them (*Frame > Tags > New Tag*). Name
   the tag after the action and end it with `_loop` if it loops: `walk_loop`. A one-shot action,
   like `attack`, gets no suffix. Add a tag for each animation.
6. Save the file inside the Godot project, e.g. `characters/hero.aseprite`.

### 2. Check the import in Godot

1. Switch to the Godot editor. It notices the new file and imports it.
2. Select the file in the FileSystem dock and open the **Import** dock. `grid/cell_size` at `(0, 0)`
   takes a third of the canvas (32x32 here). If your canvas is not a multiple of 3, type the cell
   size and click **Reimport**. If the Import dock shows another importer, pick
   **Import As: Aseprite Top-Down Grid Animations**.
3. Problems (Aseprite not found, a tag giving a name that is already taken, and so on) are reported
   in the **Output** panel, starting with `[Aseprite Top-Down Grid Animations]`.

### 3. Play the animations with an AnimatedSprite2D

1. Create a scene with a **CharacterBody2D** root (`Player`) and add an **AnimatedSprite2D** and a
   **CollisionShape2D** to it.
2. Drag `hero.aseprite` from the FileSystem dock onto the **Sprite Frames** property of the
   AnimatedSprite2D. The SpriteFrames panel at the bottom now lists `walk_down`, `walk_left_up`,
   and so on: one animation per tag and drawn direction.
3. Attach a script to `Player`:

   ```gdscript
   extends CharacterBody2D

   const SPEED := 60.0
   ## The grid directions clockwise from "right", 45 degrees apart (+y points down in Godot).
   const DIRECTIONS: Array[String] = [
   	"right", "right_down", "down", "left_down", "left", "left_up", "up", "right_up"
   ]

   @onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


   func _physics_process(_delta: float) -> void:
   	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
   	velocity = input * SPEED
   	move_and_slide()
   	if input == Vector2.ZERO:
   		_sprite.stop()
   		return
   	_sprite.play(_animation_for("walk", input))


   ## "walk" facing down-left gives "walk_left_down", or "walk_down" if that diagonal is not drawn.
   func _animation_for(action: String, facing: Vector2) -> String:
   	var sector := wrapi(roundi(facing.angle() / (PI / 4.0)), 0, DIRECTIONS.size())
   	var animation := "%s_%s" % [action, DIRECTIONS[sector]]
   	if _sprite.sprite_frames.has_animation(animation):
   		return animation
   	# Diagonal not drawn: use the closest side.
   	sector = wrapi(roundi(facing.angle() / (PI / 2.0)) * 2, 0, DIRECTIONS.size())
   	return "%s_%s" % [action, DIRECTIONS[sector]]
   ```

4. Run the scene and move with the arrow keys. The character walks in the direction of the keys
   and stops on the first frame of the animation it was playing.

### 4. Change the art

Edit the sprite in Aseprite, save it and switch back to Godot: the file is imported again and the
animations in the editor update. A game that is already running keeps the old animations until it
is restarted. A new tag gives new animations. A renamed tag renames its animations, so update the
names in your code.

### 5. Optional: drive the sprite with an AnimationPlayer

Link an AnimationPlayer when other things must follow the frames: a footstep sound on the frame the
foot lands, a hitbox during an attack, a method call at the end of an animation.

1. Add an **AnimationPlayer** to the `Player` scene.
2. Select the AnimatedSprite2D. In the Inspector, under **AnimatedSprite2D**, click **Assign...** in
   the **AnimationPlayer** section and pick the AnimationPlayer. The section reports how many
   animations it synced, and the AnimationPlayer now has `walk_down`, `walk_left_up`, and so on.
3. Save the scene. With the scene saved as `player.tscn`, the animations go to
   `player_animations.tres` next to it. A scene that had never been saved when you linked the player
   keeps them inside the scene until you click **Sync animations** after saving it.
4. In the script, call `play()` on the AnimationPlayer instead of the AnimatedSprite2D, with the
   same animation names, and remove the sprite's `play()` and *Autoplay on Load*.
5. Open an animation in the **Animation** panel and add your own tracks (audio, method calls,
   properties of other nodes). They are kept when the animations are synced again after you change
   the sprite in Aseprite.

### Try the demo

The repository is itself a Godot project. Open its `project.godot` (with Aseprite set up as above)
and run it: `examples/main.tscn` shows `examples/retro-top-down-character.aseprite` walking down,
played by its AnimationPlayer. The sprite has ten tags (`walk_loop`, `slash`, `swim_loop`, ...)
drawn facing up, down, left and right (climbing only up and down), with the diagonal cells empty.
The demo is only in the repository, not in the Asset Library download.

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
- The animations are written to a resource file of their own. Under *Project Settings > Aseprite
  Top-Down Grid Animations > Animation Player*, **External Library** (on) decides, and **Library
  Path** says where: `{scene_dir}` and `{scene}` come from the scene holding the player, so the
  default is `main.tscn` → `main_animations.tres` beside it. The scene then keeps one
  `ext_resource` line instead of the animations: the demo in `examples/` is 17 lines instead of
  1107. **Turn External Library off** to keep the animations inside the scene, which is what Godot
  does on its own. The file is written when the scene is saved.
- A library that is already a file is never moved, even when the setting names another path, and
  turning External Library off does not bring it back into the scene (clear its `resource_path` for
  that).
  A built-in library moves to the file on the next sync. If that file already exists it wins, but
  the animations only the built-in one had are copied into it, so tracks you added are not lost.
  A scene that was never saved has no path to derive from, so its library stays built-in until you
  save the scene and sync again. On any error the library stays built-in and the reason is reported.
  Two scenes naming the same file write to the same file.

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

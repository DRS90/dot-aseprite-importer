# Top-down characters

**English** | [Português (Brasil)](pt-BR/top-down.md)

A character seen from above faces up, down and sideways, and needs an animation for each direction.
Instead of one file per direction, draw every frame as a 3x3 grid of cells, one per direction, and
set `grid/directions` to `3x3`: each tag gives one animation per direction drawn. The steps assume
the addon is [installed and enabled](../README.md#installation) and can find
[the Aseprite executable](importing.md#aseprite-executable).

## 1. Turn the grid on

`grid/directions` is `none` by default: the whole frame is one cell. Turn the grid on in either of
two places:

- **For one file:** select it in the FileSystem dock, set `grid/directions` to `3x3` in the
  **Import** dock and click **Reimport**. Several files can be selected at once.
- **For the whole project:** open *Project > Project Settings > Import Defaults*, pick
  *Dot Aseprite SpriteFrames* in the importer list, set `grid/directions` to `3x3` and click
  **Save**. The **Preset** menu of the Import dock does the same from a file already set to `3x3`:
  *Set as Default for 'Dot Aseprite SpriteFrames'*. Every `.aseprite` added from then on is
  imported as a grid. Files already in the project keep their own setting, stored in their
  `.import` file: change those in the Import dock.

A top-down game also has sprites that face nowhere: a run dust puff, a hit spark, an item shine. In
a project that defaults to `3x3`, set those files back to `none` in the Import dock. A sprite that
is not a multiple of 3 fails with a message that names both ways out: a cell size, or `none`.

## 2. Draw the grid in Aseprite

1. Create a sprite three cells wide and three cells tall: for a 32x32 character, *File > New* with
   **96x96**.
2. Set *View > Grid > Grid Settings* to **32x32** and turn on *View > Show > Grid*, so each cell is
   outlined.
3. Draw the character in the cell of each direction it faces:

   ```
   left_up    up     right_up
   left     (empty)  right
   left_down  down   right_down
   ```

   Leave the center empty, and leave empty the cells of directions you don't draw (the diagonals of
   a four-direction character, for example).
4. Add frames and tags as for any sprite ([Drawing the sprite](drawing-the-sprite.md)): every frame
   holds every direction, and a tag like `walk_loop` covers all of them.
5. Save the file inside the Godot project, e.g. `characters/hero.aseprite`.

Pixels that cross a cell border end up in the neighboring direction's animation. `grid/cell_size`
at `(0, 0)` takes a third of the canvas (32x32 here); if the canvas is not a multiple of 3, type
the cell size in the Import dock and click **Reimport**: the cells start at the top left corner and
the pixels left over at the right or bottom are ignored.

## 3. Animation names

The animations are named `{tag}_{direction}` (`sprite_frames/animation_name`), without the loop
suffix: the tag `walk_loop` gives `walk_down`, `walk_left_up`, and so on. A cell with no pixels in
any frame of a tag gives no animation, so a character drawn in four directions has `walk_down`,
`walk_left`, `walk_right` and `walk_up` only.

## 4. Play the direction the character faces

1. Create a scene with a **CharacterBody2D** root (`Player`), add an **AnimatedSprite2D** and a
   **CollisionShape2D** with a *New RectangleShape2D* shape to it, and save it as `player.tscn`.
2. Drag `hero.aseprite` from the FileSystem dock onto the **Sprite Frames** property of the
   AnimatedSprite2D.
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


   ## "walk" facing down-left gives "walk_left_down", or "walk_left" if that diagonal is not drawn.
   func _animation_for(action: String, facing: Vector2) -> String:
   	var sector := wrapi(roundi(facing.angle() / (PI / 4.0)), 0, DIRECTIONS.size())
   	var animation := "%s_%s" % [action, DIRECTIONS[sector]]
   	if _sprite.sprite_frames.has_animation(animation):
   		return animation
   	# Diagonal not drawn: use the side of the longer axis (horizontal on an exact diagonal).
   	if absf(facing.x) >= absf(facing.y):
   		return "%s_%s" % [action, "right" if facing.x > 0.0 else "left"]
   	return "%s_%s" % [action, "down" if facing.y > 0.0 else "up"]
   ```

4. Run the scene and move with the arrow keys. The character walks in the direction of the keys
   and stops on the first frame of the animation it was playing.

With an [AnimationPlayer](animation-player.md) linked, call `_player.play()` with the same names
and keep `_sprite.sprite_frames.has_animation()` as it is.

## The demo

`examples/retro-top-down-character.aseprite`, in the repository's demo project, is a grid: ten tags
(`walk_loop`, `slash`, `swim_loop`, ...) drawn facing up, down, left and right (climbing only up and
down), with the diagonal cells empty. Its `.import` file sets `grid/directions` to `3x3`, and
`examples/main.tscn` shows it walking down. See [Try the demo](getting-started.md#try-the-demo).

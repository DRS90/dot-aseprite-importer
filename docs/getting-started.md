# Getting started

**English** | [Português (Brasil)](pt-BR/getting-started.md)

From an empty Aseprite file to a character that walks in every direction it was drawn in. The
steps assume the addon is [installed and enabled](../README.md#installation) and can find
[the Aseprite executable](importing.md#aseprite-executable). The other pages of the
[documentation](../README.md#documentation) cover each part in detail.

## 1. Draw the sprite in Aseprite

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
4. Add frames (*Frame > New Frame*) and draw every direction in each one. Set how long each frame
   lasts in *Frame > Frame Properties*.
5. Select the frames of one animation in the timeline and tag them (*Frame > Tags > New Tag*). Name
   the tag after the action and end it with `_loop` if it loops: `walk_loop`. A one-shot action,
   like `attack`, gets no suffix. Add a tag for each animation.
6. Save the file inside the Godot project, e.g. `characters/hero.aseprite`.

## 2. Check the import in Godot

1. Switch to the Godot editor. It notices the new file and imports it.
2. Select the file in the FileSystem dock and open the **Import** dock. `grid/cell_size` at `(0, 0)`
   takes a third of the canvas (32x32 here). If your canvas is not a multiple of 3, type the cell
   size and click **Reimport**. If the Import dock shows another importer, pick
   **Import As: Aseprite Top-Down Grid Animations**.
3. Problems (Aseprite not found, a tag giving a name that is already taken, and so on) are reported
   in the **Output** panel, starting with `[Aseprite Top-Down Grid Animations]`.

## 3. Play the animations with an AnimatedSprite2D

1. Create a scene with a **CharacterBody2D** root (`Player`), add an **AnimatedSprite2D** and a
   **CollisionShape2D** with a *New RectangleShape2D* shape to it, and save it as `player.tscn`.
2. Drag `hero.aseprite` from the FileSystem dock onto the **Sprite Frames** property of the
   AnimatedSprite2D. The SpriteFrames panel at the bottom now lists `walk_down`, `walk_left`, and so
   on: one animation per tag and drawn direction.
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

## 4. Change the art

Edit the sprite in Aseprite, save it and switch back to Godot: the file is imported again and the
animations in the editor update. A game that is already running keeps the old animations until it
is restarted. A new tag gives new animations. A renamed tag renames its animations, so update the
names in your code.

## 5. Optional: drive the sprite with an AnimationPlayer

Link an AnimationPlayer when other things must follow the frames: a footstep sound on the frame the
foot lands, a hitbox during an attack, a method call at the end of an animation.

1. Add an **AnimationPlayer** to the `Player` scene.
2. Select the AnimatedSprite2D. In the Inspector, under **AnimatedSprite2D**, click **Assign...** in
   the **AnimationPlayer** section and pick the AnimationPlayer. The section reports how many
   animations it synced, and the AnimationPlayer now has `walk_down`, `walk_left`, and so on.
3. Save the scene. The animations are stored in `player_animations.tres`, next to `player.tscn`.
4. In the script, add `@onready var _player: AnimationPlayer = $AnimationPlayer` and replace
   `_sprite.play(...)` with `_player.play(...)` and `_sprite.stop()` with `_player.stop()`: the
   names are the same, and stopping the player also leaves the sprite on the first frame. Keep
   `_sprite.sprite_frames.has_animation()` as it is. If you turned on *Autoplay on Load* in the
   SpriteFrames panel, turn it off.
5. Select the AnimationPlayer, open an animation in the **Animation** panel and add your own tracks
   (audio, method calls, properties of other nodes). They are kept when the animations are synced
   again after you change the sprite in Aseprite.

## Try the demo

The repository is itself a Godot project. Open its `project.godot` (with
[the Aseprite executable](importing.md#aseprite-executable) set up) and run it:
`examples/main.tscn` shows `examples/retro-top-down-character.aseprite` walking down, played by its
AnimationPlayer. The sprite has ten tags (`walk_loop`, `slash`, `swim_loop`, ...) drawn facing up,
down, left and right (climbing only up and down), with the diagonal cells empty. The demo is only
in the repository, not in the Asset Library download.

# Getting started

**English** | [Português (Brasil)](pt-BR/getting-started.md)

From an empty Aseprite file to a character that runs and jumps. The steps assume the addon is
[installed and enabled](../README.md#installation) and can find
[the Aseprite executable](importing.md#aseprite-executable). The other pages of the
[documentation](../README.md#documentation) cover each part in detail, and
[Top-down characters](top-down.md) covers a character that faces up, down and sideways.

## 1. Draw the sprite in Aseprite

1. Create a sprite the size of the character: *File > New* with **32x32**, for example.
2. Draw the character facing right. The game mirrors it to face left.
3. Add frames (*Frame > New Frame*) and set how long each one lasts in *Frame > Frame Properties*.
4. Select the frames of one animation in the timeline and tag them (*Frame > Tags > New Tag*). Name
   the tag after the action and end it with `_loop` if it loops: `idle_loop`, `run_loop`. A
   one-shot action, like `jump`, gets no suffix. Add a tag for each animation.
5. Save the file inside the Godot project, e.g. `characters/hero.aseprite`.

## 2. Check the import in Godot

1. Switch to the Godot editor. It notices the new file and imports it.
2. Select the file in the FileSystem dock and open the **Import** dock: `grid/directions` at `none`
   imports the whole frame, one animation per tag. If the Import dock shows another importer, pick
   **Import As: Dot Aseprite SpriteFrames**. A sprite that is not animated at all, like a shadow, a
   prop or a tileset page, is better off with *Import As: Dot Aseprite Texture*, described in
   [Importing as a texture](importing.md#importing-as-a-texture).
3. Problems (Aseprite not found, a tag giving a name that is already taken, and so on) are reported
   in the **Output** panel, starting with `[Dot Aseprite Importer]`.

## 3. Play the animations with an AnimatedSprite2D

1. Create a scene with a **Node2D** root (`Level`). Add a **StaticBody2D** with a
   **CollisionShape2D** whose shape is a wide *New RectangleShape2D*, as the floor, and save the
   scene as `level.tscn`.
2. Add a **CharacterBody2D** (`Player`) above the floor, with an **AnimatedSprite2D** and a
   **CollisionShape2D** (*New RectangleShape2D*) as its children.
3. Drag `hero.aseprite` from the FileSystem dock onto the **Sprite Frames** property of the
   AnimatedSprite2D. The SpriteFrames panel at the bottom now lists `idle`, `jump` and `run`: one
   animation per tag, without the `_loop` suffix.
4. Attach a script to `Player`:

   ```gdscript
   extends CharacterBody2D

   const SPEED := 120.0
   const JUMP_VELOCITY := -300.0

   @onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


   func _physics_process(delta: float) -> void:
   	if not is_on_floor():
   		velocity += get_gravity() * delta
   	elif Input.is_action_just_pressed("ui_accept"):
   		velocity.y = JUMP_VELOCITY
   	var input := Input.get_axis("ui_left", "ui_right")
   	velocity.x = input * SPEED
   	move_and_slide()
   	if input != 0.0:
   		_sprite.flip_h = input < 0.0
   	if not is_on_floor():
   		# play() restarts a one-shot animation that has finished, so start the jump only once.
   		if _sprite.animation != &"jump":
   			_sprite.play("jump")
   	elif input != 0.0:
   		_sprite.play("run")
   	else:
   		_sprite.play("idle")
   ```

5. Run the scene. The arrow keys run left and right, with the sprite mirrored by `flip_h`, and
   *Enter* or *Space* jumps. `jump` does not loop and is started once per jump, so it stops on its
   last frame until the character lands: calling `play()` every frame with the name of a finished
   one-shot animation would start it over.

## 4. Change the art

Edit the sprite in Aseprite, save it and switch back to Godot: the file is imported again and the
animations in the editor update. A game that is already running keeps the old animations until it
is restarted. A new tag gives new animations. A renamed tag renames its animations, so update the
names in your code.

## 5. Optional: drive the sprite with an AnimationPlayer

Link an AnimationPlayer when other things must follow the frames: a footstep sound on the frame the
foot lands, a hitbox during an attack, a method call at the end of an animation.

1. Add an **AnimationPlayer** as a child of `Player`.
2. Select the AnimatedSprite2D. In the Inspector, under **AnimatedSprite2D**, click **Assign...** in
   the **AnimationPlayer** section and pick the AnimationPlayer. The section reports how many
   animations it synced, and the AnimationPlayer now has `idle`, `jump` and `run`.
3. Save the scene. The animations are stored in `level_animations.tres`, next to `level.tscn`.
4. In the script, add `@onready var _player: AnimationPlayer = $AnimationPlayer` and replace
   `_sprite.play(...)` with `_player.play(...)`: the names are the same. Keep the check on
   `_sprite.animation`, which the player's tracks set too, and keep setting `_sprite.flip_h`, which
   is not part of the animations. If you turned on *Autoplay on Load* in
   the SpriteFrames panel, turn it off.
5. Select the AnimationPlayer, open an animation in the **Animation** panel and add your own tracks
   (audio, method calls, properties of other nodes). They are kept when the animations are synced
   again after you change the sprite in Aseprite.

## Try the demo

The repository is itself a Godot project. Open its `project.godot` (with
[the Aseprite executable](importing.md#aseprite-executable) set up) and run it:
`examples/main.tscn` shows `examples/retro-top-down-character.aseprite` walking down, played by its
AnimationPlayer. It is a [top-down character](top-down.md), imported with `grid/directions` at
`3x3`: ten tags (`walk_loop`, `slash`, `swim_loop`, ...) drawn facing up, down, left and right
(climbing only up and down), with the diagonal cells empty.

The same scene also shows the texture importer twice: `examples/shadow.aseprite` is imported with
*Import As: Dot Aseprite Texture* and drawn by an ordinary Sprite2D, and
`examples/tileset.aseprite`, imported the same way, is the texture of a TileSetAtlasSource whose
tiles are painted on a TileMapLayer. The demo is only in the repository, not in the Asset Library
download.

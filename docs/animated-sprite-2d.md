# AnimatedSprite2D

**English** | [Português (Brasil)](pt-BR/animated-sprite-2d.md)

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

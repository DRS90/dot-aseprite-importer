# AnimationPlayer

**English** | [Português (Brasil)](pt-BR/animation-player.md)

In the inspector of the AnimatedSprite2D, under **AnimatedSprite2D**, the **AnimationPlayer**
section links a player: click **Assign...** and pick an AnimationPlayer of the scene. Every
animation of the sprite's SpriteFrames becomes an animation of the same name in the player's global
library, with two tracks on the sprite, `animation` and `frame`, keyed at the Aseprite frame times
and looping like the SpriteFrames animation. Play them with `$AnimationPlayer.play("run")`.

- The animations are synced again when the `.aseprite` file is reimported (in the open scene) and
  when a scene is opened, if anything changed. **Sync animations** forces a sync. A sync marks the
  scene as modified: save it.
- A sync replaces only the sprite's `animation` and `frame` tracks. Tracks you add to the same
  animations (sounds, hitboxes, method calls) are kept. When a tag or direction disappears, its
  animation loses the sprite's tracks and is deleted only if nothing else is left in it. Those two
  tracks belong to the sync: deleted by hand, they (and their animation) come back the next time
  the scene is opened.
- Several sprites can share one AnimationPlayer (e.g. a body and a weapon from different files):
  each sprite has its own tracks.
- While an AnimationPlayer drives the sprite, don't also play the AnimatedSprite2D (`play()` or
  *Autoplay on Load*).
- The link is stored in the sprite's metadata and saved with the scene. The scene only holds
  built-in nodes and resources, so the game does not need the addon to run.
- Nodes inside an instanced scene are synced when that scene is opened. **Clear** unlinks the player
  and keeps the animations already written.
- The animations are written to a resource file of their own. Under *Project Settings > Dot Aseprite
  Importer > Animation Player*, **External Library** (on) decides, and **Library Path** says where:
  `{scene_dir}` and `{scene}` come from the scene holding the player, so the default is `main.tscn`
  → `main_animations.tres` beside it. The scene then keeps one `ext_resource` line instead of the
  animations: the demo in `examples/` is 17 lines instead of
  1107. **Turn External Library off** to keep the animations inside the scene, which is what Godot
  does on its own. Every sync writes the file itself; saving the scene only stores the reference to
  it.
- A library that is already a file is never moved, even when the setting names another path, and
  turning External Library off does not bring it back into the scene (clear its `resource_path` for
  that).
  A built-in library moves to the file on the next sync. If that file already exists it wins, but
  the animations only the built-in one had are copied into it, so tracks you added are not lost.
  A scene that was never saved has no path to derive from, so its library stays built-in until you
  save the scene and sync again. On any error the library stays built-in and the reason is reported.
  Two scenes naming the same file write to the same file.

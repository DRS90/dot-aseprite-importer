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
- [Aseprite](https://www.aseprite.org/) 1.3 with scripting support (tested with 1.3.18). Everyone
  who imports the files needs it.

## Installation

1. Copy `addons/aseprite_topdown_grid_animations` into your project's `addons/` folder.
2. Enable **Aseprite Top-Down Grid Animations** in *Project > Project Settings > Plugins*.
3. If Aseprite is not in its default location (a Steam install, for example), set
   *Editor Settings > Aseprite Top-Down Grid Animations > General > Executable Path* or the
   `ASEPRITE_PATH` environment variable. See
   [Aseprite executable](docs/importing.md#aseprite-executable).
4. For crisp pixel art, set *Project Settings > Rendering > Textures > Canvas Textures >
   Default Texture Filter* to **Nearest**.

## Quick start

1. In Aseprite, make the canvas three cells wide and three tall, draw each direction in its cell and
   tag each animation. A tag ending with `_loop` (`walk_loop`) loops.
2. Save the file inside the Godot project. When the Godot editor regains focus, the file is imported
   as SpriteFrames.
3. Drag the file onto the **Sprite Frames** property of an AnimatedSprite2D and play an animation:
   `$AnimatedSprite2D.play("walk_down")`.
4. Optionally, link an AnimationPlayer in the **AnimationPlayer** section of the sprite's inspector
   to get the same animations there and add your own tracks.

[Getting started](docs/getting-started.md) walks through these steps with a movement script.

## Documentation

- [Getting started](docs/getting-started.md): from an empty Aseprite file to a walking character,
  and the demo project.
- [Drawing the sprite](docs/drawing-the-sprite.md): grid, layers, tags and loops.
- [Importing](docs/importing.md): the Aseprite executable, when files are imported, the Import dock
  options and other Aseprite importers.
- [AnimatedSprite2D](docs/animated-sprite-2d.md): animation names, speed and loops.
- [AnimationPlayer](docs/animation-player.md): linking a player, syncs, your own tracks and the
  animation library file.
- [Known limitations](docs/limitations.md)
- [Development](docs/development.md): tests, tools and the example asset.

## Credits

The example character is built from the
["RPG Type Retro Top-Down Playable Character Template" by 5yvalia](https://5yvalia.itch.io/rpg-type-retro-top-down-playable-character-template),
released as **CC0** (public domain). Its sheets are in
`examples/rpg-type-retro-top-down-playable-character-spritesheett/`, with the `LICENSE.png` of the
download.

## License

[MIT](LICENSE)

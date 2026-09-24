# Drawing the sprite

**English** | [Português (Brasil)](pt-BR/drawing-the-sprite.md)

How to lay out the Aseprite file. The Import dock options that read it are in
[Importing](importing.md#import-options).

- Make the canvas the size of one frame of the sprite. The whole canvas is imported, edge to edge.
- Every layer is composed into the animations by default. Prefix helper layers (guides, references)
  with `_` to leave them out, or pick a single layer or group in `layers/layer`.
- Use one tag per animation. Frame durations and the tag direction (forward, reverse, ping-pong,
  ping-pong reverse) are kept. End a tag with `_loop` (`idle_loop`) to make its animation loop; the
  animation is named after the tag without it (`idle`).
- Frames outside any tag are not imported unless the file has no tags.
- A character that only turns left and right needs one side: draw it facing right and mirror it in
  the game with `flip_h`.

## A 3x3 grid of directions

A character that faces up, down and sideways can hold every direction in one file: make the canvas
three cells wide and three cells tall, e.g. **144x192** for 48x64 characters, draw each direction
in its cell, and set `grid/directions` to `3x3`. Each tag then gives one animation per direction.
[Top-down characters](top-down.md) describes the layout and how to turn the grid on for a whole
project.

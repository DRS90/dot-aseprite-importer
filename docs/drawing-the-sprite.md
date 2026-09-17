# Drawing the sprite

How to lay out the Aseprite file. The Import dock options that read it are in
[Importing](importing.md#import-options).

- Make the canvas three cells wide and three cells tall, e.g. **144x192** for 48x64 characters, and
  draw each direction in its cell. Setting Aseprite's grid (*View > Grid > Grid Settings*) to the
  cell size helps to keep every pose inside its cell.
- Pixels that cross a cell border end up in the neighboring direction's animation.
- Every layer is composed into the animations by default. Prefix helper layers (guides, references)
  with `_` to leave them out, or pick a single layer or group in `layers/layer`.
- Use one tag per animation. Frame durations and the tag direction (forward, reverse, ping-pong,
  ping-pong reverse) are kept. End a tag with `_loop` (`idle_loop`) to make its animations loop.
- Frames outside any tag are not imported unless the file has no tags.

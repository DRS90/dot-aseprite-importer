# Known limitations

**English** | [Português (Brasil)](pt-BR/limitations.md)

- The grid is either 3x3, with fixed direction names and the center cell ignored, or the single
  cell of `grid/directions` at `none`. Other grids, such as 1x4 or 4x4, are not supported.
- Only top-level layers and groups can be chosen. A group is imported as the composite of its
  children; hidden children inside a group may be included, because hidden layers are made visible
  for export.
- The tag repeat count set in Aseprite is ignored: only the loop suffix decides whether an animation
  loops.
- A file without tags gets one animation per direction with the whole timeline, named after the
  direction (`down`), or a single animation named `default` when it has no directions either. It
  does not loop.
- Layer names containing `,` or `:` are not offered in the `layers/layer` dropdown.
- Nothing happens when a `.aseprite` file is added to the project: another importer may declare a
  higher priority and be taking the file. Check **Import As** in the Import dock, described in
  [Importing](importing.md#coexistence-with-other-aseprite-importers).
- Aseprite is required to import. The imported resources live in `.godot/`, which is usually not
  committed, so everyone who opens the project needs Aseprite.
- Syncing an AnimationPlayer cannot be undone with *Undo*.
- Only tested on Windows with Godot 4.7.1 and Aseprite 1.3.18.

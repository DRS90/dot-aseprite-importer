-- Builds a 3x3 grid sprite, the format the importer reads, from a sprite drawn with one top-level
-- layer per direction. Layers named like a grid cell (left_up, up, right_up, left, right,
-- left_down, down, right_down) are placed in that cell; other layers are ignored. Frames, frame
-- durations and tags are kept.
--
-- aseprite -b --script-param src=<layers.aseprite> --script-param out=<grid.aseprite>
--          --script tests/tools/build_grid.lua

local params = app.params

local CELLS = {
  left_up = { 0, 0 },
  up = { 1, 0 },
  right_up = { 2, 0 },
  left = { 0, 1 },
  right = { 2, 1 },
  left_down = { 0, 2 },
  down = { 1, 2 },
  right_down = { 2, 2 },
}

local source = app.open(params.src)
if source == nil then
  error("cannot open '" .. tostring(params.src) .. "'")
end
local cell_width = source.width
local cell_height = source.height

-- A copy of the source spec keeps its color mode and color space.
local spec = source.spec
spec.width = cell_width * 3
spec.height = cell_height * 3
local grid = Sprite(spec)
grid:setPalette(source.palettes[1])
local layer = grid.layers[1]
layer.name = "default"

for frame = 2, #source.frames do
  grid:newEmptyFrame(frame)
end
for index, frame in ipairs(source.frames) do
  grid.frames[index].duration = frame.duration
end
for _, tag in ipairs(source.tags) do
  local copy = grid:newTag(tag.fromFrame.frameNumber, tag.toFrame.frameNumber)
  copy.name = tag.name
  copy.aniDir = tag.aniDir
end

local placed = 0
for frame = 1, #source.frames do
  local canvas = Image(grid.spec)
  for _, direction_layer in ipairs(source.layers) do
    local cell = CELLS[direction_layer.name]
    if cell then
      for _, other in ipairs(source.layers) do
        other.isVisible = other == direction_layer
      end
      local rendered = Image(source.spec)
      rendered:drawSprite(source, frame)
      canvas:drawImage(rendered, Point(cell[1] * cell_width, cell[2] * cell_height), 255,
        BlendMode.SRC)
      if frame == 1 then
        placed = placed + 1
      end
    end
  end
  grid:newCel(layer, frame, canvas, Point(0, 0))
end

if placed == 0 then
  error("no layer is named like a grid cell")
end
grid:saveAs(params.out)
print("done\t" .. grid.width .. "x" .. grid.height .. "\t" .. placed .. " directions")

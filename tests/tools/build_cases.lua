-- Builds sprites for manual tests of the importer from a 3x3 grid sprite (e.g. the output of
-- build_grid.lua). Each one covers cases the plain example does not. All but the last are grids:
-- import them with grid/directions = 3x3 (the default is none).
--   layers.aseprite            "body" plus "shadow" (below it), "_guide" (cell borders, excluded by
--                              default), group "armor" with "plate" and a hidden "helmet", hidden
--                              "hidden_fx" (also fills left and right), and "weapon, left" and
--                              "fx:glow" (names the layer dropdown does not offer)
--   eight_directions.aseprite  left and right filled, pixels in the ignored center cell, the up
--                              cell empty in the dash tag, and an excluded "_wip" tag
--   padded.aseprite            3x3 cells plus a 6 px column and an 8 px row: the default cell size
--                              fails, grid/cell_size = cell size works and ignores the leftover
--   untagged.aseprite          no tags: one strip per direction with the whole timeline
--   no_directions.aseprite     16x16 with no grid at all, one "run_loop" tag: a sprite with no
--                              direction, imported with the default grid/directions = none
--
-- aseprite -b --script-param src=<grid.aseprite> --script-param out=<folder>
--          --script tests/tools/build_cases.lua

local params = app.params

-- Cells drawn in the example grid, and every cell but the center, as {column, row}.
local DRAWN = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }
local AROUND = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }
local CANVAS = { { 0, 0 } }

local function open_source()
  local sprite = app.open(params.src)
  if sprite == nil then
    error("cannot open '" .. tostring(params.src) .. "'")
  end
  if sprite.width % 3 ~= 0 or sprite.height % 3 ~= 0 then
    error("the source is not a 3x3 grid")
  end
  return sprite, sprite.width // 3, sprite.height // 3
end

local function save(sprite, name)
  sprite:saveAs(params.out .. "/" .. name)
  sprite:close()
  print("saved\t" .. name)
end

local function find_tag(sprite, name)
  for _, tag in ipairs(sprite.tags) do
    if tag.name == name then
      return tag
    end
  end
  error("the source has no '" .. name .. "' tag")
end

-- Gives layer a cel in every frame with rects {x, y, width, height} filled in each cell.
local function paint(sprite, layer, cells, cell_width, cell_height, rects, color)
  for frame = 1, #sprite.frames do
    local image = Image(sprite.spec)
    for _, cell in ipairs(cells) do
      for _, rect in ipairs(rects) do
        local x = cell[1] * cell_width + rect[1]
        local y = cell[2] * cell_height + rect[2]
        image:clear(Rectangle(x, y, rect[3], rect[4]), color)
      end
    end
    sprite:newCel(layer, frame, image, Point(0, 0))
  end
end

local function new_layer(sprite, name)
  local layer = sprite:newLayer()
  layer.name = name
  return layer
end

local function build_layers()
  local sprite, w, h = open_source()
  sprite.layers[1].name = "body"

  local shadow = new_layer(sprite, "shadow")
  paint(sprite, shadow, DRAWN, w, h, { { 14, 42, 20, 3 } }, Color { r = 0, g = 0, b = 0, a = 110 })
  shadow.stackIndex = 1

  local guide = new_layer(sprite, "_guide")
  local borders = { { w, 0, 1, h * 3 }, { w * 2, 0, 1, h * 3 }, { 0, h, w * 3, 1 }, { 0, h * 2, w * 3, 1 } }
  paint(sprite, guide, CANVAS, w, h, borders, Color { r = 255, g = 0, b = 255, a = 255 })

  local armor = sprite:newGroup()
  armor.name = "armor"
  local plate = new_layer(sprite, "plate")
  paint(sprite, plate, DRAWN, w, h, { { 18, 22, 12, 6 } }, Color { r = 70, g = 130, b = 220, a = 255 })
  plate.parent = armor
  local helmet = new_layer(sprite, "helmet")
  paint(sprite, helmet, DRAWN, w, h, { { 18, 9, 12, 4 } }, Color { r = 230, g = 190, b = 40, a = 255 })
  helmet.parent = armor
  helmet.isVisible = false

  local hidden = new_layer(sprite, "hidden_fx")
  paint(sprite, hidden, AROUND, w, h, { { 22, 1, 4, 4 } }, Color { r = 255, g = 80, b = 200, a = 255 })
  hidden.isVisible = false

  local weapon = new_layer(sprite, "weapon, left")
  paint(sprite, weapon, DRAWN, w, h, { { 34, 24, 3, 12 } }, Color { r = 200, g = 200, b = 200, a = 255 })
  local glow = new_layer(sprite, "fx:glow")
  paint(sprite, glow, DRAWN, w, h, { { 9, 30, 3, 3 } }, Color { r = 120, g = 255, b = 120, a = 255 })

  save(sprite, "layers.aseprite")
end

local function build_eight_directions()
  local sprite, w, h = open_source()
  local layer = sprite.layers[1]
  local dash = find_tag(sprite, "dash")
  local dash_first = dash.fromFrame.frameNumber
  local dash_last = dash.toFrame.frameNumber
  for frame = 1, #sprite.frames do
    local image = Image(sprite.spec)
    image:drawSprite(sprite, frame)
    -- left and right reuse the left_down and right_down poses.
    image:drawImage(Image(image, Rectangle(0, h * 2, w, h)), Point(0, h), 255, BlendMode.SRC)
    image:drawImage(Image(image, Rectangle(w * 2, h * 2, w, h)), Point(w * 2, h), 255, BlendMode.SRC)
    image:clear(Rectangle(w + 20, h + 28, 8, 8), Color { r = 255, g = 0, b = 0, a = 255 })
    if frame >= dash_first and frame <= dash_last then
      image:clear(Rectangle(w, 0, w, h))
    end
    sprite:newCel(layer, frame, image, Point(0, 0))
  end
  local wip = sprite:newTag(1, 2)
  wip.name = "_wip"
  save(sprite, "eight_directions.aseprite")
end

local function build_padded()
  local source, w, h = open_source()
  local spec = source.spec
  spec.width = w * 3 + 6
  spec.height = h * 3 + 8
  local sprite = Sprite(spec)
  sprite:setPalette(source.palettes[1])
  for frame = 2, #source.frames do
    sprite:newEmptyFrame(frame)
  end
  for index, frame in ipairs(source.frames) do
    sprite.frames[index].duration = frame.duration
  end
  for _, tag in ipairs(source.tags) do
    local copy = sprite:newTag(tag.fromFrame.frameNumber, tag.toFrame.frameNumber)
    copy.name = tag.name
    copy.aniDir = tag.aniDir
  end
  local layer = sprite.layers[1]
  layer.name = "default"
  local red = Color { r = 255, g = 0, b = 0, a = 255 }
  for frame = 1, #source.frames do
    local image = Image(sprite.spec)
    image:drawSprite(source, frame)
    image:clear(Rectangle(w * 3, 0, 6, spec.height), red)
    image:clear(Rectangle(0, h * 3, spec.width, 8), red)
    sprite:newCel(layer, frame, image, Point(0, 0))
  end
  source:close()
  save(sprite, "padded.aseprite")
end

local function build_untagged()
  local sprite = open_source()
  while #sprite.tags > 0 do
    sprite:deleteTag(sprite.tags[1])
  end
  save(sprite, "untagged.aseprite")
end

-- A run dust puff: no grid, no direction, the default grid/directions = none. Built from
-- scratch rather than from the source, which is a 3x3 grid by definition.
local function build_no_directions()
  local source = open_source()
  local spec = source.spec
  spec.width = 16
  spec.height = 16
  local sprite = Sprite(spec)
  sprite:setPalette(source.palettes[1])
  for frame = 2, 4 do
    sprite:newEmptyFrame(frame)
  end
  local layer = sprite.layers[1]
  layer.name = "dust"
  local color = Color { r = 235, g = 225, b = 200, a = 255 }
  for frame = 1, 4 do
    local image = Image(sprite.spec)
    -- The puff grows and drifts up as the frames go by, so a wrong frame order is visible.
    local size = 2 + frame
    image:clear(Rectangle(8 - size // 2, 13 - frame - size // 2, size, size), color)
    sprite:newCel(layer, frame, image, Point(0, 0))
    sprite.frames[frame].duration = 0.08
  end
  local tag = sprite:newTag(1, 4)
  tag.name = "run_loop"
  source:close()
  save(sprite, "no_directions.aseprite")
end

build_layers()
build_eight_directions()
build_padded()
build_untagged()
build_no_directions()
print("done")

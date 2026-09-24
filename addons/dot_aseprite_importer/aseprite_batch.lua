-- Runs inside Aseprite: aseprite -b --script-param key=value ... --script aseprite_batch.lua
--
-- With cells_per_axis=3, every frame is a 3x3 grid of cells named after the direction they face
-- and the center is ignored:
--   left_up   | up   | right_up
--   left      |      | right
--   left_down | down | right_down
-- With cells_per_axis=1 the frame is a single nameless cell, for sprites that have no direction.
--
-- Starting Aseprite costs about 200 ms, plus the time it takes to open the file, while exporting
-- one strip costs a few, so a whole import is served by one export process instead of one process
-- per strip. Imports read what a file holds from its bytes (aseprite_file_reader.gd); mode=list
-- lists the same through Aseprite and is what the tests compare that reader with.
--
-- mode=list    params: file
--              Prints "size<TAB>width<TAB>height", then "layer<TAB>name<TAB>visible" ("true" or
--              "false") per top-level layer or group, then
--              "tag<TAB>name<TAB>from<TAB>to<TAB>direction" per tag (0-based frames; direction is
--              forward, reverse, pingpong or pingpong_reverse), then
--              "frame<TAB>index<TAB>duration_ms" per frame.
-- mode=export  params: file, jobs, cell_width, cell_height, cells_per_axis (3 or 1)
--              jobs is a text file with "layer<TAB>name" lines (the layers composed into every
--              strip) and "strip<TAB>output_png<TAB>tag<TAB>direction" lines. Each strip is the
--              direction cell of every frame of the tag, left to right in timeline order; an empty
--              tag exports the whole timeline and an empty direction is the only cell of
--              cells_per_axis=1. Prints "written<TAB>output_png" per strip, or
--              "empty<TAB>output_png" when the cell has no pixels in any frame of the tag (nothing
--              is saved then).
--
-- Unknown layers or tags, a direction that does not belong to the grid, and cells that do not fit
-- the sprite raise an error instead of silently exporting the wrong image. Cropping outside the
-- sprite raises nothing by itself, which is why the grid is checked here as well as in GDScript.
-- Success ends with "done<TAB>count"; the caller treats a missing "done" line as a failure.

local params = app.params

local DIRECTIONS = {
  [""] = { 0, 0 },
  left_up = { 0, 0 },
  up = { 1, 0 },
  right_up = { 2, 0 },
  left = { 0, 1 },
  right = { 2, 1 },
  left_down = { 0, 2 },
  down = { 1, 2 },
  right_down = { 2, 2 },
}

local TAG_DIRECTIONS = {
  [AniDir.FORWARD] = "forward",
  [AniDir.REVERSE] = "reverse",
  [AniDir.PING_PONG] = "pingpong",
}
if AniDir.PING_PONG_REVERSE ~= nil then
  TAG_DIRECTIONS[AniDir.PING_PONG_REVERSE] = "pingpong_reverse"
end

local sprite = app.open(params.file)
if sprite == nil then
  error("cannot open '" .. tostring(params.file) .. "'")
end

local function split_tabs(line)
  local fields = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do
    table.insert(fields, field)
  end
  return fields
end

local function show_all(layers)
  for _, layer in ipairs(layers) do
    layer.isVisible = true
    if layer.isGroup then
      show_all(layer.layers)
    end
  end
end

local function list()
  print("size\t" .. sprite.width .. "\t" .. sprite.height)
  local count = 0
  for _, layer in ipairs(sprite.layers) do
    print("layer\t" .. layer.name .. "\t" .. tostring(layer.isVisible))
    count = count + 1
  end
  for _, tag in ipairs(sprite.tags) do
    local direction = TAG_DIRECTIONS[tag.aniDir] or "forward"
    print("tag\t" .. tag.name .. "\t" .. (tag.fromFrame.frameNumber - 1) .. "\t"
      .. (tag.toFrame.frameNumber - 1) .. "\t" .. direction)
    count = count + 1
  end
  for index, frame in ipairs(sprite.frames) do
    print("frame\t" .. (index - 1) .. "\t" .. math.floor(frame.duration * 1000 + 0.5))
    count = count + 1
  end
  print("done\t" .. count)
end

-- Same result as the CLI's --all-layers --layer <name>...: only the wanted top-level layers are
-- visible, and everything inside groups is visible.
local function show_only(wanted)
  local found = {}
  for _, layer in ipairs(sprite.layers) do
    local visible = wanted[layer.name] == true
    layer.isVisible = visible
    if visible then
      found[layer.name] = true
    end
    if layer.isGroup then
      show_all(layer.layers)
    end
  end
  local any = false
  for name in pairs(wanted) do
    if not found[name] then
      error("unknown layer '" .. name .. "'")
    end
    any = true
  end
  if not any then
    error("no layers to export")
  end
end

local function cells_per_axis()
  local cells = tonumber(params.cells_per_axis)
  if cells ~= 1 and cells ~= 3 then
    error("cells_per_axis must be 1 or 3, got '" .. tostring(params.cells_per_axis) .. "'")
  end
  return cells
end

local function cell_size(cells)
  local width = tonumber(params.cell_width)
  local height = tonumber(params.cell_height)
  if width == nil or height == nil or width < 1 or height < 1 or width % 1 ~= 0
      or height % 1 ~= 0 or width * cells > sprite.width or height * cells > sprite.height then
    error("cell " .. tostring(params.cell_width) .. "x" .. tostring(params.cell_height)
      .. " does not fit " .. cells .. "x" .. cells .. " times in the "
      .. sprite.width .. "x" .. sprite.height .. " sprite")
  end
  return width, height
end

local function read_jobs()
  local wanted = {}
  local strips = {}
  for line in io.lines(params.jobs) do
    line = line:gsub("\r$", "")
    if line ~= "" then
      local fields = split_tabs(line)
      if fields[1] == "layer" and #fields == 2 then
        wanted[fields[2]] = true
      elseif fields[1] == "strip" and #fields == 4 then
        table.insert(strips, { output = fields[2], tag = fields[3], direction = fields[4] })
      else
        error("malformed job line '" .. line .. "'")
      end
    end
  end
  return wanted, strips
end

-- Strips of the same tag share its rendered frames: group them, keeping the job order.
local function group_by_tag(strips, cells)
  local order = {}
  local groups = {}
  for _, strip in ipairs(strips) do
    -- The nameless cell belongs to a grid of one and only to it; naming a direction in a grid of
    -- one, or leaving it out of a 3x3 grid, would crop a cell nobody asked for.
    if (cells == 1) ~= (strip.direction == "") then
      error("direction '" .. strip.direction .. "' does not belong to a grid of " .. cells .. "x"
        .. cells .. " cells, for '" .. strip.output .. "'")
    end
    if DIRECTIONS[strip.direction] == nil then
      error("unknown direction '" .. strip.direction .. "' for '" .. strip.output .. "'")
    end
    if groups[strip.tag] == nil then
      groups[strip.tag] = {}
      table.insert(order, strip.tag)
    end
    table.insert(groups[strip.tag], strip)
  end
  return order, groups
end

local function frame_range(tag_name)
  if tag_name == "" then
    return 1, #sprite.frames
  end
  for _, tag in ipairs(sprite.tags) do
    if tag.name == tag_name then
      return tag.fromFrame.frameNumber, tag.toFrame.frameNumber
    end
  end
  error("unknown tag '" .. tag_name .. "'")
end

local function export_tag(tag_name, strips, cell_width, cell_height)
  local first, last = frame_range(tag_name)
  local frame_count = last - first + 1
  -- A copy of the sprite spec keeps its color space: without it the PNG has no sRGB chunk and
  -- differs from what Export Sprite Sheet writes.
  local spec = sprite.spec
  spec.width = cell_width * frame_count
  spec.height = cell_height
  for _, strip in ipairs(strips) do
    strip.image = Image(spec)
    strip.filled = false
  end

  for index = 0, frame_count - 1 do
    local rendered = Image(sprite.spec)
    rendered:drawSprite(sprite, first + index)
    local position = Point(index * cell_width, 0)
    for _, strip in ipairs(strips) do
      local cell = DIRECTIONS[strip.direction]
      local bounds = Rectangle(cell[1] * cell_width, cell[2] * cell_height, cell_width, cell_height)
      local piece = Image(rendered, bounds)
      if not piece:isEmpty() then
        strip.filled = true
        strip.image:drawImage(piece, position, 255, BlendMode.SRC)
      end
    end
  end

  for _, strip in ipairs(strips) do
    if strip.filled then
      strip.image:saveAs { filename = strip.output, palette = sprite.palettes[1] }
      print("written\t" .. strip.output)
    else
      print("empty\t" .. strip.output)
    end
    strip.image = nil
  end
end

local function export()
  local cells = cells_per_axis()
  local cell_width, cell_height = cell_size(cells)
  local wanted, strips = read_jobs()
  show_only(wanted)
  local order, groups = group_by_tag(strips, cells)
  for _, tag_name in ipairs(order) do
    export_tag(tag_name, groups[tag_name], cell_width, cell_height)
  end
  print("done\t" .. #strips)
end

if params.mode == "list" then
  list()
elseif params.mode == "export" then
  export()
else
  error("unknown mode '" .. tostring(params.mode) .. "'")
end

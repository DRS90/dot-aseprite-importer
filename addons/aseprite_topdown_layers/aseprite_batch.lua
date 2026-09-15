-- Runs inside Aseprite: aseprite -b --script-param key=value ... --script aseprite_batch.lua
--
-- Starting Aseprite costs about 200 ms while exporting one strip costs a few, so a whole import is
-- served by one process per mode instead of one process per strip.
--
-- mode=list    params: file, only_visible ("true"/"false")
--              Prints "layer<TAB>name" per top-level layer or group, then "tag<TAB>name" per tag.
-- mode=export  params: file, jobs, data, sheet_type ("horizontal"/"vertical")
--              jobs is a text file with one strip per line: output_png<TAB>tag<TAB>layer[<TAB>layer]
--              An empty tag exports the whole timeline. data receives the (unused) JSON data.
--
-- Unknown layers or tags raise an error instead of silently exporting the wrong image.
-- Success ends with "done<TAB>count"; the caller treats a missing "done" line as a failure.

local params = app.params

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
  local count = 0
  for _, layer in ipairs(sprite.layers) do
    if params.only_visible ~= "true" or layer.isVisible then
      print("layer\t" .. layer.name)
      count = count + 1
    end
  end
  for _, tag in ipairs(sprite.tags) do
    print("tag\t" .. tag.name)
    count = count + 1
  end
  print("done\t" .. count)
end

-- Same result as the CLI's --all-layers --layer <name>...: only the wanted top-level layers are
-- visible, and everything inside groups is visible.
local function show_only(wanted, output)
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
      error("unknown layer '" .. name .. "' for '" .. output .. "'")
    end
    any = true
  end
  if not any then
    error("no layers for '" .. output .. "'")
  end
end

local function export()
  local sheet_type = SpriteSheetType.HORIZONTAL
  if params.sheet_type == "vertical" then
    sheet_type = SpriteSheetType.VERTICAL
  end
  local tags = {}
  for _, tag in ipairs(sprite.tags) do
    tags[tag.name] = true
  end

  local count = 0
  for line in io.lines(params.jobs) do
    line = line:gsub("\r$", "")
    if line ~= "" then
      local fields = split_tabs(line)
      local output = fields[1]
      local tag = fields[2] or ""
      if tag ~= "" and not tags[tag] then
        error("unknown tag '" .. tag .. "' for '" .. output .. "'")
      end
      local wanted = {}
      for index = 3, #fields do
        wanted[fields[index]] = true
      end
      show_only(wanted, output)
      -- Without ui, unset parameters fall back to the last Export Sprite Sheet dialog settings:
      -- every parameter that changes the image is set explicitly.
      app.command.ExportSpriteSheet {
        ui = false,
        recent = false,
        askOverwrite = false,
        openGenerated = false,
        type = sheet_type,
        columns = 0,
        rows = 0,
        width = 0,
        height = 0,
        bestFit = false,
        textureFilename = output,
        dataFilename = params.data,
        borderPadding = 0,
        shapePadding = 0,
        innerPadding = 0,
        trimSprite = false,
        trim = false,
        trimByGrid = false,
        extrude = false,
        ignoreEmpty = false,
        mergeDuplicates = false,
        layer = "",
        tag = tag,
        splitLayers = false,
        splitTags = false,
        splitGrid = false,
        listLayers = false,
        listTags = false,
        listSlices = false,
        fromTilesets = false,
      }
      count = count + 1
    end
  end
  print("done\t" .. count)
end

if params.mode == "list" then
  list()
elseif params.mode == "export" then
  export()
else
  error("unknown mode '" .. tostring(params.mode) .. "'")
end

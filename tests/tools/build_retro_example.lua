-- Builds the example sprite of this repository, examples/retro-top-down-character.aseprite, from
-- the CC0 sheets in examples/rpg-type-retro-top-down-playable-character-spritesheett/ (see
-- README > Credits). The 16x16 character of each sheet row goes to the center of its direction cell
-- and the 48x48 sword effect of the slash tag goes to its own layer:
--
--   layers: character, weapon      cells: 48x48 (canvas 144x144)
--   rows of the sheet: down, up, left, right -> bottom, top, left and right cells
--   tags: walk_loop, push_loop, pull_loop, carry_loop, pickup, throw, use, slash, swim_loop,
--         climb_loop (climb is only drawn facing up and down)
--
-- aseprite -b --script-param file=<out.aseprite> --script-param sheet=<16x16 png>
--          --script-param attack=<48x48 png> --script tests/tools/build_retro_example.lua

local params = app.params

local CHARACTER = 16
local CELL = 48
local OFFSET = (CELL - CHARACTER) // 2
-- Sheet rows are directions; each maps to a grid cell {column, row}.
local ROW_CELLS = { { 1, 2 }, { 1, 0 }, { 0, 1 }, { 2, 1 } } -- down, up, left, right
-- {name, first column, last column} of the sheet, 0-based.
local TAGS = {
  { "walk_loop", 0, 3 },
  { "push_loop", 4, 7 },
  { "pull_loop", 8, 11 },
  { "carry_loop", 12, 15 },
  { "pickup", 16, 19 },
  { "throw", 20, 23 },
  { "use", 24, 31 },
  { "slash", 32, 35 },
  { "swim_loop", 36, 39 },
  { "climb_loop", 40, 43 },
}
local SLASH_FIRST = 32
local FRAME_DURATION = 0.1

local sheet = Image { fromFile = params.sheet }
local attack = Image { fromFile = params.attack }
if sheet == nil or attack == nil then
  error("cannot load the sheets")
end
local columns = sheet.width // CHARACTER
local attack_columns = attack.width // CELL

local sprite = Sprite(ImageSpec {
  width = CELL * 3,
  height = CELL * 3,
  colorMode = ColorMode.RGB,
})
sprite.gridBounds = Rectangle(0, 0, CELL, CELL)
local character_layer = sprite.layers[1]
character_layer.name = "character"
local weapon_layer = sprite:newLayer()
weapon_layer.name = "weapon"
for frame = 2, columns do
  sprite:newEmptyFrame(frame)
end

local drawn = 0
for column = 0, columns - 1 do
  local frame = column + 1
  sprite.frames[frame].duration = FRAME_DURATION
  local body = Image(sprite.spec)
  local weapon = Image(sprite.spec)
  for row, cell in ipairs(ROW_CELLS) do
    local x = cell[1] * CELL
    local y = cell[2] * CELL
    local bounds = Rectangle(column * CHARACTER, (row - 1) * CHARACTER, CHARACTER, CHARACTER)
    local piece = Image(sheet, bounds)
    if not piece:isEmpty() then
      body:drawImage(piece, Point(x + OFFSET, y + OFFSET), 255, BlendMode.SRC)
      drawn = drawn + 1
    end
    local effect_column = column - SLASH_FIRST
    if effect_column >= 0 and effect_column < attack_columns then
      local effect_bounds = Rectangle(effect_column * CELL, (row - 1) * CELL, CELL, CELL)
      local effect = Image(attack, effect_bounds)
      if not effect:isEmpty() then
        weapon:drawImage(effect, Point(x, y), 255, BlendMode.SRC)
      end
    end
  end
  sprite:newCel(character_layer, frame, body, Point(0, 0))
  sprite:newCel(weapon_layer, frame, weapon, Point(0, 0))
end

for _, tag in ipairs(TAGS) do
  local new_tag = sprite:newTag(tag[2] + 1, tag[3] + 1)
  new_tag.name = tag[1]
end
sprite:saveAs(params.file)
print("done\t" .. columns .. " frames\t" .. drawn .. " drawn cells\t" .. #sprite.tags .. " tags")

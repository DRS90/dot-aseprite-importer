-- Builds the sprites the test runner reads with AsepriteFileReader and compares with Aseprite's
-- own listing. Each covers what the example does not:
--   layers_and_tags.aseprite  a group with a nested group, hidden layers and groups, names with a
--                             comma, a colon and non-ASCII letters (a pixel in "ação ✓" so an
--                             export of it writes a strip), every tag direction, a repeat count, a
--                             tag name used twice and a one-frame tag, and a different duration
--                             for every frame
--   tilemap.aseprite          a tilemap layer between two plain ones
--   tiny.aseprite             1x1 grayscale, one frame, no tags
--
-- aseprite -b --script-param out=<folder> --script tests/tools/build_reader_cases.lua

local out = app.params.out

local sprite = Sprite(20, 10, ColorMode.RGB)
sprite.layers[1].name = "base"
local armor = sprite:newGroup()
armor.name = "armor, plate"
local inner = sprite:newLayer()
inner.name = "inner"
inner.parent = armor
local deep = sprite:newGroup()
deep.name = "deep"
deep.parent = armor
local deeper = sprite:newLayer()
deeper.name = "deeper"
deeper.parent = deep
local hidden = sprite:newLayer()
hidden.name = "hidden:fx"
hidden.isVisible = false
local accented = sprite:newLayer()
accented.name = "ação ✓"
local guide = sprite:newGroup()
guide.name = "_guide"
guide.isVisible = false
for frame = 2, 9 do
  sprite:newEmptyFrame(frame)
end
for frame = 1, 9 do
  sprite.frames[frame].duration = frame * 0.017
end
local marked = Image(sprite.spec)
marked:drawPixel(3, 4, app.pixelColor.rgba(255, 0, 0, 255))
sprite:newCel(accented, 1, marked, Point(0, 0))
local directions = { AniDir.FORWARD, AniDir.REVERSE, AniDir.PING_PONG, AniDir.PING_PONG_REVERSE }
for index, direction in ipairs(directions) do
  local tag = sprite:newTag(index, index + 1)
  tag.name = "t" .. index
  tag.aniDir = direction
end
sprite.tags[3].repeats = 3
local repeated = sprite:newTag(6, 9)
repeated.name = "t1"
local single = sprite:newTag(9, 9)
single.name = "single frame"
sprite:saveAs(out .. "/layers_and_tags.aseprite")
sprite:close()

local tilemap = Sprite(32, 32, ColorMode.RGB)
tilemap.layers[1].name = "ground"
app.activeSprite = tilemap
app.command.NewLayer { tilemap = true, gridBounds = Rectangle(0, 0, 8, 8) }
tilemap.layers[#tilemap.layers].name = "tiles"
local top = tilemap:newLayer()
top.name = "top"
tilemap:saveAs(out .. "/tilemap.aseprite")
tilemap:close()

local tiny = Sprite(1, 1, ColorMode.GRAY)
tiny:saveAs(out .. "/tiny.aseprite")
tiny:close()

print("done")

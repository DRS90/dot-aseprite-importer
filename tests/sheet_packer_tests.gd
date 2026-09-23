extends RefCounted
## SheetPacker checks of the headless test runner, on synthetic strips: they never call Aseprite.
## [param check] is the runner's own reporting function, so one run counts every failure.

const SheetPacker := preload("res://addons/aseprite_topdown_grid_animations/sheet_packer.gd")
const SpriteFramesBuilder := preload(
	"res://addons/aseprite_topdown_grid_animations/sprite_frames_builder.gd"
)

## Decoded sheets by texture, so comparing hundreds of frames decodes each sheet once.
static var _decoded := {}

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


## Synthetic strips through the packer: each frame cut to its own pixels, repeated frames stored
## once, margins that give the cells back, and what it has to refuse.
func run() -> void:
	var cell := Vector2i(8, 8)
	var strips := _strips()
	var packer := SheetPacker.new()
	var packed := packer.pack(strips, cell)
	var sheet: Image = packed.get("sheet")
	var cells: Dictionary = packed.get("cells", {})
	if not _check.call(
		packer.errors.is_empty() and sheet != null and cells.size() == strips.size(),
		"the packer packs four strips",
		str(packer.errors)
	):
		return
	_test_trimmed_cells(cells)
	_test_repeated_cells(cells, sheet)
	var rebuilt := 0
	var total := 0
	for strip: Dictionary in strips:
		var image := (strip["image"] as Image).duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		var entries: Array[Dictionary] = cells[strip["key"]]
		for index: int in entries.size():
			var original := image.get_region(Rect2i(Vector2i(index * cell.x, 0), cell))
			var entry := entries[index]
			total += 1
			if recompose(sheet, entry["region"], entry["margin"]).get_data() == original.get_data():
				rebuilt += 1
	_check.call(
		rebuilt == total and total == 9,
		"region and margin give every cell back, the empty frame included",
		"%d of %d" % [rebuilt, total]
	)
	var again := packer.pack(strips, cell)
	var same_sheet := (again.get("sheet") as Image).get_data() == sheet.get_data()
	_check.call(
		same_sheet and str(again.get("cells")) == str(cells),
		"the same strips give the same sheet",
		str(again.get("cells"))
	)

	# Color under alpha 0: Aseprite does not call it empty, but nothing of it is visible.
	var invisible := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	invisible.fill(Color(1.0, 0.0, 0.0, 0.0))
	var with_invisible: Array[Dictionary] = [{"key": "invisible", "image": invisible}, strips[0]]
	packed = packer.pack(with_invisible, cell)
	cells = packed.get("cells", {})
	_check.call(
		packer.errors.is_empty() and cells.keys() == ["walk"] and packed.get("sheet") != null,
		"a strip with no visible pixel is left out, never a whole-atlas region",
		"%s %s" % [packer.errors, cells.keys()]
	)
	_test_builder_skips_invisible(invisible)
	var crooked: Array[Dictionary] = [
		{"key": "crooked", "image": Image.create_empty(10, 8, false, Image.FORMAT_RGBA8)}
	]
	packed = packer.pack(crooked, cell)
	_check.call(
		packed.is_empty() and packer.errors.size() == 1,
		"a strip that is not a row of cells is refused",
		str(packer.errors)
	)
	packed = packer.pack([] as Array[Dictionary], cell)
	_check.call(
		packer.errors.is_empty() and packed.get("sheet") == null,
		"nothing to pack gives no sheet and no error",
		str(packed)
	)
	_test_sheet_packer_limit(packer)


## Rows of 8x8 cells: "walk" with pixels in different places and an empty middle frame, "opaque"
## with no alpha channel (every pixel used, twice the same), "repeat" with walk's first frame in
## its place and moved, and "shape" with two solid rects of the same bytes but different sizes.
static func _strips() -> Array[Dictionary]:
	var walk := Image.create_empty(24, 8, false, Image.FORMAT_RGBA8)
	walk.fill_rect(Rect2i(2, 3, 2, 2), Color.RED)
	walk.fill_rect(Rect2i(16 + 5, 6, 1, 1), Color.BLUE)
	var opaque := Image.create_empty(16, 8, false, Image.FORMAT_RGB8)
	opaque.fill(Color.GREEN)
	var repeat := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	repeat.fill_rect(Rect2i(2, 3, 2, 2), Color.RED)
	repeat.fill_rect(Rect2i(8 + 4, 1, 2, 2), Color.RED)
	var shape := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	shape.fill_rect(Rect2i(0, 0, 2, 8), Color.YELLOW)
	shape.fill_rect(Rect2i(8, 0, 4, 4), Color.YELLOW)
	return [
		{"key": "walk", "image": walk},
		{"key": "opaque", "image": opaque},
		{"key": "repeat", "image": repeat},
		{"key": "shape", "image": shape},
	]


func _test_trimmed_cells(cells: Dictionary) -> void:
	var walk: Array[Dictionary] = cells["walk"]
	var opaque: Array[Dictionary] = cells["opaque"]
	_check.call(
		(
			walk.size() == 3
			and (walk[0]["region"] as Rect2i).size == Vector2i(2, 2)
			and walk[0]["margin"] == Rect2i(2, 3, 6, 6)
			and (walk[2]["region"] as Rect2i).size == Vector2i(1, 1)
			and walk[2]["margin"] == Rect2i(5, 6, 7, 7)
			and opaque.size() == 2
			and (opaque[0]["region"] as Rect2i).size == Vector2i(8, 8)
			and opaque[0]["margin"] == Rect2i()
		),
		"every frame is cut to its own pixels, and its margin gives the cell back",
		"%s %s" % [walk, opaque]
	)
	var empty_region: Rect2i = walk[1]["region"]
	_check.call(
		empty_region.size == Vector2i(1, 1) and walk[1]["margin"] == Rect2i(0, 0, 7, 7),
		"an empty frame is one transparent pixel with a margin, never a region of size 0",
		str(walk[1])
	)


func _test_repeated_cells(cells: Dictionary, sheet: Image) -> void:
	var walk: Array[Dictionary] = cells["walk"]
	var opaque: Array[Dictionary] = cells["opaque"]
	var repeat: Array[Dictionary] = cells["repeat"]
	var shape: Array[Dictionary] = cells["shape"]
	_check.call(
		(
			repeat[0]["region"] == walk[0]["region"]
			and repeat[1]["region"] == walk[0]["region"]
			and repeat[1]["margin"] == Rect2i(4, 1, 6, 6)
			and opaque[1]["region"] == opaque[0]["region"]
		),
		"repeated frames share a region, each with its own margin",
		"%s %s %s" % [walk[0], repeat, opaque]
	)
	_check.call(
		shape[0]["region"] != shape[1]["region"],
		"frames with the same bytes but different sizes do not share a region",
		str(shape)
	)
	var regions: Array[Rect2i] = []
	for key: String in cells:
		for entry: Dictionary in cells[key]:
			var region: Rect2i = entry["region"]
			if not regions.has(region):
				regions.append(region)
	var problems := PackedStringArray()
	var sheet_rect := Rect2i(Vector2i.ZERO, sheet.get_size())
	for index: int in regions.size():
		if not sheet_rect.encloses(regions[index]):
			problems.append("%s outside" % regions[index])
		for other: int in range(index + 1, regions.size()):
			if regions[index].intersects(regions[other]):
				problems.append("%s over %s" % [regions[index], regions[other]])
	_check.call(
		regions.size() == 6 and problems.is_empty(),
		"six distinct regions, none overlapping, all inside the sheet",
		"%d regions %s" % [regions.size(), problems]
	)


## A frame may reach the texture limit on either axis, and not one pixel past it.
func _test_sheet_packer_limit(packer: SheetPacker) -> void:
	var results := PackedStringArray()
	for past: int in [0, 1]:
		var side := SheetPacker.MAX_TEXTURE_SIZE + past
		for cell: Vector2i in [Vector2i(side, 1), Vector2i(1, side)]:
			var image := Image.create_empty(cell.x, cell.y, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			var strips: Array[Dictionary] = [{"key": "big", "image": image}]
			var packed := packer.pack(strips, cell)
			var refused := not packer.errors.is_empty() and packed.is_empty()
			results.append("%s:%s" % [cell, "refused" if refused else "ok"])
	var limit := SheetPacker.MAX_TEXTURE_SIZE
	var expected := PackedStringArray(
		[
			"(%d, 1):ok" % limit,
			"(1, %d):ok" % limit,
			"(%d, 1):refused" % (limit + 1),
			"(1, %d):refused" % (limit + 1),
		]
	)
	_check.call(
		results == expected,
		"a frame of %d px is packed, one pixel past it is refused on either axis" % limit,
		str(results)
	)


## The only strip of a file holds no visible pixel: the import gives no animation and no error, as
## when Aseprite finds the cell empty, instead of failing the whole file.
func _test_builder_skips_invisible(invisible: Image) -> void:
	var strips_dir := OS.get_cache_dir().path_join(
		"aseprite_topdown_grid_animations_tests/invisible"
	)
	DirAccess.make_dir_recursive_absolute(strips_dir)
	invisible.save_png(strips_dir.path_join("invisible.png"))
	var jobs: Array[Dictionary] = [
		{
			"direction": "up",
			"tag": "ghost",
			"animation": "ghost_up",
			"loop": false,
			"relative_path": "invisible.png",
		}
	]
	var contents := {
		"tag_ranges": {"ghost": {"from": 0, "to": 1, "direction": "forward"}},
		"frame_durations": PackedInt32Array([100, 100]),
	}
	var builder := SpriteFramesBuilder.new()
	var written := PackedStringArray(["invisible.png"])
	var frames := builder.build(jobs, written, strips_dir, contents, Vector2i(8, 8))
	_check.call(
		builder.errors.is_empty() and frames.get_animation_names().is_empty(),
		"a strip with no visible pixel gives no animation and does not fail the import",
		"%s %s" % [builder.errors, frames.get_animation_names()]
	)


## A frame as the sprite draws it. An AtlasTexture's image leaves its margin out, so the cell is
## rebuilt with the region placed where the margin puts it.
static func frame_image(texture: Texture2D) -> Image:
	var atlas := texture as AtlasTexture
	if atlas == null:
		var image := texture.get_image()
		image.convert(Image.FORMAT_RGBA8)
		return image
	if not _decoded.has(atlas.atlas):
		var decoded := atlas.atlas.get_image()
		decoded.convert(Image.FORMAT_RGBA8)
		_decoded[atlas.atlas] = decoded
	var sheet: Image = _decoded[atlas.atlas]
	return recompose(sheet, Rect2i(atlas.region), Rect2i(atlas.margin))


## The cell a region of [param sheet] fills once [param margin] gives the trimmed space back.
static func recompose(sheet: Image, region: Rect2i, margin: Rect2i) -> Image:
	var size := region.size + margin.size
	var cell := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	cell.blit_rect(sheet, region, margin.position)
	return cell

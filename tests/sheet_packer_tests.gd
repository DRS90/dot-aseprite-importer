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


## Synthetic strips through the packer: each row cut to the union of its frames, margins that give
## the cells back, and what it has to refuse.
func run() -> void:
	var cell := Vector2i(8, 8)
	# Three frames with pixels in different places, the middle one empty: the union is (2, 3) 4x4.
	var walk := Image.create_empty(24, 8, false, Image.FORMAT_RGBA8)
	walk.fill_rect(Rect2i(2, 3, 2, 2), Color.RED)
	walk.fill_rect(Rect2i(16 + 5, 6, 1, 1), Color.BLUE)
	# No alpha channel: every pixel is used, so nothing is cut.
	var opaque := Image.create_empty(16, 8, false, Image.FORMAT_RGB8)
	opaque.fill(Color.GREEN)
	var strips: Array[Dictionary] = [
		{"key": "walk", "image": walk}, {"key": "opaque", "image": opaque}
	]
	var packer := SheetPacker.new()
	var packed := packer.pack(strips, cell)
	var sheet: Image = packed.get("sheet")
	var cells: Dictionary = packed.get("cells", {})
	if not _check.call(
		packer.errors.is_empty() and sheet != null and cells.size() == 2,
		"the packer packs two strips",
		str(packer.errors)
	):
		return
	var walk_cells: Array[Dictionary] = cells["walk"]
	var opaque_cells: Array[Dictionary] = cells["opaque"]
	_check.call(
		(
			sheet.get_size() == Vector2i(16, 12)
			and sheet.get_format() == Image.FORMAT_RGBA8
			and walk_cells.size() == 3
			and walk_cells[1]["region"] == Rect2i(4, 0, 4, 4)
			and walk_cells[1]["margin"] == Rect2i(2, 3, 4, 4)
			and opaque_cells.size() == 2
			and opaque_cells[1]["region"] == Rect2i(8, 4, 8, 8)
			and opaque_cells[1]["margin"] == Rect2i()
		),
		"one row per strip, cut to the union of its frames, the widest row setting the width",
		"%s %s %s" % [sheet.get_size(), walk_cells, opaque_cells]
	)
	var rebuilt := 0
	for key: String in ["walk", "opaque"]:
		var strip := (walk if key == "walk" else opaque).duplicate() as Image
		strip.convert(Image.FORMAT_RGBA8)
		var entries: Array[Dictionary] = cells[key]
		for index: int in entries.size():
			var original := strip.get_region(Rect2i(Vector2i(index * cell.x, 0), cell))
			var entry := entries[index]
			if recompose(sheet, entry["region"], entry["margin"]).get_data() == original.get_data():
				rebuilt += 1
	_check.call(
		rebuilt == 5,
		"region and margin give every cell back, the empty frame included",
		"%d of 5" % rebuilt
	)

	# Color under alpha 0: Aseprite does not call it empty, but nothing of it is visible.
	var invisible := Image.create_empty(16, 8, false, Image.FORMAT_RGBA8)
	invisible.fill(Color(1.0, 0.0, 0.0, 0.0))
	var with_invisible: Array[Dictionary] = [
		{"key": "invisible", "image": invisible}, {"key": "walk", "image": walk}
	]
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


## The sheet may reach the texture limit on either axis, and not one pixel past it.
func _test_sheet_packer_limit(packer: SheetPacker) -> void:
	var cell := Vector2i(4, 4)
	var limit_cells := SheetPacker.MAX_TEXTURE_SIZE / cell.x
	var results := PackedStringArray()
	for cells_past: int in [0, 1]:
		var wide := Image.create_empty(
			cell.x * (limit_cells + cells_past), cell.y, false, Image.FORMAT_RGBA8
		)
		wide.fill(Color.WHITE)
		var wide_strips: Array[Dictionary] = [{"key": "wide", "image": wide}]
		var wide_packed := packer.pack(wide_strips, cell)
		results.append("wide+%d:%s" % [cells_past, "ok" if packer.errors.is_empty() else "refused"])
		var cell_image := Image.create_empty(cell.x, cell.y, false, Image.FORMAT_RGBA8)
		cell_image.fill(Color.WHITE)
		var tall_strips: Array[Dictionary] = []
		for index: int in limit_cells + cells_past:
			tall_strips.append({"key": "row_%d" % index, "image": cell_image})
		var tall_packed := packer.pack(tall_strips, cell)
		results.append("tall+%d:%s" % [cells_past, "ok" if packer.errors.is_empty() else "refused"])
		if cells_past == 1 and not (wide_packed.is_empty() and tall_packed.is_empty()):
			results.append("a refused sheet was still returned")
	_check.call(
		(
			results
			== PackedStringArray(["wide+0:ok", "tall+0:ok", "wide+1:refused", "tall+1:refused"])
		),
		(
			"a sheet of %d px is packed, one cell past it is refused on either axis"
			% SheetPacker.MAX_TEXTURE_SIZE
		),
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

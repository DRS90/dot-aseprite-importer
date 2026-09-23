extends SceneTree
## Headless test runner. Needs the Aseprite executable in the ASEPRITE_PATH environment variable:
##   ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
## Prints one PASS/FAIL line per check and exits with 1 when any check fails.

const AnimationSyncTests := preload("res://tests/animation_sync_tests.gd")
const SheetPackerTests := preload("res://tests/sheet_packer_tests.gd")
const AsepriteCli := preload("res://addons/aseprite_topdown_grid_animations/aseprite_cli.gd")
const AsepriteSource := preload("res://addons/aseprite_topdown_grid_animations/aseprite_source.gd")
const ExportPlanner := preload("res://addons/aseprite_topdown_grid_animations/export_planner.gd")
const SpriteFramesBuilder := preload(
	"res://addons/aseprite_topdown_grid_animations/sprite_frames_builder.gd"
)
const TextureImporter := preload(
	"res://addons/aseprite_topdown_grid_animations/texture_importer.gd"
)

const SOURCE := "res://examples/retro-top-down-character.aseprite"
## A second sprite, only used to prove the listing cache notices a file changing under it.
const SHADOW := "res://examples/shadow.aseprite"
const SHADOW_SIZE := Vector2i(48, 48)
const SHEETS_DIR := "res://examples/rpg-type-retro-top-down-playable-character-spritesheett"
const SHEET := SHEETS_DIR + "/16x16-rpg-topdown-playable-character-template.png"
const ATTACK_SHEET := SHEETS_DIR + "/48x48-attack.png"
const SPRITE_SIZE := Vector2i(144, 144)
const CELL_SIZE := Vector2i(48, 48)
const CHARACTER_SIZE := 16
const FRAME_COUNT := 44
## First sheet column of the slash tag, the only one with a sword effect.
const SLASH_FIRST := 32
const EXPECTED_LAYERS: Array[String] = ["character", "weapon"]
const EXPECTED_TAGS: Array[String] = [
	"walk_loop",
	"push_loop",
	"pull_loop",
	"carry_loop",
	"pickup",
	"throw",
	"use",
	"slash",
	"swim_loop",
	"climb_loop",
]
## Sheet row of every direction drawn in the example; its diagonal cells are empty.
const SHEET_ROWS := {"down": 0, "up": 1, "left": 2, "right": 3}
const DEFAULT_OPTIONS := {
	"cell_size": Vector2i.ZERO,
	"layer": "[all]",
	"layer_exclude_pattern": "^_",
	"tag_exclude_pattern": "^_",
	"animation_name": "{tag}_{direction}",
	"loop_suffix": "_loop",
}
const ASSET_HELP := (
	"The example is built from the CC0 sheets of 5yvalia with "
	+ "tests/tools/build_retro_example.lua; see docs/development.md."
)

var _failures := 0
var _tmp_dir := OS.get_cache_dir().path_join("aseprite_topdown_grid_animations_tests")


func _initialize() -> void:
	var missing := _missing_example_files()
	if missing.is_empty():
		_test_with_example_asset()
	else:
		print("SKIP: Aseprite checks, example files not found: %s" % ", ".join(missing))
		print("SKIP: " + ASSET_HELP)
	_test_example_scene_files()
	_test_planner_edge_cases()
	_test_builder()
	SheetPackerTests.new(_check).run()
	AnimationSyncTests.new(_check, get_root()).run()
	print("%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## Every file the demo scene points at has to exist and to be in git. On disk is not enough: a file
## added to examples/ but never committed works here and breaks for everyone else, which has now
## happened twice. An .aseprite also needs its .import committed, or a fresh clone reimports it with
## the default options instead of the ones the demo was built with.
func _test_example_scene_files() -> void:
	var scene := "res://examples/main.tscn"
	var text := FileAccess.get_file_as_string(scene)
	if not _check(text != "", "the demo scene is readable", scene):
		return
	var pattern := RegEx.new()
	pattern.compile('path="(res://[^"]+)"')
	var referenced := PackedStringArray()
	for match: RegExMatch in pattern.search_all(text):
		referenced.append(match.get_string(1))

	var missing := PackedStringArray()
	for path: String in referenced:
		if not FileAccess.file_exists(path):
			missing.append(path)
	_check(
		not referenced.is_empty() and missing.is_empty(),
		"every resource the demo scene references is on disk",
		"%d referenced, missing: %s" % [referenced.size(), missing]
	)

	var tracked := _tracked_files()
	if tracked.is_empty():
		print("SKIP: git has no file list here, so tracking is not checked")
		return
	var untracked := PackedStringArray()
	for path: String in referenced:
		var relative := path.trim_prefix("res://")
		if not tracked.has(relative):
			untracked.append(relative)
		# The import options are part of the example: without them the file imports as anything.
		var extension := path.get_extension().to_lower()
		if extension in ["aseprite", "ase"] and not tracked.has(relative + ".import"):
			untracked.append(relative + ".import")
	_check(
		untracked.is_empty(),
		"every resource the demo scene references is committed",
		"not in git: %s" % untracked
	)


## Paths git knows about, relative to the project, or empty when git cannot answer.
func _tracked_files() -> Dictionary:
	var root := ProjectSettings.globalize_path("res://")
	var output: Array = []
	if OS.execute("git", PackedStringArray(["-C", root, "ls-files"]), output) != 0:
		return {}
	var tracked := {}
	var listing := str(output[0]) if not output.is_empty() else ""
	for line: String in listing.replace("\r\n", "\n").split("\n", false):
		tracked[line.strip_edges()] = true
	return tracked


func _missing_example_files() -> PackedStringArray:
	var missing := PackedStringArray()
	for path: String in [SOURCE, SHADOW, SHEET, ATTACK_SHEET]:
		if not FileAccess.file_exists(path):
			missing.append(path)
	return missing


func _test_with_example_asset() -> void:
	var cli := AsepriteCli.new(OS.get_environment("ASEPRITE_PATH"))
	_check(cli.is_available(), "Aseprite executable available", cli.get_executable())
	if not cli.is_available():
		return
	var contents := _test_listing(cli)
	var planner := ExportPlanner.new()
	var jobs := _test_planner(planner, contents)
	var frames := _test_sprite_frames(cli, planner, jobs, contents)
	_test_directionless_export(cli, contents, frames)
	_test_export_rejects_bad_input(cli)
	_test_aseprite_source()
	_test_texture(cli, contents, frames)


## The texture importer's route: no grid, no tags, so one strip holds the whole canvas of every
## frame. It has to agree pixel for pixel with the grid import of the same file, survive being
## saved as a resource of its own, and refuse what it cannot represent.
func _test_texture(cli: AsepriteCli, contents: Dictionary, grid_frames: SpriteFrames) -> void:
	var planner := ExportPlanner.new()
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var options := {
		"directions": ExportPlanner.MODE_NONE,
		"cell_size": Vector2i.ZERO,
		"layer": ExportPlanner.ALL_LAYERS,
		"layer_exclude_pattern": "^_",
	}
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(), options)
	var strips_dir := _tmp_dir.path_join("texture")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		planner.cells_per_axis,
		strips_dir
	)
	if not _check(
		code == OK and cli.last_written.size() == 1,
		"the texture route exports the whole canvas as one strip",
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	):
		return
	var strip := strips_dir.path_join(str(jobs[0]["relative_path"]))
	var texture := SpriteFramesBuilder.load_strip_texture(strip, true)
	var expected_width := SPRITE_SIZE.x * FRAME_COUNT
	_check(
		texture != null and texture.get_size() == Vector2(expected_width, SPRITE_SIZE.y),
		"the strip is every frame of the timeline side by side",
		str(texture.get_size()) if texture != null else "no texture"
	)

	# The same source through both importers has to agree on the pixels it shares.
	var whole := texture.get_image()
	whole.convert(Image.FORMAT_RGBA8)
	var down := SheetPackerTests.frame_image(grid_frames.get_frame_texture(&"walk_down", 0))
	var cell := Rect2i(CELL_SIZE.x, CELL_SIZE.y * 2, CELL_SIZE.x, CELL_SIZE.y)
	_check(
		whole.get_region(cell).get_data() == down.get_data(),
		"the down cell of the texture is the grid import's walk_down frame",
		"%s vs %s" % [whole.get_size(), down.get_size()]
	)

	# Saved on its own, unlike the textures embedded in a SpriteFrames, and read back with pixels.
	var path := "user://aseprite_texture_roundtrip.res"
	_check(ResourceSaver.save(texture, path) == OK, "the texture saves as a resource of its own")
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	var back := reloaded.get_image() if reloaded != null else null
	if back != null:
		back.convert(Image.FORMAT_RGBA8)
	_check(
		reloaded != null and back != null and back.get_data() == whole.get_data(),
		"the reloaded texture still holds its pixels",
		str(reloaded)
	)
	DirAccess.remove_absolute(path)

	# An empty cell writes nothing and still returns OK: the case the importer turns into a failure.
	var empty_jobs: Array[Dictionary] = [
		{
			"direction": "left_up",
			"tag": "walk_loop",
			"animation": "empty",
			"loop": false,
			"relative_path": "empty.png",
		}
	]
	code = cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		empty_jobs,
		layers,
		CELL_SIZE,
		3,
		_tmp_dir.path_join("texture_empty")
	)
	_check(
		code == OK and cli.last_written.is_empty(),
		"a canvas with no pixels exports nothing without failing, so the importer must check",
		"%d written" % cli.last_written.size()
	)

	_check(
		(
			not TextureImporter.exceeds_texture_width(SPRITE_SIZE.x, FRAME_COUNT)
			and TextureImporter.exceeds_texture_width(SPRITE_SIZE.x, 114)
		),
		"a strip wider than a texture can be is refused",
		str(TextureImporter.MAX_TEXTURE_WIDTH)
	)


## The source shared by the importers: it verifies the executable, caches a listing by file content
## and hands out the layer dropdown. Headless, so the executable arrives as a Callable instead of
## from the Editor Settings.
func _test_aseprite_source() -> void:
	var source := AsepriteSource.new(func() -> String: return OS.get_environment("ASEPRITE_PATH"))
	var cli := source.verified_cli()
	if not _check(cli != null, "the shared source verifies the executable", source.last_error):
		return

	var first := source.list(cli, SOURCE)
	var second := source.list(cli, SOURCE)
	_check(
		is_same(first, second) and first.get("size", Vector2i.ZERO) == SPRITE_SIZE,
		"listing the same file twice returns the cached dictionary",
		str(first.get("size", Vector2i.ZERO))
	)

	# Keyed by content, not by path: a file replaced under the same name has to be listed again.
	var copy := "user://aseprite_source_copy.aseprite"
	DirAccess.copy_absolute(SOURCE, copy)
	var before: Vector2i = source.list(cli, copy).get("size", Vector2i.ZERO)
	DirAccess.copy_absolute(SHADOW, copy)
	var after: Vector2i = source.list(cli, copy).get("size", Vector2i.ZERO)
	DirAccess.remove_absolute(copy)
	_check(
		before == SPRITE_SIZE and after == SHADOW_SIZE,
		"a file replaced under the same path is listed again",
		"%s then %s" % [before, after]
	)

	_check(
		source.layer_choices(SOURCE) == "[all],character,weapon",
		"the layer dropdown offers [all] and the file's layers",
		source.layer_choices(SOURCE)
	)
	_check(
		source.layer_choices("") == "[all]",
		"without a file the dropdown offers [all] alone",
		source.layer_choices("")
	)


func _test_listing(cli: AsepriteCli) -> Dictionary:
	var contents := cli.list_contents(ProjectSettings.globalize_path(SOURCE))
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	_check(size == SPRITE_SIZE, "list_contents returns the size", "%s %s" % [size, cli.last_error])
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	_check(
		layers == PackedStringArray(EXPECTED_LAYERS), "list_contents returns layers", str(layers)
	)
	var visible: PackedStringArray = contents.get("visible_layers", PackedStringArray())
	_check(
		visible == PackedStringArray(EXPECTED_LAYERS),
		"list_contents returns visible layers",
		str(visible)
	)
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_contents returns 10 tags", str(tags))
	var ranges: Dictionary = contents.get("tag_ranges", {})
	_check(
		ranges.get("walk_loop", {}) == {"from": 0, "to": 3, "direction": "forward"},
		"list_contents returns tag ranges and directions",
		str(ranges)
	)
	var durations: PackedInt32Array = contents.get("frame_durations", PackedInt32Array())
	_check(
		durations.size() == FRAME_COUNT and durations.count(100) == FRAME_COUNT,
		"list_contents returns 44 frame durations of 100 ms",
		str(durations)
	)
	return contents


func _test_planner(planner: ExportPlanner, contents: Dictionary) -> Array[Dictionary]:
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	var jobs := planner.build_jobs(size, layers, tags, DEFAULT_OPTIONS)
	_check(jobs.size() == 80, "planner builds 8 directions x 10 tags", str(jobs.size()))
	_check(
		not planner.failed and planner.errors.is_empty(),
		"planner reports no errors",
		str(planner.errors)
	)
	_check(planner.cell_size == CELL_SIZE, "cell is a third of the sprite", str(planner.cell_size))
	_check(
		planner.composed_layers == PackedStringArray(EXPECTED_LAYERS),
		"every layer is composed",
		str(planner.composed_layers)
	)
	var walk := _find_job(jobs, "walk_down")
	_check(
		walk.get("tag") == "walk_loop" and walk.get("loop") == true,
		"walk_loop becomes the looping animation walk_down",
		str(walk)
	)
	var slash := _find_job(jobs, "slash_left")
	_check(
		slash.get("tag") == "slash" and slash.get("loop") == false,
		"slash keeps its name and does not loop",
		str(slash)
	)
	return jobs


## All 80 jobs in one Aseprite process, then the SpriteFrames: the diagonals and the sides of climb
## give no animation, and every frame matches the CC0 sheets the example was built from.
func _test_sprite_frames(
	cli: AsepriteCli, planner: ExportPlanner, jobs: Array[Dictionary], contents: Dictionary
) -> SpriteFrames:
	var strips_dir := _tmp_dir.path_join("strips")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		planner.cells_per_axis,
		strips_dir
	)
	_check(
		code == OK and cli.last_written.size() == 38,
		"export_strips writes 38 of 80 strips",
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	)
	var builder := SpriteFramesBuilder.new()
	var frames := builder.build(jobs, cli.last_written, strips_dir, contents, planner.cell_size)
	var names := frames.get_animation_names()
	_check(
		(
			builder.errors.is_empty()
			and names.size() == 38
			and not frames.has_animation(&"walk_left_up")
			and not frames.has_animation(&"climb_left")
		),
		"SpriteFrames has 38 animations, none for the empty cells",
		"%s %s" % [names, builder.errors]
	)
	if not frames.has_animation(&"walk_down"):
		_check(false, "SpriteFrames has walk_down", str(names))
		return frames
	_check(
		(
			frames.get_frame_count(&"walk_down") == 4
			and is_equal_approx(frames.get_animation_speed(&"walk_down"), 10.0)
			and frames.get_frame_duration(&"walk_down", 3) == 1.0
			and frames.get_animation_loop(&"walk_down")
			and frames.get_frame_count(&"use_left") == 8
			and not frames.get_animation_loop(&"slash_right")
		),
		"walk_down loops with 4 frames at 10 fps, use_left has 8, slash_right does not loop"
	)
	_test_shared_sheet(frames)
	_test_frames_match_sheets(frames, jobs, contents)
	return frames


## Every frame of every animation draws the same texture, so every sprite using the file does too,
## and it keeps the cell size.
func _test_shared_sheet(frames: SpriteFrames) -> void:
	var sheet: Texture2D = null
	var shared := true
	var clipped := true
	var cell_sized := true
	for animation: StringName in frames.get_animation_names():
		for index: int in frames.get_frame_count(animation):
			var atlas := frames.get_frame_texture(animation, index) as AtlasTexture
			if atlas == null:
				shared = false
				continue
			if sheet == null:
				sheet = atlas.atlas
			shared = shared and is_same(atlas.atlas, sheet)
			clipped = clipped and atlas.filter_clip
			cell_sized = cell_sized and atlas.get_size() == Vector2(CELL_SIZE)
	_check(
		sheet != null and shared and clipped and cell_sized,
		"every frame is a clipped, cell-sized region of one shared sheet",
		"shared %s, clipped %s, cell sized %s" % [shared, clipped, cell_sized]
	)


## The same file imported without directions: one animation per tag, made of whole frames. The down
## cell of those frames has to be the very image the 3x3 grid gives for walk_down, which is what
## proves the crop starts at the top left corner.
func _test_directionless_export(
	cli: AsepriteCli, contents: Dictionary, grid_frames: SpriteFrames
) -> void:
	var whole := _build_without_directions(cli, contents, Vector2i.ZERO, "no_directions")
	if whole == null:
		return
	var names := whole.get_animation_names()
	var texture := whole.get_frame_texture(&"walk", 0) as AtlasTexture
	var frame_size := texture.get_size() if texture != null else Vector2.ZERO
	_check(
		(
			names.size() == 10
			and whole.has_animation(&"walk")
			and whole.get_frame_count(&"walk") == 4
			and whole.get_animation_loop(&"walk")
			and frame_size == Vector2(SPRITE_SIZE)
		),
		"10 animations of whole 144x144 frames, walk_loop still loops as walk",
		"%s %s" % [names, frame_size]
	)
	_check_down_cell_matches(whole, grid_frames, "the whole frame")

	# A cell smaller than the sprite crops its top left corner, keeping the down cell in place.
	var cropped := _build_without_directions(
		cli, contents, Vector2i(SPRITE_SIZE.x * 2 / 3, SPRITE_SIZE.y), "no_directions_cropped"
	)
	if cropped != null:
		_check_down_cell_matches(cropped, grid_frames, "a cell cropped to two thirds")


## Exports the example with grid/directions = none and builds its SpriteFrames, or null on failure.
func _build_without_directions(
	cli: AsepriteCli, contents: Dictionary, cell: Vector2i, folder: String
) -> SpriteFrames:
	var options := DEFAULT_OPTIONS.duplicate()
	options["directions"] = ExportPlanner.MODE_NONE
	options["cell_size"] = cell
	var planner := ExportPlanner.new()
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var strips_dir := _tmp_dir.path_join(folder)
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		planner.cells_per_axis,
		strips_dir
	)
	if not _check(
		code == OK and cli.last_written.size() == 10,
		"export_strips writes one strip per tag for a %s cell" % planner.cell_size,
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	):
		return null
	var builder := SpriteFramesBuilder.new()
	return builder.build(jobs, cli.last_written, strips_dir, contents, planner.cell_size)


## Every frame of walk cut down to the down cell has to equal the walk_down frame of the 3x3 import.
func _check_down_cell_matches(
	whole: SpriteFrames, grid_frames: SpriteFrames, description: String
) -> void:
	if not whole.has_animation(&"walk") or not grid_frames.has_animation(&"walk_down"):
		_check(false, "both imports have the walk animation", description)
		return
	var down := Rect2i(CELL_SIZE.x, CELL_SIZE.y * 2, CELL_SIZE.x, CELL_SIZE.y)
	var matching := 0
	var count := whole.get_frame_count(&"walk")
	for index: int in count:
		var frame := SheetPackerTests.frame_image(whole.get_frame_texture(&"walk", index))
		var expected := SheetPackerTests.frame_image(
			grid_frames.get_frame_texture(&"walk_down", index)
		)
		if frame.get_region(down).get_data() == expected.get_data():
			matching += 1
	_check(
		count == 4 and matching == count,
		"the down cell of %s is the 3x3 walk_down frame" % description,
		"%d of %d" % [matching, count]
	)


func _test_frames_match_sheets(
	frames: SpriteFrames, jobs: Array[Dictionary], contents: Dictionary
) -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	var attack := Image.load_from_file(ProjectSettings.globalize_path(ATTACK_SHEET))
	sheet.convert(Image.FORMAT_RGBA8)
	attack.convert(Image.FORMAT_RGBA8)
	var ranges: Dictionary = contents.get("tag_ranges", {})
	var checked := 0
	var matching := 0
	for job: Dictionary in jobs:
		var animation := StringName(str(job["animation"]))
		var direction: String = job["direction"]
		if not frames.has_animation(animation) or not SHEET_ROWS.has(direction):
			continue
		var tag_range: Dictionary = ranges[job["tag"]]
		var first: int = tag_range["from"]
		var row: int = SHEET_ROWS[direction]
		for index: int in frames.get_frame_count(animation):
			var frame := SheetPackerTests.frame_image(frames.get_frame_texture(animation, index))
			checked += 1
			if frame.get_data() == _expected_frame(sheet, attack, first + index, row).get_data():
				matching += 1
	_check(
		checked == 168 and matching == checked,
		"every frame matches the sheets the example was built from",
		"%d of %d" % [matching, checked]
	)


## The cell the example should hold for one sheet column and row: the character centered, plus the
## sword effect of the slash columns.
func _expected_frame(sheet: Image, attack: Image, column: int, row: int) -> Image:
	var expected := Image.create_empty(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	var character := sheet.get_region(
		Rect2i(column * CHARACTER_SIZE, row * CHARACTER_SIZE, CHARACTER_SIZE, CHARACTER_SIZE)
	)
	var offset := (CELL_SIZE.x - CHARACTER_SIZE) / 2
	expected.blit_rect(
		character, Rect2i(0, 0, CHARACTER_SIZE, CHARACTER_SIZE), Vector2i(offset, offset)
	)
	var effect_column := column - SLASH_FIRST
	if effect_column >= 0 and (effect_column + 1) * CELL_SIZE.x <= attack.get_width():
		var effect := attack.get_region(
			Rect2i(effect_column * CELL_SIZE.x, row * CELL_SIZE.y, CELL_SIZE.x, CELL_SIZE.y)
		)
		expected.blend_rect(effect, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i.ZERO)
	return expected


func _test_export_rejects_bad_input(cli: AsepriteCli) -> void:
	var layers := PackedStringArray(["character"])
	var ghost := PackedStringArray(["ghost"])
	_expect_rejected(
		cli, "an unknown layer", ghost, CELL_SIZE, 3, "walk_loop", "up", "unknown layer 'ghost'"
	)
	_expect_rejected(
		cli, "an unknown tag", layers, CELL_SIZE, 3, "nope", "up", "unknown tag 'nope'"
	)
	_expect_rejected(
		cli,
		"an unknown direction",
		layers,
		CELL_SIZE,
		3,
		"walk_loop",
		"center",
		"unknown direction"
	)
	_expect_rejected(
		cli, "a cell too big", layers, Vector2i(50, 48), 3, "walk_loop", "up", "does not fit"
	)
	# The grid and the direction have to agree, or a crop outside the sprite would pass silently.
	_expect_rejected(
		cli,
		"a named direction without a grid",
		layers,
		SPRITE_SIZE,
		1,
		"walk_loop",
		"up",
		"does not belong to a grid of 1x1"
	)
	_expect_rejected(
		cli,
		"a nameless direction in a 3x3 grid",
		layers,
		CELL_SIZE,
		3,
		"walk_loop",
		"",
		"does not belong to a grid of 3x3"
	)
	_expect_rejected(cli, "a grid of 2", layers, CELL_SIZE, 2, "walk_loop", "up", "cells per axis")


func _expect_rejected(
	cli: AsepriteCli,
	description: String,
	layers: PackedStringArray,
	cell: Vector2i,
	cells_per_axis: int,
	tag: String,
	direction: String,
	expected_error: String
) -> void:
	var jobs: Array[Dictionary] = [
		{
			"direction": direction,
			"tag": tag,
			"animation": "rejected",
			"loop": false,
			"relative_path": "rejected.png",
		}
	]
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		layers,
		cell,
		cells_per_axis,
		_tmp_dir.path_join("rejected")
	)
	_check(
		code != OK and cli.last_error.contains(expected_error),
		"export_strips rejects " + description,
		cli.last_error
	)


func _test_planner_edge_cases() -> void:
	var planner := ExportPlanner.new()
	var layers := PackedStringArray(["body", "_guide", "fx"])
	var tags := PackedStringArray(EXPECTED_TAGS)

	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"[all] composes every layer not excluded",
		str(planner.composed_layers)
	)

	var options := DEFAULT_OPTIONS.duplicate()
	options["tag_exclude_pattern"] = "^(push_loop|pull_loop)$"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(jobs.size() == 64, "tag exclude pattern removes 2 tags", str(jobs.size()))

	jobs = planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(), DEFAULT_OPTIONS)
	_check(
		jobs.size() == 8 and _find_job(jobs, "up").get("tag") == "",
		"no tags: one animation per direction named after it",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)

	options = DEFAULT_OPTIONS.duplicate()
	options["animation_name"] = "{direction}"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.is_empty() and planner.failed and planner.errors.size() == 72,
		"a name template without {tag} collides and fails the import",
		"%d jobs, %d errors" % [jobs.size(), planner.errors.size()]
	)

	var same_names := PackedStringArray(["idle", "idle_loop"])
	jobs = planner.build_jobs(SPRITE_SIZE, layers, same_names, DEFAULT_OPTIONS)
	_check(
		(
			jobs.is_empty()
			and planner.failed
			and planner.errors.size() == 8
			and planner.errors[0].contains("already used by tag 'idle' (left_up)")
		),
		"idle and idle_loop give the same name: the import fails naming both tags",
		str(planner.errors)
	)

	jobs = planner.build_jobs(
		SPRITE_SIZE, layers, PackedStringArray(["attack/heavy"]), DEFAULT_OPTIONS
	)
	_check(
		not _find_job(jobs, "attack_heavy_up").is_empty(),
		"characters invalid in animation names become _",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)
	_test_loop_suffix(planner, layers)
	_test_layer_choice(planner, layers, tags)
	_test_cell_size(planner, layers, tags)
	_test_directionless_planner(planner, layers, tags)


func _test_directionless_planner(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["directions"] = ExportPlanner.MODE_NONE
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var walk := _find_job(jobs, "walk")
	_check(
		(
			jobs.size() == 10
			and not planner.failed
			and planner.cells_per_axis == 1
			and planner.cell_size == SPRITE_SIZE
			and walk.get("direction") == ""
			and walk.get("loop") == true
		),
		"without directions the frame is one cell and each tag is one animation",
		"%d jobs, cell %s, %s" % [jobs.size(), planner.cell_size, walk]
	)

	jobs = planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(["run__fast"]), options)
	_check(
		not _find_job(jobs, "run__fast").is_empty(),
		"dropping {direction} leaves the separators inside a tag name alone",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)

	jobs = planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(), options)
	_check(
		jobs.size() == 1 and not _find_job(jobs, ExportPlanner.DEFAULT_ANIMATION).is_empty(),
		"neither tags nor directions to name it after: one animation called default",
		str(jobs)
	)

	jobs = planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(), DEFAULT_OPTIONS)
	_check(
		jobs.size() == 8 and _find_job(jobs, ExportPlanner.DEFAULT_ANIMATION).is_empty(),
		"the fallback name never replaces a direction in a 3x3 grid",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)

	options["cell_size"] = Vector2i(200, 48)
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.is_empty()
			and planner.failed
			and planner.cell_size == Vector2i.ZERO
			and not planner.errors[0].contains("3x3")
		),
		"a cell bigger than the sprite fails without mentioning a 3x3 grid",
		str(planner.errors)
	)

	options["cell_size"] = Vector2i.ZERO
	jobs = planner.build_jobs(Vector2i(145, 144), layers, tags, options)
	_check(
		jobs.size() == 10 and not planner.failed and planner.cell_size == Vector2i(145, 144),
		"a size that is not a multiple of 3 is fine without directions",
		str(planner.cell_size)
	)

	options["directions"] = "4x4"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.is_empty()
			and planner.failed
			and planner.cells_per_axis == 0
			and planner.errors.size() == 1
			and planner.errors[0].contains("'4x4'")
		),
		"an unknown grid fails instead of falling back to 3x3",
		str(planner.errors)
	)


func _test_loop_suffix(planner: ExportPlanner, layers: PackedStringArray) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["loop_suffix"] = "_repeat"
	var tags := PackedStringArray(["idle_repeat", "run_loop"])
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var idle := _find_job(jobs, "idle_up")
	var run := _find_job(jobs, "run_loop_up")
	_check(
		idle.get("loop") == true and run.get("loop") == false,
		"a custom loop suffix decides the loop and leaves other suffixes in the name",
		"%s %s" % [idle, run]
	)

	options["loop_suffix"] = ""
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var plain := _find_job(jobs, "idle_repeat_up")
	_check(
		plain.get("loop") == false and _find_job(jobs, "run_loop_up").get("loop") == false,
		"an empty loop suffix loops nothing and keeps the tag names",
		str(plain)
	)


func _test_layer_choice(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["layer"] = ""
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"an empty layer choice means [all]",
		str(planner.composed_layers)
	)

	options["layer"] = "fx"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.size() == 80
			and planner.errors.is_empty()
			and planner.composed_layers == PackedStringArray(["fx"])
		),
		"a chosen layer is composed alone",
		str(planner.composed_layers)
	)

	options["layer"] = "_guide"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["_guide"]),
		"an excluded layer can still be chosen",
		str(planner.composed_layers)
	)

	options["layer"] = "ghost"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.is_empty() and planner.failed and planner.errors.size() == 2,
		"an unknown chosen layer fails",
		str(planner.errors)
	)

	options["layer"] = "[all]"
	options["layer_exclude_pattern"] = "."
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(jobs.is_empty() and planner.failed, "every layer excluded fails", str(planner.errors))


func _test_cell_size(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["cell_size"] = CELL_SIZE
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.cell_size == CELL_SIZE,
		"explicit cell size equal to the default",
		str(planner.cell_size)
	)

	options["cell_size"] = Vector2i(40, 0)
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.cell_size == Vector2i(40, 48),
		"smaller cell width, 0 height is a third",
		str(planner.cell_size)
	)

	for cell: Vector2i in [Vector2i(50, 48), Vector2i(-1, 48), Vector2i(48, 49)]:
		options["cell_size"] = cell
		jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
		_check(
			jobs.is_empty() and planner.failed and planner.cell_size == Vector2i.ZERO,
			"cell size %s does not fit" % cell,
			str(planner.errors)
		)

	jobs = planner.build_jobs(Vector2i(145, 144), layers, tags, DEFAULT_OPTIONS)
	_check(
		(
			jobs.is_empty()
			and planner.failed
			and planner.errors[0].contains("grid/cell_size")
			and planner.errors[0].contains(ExportPlanner.MODE_NONE)
		),
		"a size that is not a multiple of 3 fails naming both ways out",
		str(planner.errors)
	)


func _test_builder() -> void:
	var sequences := {
		"forward": PackedInt32Array([2, 3, 4, 5]),
		"reverse": PackedInt32Array([5, 4, 3, 2]),
		"pingpong": PackedInt32Array([2, 3, 4, 5, 4, 3]),
		"pingpong_reverse": PackedInt32Array([5, 4, 3, 2, 3, 4]),
	}
	for direction: String in sequences:
		var sequence := SpriteFramesBuilder.frame_sequence(2, 5, direction)
		_check(sequence == sequences[direction], direction + " frame sequence", str(sequence))
	var single := SpriteFramesBuilder.frame_sequence(3, 3, "pingpong")
	_check(single == PackedInt32Array([3]), "ping-pong of one frame plays it once", str(single))

	var timing := SpriteFramesBuilder.timing(PackedInt32Array([150, 50, 100]))
	var speed: float = timing["speed"]
	_check(
		is_equal_approx(speed, 20.0) and timing["durations"] == PackedFloat32Array([3.0, 1.0, 2.0]),
		"timing: speed is 1 / the shortest duration, durations are relative to it",
		str(timing)
	)
	_test_builder_ping_pong()


## A ping-pong tag over timeline frames 1 to 3 of a synthetic strip: cells are reused in the
## sequence 1 2 3 2, each frame keeps its Aseprite duration relative to the shortest one.
func _test_builder_ping_pong() -> void:
	var strips_dir := _tmp_dir.path_join("synthetic")
	DirAccess.make_dir_recursive_absolute(strips_dir)
	var strip := Image.create_empty(12, 4, false, Image.FORMAT_RGBA8)
	for index: int in 3:
		strip.fill_rect(Rect2i(index * 4, 0, 4, 4), Color(index / 2.0, 0.0, 0.0))
	strip.save_png(strips_dir.path_join("strip_000.png"))
	var jobs: Array[Dictionary] = [
		{
			"direction": "up",
			"tag": "bounce_loop",
			"animation": "bounce_up",
			"loop": true,
			"relative_path": "strip_000.png",
		}
	]
	var contents := {
		"tag_ranges": {"bounce_loop": {"from": 1, "to": 3, "direction": "pingpong"}},
		"frame_durations": PackedInt32Array([100, 100, 100, 200]),
	}
	var builder := SpriteFramesBuilder.new()
	var written := PackedStringArray(["strip_000.png"])
	var frames := builder.build(jobs, written, strips_dir, contents, Vector2i(4, 4))
	var regions: Array[float] = []
	var durations: Array[float] = []
	for index: int in frames.get_frame_count(&"bounce_up"):
		var atlas := frames.get_frame_texture(&"bounce_up", index) as AtlasTexture
		regions.append(atlas.region.position.x)
		durations.append(frames.get_frame_duration(&"bounce_up", index))
	_check(
		(
			builder.errors.is_empty()
			and regions == [0.0, 4.0, 8.0, 4.0]
			and frames.get_frame_texture(&"bounce_up", 0).get_size() == Vector2(4, 4)
			and durations == [1.0, 1.0, 2.0, 1.0]
			and frames.get_animation_loop(&"bounce_up")
			and is_equal_approx(frames.get_animation_speed(&"bounce_up"), 10.0)
		),
		"ping-pong animation reuses cells with Aseprite durations",
		"%s %s %s" % [regions, durations, builder.errors]
	)


func _find_job(jobs: Array[Dictionary], animation: String) -> Dictionary:
	for job: Dictionary in jobs:
		if job["animation"] == animation:
			return job
	return {}


## True when the check passed, so a test can stop instead of reporting the same failure again.
func _check(condition: bool, description: String, detail: String = "") -> bool:
	if condition:
		print("PASS: " + description)
		return true
	_failures += 1
	print("FAIL: %s (%s)" % [description, detail])
	return false

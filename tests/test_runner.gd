extends SceneTree
## Headless test runner. Needs the Aseprite executable in the ASEPRITE_PATH environment variable:
##   ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
## Prints one PASS/FAIL line per check and exits with 1 when any check fails.

const AsepriteCli := preload("res://addons/aseprite_topdown_layers/aseprite_cli.gd")
const ExportPlanner := preload("res://addons/aseprite_topdown_layers/export_planner.gd")
const SpriteFramesBuilder := preload(
	"res://addons/aseprite_topdown_layers/sprite_frames_builder.gd"
)

const SOURCE := "res://examples/character/character-matrix/character-matrix.aseprite"
const SPRITE_SIZE := Vector2i(144, 192)
const CELL_SIZE := Vector2i(48, 64)
const FRAME_COUNT := 40
const EXPECTED_DIR := "res://tests/expected/idle_loop"
const EXPECTED_LAYERS: Array[String] = ["default"]
const EXPECTED_TAGS: Array[String] = ["idle_loop", "walk", "death", "dash", "jump"]
## Directions drawn in the example; its left and right cells are empty.
const DRAWN_DIRECTIONS: Array[String] = [
	"left_up", "up", "right_up", "left_down", "down", "right_down"
]
const DEFAULT_OPTIONS := {
	"cell_size": Vector2i.ZERO,
	"layer": "[all]",
	"layer_exclude_pattern": "^_",
	"tag_exclude_pattern": "^_",
	"animation_name": "{tag}_{direction}",
	"loop_suffix": "_loop",
}
const ASSET_HELP := (
	"See README > Credits to build "
	+ "examples/character/character-matrix/character-matrix.aseprite and the reference strips in "
	+ "tests/expected/idle_loop/."
)

var _failures := 0
var _tmp_dir := OS.get_cache_dir().path_join("aseprite_topdown_layers_tests")


func _initialize() -> void:
	var missing := _missing_example_files()
	if missing.is_empty():
		_test_with_example_asset()
	else:
		print("SKIP: Aseprite checks, example asset not found: %s" % ", ".join(missing))
		print("SKIP: " + ASSET_HELP)
	_test_planner_edge_cases()
	_test_builder()
	print("%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _missing_example_files() -> PackedStringArray:
	var missing := PackedStringArray()
	if not FileAccess.file_exists(SOURCE):
		missing.append(SOURCE)
	for direction: String in DRAWN_DIRECTIONS:
		var expected := _expected_strip(direction)
		if not FileAccess.file_exists(expected):
			missing.append(expected)
	return missing


func _test_with_example_asset() -> void:
	var cli := AsepriteCli.new(OS.get_environment("ASEPRITE_PATH"))
	_check(cli.is_available(), "Aseprite executable available", cli.get_executable())
	if not cli.is_available():
		return
	var contents := _test_listing(cli)
	var planner := ExportPlanner.new()
	var jobs := _test_planner(planner, contents)
	_test_sprite_frames(cli, planner, jobs, contents)
	_test_export_rejects_bad_input(cli)


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
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_contents returns 5 tags", str(tags))
	var ranges: Dictionary = contents.get("tag_ranges", {})
	_check(
		ranges.get("walk", {}) == {"from": 8, "to": 15, "direction": "forward"},
		"list_contents returns tag ranges and directions",
		str(ranges)
	)
	var durations: PackedInt32Array = contents.get("frame_durations", PackedInt32Array())
	_check(
		durations.size() == FRAME_COUNT and durations.count(100) == FRAME_COUNT,
		"list_contents returns 40 frame durations of 100 ms",
		str(durations)
	)
	return contents


func _test_planner(planner: ExportPlanner, contents: Dictionary) -> Array[Dictionary]:
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	var jobs := planner.build_jobs(size, layers, tags, DEFAULT_OPTIONS)
	_check(jobs.size() == 40, "planner builds 8 directions x 5 tags", str(jobs.size()))
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
	var walk := _find_job(jobs, "walk_right_down")
	_check(
		(
			walk.get("tag") == "walk"
			and walk.get("direction") == "right_down"
			and walk.get("loop") == false
		),
		"walk right_down becomes the animation walk_right_down, not looping",
		str(walk)
	)
	var idle := _find_job(jobs, "idle_up")
	_check(
		idle.get("tag") == "idle_loop" and idle.get("loop") == true,
		"idle_loop becomes the looping animation idle_up",
		str(idle)
	)
	return jobs


## All 40 jobs in one Aseprite process, then the SpriteFrames: the empty left and right cells give
## no animation, and every idle frame matches the layer-per-direction reference strips.
func _test_sprite_frames(
	cli: AsepriteCli, planner: ExportPlanner, jobs: Array[Dictionary], contents: Dictionary
) -> void:
	var strips_dir := _tmp_dir.path_join("strips")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		strips_dir
	)
	_check(
		code == OK and cli.last_written.size() == 30,
		"export_strips writes 30 of 40 strips",
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	)
	var builder := SpriteFramesBuilder.new()
	var frames := builder.build(jobs, cli.last_written, strips_dir, contents, planner.cell_size)
	var names := frames.get_animation_names()
	_check(
		builder.errors.is_empty() and names.size() == 30 and not frames.has_animation(&"idle_left"),
		"SpriteFrames has 30 animations and none for the empty cells",
		"%s %s" % [names, builder.errors]
	)
	if not frames.has_animation(&"idle_down") or not frames.has_animation(&"walk_down"):
		_check(false, "SpriteFrames has idle_down and walk_down", str(names))
		return
	_check(
		(
			frames.get_frame_count(&"idle_down") == 8
			and is_equal_approx(frames.get_animation_speed(&"idle_down"), 10.0)
			and frames.get_frame_duration(&"idle_down", 7) == 1.0
			and frames.get_animation_loop(&"idle_down")
			and not frames.get_animation_loop(&"walk_down")
		),
		"idle_down has 8 frames at 10 fps and loops; walk_down does not loop"
	)
	var matching := 0
	for direction: String in DRAWN_DIRECTIONS:
		var reference := Image.load_from_file(
			ProjectSettings.globalize_path(_expected_strip(direction))
		)
		reference.convert(Image.FORMAT_RGBA8)
		var animation := StringName("idle_" + direction)
		for index: int in frames.get_frame_count(animation):
			var frame := frames.get_frame_texture(animation, index).get_image()
			frame.convert(Image.FORMAT_RGBA8)
			var cell := Rect2i(index * CELL_SIZE.x, 0, CELL_SIZE.x, CELL_SIZE.y)
			if frame.get_data() == reference.get_region(cell).get_data():
				matching += 1
	_check(matching == 48, "idle frames match the reference strips", "%d of 48" % matching)


func _test_export_rejects_bad_input(cli: AsepriteCli) -> void:
	var layers := PackedStringArray(EXPECTED_LAYERS)
	var ghost := PackedStringArray(["ghost"])
	_expect_rejected(
		cli, "an unknown layer", ghost, CELL_SIZE, "walk", "up", "unknown layer 'ghost'"
	)
	_expect_rejected(cli, "an unknown tag", layers, CELL_SIZE, "nope", "up", "unknown tag 'nope'")
	_expect_rejected(
		cli, "an unknown direction", layers, CELL_SIZE, "walk", "center", "unknown direction"
	)
	_expect_rejected(cli, "a cell too big", layers, Vector2i(50, 64), "walk", "up", "does not fit")


func _expect_rejected(
	cli: AsepriteCli,
	description: String,
	layers: PackedStringArray,
	cell: Vector2i,
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
		ProjectSettings.globalize_path(SOURCE), jobs, layers, cell, _tmp_dir.path_join("rejected")
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
		jobs.size() == 40 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"[all] composes every layer not excluded",
		str(planner.composed_layers)
	)

	var options := DEFAULT_OPTIONS.duplicate()
	options["tag_exclude_pattern"] = "^(walk|jump)$"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(jobs.size() == 24, "tag exclude pattern removes 2 tags", str(jobs.size()))

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
		jobs.size() == 8 and planner.errors.size() == 32,
		"animation names used twice are skipped and reported",
		"%d jobs, %d errors" % [jobs.size(), planner.errors.size()]
	)

	jobs = planner.build_jobs(
		SPRITE_SIZE, layers, PackedStringArray(["idle", "idle_loop"]), DEFAULT_OPTIONS
	)
	_check(
		jobs.size() == 8 and planner.errors.size() == 8,
		"idle and idle_loop give the same names: the second is reported",
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
		jobs.size() == 40 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"an empty layer choice means [all]",
		str(planner.composed_layers)
	)

	options["layer"] = "fx"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.size() == 40
			and planner.errors.is_empty()
			and planner.composed_layers == PackedStringArray(["fx"])
		),
		"a chosen layer is composed alone",
		str(planner.composed_layers)
	)

	options["layer"] = "_guide"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 40 and planner.composed_layers == PackedStringArray(["_guide"]),
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
		jobs.size() == 40 and planner.cell_size == CELL_SIZE,
		"explicit cell size equal to the default",
		str(planner.cell_size)
	)

	options["cell_size"] = Vector2i(40, 0)
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 40 and planner.cell_size == Vector2i(40, 64),
		"smaller cell width, 0 height is a third",
		str(planner.cell_size)
	)

	for cell: Vector2i in [Vector2i(50, 64), Vector2i(-1, 64), Vector2i(48, 65)]:
		options["cell_size"] = cell
		jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
		_check(
			jobs.is_empty() and planner.failed and planner.cell_size == Vector2i.ZERO,
			"cell size %s does not fit" % cell,
			str(planner.errors)
		)

	jobs = planner.build_jobs(Vector2i(145, 192), layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.is_empty() and planner.failed,
		"default cell needs a size multiple of 3",
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
			and durations == [1.0, 1.0, 2.0, 1.0]
			and frames.get_animation_loop(&"bounce_up")
			and is_equal_approx(frames.get_animation_speed(&"bounce_up"), 10.0)
		),
		"ping-pong animation reuses cells with Aseprite durations",
		"%s %s %s" % [regions, durations, builder.errors]
	)


func _expected_strip(direction: String) -> String:
	return EXPECTED_DIR.path_join("character_%s_idle_loop.png" % direction)


func _find_job(jobs: Array[Dictionary], animation: String) -> Dictionary:
	for job: Dictionary in jobs:
		if job["animation"] == animation:
			return job
	return {}


func _check(condition: bool, description: String, detail: String = "") -> void:
	if condition:
		print("PASS: " + description)
		return
	_failures += 1
	print("FAIL: %s (%s)" % [description, detail])

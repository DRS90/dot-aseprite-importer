extends SceneTree
## Headless test runner. Needs the Aseprite executable in the ASEPRITE_PATH environment variable:
##   ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
## Prints one PASS/FAIL line per check and exits with 1 when any check fails.

const AsepriteCli := preload("res://addons/aseprite_topdown_layers/aseprite_cli.gd")
const ExportPlanner := preload("res://addons/aseprite_topdown_layers/export_planner.gd")

const SOURCE := "res://examples/character/character-matrix/character-matrix.aseprite"
const TITLE := "character-matrix"
const SPRITE_SIZE := Vector2i(144, 192)
const CELL_SIZE := Vector2i(48, 64)
const EXPECTED_DIR := "res://tests/expected/idle_loop"
const EXPECTED_LAYERS: Array[String] = ["default"]
const EXPECTED_TAGS: Array[String] = ["idle_loop", "walk", "death", "dash", "jump"]
## Directions drawn in the example; its left and right cells are empty.
const DRAWN_DIRECTIONS: Array[String] = [
	"left_up", "up", "right_up", "left_down", "down", "right_down"
]
const STRIP_SIZE := Vector2i(384, 64)
const DEFAULT_OPTIONS := {
	"cell_size": Vector2i.ZERO,
	"layer_include": "",
	"layer_exclude_pattern": "^_",
	"tag_exclude_pattern": "^_",
	"output_folder": "assets/{tag}",
	"filename": "{title}_{direction}_{tag}",
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
	_test_export_strips(cli, planner, jobs)
	_test_vertical_strip(cli, planner, jobs)
	_test_export_rejects_bad_input(cli)


func _test_listing(cli: AsepriteCli) -> Dictionary:
	var source := ProjectSettings.globalize_path(SOURCE)
	var contents := cli.list_contents(source, false)
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	_check(size == SPRITE_SIZE, "list_contents returns the size", "%s %s" % [size, cli.last_error])
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	_check(
		layers == PackedStringArray(EXPECTED_LAYERS), "list_contents returns layers", str(layers)
	)
	var visible: PackedStringArray = cli.list_contents(source, true).get(
		"layers", PackedStringArray()
	)
	_check(
		visible == PackedStringArray(EXPECTED_LAYERS), "list_contents only_visible", str(visible)
	)
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_contents returns 5 tags", str(tags))
	return contents


func _test_planner(planner: ExportPlanner, contents: Dictionary) -> Array[Dictionary]:
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	var jobs := planner.build_jobs(TITLE, size, layers, tags, DEFAULT_OPTIONS)
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
	var job := _find_job(jobs, "assets/walk/character-matrix_right_down_walk.png")
	_check(
		not job.is_empty() and job["direction"] == "right_down" and job["tag"] == "walk",
		"job fields: right_down walk",
		str(job)
	)
	return jobs


## All 40 jobs in one Aseprite process: the drawn directions are written for every tag, and their
## idle_loop strips match the layer-per-direction reference strips byte for byte. The empty left
## and right cells write nothing.
func _test_export_strips(cli: AsepriteCli, planner: ExportPlanner, jobs: Array[Dictionary]) -> void:
	var output_dir := _tmp_dir.path_join("batch")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		"horizontal",
		output_dir
	)
	_check(
		code == OK and cli.last_written.size() == 30,
		"export_strips writes 30 of 40 strips",
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	)
	for job: Dictionary in jobs:
		var direction: String = job["direction"]
		var tag: String = job["tag"]
		var relative_path: String = job["relative_path"]
		var exported := output_dir.path_join(relative_path)
		if not DRAWN_DIRECTIONS.has(direction):
			_check(
				not cli.last_written.has(relative_path) and not FileAccess.file_exists(exported),
				"empty cell writes nothing: " + relative_path.get_file()
			)
			continue
		_check(cli.last_written.has(relative_path), "strip written: " + relative_path.get_file())
		if tag == "idle_loop":
			var actual_md5 := FileAccess.get_md5(exported)
			var expected_md5 := FileAccess.get_md5(_expected_strip(direction))
			_check(
				actual_md5 == expected_md5 and expected_md5 != "",
				"MD5 matches expected: " + relative_path.get_file(),
				"%s vs %s" % [actual_md5, expected_md5]
			)
			continue
		var size := _image_size(exported)
		_check(size == STRIP_SIZE, "strip is 384x64: " + relative_path.get_file(), str(size))


func _test_vertical_strip(
	cli: AsepriteCli, planner: ExportPlanner, jobs: Array[Dictionary]
) -> void:
	var relative_path := "assets/walk/character-matrix_down_walk.png"
	var job := _find_job(jobs, relative_path)
	if job.is_empty():
		_check(false, "vertical strip job exists", relative_path)
		return
	var vertical_jobs: Array[Dictionary] = [job]
	var output_dir := _tmp_dir.path_join("vertical")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		vertical_jobs,
		planner.composed_layers,
		planner.cell_size,
		"vertical",
		output_dir
	)
	var size := _image_size(output_dir.path_join(relative_path))
	_check(
		code == OK and size == Vector2i(48, 512),
		"vertical strip is 48x512",
		"%s %s" % [size, cli.last_error]
	)


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
		{"direction": direction, "tag": tag, "relative_path": "rejected.png"}
	]
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		layers,
		cell,
		"horizontal",
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

	var jobs := planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.size() == 40 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"default composes every layer not excluded",
		str(planner.composed_layers)
	)

	var options := DEFAULT_OPTIONS.duplicate()
	options["tag_exclude_pattern"] = "^(walk|jump)$"
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(jobs.size() == 24, "tag exclude pattern removes 2 tags", str(jobs.size()))

	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, PackedStringArray(), DEFAULT_OPTIONS)
	var untagged := _find_job(jobs, "assets/character-matrix_up.png")
	_check(jobs.size() == 8 and not untagged.is_empty(), "no tags: one strip per direction")

	options = DEFAULT_OPTIONS.duplicate()
	options["output_folder"] = "sprites"
	options["filename"] = "{direction}"
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(jobs.size() == 8, "colliding outputs are skipped", str(jobs.size()))
	_check(
		planner.errors.size() == 32, "colliding outputs are reported", str(planner.errors.size())
	)

	options = DEFAULT_OPTIONS.duplicate()
	options["filename"] = "{title}_{layer}_{tag}"
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.is_empty() and planner.failed and planner.errors.size() == 1,
		"the removed {layer} placeholder is an error",
		str(planner.errors)
	)

	_check(
		ExportPlanner.sanitize("body/arm left") == "body_arm_left", "sanitize replaces / and space"
	)
	_test_layer_include(planner, layers, tags)
	_test_cell_size(planner, layers, tags)


func _test_layer_include(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["layer_include"] = "fx, _guide, fx"
	var jobs := planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.size() == 40
			and planner.errors.is_empty()
			and planner.composed_layers == PackedStringArray(["fx", "_guide"])
		),
		"layers/include picks layers, excluded ones too",
		str(planner.composed_layers)
	)

	options["layer_include"] = "ghost, body"
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.size() == 40
			and planner.errors.size() == 1
			and planner.composed_layers == PackedStringArray(["body"])
		),
		"unknown included layer is reported and ignored",
		str(planner.errors)
	)

	options["layer_include"] = "ghost"
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.is_empty() and planner.failed and planner.errors.size() == 2,
		"no known included layer fails",
		str(planner.errors)
	)

	options["layer_include"] = ""
	options["layer_exclude_pattern"] = "."
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(jobs.is_empty() and planner.failed, "every layer excluded fails", str(planner.errors))


func _test_cell_size(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["cell_size"] = CELL_SIZE
	var jobs := planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 40 and planner.cell_size == CELL_SIZE,
		"explicit cell size equal to the default",
		str(planner.cell_size)
	)

	options["cell_size"] = Vector2i(40, 0)
	jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 40 and planner.cell_size == Vector2i(40, 64),
		"smaller cell width, 0 height is a third",
		str(planner.cell_size)
	)

	for cell: Vector2i in [Vector2i(50, 64), Vector2i(-1, 64), Vector2i(48, 65)]:
		options["cell_size"] = cell
		jobs = planner.build_jobs(TITLE, SPRITE_SIZE, layers, tags, options)
		_check(
			jobs.is_empty() and planner.failed and planner.cell_size == Vector2i.ZERO,
			"cell size %s does not fit" % cell,
			str(planner.errors)
		)

	jobs = planner.build_jobs(TITLE, Vector2i(145, 192), layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.is_empty() and planner.failed,
		"default cell needs a size multiple of 3",
		str(planner.errors)
	)


func _expected_strip(direction: String) -> String:
	return EXPECTED_DIR.path_join("character_%s_idle_loop.png" % direction)


static func _image_size(path: String) -> Vector2i:
	var image := Image.load_from_file(path)
	return Vector2i.ZERO if image == null else image.get_size()


func _find_job(jobs: Array[Dictionary], relative_path: String) -> Dictionary:
	for job: Dictionary in jobs:
		if job["relative_path"] == relative_path:
			return job
	return {}


func _check(condition: bool, description: String, detail: String = "") -> void:
	if condition:
		print("PASS: " + description)
		return
	_failures += 1
	print("FAIL: %s (%s)" % [description, detail])

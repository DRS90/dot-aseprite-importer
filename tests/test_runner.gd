extends SceneTree
## Headless test runner. Needs the Aseprite executable in the ASEPRITE_PATH environment variable:
##   ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
## Prints one PASS/FAIL line per check and exits with 1 when any check fails.

const AsepriteCli := preload("res://addons/aseprite_topdown_layers/aseprite_cli.gd")
const ExportPlanner := preload("res://addons/aseprite_topdown_layers/export_planner.gd")

const SOURCE := "res://examples/character/character.aseprite"
const TITLE := "character"
const EXPECTED_DIR := "res://tests/expected/idle_loop"
const EXPECTED_LAYERS: Array[String] = [
	"up", "right_up", "right_down", "left_up", "left_down", "down"
]
const EXPECTED_TAGS: Array[String] = ["idle_loop", "walk", "death", "dash", "jump"]
const STRIP_SIZE := Vector2i(384, 64)
const DEFAULT_OPTIONS := {
	"layer_exclude_pattern": "^_",
	"tag_exclude_pattern": "^_",
	"output_folder": "assets/{tag}",
	"filename": "{title}_{layer}_{tag}",
}
const ASSET_HELP := (
	"Place the example character.aseprite at "
	+ "examples/character/character.aseprite and export the reference strips to "
	+ "tests/expected/idle_loop/ (see README > Credits)."
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
	for layer: String in EXPECTED_LAYERS:
		var expected := EXPECTED_DIR.path_join("character_%s_idle_loop.png" % layer)
		if not FileAccess.file_exists(expected):
			missing.append(expected)
	return missing


func _test_with_example_asset() -> void:
	var cli := AsepriteCli.new(OS.get_environment("ASEPRITE_PATH"))
	_check(cli.is_available(), "Aseprite executable available", cli.get_executable())
	if not cli.is_available():
		return
	var layers := _test_listing(cli)
	var jobs := _test_planner(layers)
	_test_export_strips(cli, jobs)
	_test_combination_matches_cli(cli, layers)
	_test_export_rejects_unknown_names(cli)


func _test_listing(cli: AsepriteCli) -> PackedStringArray:
	var source := ProjectSettings.globalize_path(SOURCE)
	var contents := cli.list_contents(source, false)
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	_check(
		layers == PackedStringArray(EXPECTED_LAYERS),
		"list_contents returns 6 layers",
		"%s %s" % [layers, cli.last_error]
	)
	var visible: PackedStringArray = cli.list_contents(source, true).get(
		"layers", PackedStringArray()
	)
	_check(visible == PackedStringArray(["left_down"]), "list_contents only_visible", str(visible))
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_contents returns 5 tags", str(tags))
	return layers


func _test_planner(layers: PackedStringArray) -> Array[Dictionary]:
	var planner := ExportPlanner.new()
	var jobs := planner.build_jobs(TITLE, layers, PackedStringArray(EXPECTED_TAGS), DEFAULT_OPTIONS)
	_check(jobs.size() == 30, "planner builds 30 jobs", str(jobs.size()))
	_check(planner.errors.is_empty(), "planner reports no errors", str(planner.errors))
	for layer: String in EXPECTED_LAYERS:
		var expected_path := "assets/idle_loop/character_%s_idle_loop.png" % layer
		var job := _find_job(jobs, expected_path)
		_check(not job.is_empty(), "job exists: " + expected_path)
		if not job.is_empty():
			_check(job["layers"] == PackedStringArray([layer]), "job layers: " + expected_path)
	return jobs


## All 30 strips in one Aseprite process: idle_loop matches the CLI reference byte for byte, the
## other tags have the expected size.
func _test_export_strips(cli: AsepriteCli, jobs: Array[Dictionary]) -> void:
	var source := ProjectSettings.globalize_path(SOURCE)
	var output_dir := _tmp_dir.path_join("batch")
	var code := cli.export_strips(source, jobs, "horizontal", output_dir)
	_check(code == OK, "export_strips exports 30 jobs", cli.last_error)
	for job: Dictionary in jobs:
		var tag: String = job["tag"]
		var relative_path: String = job["relative_path"]
		var exported := output_dir.path_join(relative_path)
		if tag == "idle_loop":
			var expected := ProjectSettings.globalize_path(
				EXPECTED_DIR.path_join(relative_path.get_file())
			)
			var actual_md5 := FileAccess.get_md5(exported)
			var expected_md5 := FileAccess.get_md5(expected)
			_check(
				actual_md5 == expected_md5 and expected_md5 != "",
				"MD5 matches expected: " + relative_path.get_file(),
				"%s vs %s" % [actual_md5, expected_md5]
			)
			continue
		var size := Vector2i.ZERO
		var image := Image.load_from_file(exported)
		if image != null:
			size = image.get_size()
		_check(size == STRIP_SIZE, "strip is 384x64: " + relative_path.get_file(), str(size))


## A combination composes several layers: compare with the CLI's --layer a --layer b.
func _test_combination_matches_cli(cli: AsepriteCli, layers: PackedStringArray) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["combinations"] = "combo=down+up"
	var planner := ExportPlanner.new()
	var all_jobs := planner.build_jobs(TITLE, layers, PackedStringArray(EXPECTED_TAGS), options)
	var job := _find_job(all_jobs, "assets/walk/character_combo_walk.png")
	_check(not job.is_empty(), "combination job exists")
	if job.is_empty():
		return
	var jobs: Array[Dictionary] = [job]
	var output_dir := _tmp_dir.path_join("combination")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE), jobs, "horizontal", output_dir
	)
	var reference := _tmp_dir.path_join("cli").path_join("character_combo_walk.png")
	var cli_code := _export_with_cli(job["layers"], "walk", reference)
	var batch_md5 := FileAccess.get_md5(output_dir.path_join(job["relative_path"]))
	var cli_md5 := FileAccess.get_md5(reference)
	_check(
		code == OK and cli_code == OK and batch_md5 == cli_md5 and cli_md5 != "",
		"combination strip matches the CLI",
		"%s vs %s %s" % [batch_md5, cli_md5, cli.last_error]
	)


func _test_export_rejects_unknown_names(cli: AsepriteCli) -> void:
	var source := ProjectSettings.globalize_path(SOURCE)
	var output_dir := _tmp_dir.path_join("rejected")
	var unknown_layer: Array[Dictionary] = [
		{"layers": PackedStringArray(["ghost"]), "tag": "walk", "relative_path": "ghost.png"}
	]
	var code := cli.export_strips(source, unknown_layer, "horizontal", output_dir)
	_check(
		code != OK and cli.last_error.contains("unknown layer 'ghost'"),
		"export_strips rejects an unknown layer",
		cli.last_error
	)
	var unknown_tag: Array[Dictionary] = [
		{"layers": PackedStringArray(["up"]), "tag": "nope", "relative_path": "nope.png"}
	]
	code = cli.export_strips(source, unknown_tag, "horizontal", output_dir)
	_check(
		code != OK and cli.last_error.contains("unknown tag 'nope'"),
		"export_strips rejects an unknown tag",
		cli.last_error
	)


func _export_with_cli(layers: PackedStringArray, tag: String, output_png: String) -> Error:
	if FileAccess.file_exists(output_png):
		DirAccess.remove_absolute(output_png)
	DirAccess.make_dir_recursive_absolute(output_png.get_base_dir())
	var args := PackedStringArray(["-b", "--all-layers"])
	for layer: String in layers:
		args.append_array(PackedStringArray(["--layer", layer]))
	(
		args
		. append_array(
			PackedStringArray(
				[
					"--tag",
					tag,
					ProjectSettings.globalize_path(SOURCE),
					"--sheet-type",
					"horizontal",
					"--sheet",
					output_png,
				]
			)
		)
	)
	var output: Array = []
	var code := OS.execute(OS.get_environment("ASEPRITE_PATH"), args, output, true)
	return OK if code == 0 else FAILED


func _test_planner_edge_cases() -> void:
	var planner := ExportPlanner.new()
	var layers := PackedStringArray(EXPECTED_LAYERS)
	var tags := PackedStringArray(EXPECTED_TAGS)

	var options := DEFAULT_OPTIONS.duplicate()
	options["layer_exclude_pattern"] = "^up$"
	var jobs := planner.build_jobs(TITLE, layers, tags, options)
	_check(jobs.size() == 25, "layer exclude pattern removes 'up'", str(jobs.size()))

	options = DEFAULT_OPTIONS.duplicate()
	options["tag_exclude_pattern"] = "^(walk|jump)$"
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	_check(jobs.size() == 18, "tag exclude pattern removes 2 tags", str(jobs.size()))

	jobs = planner.build_jobs(TITLE, layers, PackedStringArray(), DEFAULT_OPTIONS)
	var untagged := _find_job(jobs, "assets/character_up.png")
	_check(jobs.size() == 6 and not untagged.is_empty(), "no tags: one strip per layer")

	options = DEFAULT_OPTIONS.duplicate()
	options["output_folder"] = "sprites"
	options["filename"] = "{layer}"
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	_check(jobs.size() == 6, "colliding outputs are skipped", str(jobs.size()))
	_check(
		planner.errors.size() == 24, "colliding outputs are reported", str(planner.errors.size())
	)

	_check(
		ExportPlanner.sanitize("body/arm left") == "body_arm_left", "sanitize replaces / and space"
	)
	_test_combinations(planner, layers, tags)


func _test_combinations(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["combinations"] = "test=down+up"
	var jobs := planner.build_jobs(TITLE, layers, tags, options)
	var combined := _find_job(jobs, "assets/idle_loop/character_test_idle_loop.png")
	_check(jobs.size() == 25, "combination replaces its layers: 25 jobs", str(jobs.size()))
	_check(
		not combined.is_empty() and combined["layers"] == PackedStringArray(["down", "up"]),
		"combination job composes down+up"
	)
	_check(
		_find_job(jobs, "assets/idle_loop/character_down_idle_loop.png").is_empty(),
		"combined layers are not exported alone"
	)

	options["combinations"] = "bad=down+nope"
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	_check(
		jobs.size() == 30 and planner.errors.size() == 1,
		"unknown layer skips the combination",
		str(planner.errors)
	)

	options["combinations"] = "oops; =up; empty="
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	_check(
		jobs.size() == 30 and planner.errors.size() == 3,
		"malformed combinations are reported",
		str(planner.errors)
	)

	options = DEFAULT_OPTIONS.duplicate()
	options["always_include"] = "down"
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	var with_base := _find_job(jobs, "assets/walk/character_up_walk.png")
	_check(
		(
			jobs.size() == 25
			and not with_base.is_empty()
			and with_base["layers"] == PackedStringArray(["down", "up"])
		),
		"always_include composes into every strip",
		str(jobs.size())
	)

	options["always_include"] = "down, ghost"
	options["combinations"] = "test=left_up+right_up"
	jobs = planner.build_jobs(TITLE, layers, tags, options)
	var mixed := _find_job(jobs, "assets/dash/character_test_dash.png")
	_check(
		(
			jobs.size() == 20
			and planner.errors.size() == 1
			and not mixed.is_empty()
			and mixed["layers"] == PackedStringArray(["down", "left_up", "right_up"])
		),
		"always_include + combination, unknown always_include reported",
		"%d jobs, %s" % [jobs.size(), planner.errors]
	)


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

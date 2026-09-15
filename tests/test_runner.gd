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

var _failures := 0
var _tmp_dir := OS.get_cache_dir().path_join("aseprite_topdown_layers_tests")


func _initialize() -> void:
	var cli := AsepriteCli.new(OS.get_environment("ASEPRITE_PATH"))
	_check(cli.is_available(), "Aseprite executable available", cli.get_executable())
	if _failures == 0:
		var layers := _test_listing(cli)
		var jobs := _test_planner(layers)
		_test_idle_loop_matches_expected(cli, jobs)
		_test_other_tags_strip_size(cli, jobs)
	_test_planner_edge_cases()
	print("%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _test_listing(cli: AsepriteCli) -> PackedStringArray:
	var source := ProjectSettings.globalize_path(SOURCE)
	var layers := cli.list_layers(source, false)
	_check(
		layers == PackedStringArray(EXPECTED_LAYERS), "list_layers returns 6 layers", str(layers)
	)
	var visible := cli.list_layers(source, true)
	_check(visible == PackedStringArray(["left_down"]), "list_layers only_visible", str(visible))
	var tags := cli.list_tags(source)
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_tags returns 5 tags", str(tags))
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


func _test_idle_loop_matches_expected(cli: AsepriteCli, jobs: Array[Dictionary]) -> void:
	var source := ProjectSettings.globalize_path(SOURCE)
	for job: Dictionary in jobs:
		var tag: String = job["tag"]
		if tag != "idle_loop":
			continue
		var job_layers: PackedStringArray = job["layers"]
		var relative_path: String = job["relative_path"]
		var tmp := _tmp_dir.path_join(relative_path)
		var code := cli.export_strip(source, job_layers, tag, "horizontal", tmp)
		var expected := ProjectSettings.globalize_path(
			EXPECTED_DIR.path_join(relative_path.get_file())
		)
		var actual_md5 := FileAccess.get_md5(tmp)
		var expected_md5 := FileAccess.get_md5(expected)
		_check(
			code == OK and actual_md5 == expected_md5 and expected_md5 != "",
			"MD5 matches expected: " + relative_path.get_file(),
			"%s vs %s" % [actual_md5, expected_md5]
		)


func _test_other_tags_strip_size(cli: AsepriteCli, jobs: Array[Dictionary]) -> void:
	var source := ProjectSettings.globalize_path(SOURCE)
	var done := {}
	for job: Dictionary in jobs:
		var tag: String = job["tag"]
		if tag == "idle_loop" or done.has(tag):
			continue
		done[tag] = true
		var job_layers: PackedStringArray = job["layers"]
		var relative_path: String = job["relative_path"]
		var tmp := _tmp_dir.path_join(relative_path)
		var size := Vector2i.ZERO
		if cli.export_strip(source, job_layers, tag, "horizontal", tmp) == OK:
			var image := Image.load_from_file(tmp)
			if image != null:
				size = image.get_size()
		_check(size == STRIP_SIZE, "strip is 384x64: " + relative_path.get_file(), str(size))


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

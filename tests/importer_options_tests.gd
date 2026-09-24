extends RefCounted
## Default import options of the headless test runner: a file whose options do not name a grid is
## imported with no directions, the case of a side view character that needs no grid.
## [param check] is the runner's own reporting function, so one run counts every failure.

const ExportPlanner := preload("res://addons/dot_aseprite_importer/export_planner.gd")
const Importer := preload("res://addons/dot_aseprite_importer/importer.gd")

var _check: Callable


func _init(check: Callable) -> void:
	_check = check


func run() -> void:
	_test_planner_default()
	_test_importer_default()


## A 48x48 sprite is a multiple of 3, so a 3x3 default would cut it into nine 16x16 cells named
## after directions without any error. With no grid named, it has to stay one cell.
func _test_planner_default() -> void:
	var planner := ExportPlanner.new()
	var options := {
		"layer": ExportPlanner.ALL_LAYERS,
		"animation_name": ExportPlanner.DEFAULT_ANIMATION_NAME,
		"loop_suffix": ExportPlanner.DEFAULT_LOOP_SUFFIX,
	}
	var jobs := planner.build_jobs(
		Vector2i(48, 48),
		PackedStringArray(["body"]),
		PackedStringArray(["idle_loop", "jump"]),
		options
	)
	var names := PackedStringArray()
	var loops := PackedStringArray()
	for job: Dictionary in jobs:
		names.append(str(job["animation"]))
		if job["loop"]:
			loops.append(str(job["animation"]))
	_check.call(
		(
			not planner.failed
			and planner.cells_per_axis == 1
			and planner.cell_size == Vector2i(48, 48)
			and names == PackedStringArray(["idle", "jump"])
			and loops == PackedStringArray(["idle"])
		),
		"with no grid/directions a 48x48 sprite is one cell, one animation per tag",
		"%s %s %s" % [planner.errors, planner.cell_size, names]
	)


## The option the Import dock and Project Settings > Import Defaults show, and the fallback the
## importer hands the planner, both come from ExportPlanner.DEFAULT_DIRECTIONS.
func _test_importer_default() -> void:
	var option := Importer.directions_option()
	_check.call(
		(
			option.get("default_value") == ExportPlanner.MODE_NONE
			and str(option.get("hint_string", "")).begins_with(ExportPlanner.MODE_NONE + ",")
		),
		"grid/directions defaults to none and lists it first",
		str(option)
	)
	_check.call(
		Importer.planner_options({})["directions"] == ExportPlanner.MODE_NONE,
		"the importer falls back to none for a .import without grid/directions"
	)

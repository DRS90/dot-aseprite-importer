@tool
extends RefCounted
## Wrapper around the Aseprite executable.
##
## Has no editor dependency, so headless tests can use it. Every path passed in must be absolute
## (the caller globalizes res:// paths). Starting Aseprite costs about 200 ms while exporting a
## strip costs a few, so listing and exporting each run as a single process of aseprite_batch.lua,
## whatever the number of layers and tags. The script rejects unknown layer or tag names, which the
## plain CLI silently turns into a wrong image. Failures are described in [member last_error].

const BATCH_SCRIPT := "aseprite_batch.lua"
const JOBS_FILE := "jobs.txt"
const DATA_FILE := "data.json"
const LAYER_PREFIX := "layer\t"
const TAG_PREFIX := "tag\t"
const DONE_PREFIX := "done\t"
const MAX_LOGGED_OUTPUT := 500

## Why the last failed call failed.
var last_error := ""

var _executable: String = ""
var _batch_script: String = ""


func _init(executable_path: String) -> void:
	_executable = executable_path
	var script := get_script() as Script
	_batch_script = ProjectSettings.globalize_path(
		script.resource_path.get_base_dir().path_join(BATCH_SCRIPT)
	)


## True when the configured executable exists and answers --version.
func is_available() -> bool:
	if _executable.strip_edges() == "":
		return false
	if _executable.is_absolute_path() and not FileAccess.file_exists(_executable):
		return false
	var output: Array = []
	return OS.execute(_executable, PackedStringArray(["--version"]), output) == 0


func get_executable() -> String:
	return _executable


## Names of the top-level layers and groups and of the tags, in file order:
## {"layers": PackedStringArray, "tags": PackedStringArray}. Empty when Aseprite failed.
func list_contents(aseprite_file: String, only_visible: bool) -> Dictionary:
	var lines := _run_batch(
		PackedStringArray(
			["mode=list", "file=" + aseprite_file, "only_visible=" + str(only_visible).to_lower()]
		)
	)
	if lines.is_empty():
		return {}
	var layers := PackedStringArray()
	var tags := PackedStringArray()
	for line: String in lines:
		if line.begins_with(LAYER_PREFIX):
			layers.append(line.trim_prefix(LAYER_PREFIX))
		elif line.begins_with(TAG_PREFIX):
			tags.append(line.trim_prefix(TAG_PREFIX))
	return {"layers": layers, "tags": tags}


## Exports every job built by ExportPlanner.build_jobs() in one Aseprite process, each to
## [param output_dir]/relative_path as a [param sheet_type] ("horizontal" or "vertical") sheet.
## The job list and the unused JSON data are written to [param output_dir] as well.
func export_strips(
	aseprite_file: String, jobs: Array[Dictionary], sheet_type: String, output_dir: String
) -> Error:
	last_error = ""
	if jobs.is_empty():
		return OK
	var lines := PackedStringArray()
	var outputs := PackedStringArray()
	for job: Dictionary in jobs:
		var line := _prepare_job(job, output_dir)
		if line == "":
			return ERR_INVALID_PARAMETER
		lines.append(line)
		outputs.append(line.get_slice("\t", 0))
	var jobs_path := output_dir.path_join(JOBS_FILE)
	if _write_text(jobs_path, "\n".join(lines) + "\n") != OK:
		return ERR_FILE_CANT_WRITE

	var params := PackedStringArray(
		[
			"mode=export",
			"file=" + aseprite_file,
			"jobs=" + jobs_path,
			"data=" + output_dir.path_join(DATA_FILE),
			"sheet_type=" + sheet_type,
		]
	)
	if _run_batch(params).is_empty():
		return FAILED
	for output_png: String in outputs:
		if _file_size(output_png) <= 0:
			last_error = "Aseprite did not write '%s'." % output_png
			return FAILED
	return OK


## Returns the job's line for the jobs file (output<TAB>tag<TAB>layers...) and clears its output, or
## "" with [member last_error] set when the job cannot be exported.
func _prepare_job(job: Dictionary, output_dir: String) -> String:
	var job_layers: PackedStringArray = job["layers"]
	var tag: String = job["tag"]
	var relative_path: String = job["relative_path"]
	var output_png := output_dir.path_join(relative_path)
	if job_layers.is_empty():
		last_error = "Refusing to export '%s' without layers." % output_png
		return ""
	var fields := PackedStringArray([output_png, tag]) + job_layers
	for field: String in fields:
		if field.contains("\t") or field.contains("\n") or field.contains("\r"):
			last_error = "Cannot export '%s': a name contains a tab or a line break." % output_png
			return ""
	# A leftover file from a previous run would hide a failed export.
	if FileAccess.file_exists(output_png):
		DirAccess.remove_absolute(output_png)
	DirAccess.make_dir_recursive_absolute(output_png.get_base_dir())
	return "\t".join(fields)


func _write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		last_error = "Cannot write '%s' (%s)." % [path, error_string(open_error)]
		return open_error
	file.store_string(text)
	file.close()
	return OK


## Runs aseprite_batch.lua and returns its output lines, or nothing (with [member last_error] set)
## when it did not finish with its "done" line.
func _run_batch(params: PackedStringArray) -> PackedStringArray:
	var args := PackedStringArray(["-b"])
	for param: String in params:
		args.append("--script-param")
		args.append(param)
	# Every --script-param must come before --script.
	args.append("--script")
	args.append(_batch_script)
	var output: Array = []
	# stderr is read as well, so a Lua error ends up in last_error.
	var code := OS.execute(_executable, args, output, true)
	var text := "" if output.is_empty() else str(output[0])
	var lines := text.replace("\r\n", "\n").split("\n", false)
	for line: String in lines:
		if code == 0 and line.begins_with(DONE_PREFIX):
			return lines
	last_error = (
		"Aseprite failed (exit %d): %s" % [code, text.strip_edges().right(MAX_LOGGED_OUTPUT)]
	)
	return PackedStringArray()


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()

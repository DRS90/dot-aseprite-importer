@tool
extends RefCounted
## Wrapper around the Aseprite executable.
##
## Has no editor dependency, so headless tests can use it. Every path passed in must be absolute
## (the caller globalizes res:// paths). Starting Aseprite costs about 200 ms while exporting a
## strip costs a few, so listing and exporting each run as a single process of aseprite_batch.lua,
## whatever the number of strips. The script rejects unknown layer, tag or direction names and cells
## that do not fit the sprite. Failures are described in [member last_error].

const BATCH_SCRIPT := "aseprite_batch.lua"
const JOBS_FILE := "jobs.txt"
const SIZE_PREFIX := "size\t"
const LAYER_PREFIX := "layer\t"
const TAG_PREFIX := "tag\t"
const FRAME_PREFIX := "frame\t"
const STRIP_PREFIX := "strip\t"
const WRITTEN_PREFIX := "written\t"
const DONE_PREFIX := "done\t"
const MAX_LOGGED_OUTPUT := 500

## Why the last failed call failed.
var last_error := ""
## Relative paths of the strips written by the last [method export_strips] call. A cell with no
## pixels in any frame of its tag writes nothing, so it is not listed.
var last_written := PackedStringArray()

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


## What the file holds, in file order:
## {"size": Vector2i, "layers": PackedStringArray (top-level layers and groups),
## "visible_layers": PackedStringArray, "tags": PackedStringArray,
## "tag_ranges": {name: {"from": int, "to": int, "direction": String}} (0-based frames, first tag
## of a repeated name), "frame_durations": PackedInt32Array (milliseconds)}.
## Empty when Aseprite failed.
func list_contents(aseprite_file: String) -> Dictionary:
	var lines := _run_batch(PackedStringArray(["mode=list", "file=" + aseprite_file]))
	if lines.is_empty():
		return {}
	var contents := {
		"size": Vector2i.ZERO,
		"layers": PackedStringArray(),
		"visible_layers": PackedStringArray(),
		"tags": PackedStringArray(),
		"tag_ranges": {},
		"frame_durations": PackedInt32Array(),
	}
	for line: String in lines:
		var fields := line.split("\t")
		if line.begins_with(SIZE_PREFIX) and fields.size() == 3:
			contents["size"] = Vector2i(fields[1].to_int(), fields[2].to_int())
		elif line.begins_with(LAYER_PREFIX) and fields.size() == 3:
			_add_layer(contents, fields[1], fields[2] == "true")
		elif line.begins_with(TAG_PREFIX) and fields.size() == 5:
			_add_tag(contents, fields[1], fields[2].to_int(), fields[3].to_int(), fields[4])
		elif line.begins_with(FRAME_PREFIX) and fields.size() == 3:
			var durations: PackedInt32Array = contents["frame_durations"]
			durations.append(fields[2].to_int())
			contents["frame_durations"] = durations
	return contents


## Exports every job built by ExportPlanner.build_jobs() in one Aseprite process. [param layers] are
## composed, and the job's direction cell ([param cell_size]) is cropped from every frame of its tag
## into [param output_dir]/relative_path as a horizontal strip. The strips written end up in
## [member last_written]; the job list is written to [param output_dir] as well.
func export_strips(
	aseprite_file: String,
	jobs: Array[Dictionary],
	layers: PackedStringArray,
	cell_size: Vector2i,
	output_dir: String
) -> Error:
	last_error = ""
	last_written = PackedStringArray()
	if jobs.is_empty():
		return OK
	var lines := _job_lines(jobs, layers, output_dir)
	if lines.is_empty():
		return ERR_INVALID_PARAMETER
	var jobs_path := output_dir.path_join(JOBS_FILE)
	if _write_text(jobs_path, "\n".join(lines) + "\n") != OK:
		return ERR_FILE_CANT_WRITE

	var params := PackedStringArray(
		[
			"mode=export",
			"file=" + aseprite_file,
			"jobs=" + jobs_path,
			"cell_width=%d" % cell_size.x,
			"cell_height=%d" % cell_size.y,
		]
	)
	var output := _run_batch(params)
	if output.is_empty():
		return FAILED
	var written := PackedStringArray()
	for job: Dictionary in jobs:
		var relative_path: String = job["relative_path"]
		var output_png := output_dir.path_join(relative_path)
		if not output.has(WRITTEN_PREFIX + output_png):
			continue
		if _file_size(output_png) <= 0:
			last_error = "Aseprite did not write '%s'." % output_png
			return FAILED
		written.append(relative_path)
	last_written = written
	return OK


static func _add_layer(contents: Dictionary, layer: String, visible: bool) -> void:
	var layers: PackedStringArray = contents["layers"]
	layers.append(layer)
	contents["layers"] = layers
	if visible:
		var visible_layers: PackedStringArray = contents["visible_layers"]
		visible_layers.append(layer)
		contents["visible_layers"] = visible_layers


static func _add_tag(
	contents: Dictionary, tag: String, from: int, to: int, direction: String
) -> void:
	var tags: PackedStringArray = contents["tags"]
	tags.append(tag)
	contents["tags"] = tags
	var ranges: Dictionary = contents["tag_ranges"]
	if not ranges.has(tag):
		ranges[tag] = {"from": from, "to": to, "direction": direction}


## Lines of the jobs file: the composed layers, then one strip per job. Empty, with
## [member last_error] set, when something cannot be passed to the script.
func _job_lines(
	jobs: Array[Dictionary], layers: PackedStringArray, output_dir: String
) -> PackedStringArray:
	if layers.is_empty():
		last_error = "Refusing to export without layers."
		return PackedStringArray()
	var lines := PackedStringArray()
	for layer: String in layers:
		if not _is_single_field(layer):
			last_error = "Cannot export layer '%s': its name has a tab or a line break." % layer
			return PackedStringArray()
		lines.append(LAYER_PREFIX + layer)
	for job: Dictionary in jobs:
		var line := _prepare_job(job, output_dir)
		if line == "":
			return PackedStringArray()
		lines.append(line)
	return lines


## Returns the job's line for the jobs file (strip<TAB>output<TAB>tag<TAB>direction) and clears its
## output, or "" with [member last_error] set when the job cannot be exported.
func _prepare_job(job: Dictionary, output_dir: String) -> String:
	var tag: String = job["tag"]
	var direction: String = job["direction"]
	var relative_path: String = job["relative_path"]
	var output_png := output_dir.path_join(relative_path)
	var fields := PackedStringArray([output_png, tag, direction])
	for field: String in fields:
		if not _is_single_field(field):
			last_error = "Cannot export '%s': a name has a tab or a line break." % output_png
			return ""
	# A leftover file from a previous run would hide a failed export.
	if FileAccess.file_exists(output_png):
		DirAccess.remove_absolute(output_png)
	DirAccess.make_dir_recursive_absolute(output_png.get_base_dir())
	return STRIP_PREFIX + "\t".join(fields)


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


static func _is_single_field(text: String) -> bool:
	return not (text.contains("\t") or text.contains("\n") or text.contains("\r"))


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()

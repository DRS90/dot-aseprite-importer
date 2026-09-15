@tool
extends RefCounted
## Thin wrapper around the Aseprite command line interface.
##
## Has no editor dependency, so headless tests can use it. Every path passed in must be absolute
## (the caller globalizes res:// paths). Aseprite exits with code 0 even for unknown layer or tag
## names, so callers must only pass names returned by list_layers() and list_tags().

const LOG_PREFIX := "[Aseprite Top-Down Layers] "
const MAX_LOGGED_OUTPUT := 500

var _executable: String = ""


func _init(executable_path: String) -> void:
	_executable = executable_path


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


## Names of the top-level layers and groups, in the order Aseprite lists them.
func list_layers(aseprite_file: String, only_visible: bool) -> PackedStringArray:
	var args := PackedStringArray(["-b"])
	if not only_visible:
		args.append("--all-layers")
	args.append("--list-layer-hierarchy")
	args.append(aseprite_file)
	var layers := PackedStringArray()
	for line: String in _run_and_split_lines(args):
		# Children are indented by two spaces: only the top level becomes a strip.
		if line.begins_with(" "):
			continue
		# Groups end with "/"; exporting the group name composes its children.
		layers.append(line.trim_suffix("/"))
	return layers


func list_tags(aseprite_file: String) -> PackedStringArray:
	var tags := PackedStringArray()
	for line: String in _run_and_split_lines(
		PackedStringArray(["-b", "--list-tags", aseprite_file])
	):
		var tag := line.strip_edges()
		if tag != "":
			tags.append(tag)
	return tags


## Exports [param layers] composed together, restricted to [param tag] ("" = whole timeline),
## as a single sheet of [param sheet_type] ("horizontal" or "vertical") at [param output_png].
func export_strip(
	aseprite_file: String,
	layers: PackedStringArray,
	tag: String,
	sheet_type: String,
	output_png: String
) -> Error:
	if layers.is_empty():
		push_error(LOG_PREFIX + "Refusing to export '%s' without layers." % output_png)
		return ERR_INVALID_PARAMETER
	# A leftover file from a previous run would hide a failed export.
	if FileAccess.file_exists(output_png):
		DirAccess.remove_absolute(output_png)
	DirAccess.make_dir_recursive_absolute(output_png.get_base_dir())

	var args := PackedStringArray(["-b", "--all-layers"])
	for layer: String in layers:
		args.append("--layer")
		args.append(layer)
	if tag != "":
		args.append("--tag")
		args.append(tag)
	# --layer/--tag must come before the file name, --sheet options after it.
	args.append(aseprite_file)
	args.append_array(PackedStringArray(["--sheet-type", sheet_type, "--sheet", output_png]))

	var output: Array = []
	var code := OS.execute(_executable, args, output, true)
	if code != 0 or _file_size(output_png) <= 0:
		var log_text := "" if output.is_empty() else str(output[0]).left(MAX_LOGGED_OUTPUT)
		push_error(
			(
				LOG_PREFIX
				+ (
					"Export failed (exit %d) for '%s': %s"
					% [code, output_png, log_text.strip_edges()]
				)
			)
		)
		return FAILED
	return OK


func _run_and_split_lines(args: PackedStringArray) -> PackedStringArray:
	var output: Array = []
	# stdout only: stderr noise must not be parsed as layer or tag names.
	var code := OS.execute(_executable, args, output, false)
	if code != 0:
		push_error(LOG_PREFIX + "Aseprite failed (exit %d): %s" % [code, " ".join(args)])
		return PackedStringArray()
	var text := "" if output.is_empty() else str(output[0])
	return text.replace("\r\n", "\n").split("\n", false)


static func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()

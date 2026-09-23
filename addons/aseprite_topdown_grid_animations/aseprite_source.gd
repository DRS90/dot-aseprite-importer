@tool
extends RefCounted
## Shared access to the Aseprite executable and to what each source file holds.
##
## Both importers use one instance, created by plugin.gd. What a file holds is read from its bytes
## by AsepriteFileReader, so neither the import options nor the import start Aseprite to list it:
## an import runs Aseprite once, to export. The listing is cached by file content, because Godot
## asks for the import options right before importing.
##
## Has no editor dependency: the executable path arrives as a [Callable], so headless tests pass
## their own instead of reaching for EditorSettings.

const AsepriteCli := preload("aseprite_cli.gd")
const AsepriteFileReader := preload("aseprite_file_reader.gd")
const ExportPlanner := preload("export_planner.gd")

## Prefix of every message this addon prints, so its errors are searchable in the Output panel.
const LOG_PREFIX := "[Aseprite Top-Down Grid Animations] "

## Why the last [method verified_cli] or [method list] call failed.
var last_error := ""

var _executable_path: Callable
var _reader := AsepriteFileReader.new()
## res:// path -> {"md5": String, "contents": Dictionary} of the last listing.
var _cache := {}


## [param executable_path] is called for the current path every time one is needed, so changing it
## in the Editor Settings applies without restarting.
func _init(executable_path: Callable) -> void:
	_executable_path = executable_path


## A wrapper around the configured executable, or null with [member last_error] set when there is
## no such file. Nothing is started: a bare name is looked up in the PATH, and an executable that
## exists but does not run is reported by the export itself.
func verified_cli() -> AsepriteCli:
	last_error = ""
	var executable := str(_executable_path.call())
	if AsepriteCli.find_executable(executable) == "":
		last_error = AsepriteCli.not_found_message(executable)
		return null
	return AsepriteCli.new(executable)


## What [param source_file] holds (see AsepriteCli.list_contents()), from cache when its content
## has not changed. Empty, with [member last_error] set, when the file cannot be read; failures are
## not cached, so the next call tries again.
func list(source_file: String) -> Dictionary:
	last_error = ""
	var md5 := FileAccess.get_md5(source_file)
	var cached: Dictionary = _cache.get(source_file, {})
	if not cached.is_empty() and cached["md5"] == md5:
		var contents: Dictionary = cached["contents"]
		return contents
	var listed := _reader.read(source_file)
	if listed.is_empty():
		last_error = _reader.last_error
	else:
		_cache[source_file] = {"md5": md5, "contents": listed}
	return listed


## Choices of a layers/layer dropdown: [all], then the file's top-level layers and groups. Names
## with a comma or a colon would break the hint string, so they are not offered. Works without
## Aseprite, since the file is read directly.
func layer_choices(path: String) -> String:
	var choices := PackedStringArray([ExportPlanner.ALL_LAYERS])
	# The path is empty when the import defaults are edited in Project Settings.
	if path == "" or not FileAccess.file_exists(path):
		return ",".join(choices)
	var layers: PackedStringArray = list(path).get("layers", PackedStringArray())
	for layer: String in layers:
		if not layer.contains(",") and not layer.contains(":"):
			choices.append(layer)
	return ",".join(choices)

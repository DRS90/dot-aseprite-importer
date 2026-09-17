@tool
extends RefCounted
## Shared access to the Aseprite executable and to what each source file holds.
##
## Both importers use one instance, created by plugin.gd, so the executable is checked once per
## path and a file is listed once per content instead of once per importer. Godot asks for the
## import options right before importing, so without the cache the dropdown and the import would be
## two Aseprite processes, and each process costs about 200 ms.
##
## Has no editor dependency: the executable path arrives as a [Callable], so headless tests pass
## their own instead of reaching for EditorSettings.

const AsepriteCli := preload("aseprite_cli.gd")
const ExportPlanner := preload("export_planner.gd")
const Settings := preload("settings.gd")

## Prefix of every message this addon prints, so its errors are searchable in the Output panel.
const LOG_PREFIX := "[Aseprite Top-Down Grid Animations] "

## Why the last [method verified_cli] call found no usable Aseprite.
var last_error := ""

var _executable_path: Callable
var _verified_executable := ""
## res:// path -> {"md5": String, "contents": Dictionary} of the last listing.
var _cache := {}


## [param executable_path] is called for the current path every time one is needed, so changing it
## in the Editor Settings applies without restarting.
func _init(executable_path: Callable) -> void:
	_executable_path = executable_path


## A wrapper around the configured executable, without checking that it runs. For the import
## options, where a missing Aseprite just means an empty dropdown.
func cli() -> AsepriteCli:
	return AsepriteCli.new(str(_executable_path.call()))


## The same wrapper once the executable has answered --version, or null with [member last_error]
## set. The check starts Aseprite, so it only runs again when the configured path changed.
func verified_cli() -> AsepriteCli:
	last_error = ""
	var wrapper := cli()
	if wrapper.get_executable() == _verified_executable:
		return wrapper
	if not wrapper.is_available():
		last_error = (
			"Aseprite not found at '%s'. Set Editor Settings > %s or the %s variable."
			% [wrapper.get_executable(), Settings.EXECUTABLE_KEY, Settings.EXECUTABLE_ENV]
		)
		return null
	_verified_executable = wrapper.get_executable()
	return wrapper


## What [param source_file] holds, from cache when its content has not changed. Empty when Aseprite
## failed; failures are not cached, so the next call tries again.
func list(wrapper: AsepriteCli, source_file: String) -> Dictionary:
	var md5 := FileAccess.get_md5(source_file)
	var cached: Dictionary = _cache.get(source_file, {})
	if not cached.is_empty() and cached["md5"] == md5:
		var contents: Dictionary = cached["contents"]
		return contents
	var listed := wrapper.list_contents(ProjectSettings.globalize_path(source_file))
	if not listed.is_empty():
		_cache[source_file] = {"md5": md5, "contents": listed}
	return listed


## Choices of a layers/layer dropdown: [all], then the file's top-level layers and groups. Names
## with a comma or a colon would break the hint string, so they are not offered.
func layer_choices(path: String) -> String:
	var choices := PackedStringArray([ExportPlanner.ALL_LAYERS])
	# The path is empty when the import defaults are edited in Project Settings.
	if path == "" or not FileAccess.file_exists(path):
		return ",".join(choices)
	var layers: PackedStringArray = list(cli(), path).get("layers", PackedStringArray())
	for layer: String in layers:
		if not layer.contains(",") and not layer.contains(":"):
			choices.append(layer)
	return ",".join(choices)

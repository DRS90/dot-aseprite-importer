@tool
extends EditorImportPlugin
## Imports .aseprite/.ase files drawn as a 3x3 grid of directions as one PNG strip per direction
## and tag.
##
## The imported resource is only a manifest (PackedDataContainer) with the PNGs this importer
## owns, so the next import can delete strips that are no longer produced. Strips are exported to a
## cache folder first and copied into the project only when their MD5 differs: re-importing an
## unchanged source does not cascade into texture reimports.

const AsepriteCli := preload("aseprite_cli.gd")
const ExportPlanner := preload("export_planner.gd")
const FsScanScheduler := preload("fs_scan_scheduler.gd")
const Settings := preload("settings.gd")

const IMPORTER_NAME := "aseprite_topdown_layers.importer"
const VISIBLE_NAME := "Aseprite Top-Down Layers"
const LOG_PREFIX := "[Aseprite Top-Down Layers] "
const SAVE_EXTENSION := "res"
const MANIFEST_VERSION := 1
const MANIFEST_FILES_KEY := "files"
const CACHE_FOLDER := "aseprite_topdown_layers"
const RES_PREFIX := "res://"
const SHEET_TYPES: Array[String] = ["horizontal", "vertical"]
const SHEET_TYPES_HINT := "horizontal,vertical"

const OPTION_FOLDER := "output/folder"
const OPTION_FILENAME := "output/filename"
const OPTION_DELETE_STALE := "output/delete_stale"
const OPTION_CELL_SIZE := "grid/cell_size"
const OPTION_LAYER := "layers/layer"
const OPTION_LAYER_EXCLUDE := "layers/exclude_pattern"
const OPTION_ONLY_VISIBLE := "layers/only_visible"
const OPTION_TAG_EXCLUDE := "tags/exclude_pattern"
const OPTION_SHEET_TYPE := "sheet/type"

var _scheduler: FsScanScheduler
var _settings: Settings
var _planner := ExportPlanner.new()
var _verified_executable := ""
## res:// path -> {"md5": String, "contents": Dictionary} of the last Aseprite listing.
var _contents_cache := {}


func _init(scheduler: FsScanScheduler, settings: Settings) -> void:
	_scheduler = scheduler
	_settings = settings


func _get_importer_name() -> String:
	return IMPORTER_NAME


func _get_visible_name() -> String:
	return VISIBLE_NAME


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["aseprite", "ase"])


func _get_save_extension() -> String:
	return SAVE_EXTENSION


func _get_resource_type() -> String:
	return "PackedDataContainer"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _can_import_threaded() -> bool:
	return false


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _get_import_options(path: String, _preset_index: int) -> Array[Dictionary]:
	return [
		{
			"name": OPTION_FOLDER,
			"default_value": _project_default(Settings.DEFAULT_OUTPUT_FOLDER_KEY),
		},
		{
			"name": OPTION_FILENAME,
			"default_value": _project_default(Settings.DEFAULT_FILENAME_KEY),
		},
		{"name": OPTION_DELETE_STALE, "default_value": true},
		{"name": OPTION_CELL_SIZE, "default_value": Vector2i.ZERO},
		{
			"name": OPTION_LAYER,
			"default_value": ExportPlanner.ALL_LAYERS,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": _layer_choices(path),
		},
		{
			"name": OPTION_LAYER_EXCLUDE,
			"default_value": _project_default(Settings.DEFAULT_LAYER_EXCLUDE_KEY),
		},
		{"name": OPTION_ONLY_VISIBLE, "default_value": false},
		{
			"name": OPTION_TAG_EXCLUDE,
			"default_value": _project_default(Settings.DEFAULT_TAG_EXCLUDE_KEY),
		},
		{
			"name": OPTION_SHEET_TYPE,
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": SHEET_TYPES_HINT,
		},
	]


func _import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var cli := AsepriteCli.new(_settings.get_executable_path())
	# The check starts Aseprite once (~200 ms): do it once per executable path, not per import.
	if cli.get_executable() != _verified_executable:
		if not cli.is_available():
			push_error(
				(
					LOG_PREFIX
					+ (
						"Aseprite not found at '%s'. Set Editor Settings > %s or the %s variable."
						% [cli.get_executable(), Settings.EXECUTABLE_KEY, Settings.EXECUTABLE_ENV]
					)
				)
			)
			return ERR_UNCONFIGURED
		_verified_executable = cli.get_executable()

	var contents := _list_contents(cli, source_file)
	if contents.is_empty():
		push_error(LOG_PREFIX + "%s: %s" % [source_file, cli.last_error])
		return FAILED
	var only_visible: bool = options.get(OPTION_ONLY_VISIBLE, false)
	var sprite_size: Vector2i = contents["size"]
	var layers: PackedStringArray = contents["visible_layers" if only_visible else "layers"]
	var tags: PackedStringArray = contents["tags"]

	var base_dir := source_file.get_base_dir()
	var folder := str(options.get(OPTION_FOLDER, ""))
	if folder.begins_with(RES_PREFIX):
		base_dir = RES_PREFIX
		folder = folder.trim_prefix(RES_PREFIX)
	var title := source_file.get_file().get_basename()
	var planner_options := _planner_options(options, folder)
	var jobs := _planner.build_jobs(title, sprite_size, layers, tags, planner_options)
	for message: String in _planner.errors:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, message])
	if _planner.failed:
		return FAILED
	for job: Dictionary in jobs:
		var relative_path: String = job["relative_path"]
		var target := _target_path(base_dir, relative_path)
		if not target.begins_with(RES_PREFIX):
			push_error(LOG_PREFIX + "Output '%s' is outside the project." % target)
			return ERR_FILE_BAD_PATH

	var written_strips: Array[String] = []
	var export_error := _export_to_project(
		cli, source_file, jobs, _sheet_type(options), base_dir, written_strips
	)
	if export_error != OK:
		return export_error
	var written := PackedStringArray(written_strips)

	var previous_files := _load_previous_files(save_path)
	var manifest_files := written
	var delete_stale: bool = options.get(OPTION_DELETE_STALE, true)
	if delete_stale:
		_delete_stale(previous_files, written, source_file.get_base_dir())
	else:
		# Stale strips stay listed, so turning delete_stale on later still removes them.
		manifest_files = _with_kept_files(previous_files, written)
	var save_error := _save_manifest(
		save_path, ProjectSettings.globalize_path(source_file), manifest_files
	)
	# Never scan from inside _import(): the scheduler runs it deferred, after the import ends.
	if is_instance_valid(_scheduler):
		_scheduler.schedule()
	return save_error


func _project_default(key: String) -> String:
	var fallback: String = Settings.PROJECT_DEFAULTS.get(key, "")
	if _settings == null:
		return fallback
	return _settings.get_project_default(key, fallback)


## Choices of the layer dropdown: [all], then the file's top-level layers and groups. Names with a
## comma or a colon would break the hint string, so they are not offered.
func _layer_choices(path: String) -> String:
	var choices := PackedStringArray([ExportPlanner.ALL_LAYERS])
	# The path is empty when the import defaults are edited in Project Settings.
	if path == "" or _settings == null or not FileAccess.file_exists(path):
		return ",".join(choices)
	var cli := AsepriteCli.new(_settings.get_executable_path())
	var layers: PackedStringArray = _list_contents(cli, path).get("layers", PackedStringArray())
	for layer: String in layers:
		if not layer.contains(",") and not layer.contains(":"):
			choices.append(layer)
	return ",".join(choices)


## Aseprite's listing of [param source_file], cached by file content. Godot asks for the import
## options right before importing, so the dropdown and the import share one Aseprite process.
func _list_contents(cli: AsepriteCli, source_file: String) -> Dictionary:
	var md5 := FileAccess.get_md5(source_file)
	var cached: Dictionary = _contents_cache.get(source_file, {})
	if not cached.is_empty() and cached["md5"] == md5:
		var cached_contents: Dictionary = cached["contents"]
		return cached_contents
	var contents := cli.list_contents(ProjectSettings.globalize_path(source_file))
	if not contents.is_empty():
		_contents_cache[source_file] = {"md5": md5, "contents": contents}
	return contents


func _planner_options(options: Dictionary, folder: String) -> Dictionary:
	return {
		"cell_size": options.get(OPTION_CELL_SIZE, Vector2i.ZERO),
		"layer": str(options.get(OPTION_LAYER, ExportPlanner.ALL_LAYERS)),
		"layer_exclude_pattern": str(options.get(OPTION_LAYER_EXCLUDE, "")),
		"tag_exclude_pattern": str(options.get(OPTION_TAG_EXCLUDE, "")),
		"output_folder": folder,
		"filename": str(options.get(OPTION_FILENAME, ExportPlanner.DEFAULT_FILENAME)),
	}


func _sheet_type(options: Dictionary) -> String:
	var index: int = options.get(OPTION_SHEET_TYPE, 0)
	if index < 0 or index >= SHEET_TYPES.size():
		return SHEET_TYPES[0]
	return SHEET_TYPES[index]


static func _target_path(base_dir: String, relative_path: String) -> String:
	return base_dir.path_join(relative_path).simplify_path()


## Exports the strips of [param jobs] to the cache, then copies the ones that changed into the
## project. [param written] receives the project path of every strip written; a cell with no pixels
## in its tag writes nothing.
func _export_to_project(
	cli: AsepriteCli,
	source_file: String,
	jobs: Array[Dictionary],
	sheet_type: String,
	base_dir: String,
	written: Array[String]
) -> Error:
	var absolute_source := ProjectSettings.globalize_path(source_file)
	var cache_dir := OS.get_cache_dir().path_join(CACHE_FOLDER).path_join(
		absolute_source.md5_text()
	)
	var export_error := cli.export_strips(
		absolute_source, jobs, _planner.composed_layers, _planner.cell_size, sheet_type, cache_dir
	)
	if export_error != OK:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, cli.last_error])
		return FAILED
	for relative_path: String in cli.last_written:
		var target := _target_path(base_dir, relative_path)
		var copy_error := _copy_if_changed(cache_dir.path_join(relative_path), target)
		if copy_error != OK:
			return copy_error
		written.append(target)
	return OK


## Copies only when the content differs, so unchanged strips keep their mtime and .import.
func _copy_if_changed(exported: String, target: String) -> Error:
	if (
		FileAccess.file_exists(target)
		and FileAccess.get_md5(target) == FileAccess.get_md5(exported)
	):
		return OK
	var absolute_target := ProjectSettings.globalize_path(target)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_target.get_base_dir())
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error(LOG_PREFIX + "Cannot create folder for '%s' (%s)." % [target, dir_error])
		return dir_error
	var copy_error := DirAccess.copy_absolute(exported, absolute_target)
	if copy_error != OK:
		push_error(LOG_PREFIX + "Cannot write '%s' (%s)." % [target, copy_error])
	return copy_error


## Deletes the strips of a previous import that are no longer produced, then the folders they leave
## empty, up to (not including) [param keep_dir].
func _delete_stale(
	previous: PackedStringArray, written: PackedStringArray, keep_dir: String
) -> void:
	var folders := PackedStringArray()
	for path: String in previous:
		if written.has(path) or not _is_own_output(path):
			continue
		for doomed: String in [path, path + ".import"]:
			if FileAccess.file_exists(doomed):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(doomed))
		if not folders.has(path.get_base_dir()):
			folders.append(path.get_base_dir())
	for folder: String in folders:
		_remove_empty_folders(folder, keep_dir)


## Removes [param folder] and then its parents while they are empty, stopping at [param keep_dir]
## and at res://. Removing a folder that still holds anything fails, so nothing else is deleted.
func _remove_empty_folders(folder: String, keep_dir: String) -> void:
	var current := folder
	while current.begins_with(RES_PREFIX) and current != RES_PREFIX and current != keep_dir:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(current)) != OK:
			return
		current = current.get_base_dir()


func _with_kept_files(previous: PackedStringArray, written: PackedStringArray) -> PackedStringArray:
	var files := written.duplicate()
	for path: String in previous:
		if _is_own_output(path) and not files.has(path) and FileAccess.file_exists(path):
			files.append(path)
	return files


## Only PNGs inside the project are ever listed or deleted.
static func _is_own_output(path: String) -> bool:
	return path.begins_with(RES_PREFIX) and path.get_extension() == "png"


func _load_previous_files(save_path: String) -> PackedStringArray:
	var manifest_path := "%s.%s" % [save_path, SAVE_EXTENSION]
	if not ResourceLoader.exists(manifest_path):
		return PackedStringArray()
	var manifest := (
		ResourceLoader.load(manifest_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		as PackedDataContainer
	)
	if manifest == null:
		return PackedStringArray()
	# The save path is shared with other importers of the same file: iterate the keys instead of
	# indexing, so a foreign manifest without "files" is ignored rather than raising an error.
	var container: Variant = manifest
	for key: Variant in container:
		if key is String and key == MANIFEST_FILES_KEY:
			var files: Variant = container[key]
			if files is PackedStringArray:
				return files
	return PackedStringArray()


func _save_manifest(
	save_path: String, absolute_source: String, written: PackedStringArray
) -> Error:
	var manifest := PackedDataContainer.new()
	var pack_error := (
		manifest
		. pack(
			{
				"version": MANIFEST_VERSION,
				"source_md5": FileAccess.get_md5(absolute_source),
				MANIFEST_FILES_KEY: written,
			}
		)
	)
	if pack_error != OK:
		return pack_error
	return ResourceSaver.save(manifest, "%s.%s" % [save_path, SAVE_EXTENSION])

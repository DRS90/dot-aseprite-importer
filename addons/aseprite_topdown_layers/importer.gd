@tool
extends EditorImportPlugin
## Imports .aseprite/.ase files as one PNG strip per top-level layer (or group) and tag.
##
## The imported resource is only a manifest (PackedDataContainer) with the PNGs written, so the next
## import can delete strips that are no longer produced. Strips are exported to a cache folder first
## and copied into the project only when their MD5 differs: re-importing an unchanged source does
## not cascade into texture reimports.

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
const OPTION_ONLY_VISIBLE := "layers/only_visible"
const OPTION_LAYER_EXCLUDE := "layers/exclude_pattern"
const OPTION_TAG_EXCLUDE := "tags/exclude_pattern"
const OPTION_SHEET_TYPE := "sheet/type"

var _scheduler: FsScanScheduler
var _settings: Settings
var _planner := ExportPlanner.new()


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


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
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
		{"name": OPTION_ONLY_VISIBLE, "default_value": false},
		{
			"name": OPTION_LAYER_EXCLUDE,
			"default_value": _project_default(Settings.DEFAULT_LAYER_EXCLUDE_KEY),
		},
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

	var absolute_source := ProjectSettings.globalize_path(source_file)
	var only_visible: bool = options.get(OPTION_ONLY_VISIBLE, false)
	var layers := cli.list_layers(absolute_source, only_visible)
	if layers.is_empty():
		push_error(LOG_PREFIX + "No layers found in '%s'." % source_file)
		return FAILED
	var tags := cli.list_tags(absolute_source)

	var base_dir := source_file.get_base_dir()
	var folder := str(options.get(OPTION_FOLDER, ""))
	if folder.begins_with(RES_PREFIX):
		base_dir = RES_PREFIX
		folder = folder.trim_prefix(RES_PREFIX)
	var title := source_file.get_file().get_basename()
	var jobs := _planner.build_jobs(title, layers, tags, _planner_options(options, folder))
	for message: String in _planner.errors:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, message])

	var sheet_type := _sheet_type(options)
	var cache_dir := OS.get_cache_dir().path_join(CACHE_FOLDER).path_join(
		absolute_source.md5_text()
	)
	var written := PackedStringArray()
	for job: Dictionary in jobs:
		var relative_path: String = job["relative_path"]
		var job_layers: PackedStringArray = job["layers"]
		var tag: String = job["tag"]
		var target := base_dir.path_join(relative_path).simplify_path()
		if not target.begins_with(RES_PREFIX):
			push_error(LOG_PREFIX + "Output '%s' is outside the project." % target)
			return ERR_FILE_BAD_PATH
		var exported := cache_dir.path_join(relative_path)
		if cli.export_strip(absolute_source, job_layers, tag, sheet_type, exported) != OK:
			return FAILED
		var copy_error := _copy_if_changed(exported, target)
		if copy_error != OK:
			return copy_error
		written.append(target)

	var delete_stale: bool = options.get(OPTION_DELETE_STALE, true)
	if delete_stale:
		_delete_stale(_load_previous_files(save_path), written)
	var save_error := _save_manifest(save_path, absolute_source, written)
	# Never scan from inside _import(): the scheduler runs it deferred, after the import ends.
	if is_instance_valid(_scheduler):
		_scheduler.schedule()
	return save_error


func _project_default(key: String) -> String:
	var fallback: String = Settings.PROJECT_DEFAULTS.get(key, "")
	if _settings == null:
		return fallback
	return _settings.get_project_default(key, fallback)


func _planner_options(options: Dictionary, folder: String) -> Dictionary:
	return {
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


func _delete_stale(previous: PackedStringArray, written: PackedStringArray) -> void:
	for path: String in previous:
		# Only PNGs this importer wrote inside the project are ever deleted.
		if written.has(path) or not path.begins_with(RES_PREFIX) or path.get_extension() != "png":
			continue
		for doomed: String in [path, path + ".import"]:
			if FileAccess.file_exists(doomed):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(doomed))


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

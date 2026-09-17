@tool
extends EditorImportPlugin
## Imports .aseprite/.ase files as a SpriteFrames resource, with one animation per tag, timed like
## in Aseprite. Frames drawn as a 3x3 grid of directions give one animation per direction and tag;
## with grid/directions set to none the frame is one cell and the sprite has no direction.
##
## Aseprite exports one strip per animation to a cache folder, and the strips become textures
## embedded in the imported resource: nothing is written to the project, and exporting a scene that
## uses the file exports the textures with it. The strips cannot be imported as project textures
## instead: append_import_external_resource() fails for files created during the import itself.

const AsepriteCli := preload("aseprite_cli.gd")
const ExportPlanner := preload("export_planner.gd")
const Settings := preload("settings.gd")
const SpriteFramesBuilder := preload("sprite_frames_builder.gd")

const IMPORTER_NAME := "aseprite_topdown_grid_animations.importer"
const VISIBLE_NAME := "Aseprite Top-Down Grid Animations"
const LOG_PREFIX := "[Aseprite Top-Down Grid Animations] "
const SAVE_EXTENSION := "res"
## Bumped when the imported resource changes, so Godot reimports every file using this importer.
const FORMAT_VERSION := 1
const CACHE_FOLDER := "aseprite_topdown_grid_animations"

const OPTION_DIRECTIONS := "grid/directions"
const OPTION_CELL_SIZE := "grid/cell_size"
const OPTION_LAYER := "layers/layer"
const OPTION_LAYER_EXCLUDE := "layers/exclude_pattern"
const OPTION_ONLY_VISIBLE := "layers/only_visible"
const OPTION_TAG_EXCLUDE := "tags/exclude_pattern"
const OPTION_ANIMATION_NAME := "sprite_frames/animation_name"
const OPTION_LOOP_SUFFIX := "sprite_frames/loop_suffix"

var _settings: Settings
var _planner := ExportPlanner.new()
var _builder := SpriteFramesBuilder.new()
var _verified_executable := ""
## res:// path -> {"md5": String, "contents": Dictionary} of the last Aseprite listing.
var _contents_cache := {}


func _init(settings: Settings) -> void:
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
	return "SpriteFrames"


func _get_format_version() -> int:
	return FORMAT_VERSION


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
			"name": OPTION_DIRECTIONS,
			"default_value": ExportPlanner.MODE_3X3,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "%s,%s" % [ExportPlanner.MODE_3X3, ExportPlanner.MODE_NONE],
		},
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
			"name": OPTION_ANIMATION_NAME,
			"default_value": _project_default(Settings.DEFAULT_ANIMATION_NAME_KEY),
		},
		{
			"name": OPTION_LOOP_SUFFIX,
			"default_value": _project_default(Settings.DEFAULT_LOOP_SUFFIX_KEY),
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
	var jobs := _planner.build_jobs(sprite_size, layers, tags, _planner_options(options))
	for message: String in _planner.errors:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, message])
	if _planner.failed:
		return FAILED

	var absolute_source := ProjectSettings.globalize_path(source_file)
	var strips_dir := OS.get_cache_dir().path_join(CACHE_FOLDER).path_join(
		absolute_source.md5_text()
	)
	var export_error := cli.export_strips(
		absolute_source,
		jobs,
		_planner.composed_layers,
		_planner.cell_size,
		_planner.cells_per_axis,
		strips_dir
	)
	if export_error != OK:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, cli.last_error])
		return FAILED
	var frames := _builder.build(jobs, cli.last_written, strips_dir, contents, _planner.cell_size)
	for message: String in _builder.errors:
		push_error(LOG_PREFIX + "%s: %s" % [source_file, message])
	if not _builder.errors.is_empty():
		return FAILED
	return ResourceSaver.save(frames, "%s.%s" % [save_path, SAVE_EXTENSION])


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


func _planner_options(options: Dictionary) -> Dictionary:
	return {
		"directions": str(options.get(OPTION_DIRECTIONS, ExportPlanner.MODE_3X3)),
		"cell_size": options.get(OPTION_CELL_SIZE, Vector2i.ZERO),
		"layer": str(options.get(OPTION_LAYER, ExportPlanner.ALL_LAYERS)),
		"layer_exclude_pattern": str(options.get(OPTION_LAYER_EXCLUDE, "")),
		"tag_exclude_pattern": str(options.get(OPTION_TAG_EXCLUDE, "")),
		"animation_name":
		str(options.get(OPTION_ANIMATION_NAME, ExportPlanner.DEFAULT_ANIMATION_NAME)),
		"loop_suffix": str(options.get(OPTION_LOOP_SUFFIX, ExportPlanner.DEFAULT_LOOP_SUFFIX)),
	}

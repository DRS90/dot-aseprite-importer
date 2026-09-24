@tool
extends EditorImportPlugin
## Imports .aseprite/.ase files as a SpriteFrames resource, with one animation per tag, timed like
## in Aseprite. With grid/directions set to 3x3, frames drawn as a 3x3 grid of facing directions
## give one animation per direction and tag; at none, the default, the frame is a single cell.
##
## Layers, tags and frame durations are read from the file itself, so Aseprite runs once per
## import, to export one strip per animation to a cache folder. The strips are packed into one
## sheet, each frame trimmed and repeated frames stored once, embedded in the imported resource as
## a single texture: nothing is written to the project, and exporting a scene that uses the file
## exports the texture with it.
## The sheet cannot be imported as a project texture instead: append_import_external_resource()
## fails for files created during the import itself.

const AsepriteSource := preload("aseprite_source.gd")
const ExportPlanner := preload("export_planner.gd")
const Settings := preload("settings.gd")
const SpriteFramesBuilder := preload("sprite_frames_builder.gd")

const IMPORTER_NAME := "dot_aseprite_importer.sprite_frames"
const VISIBLE_NAME := "Dot Aseprite SpriteFrames"
const LOG_PREFIX := AsepriteSource.LOG_PREFIX
const SAVE_EXTENSION := "res"
## Bumped when the imported resource changes, so Godot reimports every file using this importer.
const FORMAT_VERSION := 3
const CACHE_FOLDER := AsepriteSource.CACHE_FOLDER

const OPTION_DIRECTIONS := "grid/directions"
const OPTION_CELL_SIZE := "grid/cell_size"
const OPTION_LAYER := "layers/layer"
const OPTION_LAYER_EXCLUDE := "layers/exclude_pattern"
const OPTION_ONLY_VISIBLE := "layers/only_visible"
const OPTION_TAG_EXCLUDE := "tags/exclude_pattern"
const OPTION_ANIMATION_NAME := "sprite_frames/animation_name"
const OPTION_LOOP_SUFFIX := "sprite_frames/loop_suffix"

var _settings: Settings
var _source: AsepriteSource
var _planner := ExportPlanner.new()
var _builder := SpriteFramesBuilder.new()


func _init(settings: Settings, source: AsepriteSource) -> void:
	_settings = settings
	_source = source


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
		directions_option(),
		{"name": OPTION_CELL_SIZE, "default_value": Vector2i.ZERO},
		{
			"name": OPTION_LAYER,
			"default_value": ExportPlanner.ALL_LAYERS,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": _source.layer_choices(path),
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


## The grid/directions option, apart so headless tests can read its default: an
## EditorImportPlugin can only be instantiated by the editor.
static func directions_option() -> Dictionary:
	return {
		"name": OPTION_DIRECTIONS,
		"default_value": ExportPlanner.DEFAULT_DIRECTIONS,
		"property_hint": PROPERTY_HINT_ENUM,
		"hint_string": "%s,%s" % [ExportPlanner.MODE_NONE, ExportPlanner.MODE_3X3],
	}


func _import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var cli := _source.verified_cli()
	if cli == null:
		push_error(LOG_PREFIX + _source.last_error)
		return ERR_UNCONFIGURED

	var contents := _source.list(source_file)
	if contents.is_empty():
		push_error(LOG_PREFIX + "%s: %s" % [source_file, _source.last_error])
		return FAILED
	var only_visible: bool = options.get(OPTION_ONLY_VISIBLE, false)
	var sprite_size: Vector2i = contents["size"]
	var layers: PackedStringArray = contents["visible_layers" if only_visible else "layers"]
	var tags: PackedStringArray = contents["tags"]
	var jobs := _planner.build_jobs(sprite_size, layers, tags, planner_options(options))
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
	# Compressed: the frames' AtlasTextures take a third of the space, and it loads as fast.
	var path := "%s.%s" % [save_path, SAVE_EXTENSION]
	return ResourceSaver.save(frames, path, ResourceSaver.FLAG_COMPRESS)


func _project_default(key: String) -> String:
	var fallback: String = Settings.PROJECT_DEFAULTS.get(key, "")
	if _settings == null:
		return fallback
	return _settings.get_project_default(key, fallback)


## The import options as the planner takes them, with the defaults of any option the .import file
## does not have.
static func planner_options(options: Dictionary) -> Dictionary:
	return {
		"directions": str(options.get(OPTION_DIRECTIONS, ExportPlanner.DEFAULT_DIRECTIONS)),
		"cell_size": options.get(OPTION_CELL_SIZE, Vector2i.ZERO),
		"layer": str(options.get(OPTION_LAYER, ExportPlanner.ALL_LAYERS)),
		"layer_exclude_pattern": str(options.get(OPTION_LAYER_EXCLUDE, "")),
		"tag_exclude_pattern": str(options.get(OPTION_TAG_EXCLUDE, "")),
		"animation_name":
		str(options.get(OPTION_ANIMATION_NAME, ExportPlanner.DEFAULT_ANIMATION_NAME)),
		"loop_suffix": str(options.get(OPTION_LOOP_SUFFIX, ExportPlanner.DEFAULT_LOOP_SUFFIX)),
	}

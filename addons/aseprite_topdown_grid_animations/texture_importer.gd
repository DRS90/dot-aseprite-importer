@tool
extends EditorImportPlugin
## Imports .aseprite/.ase files as a plain texture, so the file can be used wherever Godot takes a
## Texture2D: Sprite2D, TextureRect, a shader uniform or the source image of a TileSet.
##
## The whole canvas is exported, with every frame of the timeline side by side, which is the layout
## Sprite2D.hframes and animated TileSet tiles expect; a file with a single frame therefore gives
## exactly its image. Tags, frame durations and the grid of directions belong to the SpriteFrames
## importer and are ignored here. That importer has the higher priority, so this one is chosen per
## file with Import As.

const AsepriteCli := preload("aseprite_cli.gd")
const AsepriteSource := preload("aseprite_source.gd")
const ExportPlanner := preload("export_planner.gd")
const Settings := preload("settings.gd")
const SpriteFramesBuilder := preload("sprite_frames_builder.gd")

const IMPORTER_NAME := "aseprite_topdown_grid_animations.texture_importer"
const VISIBLE_NAME := "Aseprite Texture"
const LOG_PREFIX := AsepriteSource.LOG_PREFIX
const SAVE_EXTENSION := "res"
## Bumped when the imported resource changes, so Godot reimports every file using this importer.
const FORMAT_VERSION := 1
## Below the SpriteFrames importer, which stays the default for a file nobody has chosen for.
const PRIORITY := 0.9
const CACHE_FOLDER := "aseprite_topdown_grid_animations"
## Subfolder of the cache, so the two importers of one file never share exported files.
const CACHE_LEAF := "texture"
## Widest texture the graphics drivers accept. A strip past it would render as nothing.
const MAX_TEXTURE_WIDTH := 16384

const OPTION_LAYER := "layers/layer"
const OPTION_LAYER_EXCLUDE := "layers/exclude_pattern"
const OPTION_ONLY_VISIBLE := "layers/only_visible"

var _settings: Settings
var _source: AsepriteSource
var _planner := ExportPlanner.new()


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


## The exact class, like the engine's own texture importer declares CompressedTexture2D: the type is
## what the FileSystem dock shows and what ResourceLoader.get_resource_type() reports. Dropping the
## file on a Texture2D property works either way, because the inspector asks the loaded resource
## for its class instead of reading this.
func _get_resource_type() -> String:
	return "PortableCompressedTexture2D"


func _get_format_version() -> int:
	return FORMAT_VERSION


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_priority() -> float:
	return PRIORITY


func _get_import_order() -> int:
	return 0


## Both importers share one listing cache, which is a plain Dictionary.
func _can_import_threaded() -> bool:
	return false


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _get_import_options(path: String, _preset_index: int) -> Array[Dictionary]:
	return [
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
	]


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
	var strip := _export_strip(cli, source_file, options)
	if strip == "":
		return FAILED
	# The compressed bytes are kept, so Make Unique and Save As on the imported texture do not hand
	# back an empty image.
	var texture := SpriteFramesBuilder.load_strip_texture(strip, true)
	if texture == null:
		_report(source_file, "cannot read the exported image.")
		return FAILED
	return ResourceSaver.save(texture, "%s.%s" % [save_path, SAVE_EXTENSION])


## Exports the whole canvas, every frame side by side, and returns the file Aseprite wrote, or ""
## after reporting why it could not. Failing instead of saving something wrong is what keeps the
## previously imported texture in place.
func _export_strip(cli: AsepriteCli, source_file: String, options: Dictionary) -> String:
	var contents := _source.list(cli, source_file)
	if contents.is_empty():
		_report(source_file, cli.last_error)
		return ""
	var only_visible: bool = options.get(OPTION_ONLY_VISIBLE, false)
	var layers: PackedStringArray = contents["visible_layers" if only_visible else "layers"]
	# No tags: one job for the whole timeline, and no grid, so the cell is the whole canvas.
	var jobs := _planner.build_jobs(
		contents["size"], layers, PackedStringArray(), _planner_options(options)
	)
	for message: String in _planner.errors:
		_report(source_file, message)
	if _planner.failed:
		return ""

	var frames: int = contents.get("frame_durations", PackedInt32Array()).size()
	if exceeds_texture_width(_planner.cell_size.x, frames):
		_report(
			source_file,
			(
				"its %d frames make a strip %d pixels wide, over the %d a texture can be."
				% [frames, _planner.cell_size.x * frames, MAX_TEXTURE_WIDTH]
			)
		)
		return ""

	var absolute_source := ProjectSettings.globalize_path(source_file)
	# A leaf of its own, so the two importers of a same file do not share a folder.
	var strips_dir := (
		OS
		. get_cache_dir()
		. path_join(CACHE_FOLDER)
		. path_join(absolute_source.md5_text())
		. path_join(CACHE_LEAF)
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
		_report(source_file, cli.last_error)
		return ""
	# A canvas with no pixels in any frame writes no strip at all.
	if cli.last_written.is_empty():
		_report(source_file, "the chosen layers have no pixels in any frame.")
		return ""
	return strips_dir.path_join(str(jobs[0]["relative_path"]))


func _report(source_file: String, message: String) -> void:
	push_error(LOG_PREFIX + "%s: %s" % [source_file, message])


## True when [param frames] cells of [param cell_width] side by side would be wider than the
## graphics drivers accept, which would render as nothing at all.
static func exceeds_texture_width(cell_width: int, frames: int) -> bool:
	return cell_width * frames > MAX_TEXTURE_WIDTH


func _project_default(key: String) -> String:
	var fallback: String = Settings.PROJECT_DEFAULTS.get(key, "")
	if _settings == null:
		return fallback
	return _settings.get_project_default(key, fallback)


func _planner_options(options: Dictionary) -> Dictionary:
	return {
		"directions": ExportPlanner.MODE_NONE,
		"cell_size": Vector2i.ZERO,
		"layer": str(options.get(OPTION_LAYER, ExportPlanner.ALL_LAYERS)),
		"layer_exclude_pattern": str(options.get(OPTION_LAYER_EXCLUDE, "")),
	}

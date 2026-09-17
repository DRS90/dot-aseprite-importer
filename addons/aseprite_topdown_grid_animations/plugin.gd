@tool
extends EditorPlugin
## Registers the addon's two importers (a SpriteFrames of the 3x3 grid of directions, and a plain
## texture), its settings, the AnimationPlayer section of the AnimatedSprite2D inspector and the
## Project > Tools item, and keeps linked AnimationPlayers in sync with their sprites.

const AnimatedSpriteInspector := preload("animated_sprite_inspector.gd")
const AnimationSync := preload("animation_sync.gd")
const AsepriteSource := preload("aseprite_source.gd")
const Importer := preload("importer.gd")
const Settings := preload("settings.gd")
const TextureImporter := preload("texture_importer.gd")

const REIMPORT_ALL_MENU := "Aseprite Top-Down Grid Animations: Reimport all"
const SOURCE_EXTENSIONS: Array[String] = ["aseprite", "ase"]

var _settings: Settings
var _source: AsepriteSource
var _importer: Importer
var _texture_importer: TextureImporter
var _inspector: AnimatedSpriteInspector
var _sync := AnimationSync.new()


func _enter_tree() -> void:
	_settings = Settings.new()
	_settings.register()
	# One source for every importer: the executable is checked once and a file listed once.
	_source = AsepriteSource.new(_settings.get_executable_path)
	_importer = Importer.new(_settings, _source)
	add_import_plugin(_importer)
	_texture_importer = TextureImporter.new(_settings, _source)
	add_import_plugin(_texture_importer)
	_inspector = AnimatedSpriteInspector.new()
	add_inspector_plugin(_inspector)
	add_tool_menu_item(REIMPORT_ALL_MENU, _reimport_all)
	EditorInterface.get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system.resources_reimported.is_connected(_on_resources_reimported):
		file_system.resources_reimported.disconnect(_on_resources_reimported)
	remove_tool_menu_item(REIMPORT_ALL_MENU)
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
	if _texture_importer != null:
		remove_import_plugin(_texture_importer)
		_texture_importer = null
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null


func _on_resources_reimported(resources: PackedStringArray) -> void:
	for path: String in resources:
		if SOURCE_EXTENSIONS.has(path.get_extension().to_lower()):
			# The editor reloads the reimported SpriteFrames after this signal: sync a frame later.
			_sync_edited_scene.call_deferred()
			return


func _on_scene_changed(_scene_root: Node) -> void:
	_sync_edited_scene()


## Syncs every AnimatedSprite2D of the edited scene whose linked AnimationPlayer is out of date.
func _sync_edited_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var nodes := root.find_children("*", "AnimatedSprite2D", true, false)
	nodes.append(root)
	var changed := false
	for node: Node in nodes:
		var sprite := node as AnimatedSprite2D
		# Nodes of instanced scenes belong to their own scene: changes made here would be lost.
		if sprite == null or (sprite != root and sprite.owner != root):
			continue
		if _sync.sync_linked(sprite, false):
			changed = true
			for message: String in _sync.errors:
				push_warning(AsepriteSource.LOG_PREFIX + message)
	if changed:
		EditorInterface.mark_scene_as_unsaved()


## Forces a reimport of every .aseprite/.ase file assigned to one of this addon's importers, e.g.
## after the executable path or a project default changed.
func _reimport_all() -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system.is_scanning():
		push_warning(
			AsepriteSource.LOG_PREFIX + "The file system is being scanned; try again after it."
		)
		return
	var sources := _find_sources(file_system.get_filesystem())
	if sources.is_empty():
		push_warning(AsepriteSource.LOG_PREFIX + "No .aseprite/.ase file uses this addon.")
		return
	file_system.reimport_files(sources)


func _find_sources(directory: EditorFileSystemDirectory) -> PackedStringArray:
	var sources := PackedStringArray()
	if directory == null:
		return sources
	for index: int in directory.get_file_count():
		var path := directory.get_file_path(index)
		if SOURCE_EXTENSIONS.has(path.get_extension().to_lower()) and _uses_this_addon(path):
			sources.append(path)
	for index: int in directory.get_subdir_count():
		sources.append_array(_find_sources(directory.get_subdir(index)))
	return sources


## True when [param path] is imported by this addon, whichever of its importers was chosen.
static func _uses_this_addon(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return false
	var importer := str(config.get_value("remap", "importer", ""))
	return importer == Importer.IMPORTER_NAME or importer == TextureImporter.IMPORTER_NAME

@tool
extends EditorPlugin
## Registers the Aseprite Top-Down Layers importer, its settings and the Project > Tools item.

const FsScanScheduler := preload("fs_scan_scheduler.gd")
const Importer := preload("importer.gd")
const Settings := preload("settings.gd")

const REIMPORT_ALL_MENU := "Aseprite Top-Down Layers: Reimport all"
const SOURCE_EXTENSIONS: Array[String] = ["aseprite", "ase"]

var _settings: Settings
var _scheduler: FsScanScheduler
var _importer: Importer


func _enter_tree() -> void:
	_settings = Settings.new()
	_settings.register()
	_scheduler = FsScanScheduler.new()
	add_child(_scheduler)
	_importer = Importer.new(_scheduler, _settings)
	add_import_plugin(_importer)
	add_tool_menu_item(REIMPORT_ALL_MENU, _reimport_all)


func _exit_tree() -> void:
	remove_tool_menu_item(REIMPORT_ALL_MENU)
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null
	if is_instance_valid(_scheduler):
		_scheduler.queue_free()
	_scheduler = null


## Forces a reimport of every .aseprite/.ase file assigned to this importer, e.g. after the
## executable path or a project default changed.
func _reimport_all() -> void:
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system.is_scanning():
		push_warning(Importer.LOG_PREFIX + "The file system is being scanned; try again after it.")
		return
	var sources := _find_sources(file_system.get_filesystem())
	if sources.is_empty():
		push_warning(Importer.LOG_PREFIX + "No .aseprite/.ase file uses this importer.")
		return
	file_system.reimport_files(sources)


func _find_sources(directory: EditorFileSystemDirectory) -> PackedStringArray:
	var sources := PackedStringArray()
	if directory == null:
		return sources
	for index: int in directory.get_file_count():
		var path := directory.get_file_path(index)
		if SOURCE_EXTENSIONS.has(path.get_extension().to_lower()) and _uses_this_importer(path):
			sources.append(path)
	for index: int in directory.get_subdir_count():
		sources.append_array(_find_sources(directory.get_subdir(index)))
	return sources


static func _uses_this_importer(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return false
	return str(config.get_value("remap", "importer", "")) == Importer.IMPORTER_NAME

@tool
extends EditorPlugin
## Registers the Aseprite Top-Down Layers importer and its settings.

const FsScanScheduler := preload("fs_scan_scheduler.gd")
const Importer := preload("importer.gd")
const Settings := preload("settings.gd")

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


func _exit_tree() -> void:
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null
	if is_instance_valid(_scheduler):
		_scheduler.queue_free()
	_scheduler = null

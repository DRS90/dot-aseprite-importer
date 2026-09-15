@tool
extends Node
## Debounced EditorFileSystem.scan().
##
## The importer writes PNGs during _import(), where scanning or reimporting is not allowed. It calls
## schedule() instead; the scan runs once no call arrived for WAIT_TIME_SECONDS, deferred, and
## never on top of a scan that is already running.

const WAIT_TIME_SECONDS := 0.8

var _time_left := 0.0
var _scheduled := false


func _ready() -> void:
	set_process(_scheduled)


func schedule() -> void:
	_time_left = WAIT_TIME_SECONDS
	_scheduled = true
	set_process.call_deferred(true)


func _process(delta: float) -> void:
	if not _scheduled:
		set_process(false)
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	var file_system := EditorInterface.get_resource_filesystem()
	if file_system == null:
		return
	if file_system.is_scanning():
		# Files written during this scan may be missed by it: try again after it ends.
		_time_left = WAIT_TIME_SECONDS
		return
	_scheduled = false
	set_process(false)
	file_system.scan.call_deferred()

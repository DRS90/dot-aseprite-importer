@tool
extends VBoxContainer
## Inspector section of an AnimatedSprite2D: links an AnimationPlayer and syncs the sprite's
## animations into it.

const AnimationSync := preload("animation_sync.gd")
const LOG_PREFIX := "[Aseprite Top-Down Layers] "

var _sprite: AnimatedSprite2D
var _sync := AnimationSync.new()
var _player_button := Button.new()
var _clear_button := Button.new()
var _sync_button := Button.new()
var _status := Label.new()


func _init(sprite: AnimatedSprite2D) -> void:
	_sprite = sprite
	var title := Label.new()
	title.text = "AnimationPlayer"
	title.tooltip_text = "AnimationPlayer that receives this sprite's animations."
	add_child(title)

	var row := HBoxContainer.new()
	_player_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_button.clip_text = true
	_player_button.tooltip_text = "Choose the AnimationPlayer."
	_player_button.pressed.connect(_on_player_pressed)
	row.add_child(_player_button)
	_clear_button.text = "Clear"
	_clear_button.tooltip_text = "Unlink the AnimationPlayer. Its animations are kept."
	_clear_button.pressed.connect(_on_clear_pressed)
	row.add_child(_clear_button)
	add_child(row)

	_sync_button.text = "Sync animations"
	_sync_button.tooltip_text = (
		"Write this sprite's animations into the AnimationPlayer now. This also happens when the "
		+ "Aseprite file is reimported and when the scene is opened."
	)
	_sync_button.pressed.connect(_sync_now)
	add_child(_sync_button)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_refresh()


func _refresh() -> void:
	var player := AnimationSync.linked_player(_sprite)
	_player_button.text = "Assign..." if player == null else str(_sprite.get_path_to(player))
	_clear_button.disabled = player == null
	_sync_button.disabled = player == null


func _on_player_pressed() -> void:
	var current := AnimationSync.linked_player(_sprite)
	EditorInterface.popup_node_selector(_on_player_selected, [&"AnimationPlayer"], current)


func _on_player_selected(path: NodePath) -> void:
	if path.is_empty():
		return
	var root := EditorInterface.get_edited_scene_root()
	var player: AnimationPlayer = null
	if root != null:
		player = root.get_node_or_null(path) as AnimationPlayer
	if player == null:
		_status.text = "Cannot find the AnimationPlayer at %s." % path
		return
	AnimationSync.link(_sprite, player)
	_sync_now()


func _on_clear_pressed() -> void:
	AnimationSync.link(_sprite, null)
	EditorInterface.mark_scene_as_unsaved()
	_status.text = "Unlinked. The animations already written stay in the AnimationPlayer."
	_refresh()


func _sync_now() -> void:
	if _sprite.sprite_frames == null:
		_status.text = "Assign SpriteFrames (an .aseprite file) to this sprite first."
		_refresh()
		return
	_sync.sync_linked(_sprite, true)
	EditorInterface.mark_scene_as_unsaved()
	for message: String in _sync.errors:
		push_warning(LOG_PREFIX + message)
	var count := _sprite.sprite_frames.get_animation_names().size()
	_status.text = (
		"Synced %d animations." % count if _sync.errors.is_empty() else "\n".join(_sync.errors)
	)
	_refresh()

@tool
extends EditorInspectorPlugin
## Adds the AnimationPlayer section to the AnimatedSprite2D category of the inspector.

const AnimationPlayerPanel := preload("animation_player_panel.gd")
const CATEGORY := "AnimatedSprite2D"


func _can_handle(object: Object) -> bool:
	return object is AnimatedSprite2D


func _parse_category(object: Object, category: String) -> void:
	var sprite := object as AnimatedSprite2D
	if sprite != null and category == CATEGORY:
		add_custom_control(AnimationPlayerPanel.new(sprite))

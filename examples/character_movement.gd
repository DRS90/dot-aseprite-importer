extends AnimatedSprite2D
## Demo movement: arrow keys walk in four directions through the linked AnimationPlayer, and
## releasing them stands on the first frame of the last direction.

const SPEED := 60.0

@export var animation_player: AnimationPlayer

var _facing := "down"


func _process(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	position += input * SPEED * delta
	if input != Vector2.ZERO:
		if absf(input.x) > absf(input.y):
			_facing = "right" if input.x > 0.0 else "left"
		else:
			_facing = "down" if input.y > 0.0 else "up"
	var animation_name := "walk_" + _facing
	if input == Vector2.ZERO:
		animation_player.play(animation_name)
		animation_player.seek(0.0, true)
		animation_player.pause()
	elif animation_player.current_animation != animation_name or not animation_player.is_playing():
		animation_player.play(animation_name)

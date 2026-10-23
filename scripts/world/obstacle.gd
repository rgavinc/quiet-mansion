extends Node2D
## Breakable prop — makes noise when knocked. Back End owns.

@export var noise_level: float = 1.0
var broken: bool = false

func _ready() -> void:
	add_to_group("obstacles")
	var r := ColorRect.new()
	r.size = Vector2(20, 20)
	r.position = Vector2(-10, -10)
	r.color = Color(0.45, 0.35, 0.25)
	add_child(r)

func break_apart() -> void:
	if broken:
		return
	broken = true
	GameState.make_noise(noise_level, global_position)
	queue_free()

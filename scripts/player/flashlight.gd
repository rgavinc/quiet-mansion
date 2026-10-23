extends Node2D
## Mouse-aim cone. Front End owns feel; keep API stable for darkness overlay.

func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())

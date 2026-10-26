class_name Vase
extends WorldObject
## Vase: default noise radius, can be picked up and thrown, may hide gold.


func _init() -> void:
	display_name = "Vase"
	art_slot = "vase_idle"
	can_pick_up = true
	throwable = true
	size = Vector2(16, 22)


func _ready() -> void:
	if gold_inside == 0 and randf() < 0.45:
		gold_inside = randi_range(1, 3)
	super._ready()

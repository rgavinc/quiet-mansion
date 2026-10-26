extends Node2D
## Loose gold. Collected by walking over it.

var amount: int = 1


func _ready() -> void:
	add_to_group("gold")
	var r := ColorRect.new()
	r.size = Vector2(6, 6)
	r.position = Vector2(-3, -3)
	r.color = Color(1.0, 0.82, 0.2)
	add_child(r)


func _physics_process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p and p.global_position.distance_to(global_position) <= 14.0:
		PlayerStats.add_gold(amount)
		queue_free()

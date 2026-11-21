extends Node2D
## Loose gold. Collected by walking over it. Renders `gold_coin` (a stacked pile when
## the amount is more than 1); a 6×6 ColorRect if that slot is missing.

var amount: int = 1


func _ready() -> void:
	add_to_group("gold")
	PropVisual.add_gold_pile(self, amount)


func _physics_process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p and p.global_position.distance_to(global_position) <= 14.0:
		PlayerStats.add_gold(amount)
		queue_free()

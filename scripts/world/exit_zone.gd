extends Area2D
## Reach exit to win round 1. Back End owns.

func _ready() -> void:
	add_to_group("exit")
	monitoring = true
	monitorable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 64)
	shape.shape = rect
	add_child(shape)
	var spr := Sprite2D.new()
	var tex := load("res://assets/art/props/exit_door.png")
	if tex:
		spr.texture = tex
	add_child(spr)
	body_entered.connect(_on_body)
	# Also detect CharacterBody2D via area if needed — use physics process proximity as fallback

func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		GameState.on_reach_exit()

func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and global_position.distance_to(player.global_position) < 40.0:
		GameState.on_reach_exit()

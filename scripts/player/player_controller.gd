extends CharacterBody2D
## WASD move + mouse flashlight child. Back End owns motion/noise API.

@export var knock_range: float = 36.0

func _ready() -> void:
	add_to_group("player")
	var spr := Sprite2D.new()
	var tex := load("res://assets/art/characters/boy_side_idle.png")
	if tex:
		spr.texture = tex
	add_child(spr)
	var light := Node2D.new()
	light.name = "Flashlight"
	light.set_script(load("res://scripts/player/flashlight.gd"))
	add_child(light)

func _physics_process(_delta: float) -> void:
	if GameState.game_over:
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = dir * PlayerStats.get_stat(&"move_speed")
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	# Input-map actions only (see project.godot). Space = jump, RMB = light toggle.
	if event.is_action_pressed(&"flashlight_toggle"):
		var light := get_node_or_null(^"Flashlight")
		if light:
			light.visible = not light.visible
	# Interim: LMB knocks nearby things until the hold-to-pickup / tap-to-throw state lands.
	elif event.is_action_pressed(&"interact"):
		_try_knock()

func _try_knock() -> void:
	var made_noise := false
	for node in get_tree().get_nodes_in_group("obstacles"):
		if node is Node2D and global_position.distance_to((node as Node2D).global_position) <= knock_range:
			if node.has_method("break_apart"):
				node.break_apart()
				made_noise = true
	for node in get_tree().get_nodes_in_group("puppets"):
		if node is Node2D and global_position.distance_to((node as Node2D).global_position) <= knock_range:
			if node.has_method("try_knock_kill"):
				var killed: bool = node.try_knock_kill()
				if not killed:
					made_noise = true
	if made_noise:
		GameState.make_noise(1.0, global_position)

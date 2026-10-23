extends CharacterBody2D
## WASD move + mouse flashlight child. Back End owns motion/noise API.

@export var move_speed: float = 140.0
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
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	velocity = dir.normalized() * move_speed if dir != Vector2.ZERO else Vector2.ZERO
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	# Space / left-click near obstacle = try knock (noise + maybe kill calm puppet)
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_try_knock()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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

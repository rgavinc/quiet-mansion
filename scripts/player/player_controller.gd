extends CharacterBody2D
## WASD move + mouse flashlight child. Back End owns motion/noise API.

@export var knock_range: float = 36.0

var facing: int = 1  # 1 right, -1 left
var _interact_down_ms: int = -1

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
	if dir.x != 0.0:
		facing = 1 if dir.x > 0.0 else -1
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
			FESignals.set_flashlight(light.visible)  # HUD ring/startle follow the real light
	elif event.is_action_pressed(&"interact"):
		_interact_down_ms = Time.get_ticks_msec()
	elif event.is_action_released(&"interact") and _interact_down_ms >= 0:
		var held := (Time.get_ticks_msec() - _interact_down_ms) / 1000.0
		_interact_down_ms = -1
		# Tap only (< tap_threshold). A hold is the pickup channel (next PR), never a knock.
		if held < PlayerStats.get_stat(&"tap_threshold"):
			_try_knock()

## Tap LMB, empty hands: knock over the ONE nearest prop in range on the side you face.
func _try_knock() -> void:
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("obstacles") + get_tree().get_nodes_in_group("puppets"):
		if not (node is Node2D):
			continue
		var to := (node as Node2D).global_position - global_position
		var d := to.length()
		if d > knock_range or to.x * facing < -4.0:
			continue
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return
	var made_noise := false
	if best.has_method("break_apart"):
		best.break_apart()
		made_noise = true
	elif best.has_method("try_knock_kill"):
		made_noise = not best.try_knock_kill()
	if made_noise:
		GameState.make_noise(PlayerStats.get_stat(&"noise_mult"), global_position)

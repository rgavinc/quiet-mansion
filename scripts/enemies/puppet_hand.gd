extends CharacterBody2D
## Calm until noise nearby — then enraged chase. Back End owns.

@export var hear_radius: float = 160.0
@export var chase_speed: float = 95.0
@export var catch_distance: float = 22.0

var enraged: bool = false
var _spr: Sprite2D

func _ready() -> void:
	add_to_group("puppets")
	_spr = Sprite2D.new()
	_set_calm_tex()
	add_child(_spr)
	GameState.noise_made.connect(_on_noise)

func _set_calm_tex() -> void:
	var tex := load("res://assets/art/characters/puppet_hand_calm.png")
	if tex and _spr:
		_spr.texture = tex

func _set_enraged_tex() -> void:
	var tex := load("res://assets/art/characters/puppet_hand_enraged.png")
	if tex and _spr:
		_spr.texture = tex

func _on_noise(level: float, at: Vector2) -> void:
	if enraged or GameState.game_over:
		return
	if global_position.distance_to(at) <= hear_radius * maxf(level, 0.5):
		_alert()

func _alert() -> void:
	enraged = true
	_set_enraged_tex()
	GameState.register_alert()

func _physics_process(_delta: float) -> void:
	if GameState.game_over or not enraged:
		velocity = Vector2.ZERO
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var dir := (player.global_position - global_position).normalized()
	velocity = dir * chase_speed
	move_and_slide()
	if global_position.distance_to(player.global_position) <= catch_distance:
		GameState.on_caught()

## Knock while calm can kill; while enraged or miss → noise risk (caller emits noise).
func try_knock_kill() -> bool:
	if enraged:
		return false
	# 50/50 — miss startles this puppet
	if randf() < 0.5:
		queue_free()
		return true
	_alert()
	return false

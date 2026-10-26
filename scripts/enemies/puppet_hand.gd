extends CharacterBody2D
## Calm until noise nearby — then enraged chase. Back End owns.

@export var hear_radius: float = 160.0
@export var chase_speed: float = 95.0
@export var catch_distance: float = 22.0

var enraged: bool = false
var _spr: AnimatedSprite2D

func _ready() -> void:
	add_to_group("puppets")
	collision_layer = PlayerStats.LAYER_ENEMY
	collision_mask = PlayerStats.LAYER_WORLD
	_spr = AnimatedSprite2D.new()
	add_child(_spr)
	_set_calm_tex()
	NoiseBus.noise.connect(_on_bus_noise)

func _set_calm_tex() -> void:
	_play("puppet_calm")

func _set_enraged_tex() -> void:
	_play("puppet_chase")

## Art by manifest slot only.
func _play(slot: String) -> void:
	if _spr == null:
		return
	if _spr.sprite_frames == null:
		_spr.sprite_frames = AnimLibrary.frames_for(["puppet_calm", "puppet_startle", "puppet_chase"])
	if _spr.sprite_frames.has_animation(slot):
		_spr.play(slot)
		_spr.offset = AnimLibrary.offset_for(slot)

## Hears any noise whose radius reaches it, on screen or not.
func _on_bus_noise(at: Vector2, radius: float, _loudness: float, _source: Node) -> void:
	if enraged or GameState.game_over:
		return
	if NoiseBus.can_hear(global_position, at, radius):
		_alert()


## Thrown object hit: calm puppet is destroyed, an enraged one is stunned briefly.
var _stun_left: float = 0.0
func on_hit_by_throw(_item: Dictionary) -> void:
	if not enraged:
		queue_free()
	else:
		_stun_left = 1.5


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
	if _stun_left > 0.0:
		_stun_left -= _delta
		velocity = Vector2.ZERO
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var dir := (player.global_position - global_position).normalized()
	velocity = dir * chase_speed
	move_and_slide()
	if global_position.distance_to(player.global_position) <= catch_distance:
		# A touch costs one heart (3 = game over via PlayerStats); invuln_time stops repeat hits.
		if PlayerStats.take_hit(1):
			# Shove with collision so a hit can never push the boy through a wall or off the map.
			if player is PhysicsBody2D:
				(player as PhysicsBody2D).move_and_collide(dir * 48.0)

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

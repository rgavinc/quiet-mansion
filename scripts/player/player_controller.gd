extends CharacterBody2D
## Player: move, flashlight (RMB toggle), LMB tap = throw held item at the ringed enemy
## (or knock a prop with empty hands), LMB hold = pickup channel, wheel = inventory.
## Every number comes from PlayerStats. Back End owns.

enum State { NORMAL, PICKUP, CLIMB }

@export var knock_range: float = 36.0
## Side-scroller physics (gravity, jump, stairs). The generator's floor layout turns this on;
## the old top-down test map leaves it off.
@export var side_scroll: bool = false

var state: State = State.NORMAL
var facing: int = 1  # 1 right, -1 left
var inventory: Inventory
var pickup_target: WorldObject = null
var pickup_progress: float = 0.0

var _interact_down: bool = false
var _interact_held: float = 0.0
var _hp_seen: int = -1
var stair: Stair = null
var _stair_t: float = 0.0
var _jump_queued: bool = false
var _throw_anim_left: float = 0.0
var _hurt_anim_left: float = 0.0
var _anim: AnimatedSprite2D
## Test hook: when set, used instead of is_on_floor().
var floor_override: int = -1  # -1 real, 0 airborne, 1 grounded

const ANIM_SLOTS := ["boy_idle", "boy_run", "boy_jump", "boy_pickup", "boy_carry",
		"boy_throw", "boy_climb_stairs", "boy_hurt"]


func _ready() -> void:
	add_to_group("player")
	collision_layer = PlayerStats.LAYER_PLAYER
	collision_mask = PlayerStats.LAYER_WORLD | PlayerStats.LAYER_ENEMY
	_anim = AnimatedSprite2D.new()
	_anim.name = "Anim"
	_anim.sprite_frames = AnimLibrary.frames_for(ANIM_SLOTS)
	add_child(_anim)
	_play_anim("boy_idle")
	var light := Node2D.new()
	light.name = "Flashlight"
	light.set_script(load("res://scripts/player/flashlight.gd"))
	add_child(light)
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	_hp_seen = PlayerStats.health
	PlayerStats.health_changed.connect(_on_health_changed)


func light_on() -> bool:
	var l := get_node_or_null(^"Flashlight")
	return l != null and l.visible


func _physics_process(delta: float) -> void:
	if GameState.game_over:
		velocity = Vector2.ZERO
		return
	tick(delta, Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"))
	if state != State.CLIMB:
		move_and_slide()
	_update_anim(delta)


## All per-frame logic, separate from input polling so tests can drive it.
func tick(delta: float, dir: Vector2) -> void:
	if _interact_down:
		_interact_held += delta
		if state == State.NORMAL and _interact_held >= PlayerStats.get_stat(&"tap_threshold"):
			_try_start_pickup()
	match state:
		State.PICKUP:
			velocity.x = 0.0  # locked in: no moving, no light (gravity still applies)
			if not side_scroll:
				velocity = Vector2.ZERO
			_apply_gravity(delta)
			_tick_pickup(delta)
		State.CLIMB:
			_tick_climb(delta, dir)
		_:
			if dir.x != 0.0:
				facing = 1 if dir.x > 0.0 else -1
			if side_scroll:
				velocity.x = dir.x * PlayerStats.get_stat(&"move_speed")
				_apply_gravity(delta)
				if _jump_queued and _grounded():
					velocity.y = -PlayerStats.get_stat(&"jump_velocity")
				if absf(dir.y) > 0.5:
					_try_enter_stair(dir.y)
			else:
				velocity = dir * PlayerStats.get_stat(&"move_speed")
			_update_hover_select()
	_jump_queued = false


func _grounded() -> bool:
	return is_on_floor() if floor_override < 0 else floor_override == 1


func _apply_gravity(delta: float) -> void:
	if side_scroll and not _grounded():
		velocity.y += PlayerStats.get_stat(&"gravity") * delta


func jump() -> void:
	if side_scroll and state == State.NORMAL:
		_jump_queued = true


# --- stairs -----------------------------------------------------------------
func _try_enter_stair(up_down: float) -> void:
	for s in get_tree().get_nodes_in_group("stairs"):
		if s is Stair and s.is_near(global_position):
			var t: float = s.t_at(global_position)
			# up (negative y) only if not already at top, down only if not at bottom
			if (up_down < 0.0 and t < 0.98) or (up_down > 0.0 and t > 0.02):
				stair = s
				_stair_t = t
				state = State.CLIMB
				velocity = Vector2.ZERO
				return


func _tick_climb(delta: float, dir: Vector2) -> void:
	if not is_instance_valid(stair):
		state = State.NORMAL
		return
	var length := stair.global_bottom().distance_to(stair.global_top())
	var along := -dir.y if absf(dir.y) > 0.1 else dir.x * signf(stair.global_top().x - stair.global_bottom().x)
	_stair_t = clampf(_stair_t + along * PlayerStats.get_stat(&"climb_speed") * delta / maxf(length, 1.0), 0.0, 1.0)
	global_position = stair.point_at(_stair_t)
	var dx := stair.global_top().x - stair.global_bottom().x
	if along != 0.0:
		facing = 1 if (along > 0.0) == (dx > 0.0) else -1
	if (_stair_t >= 1.0 and along > 0.0) or (_stair_t <= 0.0 and along < 0.0):
		state = State.NORMAL  # stepped off onto the floor
		stair = null
		velocity = Vector2.ZERO


# --- animation (slot names only; art comes from the manifest) -------------------
func _play_anim(slot: String) -> void:
	if _anim and _anim.sprite_frames and _anim.sprite_frames.has_animation(slot):
		if _anim.animation != slot or not _anim.is_playing():
			_anim.play(slot)
		_anim.offset = AnimLibrary.offset_for(slot)


func _update_anim(delta: float) -> void:
	if _anim == null:
		return
	_throw_anim_left = maxf(_throw_anim_left - delta, 0.0)
	_hurt_anim_left = maxf(_hurt_anim_left - delta, 0.0)
	_anim.flip_h = facing < 0
	if _hurt_anim_left > 0.0:
		_play_anim("boy_hurt")
	elif _throw_anim_left > 0.0:
		_play_anim("boy_throw")
	elif state == State.PICKUP:
		_play_anim("boy_pickup")
	elif state == State.CLIMB:
		_play_anim("boy_climb_stairs")
		var dx := stair.global_top().x - stair.global_bottom().x if is_instance_valid(stair) else 1.0
		_anim.flip_h = dx < 0.0
	elif side_scroll and not _grounded():
		_play_anim("boy_jump")
		_anim.frame = 1 if velocity.y < -60.0 else (2 if velocity.y < 60.0 else 3)
		_anim.pause()
	elif absf(velocity.x) > 5.0 or (not side_scroll and velocity.length() > 5.0):
		_play_anim("boy_carry" if not inventory.current().is_empty() else "boy_run")
	else:
		_play_anim("boy_idle")


func _unhandled_input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	if event.is_action_pressed(&"jump"):
		jump()
	elif event.is_action_pressed(&"flashlight_toggle"):
		toggle_light()
	elif event.is_action_pressed(&"interact"):
		interact_pressed()
	elif event.is_action_released(&"interact"):
		interact_released()
	elif event.is_action_pressed(&"inv_next"):
		inventory.cycle(1)
	elif event.is_action_pressed(&"inv_prev"):
		inventory.cycle(-1)


func toggle_light() -> void:
	if state == State.PICKUP:
		return
	var light := get_node_or_null(^"Flashlight")
	if light:
		light.visible = not light.visible
		FESignals.set_flashlight(light.visible)


func interact_pressed() -> void:
	_interact_down = true
	_interact_held = 0.0


func interact_released() -> void:
	if not _interact_down:
		return
	_interact_down = false
	if state == State.PICKUP:
		_cancel_pickup()  # let go early = lose progress
		return
	if _interact_held < PlayerStats.get_stat(&"tap_threshold"):
		_tap()


# --- tap: throw or knock ----------------------------------------------------
func _tap() -> void:
	var held := inventory.current()
	if not held.is_empty():
		var tgt: Node2D = FESignals.selected_enemy
		if held.get("throwable", false) and is_instance_valid(tgt):
			throw_at(tgt)
		return  # holding something with no ringed enemy: tap does nothing
	_try_knock()


func throw_at(tgt: Node2D) -> Node2D:
	var it := inventory.take_current()
	if it.is_empty():
		return null
	var t := Node2D.new()
	t.set_script(load("res://scripts/world/thrown_object.gd"))
	get_parent().add_child(t)
	t.setup(global_position + Vector2(0, -20), it, tgt, self)
	_throw_anim_left = 0.33
	return t


## Empty hands: knock over the ONE nearest knockable prop in range on the side you face.
## Puppets are never tapped directly: the prop falls toward `facing`, and an enemy right
## where it lands is hit (calm dies, enraged is stunned). The break makes the noise, once.
const KNOCK_FALL_DIST := 28.0

func _try_knock() -> void:
	var best: WorldObject = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("world_objects"):
		if not (node is WorldObject) or node.broken or not node.breakable:
			continue
		var to: Vector2 = node.global_position - global_position
		var d := to.length()
		if d > knock_range or to.x * facing < -4.0:
			continue
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return
	var land := best.global_position + Vector2(facing * KNOCK_FALL_DIST, 0)
	for e in get_tree().get_nodes_in_group("puppets"):
		if e is Node2D and e.global_position.distance_to(land) <= 20.0 and e.has_method("on_hit_by_throw"):
			e.on_hit_by_throw(best.to_item())
			break
	best.break_apart()


# --- hold: pickup channel ---------------------------------------------------
func _nearest_pickup() -> WorldObject:
	var best: WorldObject = null
	var best_d := PlayerStats.get_stat(&"pickup_range")
	for o in get_tree().get_nodes_in_group("world_objects"):
		if o is WorldObject and o.can_pick_up and not o.broken:
			var d := global_position.distance_to(o.global_position)
			if d <= best_d:
				best_d = d
				best = o
	return best


func _try_start_pickup() -> void:
	var t := _nearest_pickup()
	if t == null:
		return
	if inventory.is_full() and not t is Chest:   # opening a chest needs no free slot
		return
	state = State.PICKUP
	pickup_target = t
	# Count from the button press, not from the tap threshold, so a full pickup = pickup_time.
	var dur := maxf(PlayerStats.get_stat(&"pickup_time") * t.pickup_time_mult, 0.05)
	pickup_progress = clampf(_interact_held / dur, 0.0, 0.99)
	FESignals.report_pickup_started(t)


func _tick_pickup(delta: float) -> void:
	if not is_instance_valid(pickup_target) or pickup_target.broken \
			or global_position.distance_to(pickup_target.global_position) > PlayerStats.get_stat(&"pickup_range"):
		_cancel_pickup()
		return
	var dur := maxf(PlayerStats.get_stat(&"pickup_time") * pickup_target.pickup_time_mult, 0.05)
	pickup_progress = minf(pickup_progress + delta / dur, 1.0)
	FESignals.report_pickup_progress(pickup_progress)
	if pickup_progress >= 1.0:
		_complete_pickup()


func _complete_pickup() -> void:
	var t := pickup_target
	state = State.NORMAL
	pickup_target = null
	if t.on_hold_complete(self):
		pass   # e.g. a chest opened; nothing goes into the hands
	elif inventory.add(t.to_item()):
		t.broken = true  # removed from world silently
		t.queue_free()
	FESignals.report_pickup_completed()


func _cancel_pickup() -> void:
	if state != State.PICKUP:
		return
	state = State.NORMAL
	pickup_target = null
	pickup_progress = 0.0
	FESignals.report_pickup_cancelled()


func _on_health_changed(current: int, _max: int) -> void:
	if current < _hp_seen:
		_cancel_pickup()  # getting hit breaks the channel
		_hurt_anim_left = 0.4
	_hp_seen = current


# --- flashlight hover-select ------------------------------------------------
## Mouse over an enemy inside the lit cone selects it (ring). The last selection stays
## when the light goes off; hovering another enemy replaces it.
func _update_hover_select() -> void:
	if not light_on() or not is_inside_tree():
		return
	var mouse := get_global_mouse_position()
	var aim := (mouse - global_position)
	var rng := PlayerStats.get_stat(&"light_range")
	var half := deg_to_rad(PlayerStats.get_stat(&"light_angle_deg") * 0.5)
	for e in get_tree().get_nodes_in_group("puppets"):
		if not (e is Node2D):
			continue
		var to: Vector2 = e.global_position - global_position
		var lit := to.length() <= rng and absf(aim.angle_to(to)) <= half
		FESignals.report_lit(e, lit)
		if lit and e.global_position.distance_to(mouse) <= 28.0:
			FESignals.select_enemy(e)

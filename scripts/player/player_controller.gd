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
var _stair_approach: bool = false   # entered off the line: step along the floor to the stair end first
var _stair_t: float = 0.0
var _jump_queued: bool = false
var _throw_anim_left: float = 0.0
var _hurt_anim_left: float = 0.0
var _anim: AnimatedSprite2D
## Test hook: when set, used instead of is_on_floor().
var floor_override: int = -1  # -1 real, 0 airborne, 1 grounded

## Landing on furniture creaks (PRODUCT.md "Perching has risk"): a NoiseBus noise at his feet,
## radius x the noise_mult stat (items) and the item noise hooks, like the chest creak.
signal creaked(furniture_px: float)
@export var furniture_creak_radius: float = NoiseBus.DEFAULT_RADIUS * 0.5   # about half a screen
@export var furniture_creak_loudness: float = 0.6
## Furniture = something he lands on with another world surface below it within this many px
## (4-tile furniture is 64px; a 16px slab over a room has 144px of air below).
const FURNITURE_PROBE_PX := 80.0
var _was_grounded: bool = true

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
	# Every stage builds a fresh player: this IS stage start for item behaviour
	# (charges refill, Music Box lures into the pocket, ...).
	PlayerStats.begin_stage(self)


func light_on() -> bool:
	var l := get_node_or_null(^"Flashlight")
	return l != null and l.visible


## Last flashlight aim (mouse direction); tests may set it.
var aim_dir: Vector2 = Vector2.RIGHT

## True if world point `p` is inside the lit cone. Enemies use this for their startle
## build-up (they add their own line-of-sight check, so walls block the beam).
func lights(p: Vector2) -> bool:
	if not light_on():
		return false
	var to := p - global_position
	if to.length() > PlayerStats.get_stat(&"light_range"):
		return false
	var half := deg_to_rad(PlayerStats.get_stat(&"light_angle_deg") * 0.5)
	return to.length() < 0.01 or absf(aim_dir.angle_to(to)) <= half


func _physics_process(delta: float) -> void:
	if GameState.game_over:
		velocity = Vector2.ZERO
		return
	tick(delta, Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"))
	if state != State.CLIMB:
		move_and_slide()
	_check_landing()
	_update_anim(delta)


## Just landed (side-scroll, not on a stair): creak if it's furniture.
func _check_landing() -> void:
	var g := side_scroll and state != State.CLIMB and _grounded()
	if g and not _was_grounded:
		var h := furniture_under()
		if h > 0.0:
			creak(h)
	_was_grounded = g


## Height (px) of the furniture he's standing on, 0 if he's on a floor. Generic: a ray from
## just inside what's under his feet straight down; another world surface close below means
## he's on top of a piece of furniture (any size, any body), not a slab.
func furniture_under() -> float:
	if not is_inside_tree():
		return 0.0
	var feet := Enemy.body_feet(self)
	var q := PhysicsRayQueryParameters2D.create(feet + Vector2(0, 2), feet + Vector2(0, FURNITURE_PROBE_PX),
			PlayerStats.LAYER_WORLD, [get_rid()])
	q.hit_from_inside = false   # skip the piece we stand on, find the floor under it
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	return (hit.position as Vector2).y - feet.y


func creak(furniture_px: float) -> void:
	NoiseBus.emit_noise(Enemy.body_feet(self), furniture_creak_radius * PlayerStats.get_stat(&"noise_mult"), furniture_creak_loudness, self)
	_spawn_creak_vfx()
	creaked.emit(furniture_px)


const VFX_CREAK_SLOT := "vfx_creak"


## vfx_creak (manifest, 5f @12fps, one-shot): a dust puff + creak lines at the furniture top,
## pivot on his feet, freed after the last frame. No slot / no art yet (PR #40): nothing spawns.
func _spawn_creak_vfx() -> Node2D:
	if not AnimLibrary.has_slot(VFX_CREAK_SLOT) or get_parent() == null:
		return null
	var sf := AnimLibrary.frames_for([VFX_CREAK_SLOT])
	if not sf.has_animation(VFX_CREAK_SLOT):
		return null   # texture missing
	sf.set_animation_loop(VFX_CREAK_SLOT, false)
	var v := AnimatedSprite2D.new()
	v.name = "VfxCreak"
	v.sprite_frames = sf
	v.offset = AnimLibrary.offset_for(VFX_CREAK_SLOT)
	v.z_index = 5
	v.top_level = true
	v.animation_finished.connect(v.queue_free)
	get_parent().add_child(v)
	v.global_position = Enemy.body_feet(self)
	v.play(VFX_CREAK_SLOT)
	return v


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
				velocity.x = dir.x * move_speed()
				_apply_gravity(delta)
				if _jump_queued and _grounded():
					velocity.y = -PlayerStats.get_stat(&"jump_velocity")
				if absf(dir.y) > 0.5:
					_try_enter_stair(dir.y)
			else:
				velocity = dir * move_speed()
			_update_hover_select()
	_jump_queued = false


## Walk speed now: the stat, times item carry penalties for what is held (Heavy Vases).
func move_speed() -> float:
	return PlayerStats.get_stat(&"move_speed") * PlayerStats.carry_speed_mult(inventory.items if inventory else [])


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
			var t: float = s.entry_t(global_position)   # anywhere in the 320px trigger
			# up (negative y) only if not already at top, down only if not at bottom
			if (up_down < 0.0 and t < 0.98) or (up_down > 0.0 and t > 0.02):
				stair = s
				_stair_t = t
				_stair_approach = not s.on_line(global_position)   # wide trigger: no snap
				state = State.CLIMB
				velocity = Vector2.ZERO
				return


func _tick_climb(delta: float, dir: Vector2) -> void:
	if not is_instance_valid(stair):
		state = State.NORMAL
		return
	var length := stair.global_bottom().distance_to(stair.global_top())
	var along := -dir.y if absf(dir.y) > 0.1 else dir.x * signf(stair.global_top().x - stair.global_bottom().x)
	if _stair_approach:
		# Walk to the stair end on this floor (any stair width), then climb from there.
		var into := 1.0 if _stair_t <= 0.5 else -1.0   # +along climbs up from the bottom
		if along * into < 0.0:
			_stair_approach = false   # pressed away: let go of the stair
			state = State.NORMAL
			stair = null
			return
		if along == 0.0:
			return
		var goal := stair.point_at(_stair_t)
		var step := PlayerStats.get_stat(&"climb_speed") * delta
		if goal.x != global_position.x:
			facing = 1 if goal.x > global_position.x else -1
		global_position = global_position.move_toward(goal, step)
		if global_position.distance_to(goal) < 0.5:
			_stair_approach = false
		return
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
	var tgt: Node2D = FESignals.selected_enemy
	if not held.is_empty() and held.get("throwable", false) and is_instance_valid(tgt):
		throw_at(tgt)
	elif held.is_empty() and knock_target() != null:
		_try_knock()
	elif PlayerStats.lure_charges() > 0:
		throw_lure()
	# else: holding something with no ringed enemy and no lures: tap does nothing


## What PlayerStats.tap_throws_lure() asks: would a tap with NOTHING ringed throw a lure?
## Yes with lures in the pocket, unless the hands are empty and a prop is in knock reach.
func tap_would_throw_lure() -> bool:
	if PlayerStats.lure_charges() <= 0:
		return false
	return not (inventory.current().is_empty() and knock_target() != null)


## Music Box: throws one pocket lure the way the boy FACES (PRODUCT.md), never the last
## mouse aim. Hands are untouched. Null with an empty pocket.
func throw_lure() -> Node2D:
	var lure := PlayerStats.next_lure()
	if lure.is_empty():
		return null
	return _launch(lure, null, global_position + Vector2(facing, 0) * LURE_THROW_DIST)


func throw_at(tgt: Node2D) -> Node2D:
	return _throw(tgt, Vector2.INF)


## Throws the held item toward a world point.
const LURE_THROW_DIST := 320.0

func throw_toward(point: Vector2) -> Node2D:
	return _throw(null, point)


func _throw(tgt: Node2D, point: Vector2) -> Node2D:
	var it := inventory.take_current()
	if it.is_empty():
		return null
	return _launch(it, tgt, point)


func _launch(it: Dictionary, tgt: Node2D, point: Vector2) -> Node2D:
	PlayerStats.dispatch_throw(it, tgt if tgt != null else point)   # item hooks may tag the dict
	var t := Node2D.new()
	t.set_script(load("res://scripts/world/thrown_object.gd"))
	t.set("item", it)   # before _ready: the flight art depends on it
	get_parent().add_child(t)
	t.setup(global_position + Vector2(0, -20), it, tgt, self, point)
	_throw_anim_left = 0.33
	return t


## Empty hands: knock over the ONE nearest knockable prop in range on the side you face.
## Puppets are never tapped directly: the prop falls toward `facing`, and an enemy right
## where it lands is hit (calm dies, enraged is stunned). The break makes the noise, once.
const KNOCK_FALL_DIST := 28.0

## The ONE nearest knockable prop in range on the side the boy faces (null if none).
func knock_target() -> WorldObject:
	if not is_inside_tree():
		return null
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
	return best


func _try_knock() -> void:
	var best := knock_target()
	if best == null:
		return
	var land := best.global_position + Vector2(facing * KNOCK_FALL_DIST, 0)
	for e in get_tree().get_nodes_in_group("puppets"):
		if e is Node2D and e.global_position.distance_to(land) <= 20.0 and e.has_method("on_hit_by_throw"):
			var knocked := best.to_item()
			PlayerStats.dispatch_throw(knocked, e)   # a knocked vase counts as a vase hit
			e.on_hit_by_throw(knocked)
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
	# A cancel (hit, out of range, let go) ends the hold for good: forget the press so a
	# still-held button can't restart the channel from the time already held. New press needed.
	_interact_down = false
	_interact_held = 0.0
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
	if aim.length() > 0.01:
		aim_dir = aim
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

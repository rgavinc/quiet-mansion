class_name Enemy
extends CharacterBody2D
## Enemy state machine. Back End owns. Subclasses (puppet_hand.gd) only override defaults.
##
##   CALM ──light builds startle──▶ STARTLED ──▶ CHASE ◀──noise (instant, any calm state)
##   CHASE ──loses sight──▶ SEARCH (memory drains, faster when farther: memory_time, give_up_distance) ──0──▶ RETURN ──home──▶ CALM
##   CHASE/SEARCH ──lands a hit──▶ RECOVER (backs off, can't hit) ──▶ CHASE/SEARCH
##   aroused + throw/knock ──▶ STUNNED ──▶ CHASE/SEARCH;  calm (CALM/RETURN) + throw ──▶ dies
##
## Movement: top-down (old map) moves freely in 2D. Side-scroll (player.side_scroll or our own
## `side_scroll`) walkers obey gravity, stay on slabs and change floors only by `Stair`s
## (LEVELGEN.md). `movement == &"float"` (stage 4+) ignores gravity and drifts through slabs.
## Enemies always simulate, on screen or not.

enum State { CALM, STARTLED, CHASE, SEARCH, RETURN, RECOVER, STUNNED }

const MOVE_WALK := &"walk"
const MOVE_FLOAT := &"float"

## Optional EnemyDef resource (Lead). Any property below whose name it also has is copied in _ready.
@export var def: Resource = null
@export var type_id: StringName = &"enemy"
@export var movement: StringName = MOVE_WALK
@export var side_scroll: bool = false        # forced on; otherwise follows the player's side_scroll
@export var walk_speed: float = 45.0         # calm patrol / walking home
@export var chase_speed: float = 95.0
@export var float_speed: float = 45.0        # float type: slow drift, straight through floors
@export var climb_speed: float = 80.0        # along a stair
@export var hear_radius: float = 160.0       # legacy GameState.noise_made path only
@export var hearing_mult: float = 1.0        # scales NoiseBus radius for this enemy
@export var sight_range: float = 560.0
@export var memory_time: float = 4.0         # s of lost sight before giving up
## PRODUCT.md: the gauge drains faster the farther the boy is. Drain rate while searching =
## (1 / memory_time) * clamp(distance / give_up_distance, 0.25, 4): at give_up_distance it
## empties in memory_time; right next to him it takes 4x longer.
@export var give_up_distance: float = 900.0
@export var noise_track_time: float = 3.0    # s a noise lets it track the boy without sight
@export var light_track_time: float = 1.0    # same, after a light startle
## Startle -> chase delay. <= 0 (default) = the startle/scream animation's length, read from the
## manifest (frames / fps of `anim_startle` via AnimLibrary), so the chase starts when the scream
## ends (PRODUCT.md: ~0.5 s). > 0 = fixed seconds (per-type override in an EnemyDef).
@export var startle_reaction_time: float = 0.0
@export var recover_time: float = 1.5        # after landing a hit: back off, no hits
@export var backoff_speed: float = 60.0
@export var stun_time: float = 1.5
@export var patrol_radius: float = 0.0       # 0 = idle at home
@export var shove_distance: float = 48.0
## Catch = the player's body overlapping this hit Area2D. Independent of the movement
## collider and the art, so neither can silently remove the danger again.
@export var hit_radius: float = 18.0
@export var anim_calm: String = ""
@export var anim_startle: String = ""
@export var anim_chase: String = ""

const STARTLE_FALLBACK_TIME := 0.5   # startle slot missing / no frames / no fps
## Ledge backstop (walkers): how far below the feet a floor must be just ahead of them.
const LEDGE_PROBE_DEPTH := 24.0

const DEF_FIELDS := [&"type_id", &"movement", &"walk_speed", &"chase_speed", &"float_speed",
	&"climb_speed", &"hear_radius", &"hearing_mult", &"sight_range", &"memory_time",
	&"noise_track_time", &"light_track_time", &"startle_reaction_time", &"recover_time",
	&"backoff_speed", &"stun_time", &"patrol_radius", &"shove_distance", &"hit_radius",
	&"anim_calm", &"anim_startle", &"anim_chase", &"give_up_distance"]

var state: State = State.CALM
var home: Vector2 = Vector2.ZERO
var startle: float = 0.0          # 0..1, light build-up
var memory: float = 1.0           # 0..1, chase memory (FE arrow gauge)
var last_known: Vector2 = Vector2.ZERO
var hitbox: Area2D
var stair: Stair = null           # Stair node being climbed (null for a LevelNav hop)
var climbing: bool:
	get: return _climb_on
## Test hook / override: any object with LevelNav's floor_of(p) + next_waypoint(a, b).
## null = use LevelNav.current when that script exists (Lead PR #13), else scan group "stairs".
var nav_override: Object = null
## True from chase start until it gives up (RETURN) or dies: CHASE, SEARCH, and the RECOVER /
## STUNNED pauses inside a chase. Exactly the span FESignals.chasing holds it (report_chase),
## and what GameState.chasing_count() / FESignals.chasing_count() count.
func is_chasing() -> bool:
	return _reported_chase and not gone
var gone: bool = false             # set in _exit_tree; GameState stops counting it
## Legacy flag FE polls until chase reports are wired: same as is_chasing().
var enraged: bool:
	get: return is_chasing()
## Not calm: hunting, or startled by light (a throw stuns instead of killing).
func is_aroused() -> bool:
	return state in [State.STARTLED, State.CHASE, State.SEARCH, State.RECOVER, State.STUNNED]

## Test hooks (like PlayerController.floor_override): -1 real, 0 false, 1 true.
var sight_override: int = -1
var lit_override: int = -1
var floor_override: int = -1

var _state_left: float = 0.0      # timer for STARTLED / RECOVER / STUNNED
var _track_left: float = 0.0      # tracks the boy without sight (heard him)
var _climb_on: bool = false
var _climb_pts: PackedVector2Array = []   # feet points: where we were, stair foot, stair end
var _climb_i: int = 0                       # next point to reach
var _patrol_dir: float = 1.0
var _reported_chase: bool = false
var _reported_startle: float = -1.0
var _home_set: bool = false
var _spr: AnimatedSprite2D
## True when the last _move_to stopped at a floor edge (ledge backstop). Read-only for tests.
var ledge_stopped: bool = false


func _ready() -> void:
	if def != null:
		apply_def(def)
	add_to_group("enemies")
	collision_layer = PlayerStats.LAYER_ENEMY
	_apply_mask()
	_spr = AnimatedSprite2D.new()
	_spr.name = "Anim"
	add_child(_spr)
	_play(anim_calm)
	NoiseBus.noise.connect(_on_bus_noise)   # NoiseBus also re-emits GameState.noise_made: listen once
	hitbox = Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 0
	hitbox.collision_mask = PlayerStats.LAYER_PLAYER
	hitbox.monitorable = false
	var hs := CollisionShape2D.new()
	var hc := CircleShape2D.new()
	hc.radius = hit_radius
	hs.shape = hc
	hitbox.add_child(hs)
	add_child(hitbox)
	floor_snap_length = 6.0


func _exit_tree() -> void:
	gone = true
	if _reported_chase:
		_reported_chase = false
		FESignals.report_chase(self, false)
		GameState.register_alert()


## Copies matching fields from an EnemyDef (duck-typed: only names it actually has).
func apply_def(d: Resource) -> void:
	for f in DEF_FIELDS:
		if f in d:
			set(f, d.get(f))


func get_type_id() -> StringName:
	return type_id


func is_floating() -> bool:
	return movement == MOVE_FLOAT


func _apply_mask() -> void:
	# Solid against the boy always. Floaters drift through slabs and walls (PD #20).
	collision_mask = PlayerStats.LAYER_PLAYER | (0 if is_floating() else PlayerStats.LAYER_WORLD)


# --- art (manifest slots only) ---------------------------------------------------
## Chase slot: floaters use `<chase>_float` (puppet_chase_float, PR #17) when the manifest has it.
func chase_slot() -> String:
	if is_floating() and not anim_chase.is_empty() and AnimLibrary.has_slot(anim_chase + "_float"):
		return anim_chase + "_float"
	return anim_chase


func _play(slot: String) -> void:
	if _spr == null or slot.is_empty():
		return
	if _spr.sprite_frames == null:
		var slots: Array = []
		for s in [anim_calm, anim_startle, chase_slot()]:
			if not s.is_empty():
				slots.append(s)
		_spr.sprite_frames = AnimLibrary.frames_for(slots)
		# Startle plays once and holds its last frame (frame count from the manifest via
		# AnimLibrary; works for the 5-frame and the 7-frame strips).
		if not anim_startle.is_empty() and _spr.sprite_frames.has_animation(anim_startle):
			_spr.sprite_frames.set_animation_loop(anim_startle, false)
	if not _spr.sprite_frames.has_animation(slot):
		return
	if slot == anim_startle and _spr.animation == slot:
		return   # STARTLED -> STUNNED (or re-startle): keep playing / holding, never restart
	_spr.play(slot)
	_spr.offset = AnimLibrary.offset_for(slot)


# --- senses -------------------------------------------------------------------
func _player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node2D


func is_side_scroll() -> bool:
	if side_scroll:
		return true
	var p := _player()
	return p != null and "side_scroll" in p and bool(p.get("side_scroll"))


func can_see(p: Node2D) -> bool:
	if sight_override >= 0:
		return sight_override == 1
	if p == null:
		return false
	if global_position.distance_to(p.global_position) > sight_range:
		return false
	if not is_inside_tree():
		return true
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters2D.create(global_position, p.global_position, PlayerStats.LAYER_WORLD, [get_rid()])
	return space.intersect_ray(q).is_empty()


func is_lit_by(p: Node2D) -> bool:
	if lit_override >= 0:
		return lit_override == 1
	if p == null or not p.has_method("lights"):
		return false
	return p.lights(global_position) and can_see(p)


## Noise reaches any enemy inside its radius, on screen or not. More dangerous than light:
## no build-up, and it tracks the boy for noise_track_time even without sight.
func _on_bus_noise(at: Vector2, radius: float, _loudness: float, _source: Node) -> void:
	if GameState.game_over or not is_inside_tree():
		return
	if NoiseBus.can_hear(global_position, at, radius, hearing_mult):
		hear_noise()


## Legacy GameState.make_noise path (not connected; callers may invoke it directly).
func _on_noise(level: float, at: Vector2) -> void:
	if GameState.game_over or not is_inside_tree():
		return
	if global_position.distance_to(at) <= hear_radius * maxf(level, 0.5):
		hear_noise()


func hear_noise() -> void:
	if state in [State.RECOVER, State.STUNNED]:
		_track_left = maxf(_track_left, noise_track_time)
		return
	_enter_chase(noise_track_time)


## Old name kept (tests, knock miss): instant chase as if it heard a noise.
func _alert() -> void:
	hear_noise()


# --- transitions --------------------------------------------------------------
func _set_state(s: State) -> void:
	state = s
	match s:
		State.CALM, State.RETURN:
			_play(anim_calm)
		State.STARTLED, State.STUNNED:
			_play(anim_startle)   # once, then hold the last frame while startled / stunned
		_:
			_play(chase_slot())


func _enter_chase(track: float) -> void:
	_track_left = maxf(_track_left, track)
	var p := _player()
	if p:
		last_known = p.global_position
	_set_state(State.CHASE)
	_set_startle(0.0)
	memory = 1.0
	if not _reported_chase:
		_reported_chase = true
		FESignals.report_chase(self, true)
		GameState.register_alert()   # live chasing count changed (HUD)
	FESignals.report_chase_memory(self, memory)


func _enter_startled() -> void:
	_set_state(State.STARTLED)
	_state_left = startle_delay()
	_set_startle(1.0)


## Seconds from STARTLED to CHASE: startle_reaction_time if > 0, else the startle animation's
## manifest length (frames / fps), else STARTLE_FALLBACK_TIME.
func startle_delay() -> float:
	if startle_reaction_time > 0.0:
		return startle_reaction_time
	return startle_anim_length(anim_startle)


static func startle_anim_length(slot: String) -> float:
	if slot.is_empty() or not AnimLibrary.has_slot(slot):
		return STARTLE_FALLBACK_TIME
	var m := AnimLibrary.meta(slot)
	var n := int(m.get("frames", 0))
	var fps := float(m.get("fps", 0.0))
	if n <= 0 or fps <= 0.0:
		return STARTLE_FALLBACK_TIME
	return n / fps


func _enter_return() -> void:
	_set_state(State.RETURN)
	memory = 0.0
	_track_left = 0.0
	if _reported_chase:
		_reported_chase = false
		FESignals.report_chase(self, false)   # FE drops the arrow + memory entry
		GameState.register_alert()


func _enter_calm() -> void:
	_set_state(State.CALM)
	_set_startle(0.0)


func _resume_hunt() -> void:
	# After RECOVER / STUNNED: chase if it can see or still tracks the boy, else search.
	_set_state(State.CHASE)
	var p := _player()
	if p and not (can_see(p) or _track_left > 0.0):
		state = State.SEARCH


func _set_startle(v: float) -> void:
	startle = clampf(v, 0.0, 1.0)
	if not is_equal_approx(startle, _reported_startle) and is_inside_tree():
		_reported_startle = startle
		FESignals.report_startle(self, startle)


## Thrown object / knocked prop: calm enemy is destroyed, an enraged one is stunned.
func on_hit_by_throw(_item: Dictionary) -> void:
	if not is_aroused():
		queue_free()
		return
	_set_state(State.STUNNED)
	_state_left = stun_time


## Knock while calm can kill; while enraged or a miss → it chases.
func try_knock_kill() -> bool:
	if is_aroused():
		return false
	if randf() < 0.5:
		queue_free()
		return true
	_alert()
	return false


# --- per frame ------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if GameState.game_over:
		velocity = Vector2.ZERO
		return
	tick(delta)
	if not climbing:
		move_and_slide()
	_try_hit()


## All per-frame logic (no move_and_slide), so tests can drive it.
func tick(delta: float) -> void:
	if not _home_set:
		_home_set = true
		home = global_position
	var p := _player()
	var sees := p != null and can_see(p)
	_track_left = maxf(_track_left - delta, 0.0)
	match state:
		State.CALM, State.RETURN:
			_tick_startle(delta, p)
			if state == State.CALM:
				_tick_patrol(delta)
			elif state == State.RETURN:
				if _arrived(home):
					_enter_calm()
					_stop()
				else:
					_move_to(home, walk_speed, delta)
		State.STARTLED:
			_stop_x(delta)
			_state_left -= delta
			if _state_left <= 1e-4:   # float slack: 30 x (1/60) must end a 0.5 s scream on frame 30
				_enter_chase(light_track_time)
		State.CHASE, State.SEARCH:
			_tick_hunt(delta, p, sees)
		State.RECOVER:
			_state_left -= delta
			if p and not climbing:
				_back_off(delta, p)
			else:
				_stop_x(delta)
			if _state_left <= 0.0:
				_resume_hunt()
		State.STUNNED:
			_stop_x(delta)
			_state_left -= delta
			if _state_left <= 0.0:
				_resume_hunt()


func _tick_startle(delta: float, p: Node2D) -> void:
	if p != null and is_lit_by(p):
		var t := PlayerStats.get_stat(&"light_startle_time") / maxf(PlayerStats.get_stat(&"light_detect_mult"), 0.01)
		_set_startle(startle + delta / maxf(t, 0.01))
		if startle >= 1.0:
			_enter_startled()
	elif startle > 0.0:
		_set_startle(0.0)   # beam left it: build-up resets (same as FE's lit rule)


func _tick_hunt(delta: float, p: Node2D, sees: bool) -> void:
	if p == null:
		_enter_return()
		return
	if sees or _track_left > 0.0:
		last_known = p.global_position
		if state != State.CHASE or memory < 1.0:
			state = State.CHASE
			memory = 1.0
			FESignals.report_chase_memory(self, memory)
		_move_to(p.global_position, chase_speed, delta)
		return
	state = State.SEARCH
	var far := clampf(global_position.distance_to(p.global_position) / maxf(give_up_distance, 1.0), 0.25, 4.0)
	memory = maxf(memory - delta * far / maxf(memory_time, 0.01), 0.0)
	FESignals.report_chase_memory(self, memory)
	if memory <= 0.0:
		_enter_return()
		return
	if _arrived(last_known):
		_stop()
	else:
		_move_to(last_known, chase_speed, delta)


func _tick_patrol(delta: float) -> void:
	if climbing:
		_tick_climb(delta)   # never park on a stair
		return
	if patrol_radius <= 0.0:
		_stop_x(delta)
		return
	var tgt := home + Vector2(patrol_radius * _patrol_dir, 0)
	if absf(global_position.x - tgt.x) < 4.0:
		_patrol_dir = -_patrol_dir
	_move_to(Vector2(tgt.x, global_position.y if is_side_scroll() else home.y), walk_speed, delta)
	if ledge_stopped:
		_patrol_dir = -_patrol_dir   # floor edge / opening ahead: turn back


func _back_off(delta: float, p: Node2D) -> void:
	var away := global_position - p.global_position
	if away.length() < 0.01:
		away = Vector2.RIGHT
	if is_side_scroll() and not is_floating():
		velocity.x = signf(away.x) * backoff_speed
		if _ledge_ahead(signf(velocity.x), backoff_speed * delta):
			velocity.x = 0.0   # backing off never drops it off a ledge either
		_apply_gravity(delta)
	else:
		velocity = away.normalized() * backoff_speed


# --- hits -------------------------------------------------------------------------
func _try_hit() -> void:
	if not (state == State.CHASE or state == State.SEARCH) or hitbox == null:
		return
	var p := _player()
	if p == null or not hitbox.overlaps_body(p):
		return  # polled every frame, so a boy who stays in contact is hit again later
	if PlayerStats.take_hit(1):
		on_landed_hit(p)


## A landed hit: shove the boy (with collision, never through a wall), then back off.
func on_landed_hit(p: Node2D) -> void:
	var dir := (p.global_position - global_position).normalized()
	if is_side_scroll():
		dir = Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0.0)
	if p is PhysicsBody2D and p.is_inside_tree():
		(p as PhysicsBody2D).move_and_collide(dir * shove_distance)
	_set_state(State.RECOVER)
	_state_left = recover_time


# --- movement + floors ---------------------------------------------------------------
func _arrived(target: Vector2) -> bool:
	if is_side_scroll() and not is_floating():
		return absf(global_position.x - target.x) < 6.0 and floor_of(global_position) == floor_of(target)
	return global_position.distance_to(target) < 6.0


func _stop() -> void:
	if is_side_scroll() and not is_floating():
		velocity.x = 0.0
	else:
		velocity = Vector2.ZERO


func _stop_x(delta: float) -> void:
	_stop()
	if not climbing:
		_apply_gravity(delta)


func _grounded() -> bool:
	return is_on_floor() if floor_override < 0 else floor_override == 1


func _apply_gravity(delta: float) -> void:
	if is_side_scroll() and not is_floating() and not _grounded():
		velocity.y += PlayerStats.get_stat(&"gravity") * delta


## Moves toward `target`: free 2D (top-down / float) or walk + stairs (side-scroll).
func _move_to(target: Vector2, speed: float, delta: float) -> void:
	ledge_stopped = false
	if is_floating():
		var to := target - global_position
		velocity = to.normalized() * minf(float_speed, speed) if to.length() > 2.0 else Vector2.ZERO
		return
	if not is_side_scroll():
		var d := target - global_position
		velocity = d.normalized() * speed if d.length() > 1.0 else Vector2.ZERO
		return
	if climbing:
		_tick_climb(delta)
		return
	var goal_x := target.x
	var feet := _feet()
	var heading_to_stair := false
	var nav := level_nav()
	if nav != null:
		# Lead's floor graph (LEVELGEN.md "LevelNav"): plain data, same on and off screen.
		var wp: Dictionary = nav.next_waypoint(global_position, target)
		if wp.is_empty():
			goal_x = global_position.x   # unreachable from here: wait on this floor
		else:
			goal_x = (wp.point as Vector2).x
			heading_to_stair = wp.has("stair_to")
			if wp.has("stair_to") and _grounded():
				var st: Dictionary = wp.get("stair", {})
				var rect := Stair.trigger_rect(st.get("bottom", wp.point), st.get("top", wp.stair_to))
				if absf(global_position.x - goal_x) <= 6.0 or rect.has_point(feet):
					_start_climb(feet, wp.point, wp.stair_to, null)
					return
	else:
		var mine := floor_of(global_position)
		var theirs := floor_of(target)
		if mine != theirs and mine != -999 and theirs != -999:
			var s := stair_toward(mine, theirs)
			if s != null:
				var up := theirs > mine
				var entry := s.global_bottom() if up else s.global_top()
				var exit := s.global_top() if up else s.global_bottom()
				goal_x = entry.x
				heading_to_stair = true
				if _grounded() and (absf(global_position.x - entry.x) <= 6.0 or s.contains(feet)):
					_start_climb(feet, entry, exit, s)
					return
	var dx := goal_x - global_position.x
	velocity.x = signf(dx) * speed if absf(dx) > 2.0 else 0.0
	if velocity.x != 0.0 and not (heading_to_stair and absf(dx) <= _foot() + 12.0) and _ledge_ahead(signf(velocity.x), absf(velocity.x) * delta):
		velocity.x = 0.0   # backstop: walkers never step off a ledge, in any state (stairs only)
		ledge_stopped = true
	_apply_gravity(delta)


## Ledge backstop (Lead's #13 rail is the real fix; this keeps walkers honest anywhere):
## a grounded side-scroll walker probes straight down just ahead of its feet against
## LAYER_WORLD; no floor within LEDGE_PROBE_DEPTH means a floor edge / opening. Real physics
## only (floor_override test hook off, actually on the floor); floaters never probe.
func _ledge_ahead(dir: float, step: float) -> bool:
	if is_floating() or floor_override >= 0 or not is_inside_tree() or not is_on_floor():
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var feet := _feet()
	var x := feet.x + dir * (_foot_half_width() + 2.0 + step)
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, feet.y - 4.0), Vector2(x, feet.y + LEDGE_PROBE_DEPTH),
		PlayerStats.LAYER_WORLD, [get_rid()])
	return space.intersect_ray(q).is_empty()


func _foot_half_width() -> float:
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			return (c.shape as RectangleShape2D).size.x * 0.5
	return _foot()


## Stair from floor `mine` one step toward `target_floor`, nearest entry first.
func stair_toward(mine: int, target_floor: int) -> Stair:
	if not is_inside_tree():
		return null
	var up := target_floor > mine
	var best: Stair = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("stairs"):
		if not (n is Stair):
			continue
		var s: Stair = n
		if (up and s.from_floor != mine) or (not up and s.to_floor != mine):
			continue
		var entry := s.global_bottom() if up else s.global_top()
		var d := absf(entry.x - global_position.x)
		if d < best_d:
			best_d = d
			best = s
	return best


## Floor index of a point, from the stairs' slab heights (LEVELGEN: stair bottom = from_floor
## slab top, stair top = to_floor slab top). -999 when there are no stairs (single floor).
func floor_of(p: Vector2) -> int:
	var nav := level_nav()
	if nav != null:
		return int(nav.floor_of(p))
	if not is_inside_tree():
		return -999
	var best := -999
	var best_y := INF
	for n in get_tree().get_nodes_in_group("stairs"):
		if not (n is Stair):
			continue
		var s: Stair = n
		for pair in [[s.from_floor, s.global_bottom().y], [s.to_floor, s.global_top().y]]:
			var y: float = pair[1]
			if y >= p.y - 2.0 and y < best_y:   # the slab under this point
				best_y = y
				best = pair[0]
	return best


func _foot() -> float:
	for c in get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			return (c.shape as CircleShape2D).radius
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			return (c.shape as RectangleShape2D).size.y * 0.5
	return 0.0


func _feet() -> Vector2:
	return global_position + Vector2(0, _foot())


## Committed stair hop, entered anywhere in the 320px trigger: step along the floor to the
## stair foot `entry` (no snap), then climb to `exit` on the next floor. Feet points.
func _start_climb(from: Vector2, entry: Vector2, exit: Vector2, s: Stair) -> void:
	stair = s
	_climb_on = true
	_climb_pts = PackedVector2Array([from, entry, exit])
	_climb_i = 1
	velocity = Vector2.ZERO


func _tick_climb(delta: float) -> void:
	if stair != null and not is_instance_valid(stair):
		stair = null
	var pos := _feet()
	var step := climb_speed * delta
	while step > 0.0 and _climb_i < _climb_pts.size():
		var goal := _climb_pts[_climb_i]
		var d := pos.distance_to(goal)
		if d <= step:
			pos = goal
			step -= d
			_climb_i += 1
		else:
			pos = pos.move_toward(goal, step)
			step = 0.0
	global_position = pos - Vector2(0, _foot())
	velocity = Vector2.ZERO
	if _climb_i >= _climb_pts.size():
		_climb_on = false   # stepped off onto the next floor
		stair = null


# --- LevelNav (Lead PR #13), optional --------------------------------------------
const LEVEL_NAV_PATH := "res://scripts/levelgen/level_nav.gd"
static var _nav_script: Variant = null   # Script, or false when the file isn't there


## The level's floor graph if one is loaded (LevelNav.current), else null (fall back to stairs).
## Looked up by path so this file compiles with or without the LevelNav class.
func level_nav() -> Object:
	if nav_override != null:
		return nav_override
	if _nav_script == null:
		_nav_script = load(LEVEL_NAV_PATH) if ResourceLoader.exists(LEVEL_NAV_PATH) else false
	if _nav_script is Script:
		var cur: Variant = (_nav_script as Script).get(&"current")
		if cur is Object and is_instance_valid(cur):
			return cur
	return null

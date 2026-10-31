class_name Enemy
extends CharacterBody2D
## Enemy state machine. Back End owns. Subclasses (puppet_hand.gd) only override defaults.
##
##   CALM ──light builds startle──▶ STARTLED ──▶ CHASE ◀──noise (instant, any calm state)
##   CHASE ──loses sight──▶ SEARCH (memory drains, faster when farther: memory_time, give_up_distance) ──0──▶ RETURN ──home──▶ CALM
##   CHASE/SEARCH ──lands a hit──▶ RECOVER (backs off, can't hit) ──▶ CHASE/SEARCH
##   aroused + throw/knock ──▶ STUNNED ──▶ CHASE/SEARCH;  calm (CALM/RETURN) + throw ──▶ dies
##   CHASE/SEARCH walker under a perched boy ──▶ REACH (telegraphed reach_time) ──▶ hit + RECOVER,
##     or ──boy leaves reach──▶ CHASE (PRODUCT.md "Perching has risk")
##
## Movement: top-down (old map) moves freely in 2D. Side-scroll (player.side_scroll or our own
## `side_scroll`) walkers obey gravity, stay on slabs and change floors only by `Stair`s
## (LEVELGEN.md). `movement == &"float"` (stage 4+) ignores gravity and drifts through slabs.
## Enemies always simulate, on screen or not.

enum State { CALM, STARTLED, CHASE, SEARCH, RETURN, RECOVER, STUNNED, REACH, RATTLE }

## Perch reach telegraph for FE / Designer: REACH starts, then ends caught (hit landed) or not
## (boy hopped off / out of reach, or the reach was interrupted by a stun).
signal reach_started
signal reach_ended(caught: bool)
## Rattle (PRODUCT.md "No safe camping"): a walker that can't reach a perched boy shakes the
## furniture. `rattled` fires with each loud noise, `rattle_ended(shaken)` when it stops
## (shaken = the boy was shaken off; false = cancelled: he left, stun, state change).
signal rattle_started
signal rattled(at: Vector2)
signal rattle_ended(shaken: bool)

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
## Perch reach (walkers only). The catch lands reach_time after the reach starts if > 0, else
## on the anim_reach slot's manifest catch frame (hit_frame / fps), else REACH_FALLBACK_TIME.
@export var anim_reach: String = ""
@export var reach_time: float = 0.0
## Boy's feet above our feet (px) we can still reach: > 0 overrides, else the anim_reach slot's
## manifest reach_height_px, else REACH_HEIGHT_FALLBACK (40: 2 tiles = 32 in, 3 tiles = 48 out).
@export var perch_reach_height: float = 0.0
## Horizontal feet-to-feet distance (px) that counts as "under him".
@export var perch_reach_x: float = 30.0
## Rattle: art slot (puppet_rattle, loops), seconds unreachable before it starts, seconds of
## rattling before the boy is shaken off, loud-noise radius / loudness, and the noise cadence
## (0 = one per animation loop of the manifest slot, else seconds between noises).
@export var anim_rattle: String = ""
@export var rattle_wait: float = 3.0
@export var rattle_time: float = 3.0
@export var rattle_noise_radius: float = NoiseBus.DEFAULT_RADIUS
@export var rattle_noise_loudness: float = 1.0
@export var rattle_noise_every: float = 0.0
## Tallest piece it rattles (4 tiles = 64 + margin); a hop above it still counts as "on it".
@export var rattle_max_height: float = 72.0

const STARTLE_FALLBACK_TIME := 0.5   # startle slot missing / no frames / no fps
const REACH_FALLBACK_TIME := 0.6     # PD: a clear ~0.6 s reach when there's no reach anim
const REACH_HEIGHT_FALLBACK := 40.0  # PD: 8 px margin over 2 tiles (32) and under 3 (48)
## Boy's feet at least this far above ours (and standing) = perched, not on our floor.
const PERCH_MIN_PX := 8.0
## A cancelled reach resumes (not restarts) if he's back in reach within this many seconds.
const REACH_RESUME_TIME := 1.0
## Sprite facing: walk art faces right (manifest: "flip_h for left"). Below the velocity deadzone the
## walker keeps its facing, or turns to the boy while it is hunting / reaching (no flicker at vx ~ 0).
const FACE_VEL_DEADZONE := 8.0
const FACE_TARGET_DEADZONE := 6.0
## Turning toward a still boy needs him this far on the other side (hysteresis), and no turn
## follows another within FACE_HOLD_TIME, so a boy wobbling +-7 px around a walker can't flicker it.
const FACE_TURN_PX := 12.0
const FACE_HOLD_TIME := 0.2
## Walker beside a piece it rattles: centre within half the piece + this.
const RATTLE_STAND_X := 40.0
const RATTLE_SLOT_FALLBACK_LOOP := 0.5
const VFX_RATTLE_SLOT := "vfx_rattle"
## Ledge backstop (walkers): how far below the feet a floor must be just ahead of them.
const LEDGE_PROBE_DEPTH := 24.0
const LEDGE_PROBE_LIFT := 4.0     # ray starts this far above the feet

const DEF_FIELDS := [&"type_id", &"movement", &"walk_speed", &"chase_speed", &"float_speed",
	&"climb_speed", &"hear_radius", &"hearing_mult", &"sight_range", &"memory_time",
	&"noise_track_time", &"light_track_time", &"startle_reaction_time", &"recover_time",
	&"backoff_speed", &"stun_time", &"patrol_radius", &"shove_distance", &"hit_radius",
	&"anim_calm", &"anim_startle", &"anim_chase", &"give_up_distance",
	&"anim_reach", &"reach_time", &"perch_reach_height", &"perch_reach_x",
	&"anim_rattle", &"rattle_wait", &"rattle_time"]

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
	return state in [State.STARTLED, State.CHASE, State.SEARCH, State.RECOVER, State.STUNNED, State.REACH, State.RATTLE]

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
var face_dir := 1               # 1 = looking right, -1 = left (sprite flip_h from this)
var _spr_slot := ""           # slot whose manifest offset the sprite uses
var _spr_feet := Vector2.ZERO   # origin -> feet the sprite offset was last built with
var _stun_calm: bool = false        # Flash Bulb stun: back to CALM afterwards, never chase
## True when the last _move_to stopped at a floor edge (ledge backstop). Read-only for tests.
var ledge_stopped: bool = false
## 0..1 progress of the current perch reach (0 when not reaching). FE telegraph.
var reach_progress: float = 0.0
var _reach_total: float = 0.0
var _reach_landing: bool = false
var _reach_saved: float = 0.0
## He was last standing perched above us and hasn't stood anywhere since (hop off / in place).
var _boy_off_perch: bool = false
var _reach_resume_left: float = 0.0
var _face_hold: float = 0.0
# rattle
var _rattle_shaken: bool = false
var _rattle_unreach: float = 0.0       # s unreachable so far (CHASE/SEARCH)
var _rattle_clock: float = 0.0         # s into the current rattle
var _rattle_noise_n: int = 0           # noises emitted so far this rattle
var _rattle_piece: Dictionary = {}     # {rect: Rect2 (global), body: Node}; cached while he stands
var _rattle_vfx: AnimatedSprite2D = null
var _wobble_nodes: Array = []          # [{node, base_x}] visuals the rattle shifts (never collision)
## Current wobble step in px (already negated for a flipped walker). 0 when not rattling.
var rattle_wobble: float = 0.0
## 0..1 progress to the shake-off (0 when not rattling). FE telegraph.
var rattle_progress: float = 0.0


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
		for s in [anim_calm, anim_startle, chase_slot(), anim_reach, anim_rattle]:
			if not s.is_empty() and ((s != anim_reach and s != anim_rattle) or AnimLibrary.has_slot(s)):   # reach art may not be merged yet
				slots.append(s)
		_spr.sprite_frames = AnimLibrary.frames_for(slots)
		# Startle plays once and holds its last frame (frame count from the manifest via
		# AnimLibrary; works for the 5-frame and the 7-frame strips).
		if not anim_startle.is_empty() and _spr.sprite_frames.has_animation(anim_startle):
			_spr.sprite_frames.set_animation_loop(anim_startle, false)
		if not anim_reach.is_empty() and _spr.sprite_frames.has_animation(anim_reach):
			_spr.sprite_frames.set_animation_loop(anim_reach, false)   # one reach, holds the grab
		if not anim_rattle.is_empty() and _spr.sprite_frames.has_animation(anim_rattle):
			_spr.sprite_frames.set_animation_loop(anim_rattle, true)
	if not _spr.sprite_frames.has_animation(slot):
		return
	if slot == anim_startle and _spr.animation == slot:
		return   # STARTLED -> STUNNED (or re-startle): keep playing / holding, never restart
	_spr.play(slot)
	_spr_slot = slot
	_apply_spr_offset()
	_apply_flip()


## Turn the sprite toward the way it moves (vx past the deadzone) or, standing still while
## startled / chasing / searching / reaching, toward the boy. The art faces right unless the
## slot's manifest entry says `facing = "left"` (or `flip = true`); flip_h mirrors about the
## pivot column (x = frame centre for every puppet slot, so the feet don't move).
func update_facing(vx: float, delta: float = -1.0) -> void:
	if delta < 0.0:
		delta = get_physics_process_delta_time()
	_face_hold = maxf(_face_hold - delta, 0.0)
	var want := face_dir
	if absf(vx) > FACE_VEL_DEADZONE:
		want = 1 if vx > 0.0 else -1
	elif state in [State.STARTLED, State.CHASE, State.SEARCH, State.REACH, State.RATTLE, State.STUNNED, State.RECOVER]:
		var p := _player()
		if p != null:
			var dx := p.global_position.x - global_position.x
			# turning needs the boy clearly on the other side (hysteresis)
			if absf(dx) > FACE_TURN_PX:
				want = 1 if dx > 0.0 else -1
	if want != face_dir and _face_hold <= 0.0:
		face_dir = want
		_face_hold = FACE_HOLD_TIME
	_apply_flip()


func _apply_flip() -> void:
	if _spr != null:
		_spr.flip_h = (face_dir < 0) != art_faces_left(_spr_slot)


## Manifest: `facing = "left"` / -1, or `flip = true`, marks art drawn facing left.
static func art_faces_left(slot: String) -> bool:
	var m := AnimLibrary.meta(slot)
	if bool(m.get("flip", false)):
		return true
	var f: Variant = m.get("facing", "right")
	return (f is String and str(f).to_lower() == "left") or ((f is int or f is float) and float(f) < 0.0)


## Art pivot = feet (manifest), so the sprite is anchored to the REAL feet: the pivot offset
## plus origin -> feet from the collision shape (same math as _feet()). A centred r=14 circle
## (old map, tests, #13's generator) has its feet 14px below the origin, a feet-origin shape 0.
func _apply_spr_offset() -> void:
	if _spr == null or _spr_slot.is_empty():
		return
	_spr_feet = _feet_offset()
	_spr.offset = AnimLibrary.offset_for(_spr_slot) + _spr_feet


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
		if _source != null and is_instance_valid(_source) and _source.has_method(&"is_lure"):
			hear_lure(at)
		else:
			hear_noise()


## Legacy GameState.make_noise path (not connected; callers may invoke it directly).
func _on_noise(level: float, at: Vector2) -> void:
	if GameState.game_over or not is_inside_tree():
		return
	if global_position.distance_to(at) <= hear_radius * maxf(level, 0.5):
		hear_noise()


func hear_noise() -> void:
	if state in [State.RECOVER, State.STUNNED, State.REACH, State.RATTLE]:
		_track_left = maxf(_track_left, noise_track_time)
		return
	_enter_chase(noise_track_time)


## A lure (Music Box) plays at `at`: hunt toward IT, not the boy (SEARCH with last_known =
## the lure; each pulse refills memory). Sight of the boy still wins in _tick_hunt.
func hear_lure(at: Vector2) -> void:
	if state in [State.RECOVER, State.STUNNED, State.REACH, State.RATTLE]:
		return
	_enter_chase(0.0)
	_track_left = 0.0
	last_known = at
	state = State.SEARCH
	memory = 1.0
	FESignals.report_chase_memory(self, memory)


## Flash Bulb: the startle completed but is stunned instead of chasing; afterwards calm.
func stun_from_startle(t: float) -> void:
	_set_state(State.STUNNED)
	_state_left = t
	_stun_calm = true


## Off screen relative to the boy (1280x720 view centred on him).
func is_off_screen() -> bool:
	var p := _player()
	return p != null and PlayerStats.is_off_screen(global_position, p.global_position)


## Old name kept (tests, knock miss): instant chase as if it heard a noise.
func _alert() -> void:
	hear_noise()


# --- transitions --------------------------------------------------------------
func _set_state(s: State) -> void:
	if state == State.REACH and s != State.REACH:
		reach_progress = 0.0
		reach_ended.emit(_reach_landing)
		_reach_landing = false
	if state == State.RATTLE and s != State.RATTLE:
		var shaken := _rattle_shaken
		_rattle_shaken = false
		_end_rattle(shaken)
	if s != State.CHASE and s != State.SEARCH:
		_rattle_unreach = 0.0
	state = s
	match s:
		State.CALM, State.RETURN:
			_play(anim_calm)
		State.STARTLED, State.STUNNED:
			_play(anim_startle)   # once, then hold the last frame while startled / stunned
		State.REACH:
			if not anim_reach.is_empty() and AnimLibrary.has_slot(anim_reach):
				_play(anim_reach)
			else:
				_play(chase_slot())   # no reach art yet: FE telegraphs from reach_started / reach_progress
		State.RATTLE:
			if not anim_rattle.is_empty() and AnimLibrary.has_slot(anim_rattle):
				_play(anim_rattle)
			else:
				_play(chase_slot())
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
	return anim_length(slot, STARTLE_FALLBACK_TIME)


## Manifest length of a one-shot slot (frames / fps), else `fallback`.
static func anim_length(slot: String, fallback: float) -> float:
	if slot.is_empty() or not AnimLibrary.has_slot(slot):
		return fallback
	var m := AnimLibrary.meta(slot)
	var n := int(m.get("frames", 0))
	var fps := float(m.get("fps", 0.0))
	if n <= 0 or fps <= 0.0:
		return fallback
	return n / fps


## Seconds from reach start to the catch: reach_time if > 0, else the reach slot's catch frame
## from the manifest (hit_frame / fps; puppet_reach_up: 6 / 10 = 0.6 s), else 0.6 s.
func reach_delay() -> float:
	if reach_time > 0.0:
		return reach_time
	var m := _reach_meta()
	var hf := int(m.get("hit_frame", -1))
	var fps := float(m.get("fps", 0.0))
	if hf >= 0 and fps > 0.0:
		return hf / fps
	return REACH_FALLBACK_TIME


## Highest perch (boy's feet above ours, px) the reach catches: perch_reach_height if > 0,
## else the reach slot's manifest reach_height_px, else 40.
func reach_height() -> float:
	if perch_reach_height > 0.0:
		return perch_reach_height
	var h := float(_reach_meta().get("reach_height_px", 0.0))
	return h if h > 0.0 else REACH_HEIGHT_FALLBACK


func _reach_meta() -> Dictionary:
	if anim_reach.is_empty() or not AnimLibrary.has_slot(anim_reach):
		return {}
	return AnimLibrary.meta(anim_reach)


func is_reaching() -> bool:
	return state == State.REACH


# --- perch reach (PRODUCT.md "Perching has risk") -------------------------------------
## Boy's feet height above OUR feet (px, + = higher), measured from both real colliders, so it
## works for any furniture (no layout classes needed). NAN when he isn't standing on something
## (airborne, on a stair).
func perch_height(p: Node2D) -> float:
	if p == null or not _boy_standing(p):
		return NAN
	return _feet().y - body_feet(p).y


func _boy_standing(p: Node2D) -> bool:
	if "stair" in p and p.get("stair") != null:
		return false   # on (or walking onto) a stair
	if p.has_method(&"_grounded"):
		return bool(p.call(&"_grounded"))
	return p is CharacterBody2D and (p as CharacterBody2D).is_on_floor()


## Boy standing on something above our floor: contact hits are off, only the reach catches.
func boy_perched(p: Node2D) -> bool:
	if not is_side_scroll() or is_floating():
		return false
	var h := perch_height(p)
	return not is_nan(h) and h >= PERCH_MIN_PX


## Under a perched boy and he's low enough to grab (1-2 tiles; 3 tiles is out of reach).
func perch_in_reach(p: Node2D) -> bool:
	if not boy_perched(p) or climbing or not _grounded():
		return false
	if perch_height(p) > reach_height():
		return false
	return absf(body_feet(p).x - _feet().x) <= perch_reach_x


func _note_perch(p: Node2D) -> void:
	if p == null or ("stair" in p and p.get("stair") != null):
		_boy_off_perch = false   # on a stair he is fair game (QA: no stair immunity)
	elif _boy_standing(p):
		_boy_off_perch = boy_perched(p)


func _enter_reach() -> void:
	_reach_total = maxf(reach_delay(), 0.0)
	_state_left = _reach_saved if _reach_resume_left > 0.0 else _reach_total
	_reach_resume_left = 0.0
	reach_progress = 0.0
	_set_state(State.REACH)
	reach_started.emit()


## The reach holds while he stands perched within reach (perch_in_reach). Leaving it in any
## way (hop / walk off, onto a stair, out of x) cancels at once; back in reach within
## REACH_RESUME_TIME resumes the remaining time, so hopping in place can't reset the reach.
func _tick_reach(delta: float, p: Node2D) -> void:
	_stop_x(delta)
	if p == null or not perch_in_reach(p):
		_reach_saved = _state_left
		_reach_resume_left = REACH_RESUME_TIME
		_set_state(State.CHASE)   # hopped off / out of reach in time: reach_ended(false)
		return
	_state_left -= delta
	reach_progress = clampf(1.0 - _state_left / maxf(_reach_total, 1e-4), 0.0, 1.0)
	if _state_left > 1e-4:   # same float slack as STARTLED (36 x 1/60 ends a 0.6 s reach)
		return
	_reach_landing = true
	_reach_resume_left = 0.0
	if PlayerStats.take_hit(1):
		on_landed_hit(p)   # -> RECOVER, reach_ended(true)
	else:
		_set_state(State.CHASE)   # invulnerable: reach still landed (reach_ended(true))


# --- rattle (PRODUCT.md "No safe camping") --------------------------------------------
## Boy above us (standing on a piece, or hopping on it) where we can't grab him: higher than
## reach_height, up to a 4-tile piece, with us beside that piece. Walkers only; floaters never.
func rattle_blocked(p: Node2D) -> bool:
	if p == null or not is_side_scroll() or is_floating() or climbing or not _grounded():
		return false
	if "stair" in p and p.get("stair") != null:
		return false
	var standing := _boy_standing(p)
	var raw := _feet().y - body_feet(p).y
	if standing:
		if raw <= reach_height() or raw > rattle_max_height:
			return false
		_rattle_piece = _find_piece(p)
	else:
		if raw <= reach_height() or _rattle_piece.is_empty():
			return false   # airborne with nothing known under him: hopped off, not on it
	var ours := _feet().x
	if _rattle_piece.is_empty():
		return absf(body_feet(p).x - ours) <= 2.0 * RATTLE_STAND_X
	var r: Rect2 = _rattle_piece.rect
	return absf(ours - r.get_center().x) <= r.size.x * 0.5 + RATTLE_STAND_X


## The WORLD box under his feet: {rect (global), body}. Empty if nothing rectangular found.
func _find_piece(p: Node2D) -> Dictionary:
	if not is_inside_tree():
		return {}
	var feet := body_feet(p)
	var q := PhysicsRayQueryParameters2D.create(feet + Vector2(0, -1), feet + Vector2(0, 6),
			PlayerStats.LAYER_WORLD, [p.get_rid()] if p is CollisionObject2D else [])
	q.hit_from_inside = false
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is Node):
		return {}
	var body: Node = hit.collider
	var best := {}
	for c in body.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			var cs := c as CollisionShape2D
			var size := ((cs.shape as RectangleShape2D).size * cs.global_scale.abs())
			var r := Rect2(cs.global_position - size * 0.5, size)
			if r.grow(1.5).has_point(hit.position):
				best = {rect = r, body = body}
				break
	return best


## True once he has been out of our reach (rattle_blocked) for rattle_wait seconds. Any frame
## he isn't (he left, we aren't beside the piece, reachable now) resets the count.
func _tick_rattle_wait(delta: float, p: Node2D) -> bool:
	if rattle_wait < 0.0 or not rattle_blocked(p):
		_rattle_unreach = 0.0
		return false
	_rattle_unreach += delta
	return _rattle_unreach >= rattle_wait - 1e-4


func rattle_loop_time() -> float:
	return anim_length(anim_rattle, RATTLE_SLOT_FALLBACK_LOOP) if not anim_rattle.is_empty() else RATTLE_SLOT_FALLBACK_LOOP


func rattle_noise_interval() -> float:
	return rattle_noise_every if rattle_noise_every > 0.0 else maxf(rattle_loop_time(), 0.05)


func _rattle_wobble_steps() -> Array:
	var a: Variant = AnimLibrary.meta(anim_rattle).get("furniture_wobble_px", []) if not anim_rattle.is_empty() else []
	return a if a is Array else []


func _enter_rattle(p: Node2D) -> void:
	_rattle_unreach = 0.0
	_rattle_clock = 0.0
	_rattle_noise_n = 0
	rattle_progress = 0.0
	_state_left = maxf(rattle_time, 0.0)
	_set_state(State.RATTLE)
	_spawn_rattle_vfx()
	_collect_wobble_nodes(p)
	rattle_started.emit()
	_rattle_noise()   # the first rattle is loud at once


func _tick_rattle(delta: float, p: Node2D) -> void:
	_stop_x(delta)
	if p == null or not rattle_blocked(p):
		_set_state(State.CHASE)   # he left / we can't stand beside it: cancelled, timers reset
		return
	_rattle_clock += delta
	_state_left -= delta
	rattle_progress = clampf(1.0 - _state_left / maxf(rattle_time, 1e-4), 0.0, 1.0)
	var every := rattle_noise_interval()
	while float(_rattle_noise_n) * every <= _rattle_clock + 1e-4 and _rattle_noise_n * every < rattle_time - 1e-4:
		_rattle_noise()
	_apply_rattle_wobble()
	if _state_left > 1e-4:
		return
	_shake_off(p)


func _rattle_noise() -> void:
	_rattle_noise_n += 1
	var at := _rattle_top_point()
	NoiseBus.emit_noise(at, rattle_noise_radius, rattle_noise_loudness, self)
	rattled.emit(at)


## Furniture top centre (where vfx_rattle sits); our feet if the piece is unknown.
func _rattle_top_point() -> Vector2:
	if _rattle_piece.is_empty():
		return _feet()
	var r: Rect2 = _rattle_piece.rect
	return Vector2(r.get_center().x, r.position.y)


func _rattle_frame() -> int:
	var n := maxi(int(AnimLibrary.meta(anim_rattle).get("frames", 1)), 1) if not anim_rattle.is_empty() else 1
	var fps := float(AnimLibrary.meta(anim_rattle).get("fps", 12)) if not anim_rattle.is_empty() else 12.0
	return int(floor(_rattle_clock * maxf(fps, 1.0) + 1e-4)) % n


## One manifest wobble step per rattle frame, negated when the walker is flipped. Visuals only
## (the furniture's visual and the boy's sprite); collision never moves.
func _apply_rattle_wobble() -> void:
	var steps := _rattle_wobble_steps()
	var idx := _rattle_frame()
	if _spr != null and _spr.animation == anim_rattle:
		_spr.frame = idx
	var w := 0.0
	if not steps.is_empty():
		w = float(steps[idx % steps.size()])
		if _spr != null and _spr.flip_h:
			w = -w
	_set_wobble(w)


func _set_wobble(w: float) -> void:
	rattle_wobble = w
	for e in _wobble_nodes:
		if is_instance_valid(e.node):
			e.node.position.x = e.base_x + w


func _collect_wobble_nodes(p: Node2D) -> void:
	_wobble_nodes.clear()
	var boy_spr: Variant = p.get("_anim") if "_anim" in p else null
	if boy_spr is Node2D:
		_wobble_nodes.append({node = boy_spr, base_x = (boy_spr as Node2D).position.x})
	var v: CanvasItem = _find_furniture_visual()
	if v != null:
		_wobble_nodes.append({node = v, base_x = v.get("position").x})


## The piece's visual: a CanvasItem child of its body (Sprite2D / ColorRect / Control, never a
## collision shape) or a node in group "furniture_visual", whose rect top is on the piece's top
## and spans the boy's column. Per-piece visuals only; a shared level-wide node is skipped.
func _find_furniture_visual() -> CanvasItem:
	if _rattle_piece.is_empty():
		return null
	var r: Rect2 = _rattle_piece.rect
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("furniture_visual"):
		cands.append(n)
	var body: Node = _rattle_piece.body
	for c in body.get_children():
		cands.append(c)
	for c in cands:
		if not (c is Sprite2D or c is ColorRect or c is AnimatedSprite2D):
			continue
		var vr := _visual_rect(c)
		if vr.size == Vector2.ZERO:
			continue
		if absf(vr.position.y - r.position.y) <= 2.0 and absf(vr.get_center().x - r.get_center().x) <= 4.0 \
				and absf(vr.size.x - r.size.x) <= 4.0:
			return c
	return null


static func _visual_rect(c: Node) -> Rect2:
	if c is ColorRect:
		return Rect2((c as ColorRect).global_position, (c as ColorRect).size)
	if c is Sprite2D:
		var sp := c as Sprite2D
		if sp.texture == null:
			return Rect2()
		var sz := sp.texture.get_size() / Vector2(maxi(sp.hframes, 1), maxi(sp.vframes, 1)) * sp.global_scale.abs()
		var o := sp.global_position + sp.offset * sp.global_scale
		return Rect2(o - sz * 0.5 if sp.centered else o, sz)
	return Rect2()


func _spawn_rattle_vfx() -> void:
	if _rattle_vfx != null and is_instance_valid(_rattle_vfx):
		_rattle_vfx.queue_free()
	_rattle_vfx = null
	if not AnimLibrary.has_slot(VFX_RATTLE_SLOT) or get_parent() == null:
		return
	var sf := AnimLibrary.frames_for([VFX_RATTLE_SLOT])
	if not sf.has_animation(VFX_RATTLE_SLOT):
		return
	sf.set_animation_loop(VFX_RATTLE_SLOT, true)
	var v := AnimatedSprite2D.new()
	v.name = "VfxRattle"
	v.sprite_frames = sf
	v.offset = AnimLibrary.offset_for(VFX_RATTLE_SLOT)
	v.z_index = 5
	v.top_level = true
	get_parent().add_child(v)
	v.global_position = _rattle_top_point()
	v.play(VFX_RATTLE_SLOT)
	_rattle_vfx = v


## Leaving RATTLE (any way): vfx freed, wobble restored, timers reset, rattle_ended(shaken).
func _end_rattle(shaken: bool) -> void:
	_set_wobble(0.0)
	_wobble_nodes.clear()   # _set_wobble(0) just put every node back on its base x
	if _rattle_vfx != null and is_instance_valid(_rattle_vfx):
		_rattle_vfx.queue_free()
	_rattle_vfx = null
	rattle_progress = 0.0
	_rattle_clock = 0.0
	_rattle_noise_n = 0
	_rattle_unreach = 0.0
	_rattle_piece = {}
	rattle_ended.emit(shaken)


## 3 s of rattling: the boy drops off the piece's edge toward our side (PlayerController
## .shake_off: a small kick + push under real physics, so he lands on the floor, never in a wall).
func _shake_off(p: Node2D) -> void:
	var cx := _rattle_top_point().x
	var dir := signf(_feet().x - cx)
	if dir == 0.0:
		dir = -1.0 if face_dir < 0 else 1.0
	_boy_off_perch = true   # airborne until he lands: no contact hit mid-fall
	if p != null and p.has_method(&"shake_off"):
		p.call(&"shake_off", dir)
	_end_rattle_state(true)


func _end_rattle_state(shaken: bool) -> void:
	_rattle_shaken = shaken
	_set_state(State.CHASE)


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
	_state_left = maxf(_state_left if _stun_calm else 0.0, stun_time * PlayerStats.clamp_mult(&"stun_mult", float(_item.get("stun_mult", 1.0))))   # Heavy Vases (capped)


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
	update_facing(velocity.x, delta)   # intended velocity, before the slide zeroes it against a wall
	if not climbing:
		move_and_slide()
	_try_hit()


## All per-frame logic (no move_and_slide), so tests can drive it.
func tick(delta: float) -> void:
	if _spr != null and _feet_offset() != _spr_feet:
		_apply_spr_offset()   # collider swapped/moved after _ready: keep the art on the feet
	if not _home_set:
		_home_set = true
		home = global_position
	var p := _player()
	var sees := p != null and can_see(p)
	_track_left = maxf(_track_left - delta, 0.0)
	_reach_resume_left = maxf(_reach_resume_left - delta, 0.0)
	_note_perch(p)
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
			# float slack: 30 x (1/60) must end a 0.5 s scream on frame 30; item hooks (Flash Bulb)
			if _state_left <= 1e-4 and not PlayerStats.startle_handled(self):
				_enter_chase(light_track_time)
		State.CHASE, State.SEARCH:
			if p != null and perch_in_reach(p):
				_enter_reach()
				_stop_x(delta)
			elif p != null and _tick_rattle_wait(delta, p):
				_enter_rattle(p)
				_stop_x(delta)
			else:
				_tick_hunt(delta, p, sees)
		State.REACH:
			_tick_reach(delta, p)
		State.RATTLE:
			_tick_rattle(delta, p)
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
				if _stun_calm:
					_stun_calm = false
					if _track_left > 0.0:
						_enter_chase(_track_left)   # heard the boy meanwhile
					else:
						_enter_calm()
				else:
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
	var drain := PlayerStats.memory_drain_mult(self, is_off_screen())   # item hooks (Cracked Mirror)
	memory = maxf(memory - delta * far * drain / maxf(memory_time, 0.01), 0.0)
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
	if boy_perched(p) or (_boy_off_perch and not _boy_standing(p)):
		return  # perched (or hopping off / in place): only the telegraphed reach catches him
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
		return absf(global_position.x - target.x) < 6.0 and floor_of(_feet()) == floor_of(target)
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
		var wp: Dictionary = nav.next_waypoint(feet, target)
		if wp.is_empty():
			goal_x = feet.x   # unreachable from here: wait on this floor
		else:
			goal_x = (wp.point as Vector2).x
			heading_to_stair = wp.has("stair_to")
			if wp.has("stair_to") and _grounded():
				var st: Dictionary = wp.get("stair", {})
				var rect := Stair.trigger_rect(st.get("bottom", wp.point), st.get("top", wp.stair_to))
				if absf(feet.x - goal_x) <= 6.0 or rect.has_point(feet):
					_start_climb(feet, wp.point, wp.stair_to, null)
					return
	else:
		var mine := floor_of(feet)
		var theirs := floor_of(target)
		if mine != theirs and mine != -999 and theirs != -999:
			var s := stair_toward(mine, theirs)
			if s != null:
				var up := theirs > mine
				var entry := s.global_bottom() if up else s.global_top()
				var exit := s.global_top() if up else s.global_bottom()
				goal_x = entry.x
				heading_to_stair = true
				if _grounded() and (absf(feet.x - entry.x) <= 6.0 or s.contains(feet)):
					_start_climb(feet, entry, exit, s)
					return
	var dx := goal_x - feet.x
	velocity.x = signf(dx) * speed if absf(dx) > 2.0 else 0.0
	if velocity.x != 0.0 and not (heading_to_stair and absf(dx) <= _foot_half_width() + 12.0) and _ledge_ahead(signf(velocity.x), absf(velocity.x) * delta):
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
	# From a few px above the collider's bottom (never inside the slab) to 24 px below it.
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, feet.y - LEDGE_PROBE_LIFT), Vector2(x, feet.y + LEDGE_PROBE_DEPTH),
		PlayerStats.LAYER_WORLD, [get_rid()])
	return space.intersect_ray(q).is_empty()


func _foot_half_width() -> float:
	var cs := _body_shape()
	if cs == null:
		return 0.0
	return shape_half_extents(cs.shape).x * absf(cs.global_transform.get_scale().x if cs.is_inside_tree() else cs.scale.x)


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


## The movement collider: first CollisionShape2D child with a shape (not the Hitbox's).
func _body_shape() -> CollisionShape2D:
	for c in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null and not (c as CollisionShape2D).disabled:
			return c
	return null


## Local half extents (x, y) of a circle / capsule / rectangle shape; ZERO otherwise.
static func shape_half_extents(sh: Shape2D) -> Vector2:
	if sh is CircleShape2D:
		var r := (sh as CircleShape2D).radius
		return Vector2(r, r)
	if sh is CapsuleShape2D:
		var cap := sh as CapsuleShape2D
		return Vector2(cap.radius, maxf(cap.height * 0.5, cap.radius))   # height includes the caps
	if sh is RectangleShape2D:
		return (sh as RectangleShape2D).size * 0.5
	return Vector2.ZERO


## Feet = bottom-centre of the real movement collider, in global space: works for a shape
## centred on the origin (old map, tests) and for one offset so the origin is the feet
## (Lead's generator: circle at (0,-r)). No collider -> the origin.
func _feet() -> Vector2:
	return body_feet(self)


## Bottom-centre of any body's first enabled CollisionShape2D child (global); its origin if none.
## Used for our own feet and the boy's (player shape is offset to his feet in #13, centred in tests).
static func body_feet(b: Node2D) -> Vector2:
	var cs: CollisionShape2D = null
	for c in b.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null and not (c as CollisionShape2D).disabled:
			cs = c
			break
	if cs == null:
		return b.global_position
	var he := shape_half_extents(cs.shape)
	if not cs.is_inside_tree():
		return b.global_position + cs.position + Vector2(0, he.y)
	return cs.global_transform * Vector2(0, he.y)


## Origin -> feet, global. Kept as `_foot()` (its y) for older callers/tests.
func _feet_offset() -> Vector2:
	return _feet() - global_position


func _foot() -> float:
	return _feet_offset().y


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
	global_position = pos - _feet_offset()
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

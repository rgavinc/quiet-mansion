extends RefCounted
## Enemy state machine, REAL physics (real frames, main.gd-sized colliders).
##  - after a hit the puppet backs off: no second hit within 1.5s, a standing boy
##    doesn't go 3 -> 0 from one puppet in under 4.5s (PD tuning note)
##  - side-scroll walker falls under gravity, stays on its slab, and climbs a Stair to
##    reach a boy on the next floor (QA #20); without a stair it can't reach him
##  - float type drifts straight through a slab to the next floor
##  - startle -> chase waits for the scream animation (manifest frames / fps), real frames
##  - ledge backstop: a walker never walks off a floor edge into a gap; a floater crosses it
##  - QA B1: feet come from the real collider, so all of the above holds for a shape centred
##    on the origin AND for one offset to (0,-14) with the origin at the feet (Lead's generator):
##    flat-floor chase actually moves, gap holds, stair climb ends with feet on the upper floor
##  - Perch (PRODUCT.md "Perching has risk"): a walker under a boy on 1- or 2-tile furniture
##    catches him after the ~0.6 s reach, never instantly; a hop off at 0.5 s escapes; a hop in
##    place doesn't reset the reach; 3 tiles is out of reach; landing on furniture creaks (noise
##    radius x noise_mult), landing on a floor doesn't, and the creak wakes a calm walker below

var _holder: Node2D


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["hit_then_backoff_no_rehit_1_5s", _recover],
		["walker_gravity_and_stairs_to_next_floor", _walker_stairs],
		["walker_without_stairs_stays_on_floor", _walker_no_stairs],
		["float_crosses_floors_without_stairs", _floater],
		["startle_chase_when_scream_anim_ends", _startle_real],
		["walker_turns_at_gap_floater_crosses", _ledge_gap],
		["b1_flat_chase_moves_centred", _flat_chase.bind(0.0)],
		["b1_flat_chase_moves_origin_at_feet", _flat_chase.bind(-14.0)],
		["b1_gap_holds_centred", _gap_feet.bind(0.0)],
		["b1_gap_holds_origin_at_feet", _gap_feet.bind(-14.0)],
		["b1_stair_feet_on_upper_floor_centred", _stair_feet.bind(0.0)],
		["b1_stair_feet_on_upper_floor_origin_at_feet", _stair_feet.bind(-14.0)],
		["perch_reach_delay_fallback_and_overrides", _reach_delay],
		["perch_1_tile_caught_after_reach", _perch_catch.bind(1, -12.0)],
		["perch_2_tile_caught_after_reach", _perch_catch.bind(2, -12.0)],
		["perch_2_tile_caught_after_reach_centred_boy", _perch_catch.bind(2, 0.0)],
		["perch_1_tile_hop_off_at_0_5s_escapes", _perch_hop_off.bind(1)],
		["perch_2_tile_hop_off_at_0_5s_escapes", _perch_hop_off.bind(2)],
		["perch_hop_in_place_does_not_reset_reach", _perch_hop_in_place],
		["perch_3_tile_out_of_reach", _perch_out_of_reach],
		["perch_creak_on_furniture_scaled_by_noise_mult", _perch_creak],
		["perch_creak_wakes_calm_walker_below", _perch_creak_wakes],
		["perch_creak_vfx_hook_on_landing", _perch_creak_vfx],
	]
	for c in checks:
		PlayerStats.reset(); GameState.reset(); FESignals.reset()
		_holder = Node2D.new()
		tree.root.add_child(_holder)
		var r: Variant = await c[1].call(tree)
		# A runtime script error aborts the check and returns null: count it as a failure.
		var err: String = r if r is String else "script error (check returned %s)" % [r]
		_holder.queue_free()
		await tree.process_frame
		if not err.is_empty():
			failures.append("%s: %s" % [c[0], err])
	PlayerStats.reset(); GameState.reset(); FESignals.reset()
	return {"passed": checks.size() - failures.size(), "total": checks.size(), "failures": failures}


func _boy(at: Vector2, side := false) -> CharacterBody2D:
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	p.side_scroll = side
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 12; cs.shape = c; p.add_child(cs)
	_holder.add_child(p); p.global_position = at
	return p


func _puppet(at: Vector2) -> CharacterBody2D:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 14; cs.shape = c; e.add_child(cs)
	_holder.add_child(e); e.global_position = at
	return e


## Floor slab (LEVELGEN: 16px thick, top surface at y = top).
func _slab(x0: float, x1: float, top: float) -> void:
	var b := StaticBody2D.new()
	b.collision_layer = PlayerStats.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape2D.new(); var r := RectangleShape2D.new(); r.size = Vector2(x1 - x0, 16); cs.shape = r
	b.add_child(cs)
	_holder.add_child(b); b.global_position = Vector2((x0 + x1) * 0.5, top + 8)


func _stair(bottom: Vector2, top: Vector2) -> Stair:
	var s: Stair = load("res://scripts/world/stair.gd").new()
	s.bottom = Vector2.ZERO
	s.top = top - bottom
	s.from_floor = 0
	s.to_floor = 1
	_holder.add_child(s); s.global_position = bottom
	return s


func _recover(tree: SceneTree) -> Variant:
	var p := _boy(Vector2(100, 100))
	var e := _puppet(Vector2(220, 100))
	e._alert()
	var hits: Array[float] = []
	var hp := PlayerStats.health
	var frames := 0
	while frames < 600 and PlayerStats.health > 0:
		await tree.physics_frame
		frames += 1
		if PlayerStats.health < hp:
			hp = PlayerStats.health
			hits.append(frames / 60.0)
	if hits.is_empty(): return "no hit at all"
	if hits[0] > 3.0: return "first hit at %.2fs" % hits[0]
	if hits.size() < 2: return "never hit again in 10s (puppet gave up?)"
	for i in range(1, hits.size()):
		if hits[i] - hits[i - 1] < 1.5: return "hits %.2fs apart (%s)" % [hits[i] - hits[i - 1], hits]
	if PlayerStats.health == 0 and hits[-1] < 4.5: return "3 -> 0 in %.2fs" % hits[-1]
	return ""


## Two floors: ground slab top y=400, upper slab top y=240 (160px apart). Boy upstairs.
func _two_floors(stairs: bool) -> Dictionary:
	_slab(-200, 1000, 400)
	_slab(380, 1000, 240)
	var s: Stair = _stair(Vector2(300, 400), Vector2(396, 240)) if stairs else null
	var p := _boy(Vector2(700, 200), true)
	var e := _puppet(Vector2(100, 300))   # in the air above the ground floor
	e.sight_override = 1   # this test is about pathing, not sight
	e.chase_speed = 120.0
	return {"p": p, "e": e, "s": s}


func _walker_stairs(tree: SceneTree) -> Variant:
	var d := _two_floors(true)
	var e: CharacterBody2D = d.e
	var p: CharacterBody2D = d.p
	await tree.physics_frame
	e._alert()
	var fell := false
	var climbed := false
	var frames := 0
	var reached := false
	while frames < 900:
		await tree.physics_frame
		frames += 1
		if e.is_on_floor() and e.global_position.y > 380.0 and not e.climbing: fell = true
		if e.climbing: climbed = true
		if fell and not e.climbing and e.global_position.y < 380.0 and e.global_position.y > 245.0 and e.global_position.x < 290.0:
			return "flew instead of walking (%s)" % e.global_position
		if e.floor_of(e.global_position) == 1 and e.global_position.distance_to(p.global_position) < 40.0:
			reached = true
			break
	if not fell: return "never fell to the ground slab"
	if not climbed: return "never used the stair"
	if not reached: return "did not reach the boy upstairs (at %s, boy %s)" % [e.global_position, p.global_position]
	if absf(e.global_position.y - (240 - 14)) > 4.0: return "not standing on the upper slab (y %.1f)" % e.global_position.y
	return ""


func _walker_no_stairs(tree: SceneTree) -> Variant:
	var d := _two_floors(false)
	var e: CharacterBody2D = d.e
	e.side_scroll = true   # no stairs: floor graph unknown, still must not leave its slab
	await tree.physics_frame
	e._alert()
	var lowest := 0.0
	for i in 180:
		await tree.physics_frame
		if i > 60: lowest = maxf(lowest, absf(e.global_position.y - (400 - 14)))
	return "" if lowest < 3.0 else "left the ground slab (off by %.1fpx, at %s)" % [lowest, e.global_position]


func _floater(tree: SceneTree) -> Variant:
	_slab(-200, 1000, 400)
	_slab(-200, 1000, 240)   # solid ceiling/upper slab, no stair at all
	var p := _boy(Vector2(400, 200), true)
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	e.movement = &"float"
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 14; cs.shape = c; e.add_child(cs)
	_holder.add_child(e); e.global_position = Vector2(300, 386)
	e.sight_override = 1
	await tree.physics_frame
	e._alert()
	var start_y := e.global_position.y
	for i in 600:
		await tree.physics_frame
		if PlayerStats.health < 3 or e.global_position.distance_to(p.global_position) < 34.0:
			return "" if e.global_position.y < 270.0 else "never rose through the slab (y %.0f)" % e.global_position.y
	return "float stuck (from y %.0f to %s)" % [start_y, e.global_position]


## Real frames: lit for light_startle_time -> STARTLED -> CHASE exactly when the scream
## animation (frames / fps from the manifest) has played through, holding its last frame.
func _startle_real(tree: SceneTree) -> Variant:
	_boy(Vector2(100, 100))
	var e := _puppet(Vector2(300, 100))
	e.sight_override = 1
	await tree.physics_frame
	e.lit_override = 1
	var f := 0
	while e.state != e.State.STARTLED and f < 180:
		await tree.physics_frame
		f += 1
	if e.state != e.State.STARTLED: return "never startled"
	var want: float = e.startle_delay()
	var spr: AnimatedSprite2D = e.get_node("Anim")
	var startled := 0
	var last_frame := -1
	while e.state == e.State.STARTLED and startled < 120:
		last_frame = spr.frame
		await tree.physics_frame
		startled += 1
	if e.state != e.State.CHASE: return "STARTLED -> state %d" % e.state
	var t := startled / float(Engine.physics_ticks_per_second)
	if absf(t - want) > 2.5 / Engine.physics_ticks_per_second: return "chase %.3fs after startle, scream anim %.3fs" % [t, want]
	var n := spr.sprite_frames.get_frame_count(e.anim_startle) if spr.sprite_frames.has_animation(e.anim_startle) else 0
	if n > 0 and last_frame < n - 2: return "chased at scream frame %d of %d" % [last_frame, n]
	return ""


## Ground slab with a 100px gap (x 300..400, a floor opening). The walker patrols toward it,
## then chases a boy on the far side: it never falls in. A floater patrolling the same line
## drifts across it.
func _ledge_gap(tree: SceneTree) -> Variant:
	_slab(-400, 300, 400)
	_slab(400, 1200, 400)
	var e := _puppet(Vector2(200, 386))
	e.side_scroll = true
	e.sight_override = 0
	e.patrol_radius = 200.0   # home 200 -> patrol target x 400, across the gap
	var fl := _puppet(Vector2(200, 386))
	fl.movement = &"float"
	fl._apply_mask()
	fl.side_scroll = true
	fl.sight_override = 0
	fl.patrol_radius = 300.0   # target x 500: all the way over the gap to the far slab
	var max_x := -INF
	var turned := false
	var fl_crossed := false
	for i in 600:
		await tree.physics_frame
		if e.global_position.y > 386.0 + 3.0: return "walker fell into the gap at frame %d (%s)" % [i, e.global_position]
		max_x = maxf(max_x, e.global_position.x)
		if max_x > 280.0 and e.global_position.x < max_x - 30.0: turned = true
		if fl.global_position.x > 410.0: fl_crossed = true
	if max_x >= 300.0: return "walker stood over the gap (x %.0f)" % max_x
	if not turned: return "patrolling walker did not turn back at the edge (max x %.0f, at %.0f)" % [max_x, e.global_position.x]
	if not fl_crossed: return "floater did not cross the gap (x %.0f)" % fl.global_position.x
	# CHASE never steps off either: the boy is right across the gap, same floor height.
	var p := _boy(Vector2(520, 386), true)
	e.sight_override = 1
	e.hear_noise()
	for i in 300:
		await tree.physics_frame
		if e.global_position.y > 386.0 + 3.0: return "chasing walker fell into the gap (%s)" % e.global_position
	if e.global_position.x >= 300.0: return "chasing walker over the gap (x %.0f)" % e.global_position.x
	return "" if p.global_position.x > 400.0 else "boy moved?"


## Walker whose r=14 circle sits at (0, off): off 0 = centred (old map), off -14 = origin at
## the feet (LevelGenerator._circle). Placed so its collider bottom (feet) is at `feet`.
func _walker_feet(feet: Vector2, off: float) -> CharacterBody2D:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 14; cs.shape = c
	cs.position = Vector2(0, off); cs.name = "Body"
	e.add_child(cs)
	_holder.add_child(e); e.global_position = feet - Vector2(0, off + 14.0)
	e.side_scroll = true
	return e


## Collider bottom, measured independently of enemy_base's own _feet().
func _bottom(e: CharacterBody2D) -> Vector2:
	var cs: CollisionShape2D = e.get_node("Body")
	return cs.global_position + Vector2(0, 14)


## QA B1 repro: walker on a flat floor, _enter_chase toward a boy 300px away. It must move
## (> 150px in 600 frames) and the ledge backstop must not fire on most frames.
func _flat_chase(tree: SceneTree, off: float) -> Variant:
	_slab(-400, 1600, 400)
	var e := _walker_feet(Vector2(200, 400), off)
	e.sight_override = 1
	e.chase_speed = 120.0
	await tree.physics_frame
	await tree.physics_frame
	var p := _boy(Vector2(500, 388), true)
	var x0 := e.global_position.x
	e._enter_chase(9999)
	var stopped := 0
	var moved := 0.0
	for i in 600:
		await tree.physics_frame
		if e.ledge_stopped: stopped += 1
		moved = maxf(moved, absf(e.global_position.x - x0))
		if absf(_bottom(e).y - 400.0) > 3.0 and i > 10: return "left the floor (feet y %.1f)" % _bottom(e).y
	if moved <= 150.0: return "moved only %.1fpx toward the boy (ledge_stopped %d/600 frames)" % [moved, stopped]
	if stopped * 2 >= 600: return "ledge_stopped on %d/600 frames" % stopped
	return "" if p != null else "no boy"


## The gap test with feet measured from the collider: never falls in, turns back, and the
## chase across the gap stops at the edge.
func _gap_feet(tree: SceneTree, off: float) -> Variant:
	_slab(-400, 300, 400)
	_slab(400, 1200, 400)
	var e := _walker_feet(Vector2(200, 400), off)
	e.sight_override = 0
	e.patrol_radius = 200.0
	var max_x := -INF
	var turned := false
	for i in 600:
		await tree.physics_frame
		if _bottom(e).y > 403.0: return "walker fell into the gap at frame %d (feet %s)" % [i, _bottom(e)]
		max_x = maxf(max_x, e.global_position.x)
		if max_x > 280.0 and e.global_position.x < max_x - 30.0: turned = true
	if max_x >= 300.0: return "walker stood over the gap (x %.0f)" % max_x
	if max_x < 250.0: return "walker barely patrolled toward the edge (max x %.0f)" % max_x
	if not turned: return "did not turn back at the edge (max x %.0f)" % max_x
	_boy(Vector2(520, 388), true)
	e.sight_override = 1
	e._enter_chase(9999)
	for i in 300:
		await tree.physics_frame
		if _bottom(e).y > 403.0: return "chasing walker fell into the gap (feet %s)" % _bottom(e)
	if e.global_position.x >= 300.0: return "chasing walker over the gap (x %.0f)" % e.global_position.x
	return ""


## Ground slab y=400, upper slab y=240, stair 300->396. The walker climbs and its collider
## bottom ends on the upper floor surface within 1px.
func _stair_feet(tree: SceneTree, off: float) -> Variant:
	_slab(-200, 1000, 400)
	_slab(380, 1000, 240)
	_stair(Vector2(300, 400), Vector2(396, 240))
	var e := _walker_feet(Vector2(100, 400), off)
	e.sight_override = 1
	e.chase_speed = 120.0
	await tree.physics_frame
	await tree.physics_frame
	var p := _boy(Vector2(700, 228), true)
	e._enter_chase(9999)
	var climbed := false
	for i in 900:
		await tree.physics_frame
		if e.climbing: climbed = true
		if climbed and not e.climbing and e.is_on_floor() and _bottom(e).y < 300.0 \
				and e.global_position.x > 420.0:
			var dy := _bottom(e).y - 240.0
			# a few settle frames, then measure again
			for k in 10: await tree.physics_frame
			dy = _bottom(e).y - 240.0
			if absf(dy) > 1.0: return "feet %.2fpx off the upper floor (feet y %.2f)" % [dy, _bottom(e).y]
			return "" if p != null else "no boy"
	if not climbed: return "never climbed (at %s, feet %s)" % [e.global_position, _bottom(e)]
	return "did not land on the upper floor (feet %s, climbing %s)" % [_bottom(e), e.climbing]


# --- perch -------------------------------------------------------------------------------
const PERCH_FLOOR := 400.0
const PERCH_X := 312.0


## Floor slab + a 4-tile-wide furniture block h tiles (16px) tall at x 280..344, its own WORLD
## body (like #13's LowFurniture). Returns the furniture body.
func _furniture(h_tiles: int) -> StaticBody2D:
	_slab(-400, 1600, PERCH_FLOOR)
	var b := StaticBody2D.new()
	b.collision_layer = PlayerStats.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape2D.new(); var r := RectangleShape2D.new()
	r.size = Vector2(64, h_tiles * 16); cs.shape = r
	b.add_child(cs)
	_holder.add_child(b); b.global_position = Vector2(PERCH_X, PERCH_FLOOR - h_tiles * 8)
	return b


## Real side-scroll boy whose r=12 circle sits at (0, off) (-12 = #13's feet origin), feet at `feet`.
func _perch_boy(feet: Vector2, off := -12.0) -> CharacterBody2D:
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	p.side_scroll = true
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 12; cs.shape = c
	cs.position = Vector2(0, off)
	p.add_child(cs)
	_holder.add_child(p); p.global_position = feet - Vector2(0, off + 12.0)
	return p


## Walker 40px left of the furniture's middle, walking in under it (passes through it, like
## #13's walkers); on 1 tile its head meets the boy and it stops ~22px short, still in reach.
func _under_walker(furn: StaticBody2D, chase := true) -> CharacterBody2D:
	var e := _walker_feet(Vector2(PERCH_X - 40.0, PERCH_FLOOR), 0.0)
	e.add_collision_exception_with(furn)
	e.sight_override = 1
	if chase:
		e._enter_chase(9999)
	return e


class Watch:
	var started := -1
	var ended: Array = []   # [frame, caught]
	var frame := 0
	func on_start() -> void: started = frame
	func on_end(caught: bool) -> void: ended.append([frame, caught])


func _watch(e: CharacterBody2D) -> Watch:
	var w := Watch.new()
	e.reach_started.connect(w.on_start)
	e.reach_ended.connect(w.on_end)
	return w


## Catch timing and reach height: reach_time / perch_reach_height overrides, else the reach
## slot's manifest hit_frame / fps and reach_height_px, else 0.6 s / 40 px. The puppet's own
## slot is checked against whatever the manifest on this branch says (#40 adds it).
func _reach_delay(_tree: SceneTree) -> Variant:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_holder.add_child(e)
	if e.anim_reach != "puppet_reach_up": return "puppet anim_reach is %s" % e.anim_reach
	var m: Dictionary = AnimLibrary.meta("puppet_reach_up")
	var want_t := 0.6
	var want_h := 40.0
	if m.has("hit_frame") and float(m.get("fps", 0)) > 0.0: want_t = int(m.hit_frame) / float(m.fps)
	if float(m.get("reach_height_px", 0)) > 0.0: want_h = float(m.reach_height_px)
	if absf(e.reach_delay() - want_t) > 1e-6: return "puppet reach %.3fs, want %.3f" % [e.reach_delay(), want_t]
	if absf(e.reach_height() - want_h) > 1e-6: return "puppet reach height %.1f, want %.1f" % [e.reach_height(), want_h]
	e.anim_reach = "no_such_slot"
	if absf(e.reach_delay() - 0.6) > 1e-6: return "no reach anim: delay %.3f, want 0.6 fallback" % e.reach_delay()
	if absf(e.reach_height() - 40.0) > 1e-6: return "no reach anim: height %.1f, want 40 fallback" % e.reach_height()
	AnimLibrary.meta("puppet_calm")   # make sure the manifest is loaded before injecting
	AnimLibrary._entries["__test_reach"] = {"slot": "__test_reach", "frames": 12, "fps": 12, "hit_frame": 9, "reach_height_px": 37}
	e.anim_reach = "__test_reach"
	var t: float = e.reach_delay()
	var h: float = e.reach_height()
	e.reach_time = 0.9
	e.perch_reach_height = 50.0
	var t2: float = e.reach_delay()
	var h2: float = e.reach_height()
	AnimLibrary._entries.erase("__test_reach")
	if absf(t - 0.75) > 1e-6: return "manifest hit_frame 9 @12fps: delay %.3f, want 0.75" % t
	if absf(h - 37.0) > 1e-6: return "manifest reach_height_px 37: height %.1f" % h
	if absf(t2 - 0.9) > 1e-6: return "reach_time override ignored (%.3f)" % t2
	if absf(h2 - 50.0) > 1e-6: return "perch_reach_height override ignored (%.1f)" % h2
	return ""


## Boy perched h tiles up, walker right under him chasing: no hit at all until the reach lands
## at 0.6 s (36 frames), then exactly one hit.
func _perch_catch(tree: SceneTree, h_tiles: int, off: float) -> Variant:
	var furn := _furniture(h_tiles)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - h_tiles * 16), off)
	for i in 3: await tree.physics_frame
	var hp := PlayerStats.health
	var e := _under_walker(furn)
	var w := _watch(e)
	var hit_at := -1
	for f in 120:
		w.frame = f
		await tree.physics_frame
		if PlayerStats.health < hp:
			hit_at = f
			break
	if w.started < 0: return "never started a reach (h %.1f, boy standing %s, hit_at %d)" % [e.perch_height(p), p._grounded(), hit_at]
	if hit_at < 0: return "reach never caught him (ended %s)" % [w.ended]
	var t := (hit_at - w.started) / float(Engine.physics_ticks_per_second)
	if absf(t - 0.6) > 2.5 / Engine.physics_ticks_per_second: return "caught %.3fs after the reach started, want 0.6" % t
	if w.ended.is_empty() or not w.ended[0][1]: return "reach_ended(true) not sent (%s)" % [w.ended]
	if PlayerStats.health != hp - 1: return "health %d, want %d" % [PlayerStats.health, hp - 1]
	return ""


## Hop off to the right at 0.5 s into the reach: the reach is cancelled, never lands, and the
## boy gets away clean for a full second.
func _perch_hop_off(tree: SceneTree, h_tiles: int) -> Variant:
	var furn := _furniture(h_tiles)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - h_tiles * 16))
	for i in 3: await tree.physics_frame
	var hp := PlayerStats.health
	var e := _under_walker(furn)
	var w := _watch(e)
	var f := 0
	while w.started < 0 and f < 30:
		w.frame = f; await tree.physics_frame; f += 1
	if w.started < 0: return "never started a reach"
	for i in 30:   # 0.5 s of reach
		w.frame = f; await tree.physics_frame; f += 1
	if PlayerStats.health < hp: return "hit before the hop (frame %d)" % f
	Input.action_press(&"move_right")
	p.jump()
	var err := ""
	for i in 60:
		w.frame = f; await tree.physics_frame; f += 1
		if PlayerStats.health < hp:
			err = "hit %d frames after hopping off (reach ended %s)" % [i, w.ended]
			break
	Input.action_release(&"move_right")
	if not err.is_empty(): return err
	if w.ended.is_empty() or w.ended[0][1]: return "reach not cancelled (ended %s)" % [w.ended]
	return ""


## A hop straight up at 0.5 s and back down onto the same perch resumes the reach: caught
## within ~0.2 s of landing, not a fresh 0.6 s later.
func _perch_hop_in_place(tree: SceneTree) -> Variant:
	var furn := _furniture(2)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 32))
	for i in 3: await tree.physics_frame
	var hp := PlayerStats.health
	var e := _under_walker(furn)
	var w := _watch(e)
	var f := 0
	while w.started < 0 and f < 30:
		w.frame = f; await tree.physics_frame; f += 1
	for i in 30:
		w.frame = f; await tree.physics_frame; f += 1
	p.jump()
	var landed := -1
	var airborne := false
	for i in 120:
		w.frame = f; await tree.physics_frame; f += 1
		if not p.is_on_floor(): airborne = true
		if airborne and landed < 0 and p.is_on_floor(): landed = f
		if PlayerStats.health < hp:
			if landed < 0: return "hit in mid-air (frame %d)" % f
			var after := (f - landed) / float(Engine.physics_ticks_per_second)
			return "" if after <= 0.2 else "reach restarted: caught %.2fs after landing back" % after
	return "never caught after hopping in place (airborne %s, landed %d, ended %s)" % [airborne, landed, w.ended]


## 3 tiles up (48px) is out of reach: no reach, no hit, for 2 s with the walker right under.
func _perch_out_of_reach(tree: SceneTree) -> Variant:
	var furn := _furniture(3)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48))
	for i in 3: await tree.physics_frame
	var hp := PlayerStats.health
	var e := _under_walker(furn)
	var w := _watch(e)
	var under := 0
	for f in 120:
		w.frame = f
		await tree.physics_frame
		if absf(e._feet().x - PERCH_X) < 20.0: under += 1
	if under < 60: return "walker wasn't under him (only %d frames)" % under
	if not p._grounded(): return "boy not standing on the 3-tile piece"
	if w.started >= 0: return "reached for a 3-tile perch (h %.1f)" % e.perch_height(p)
	if PlayerStats.health < hp: return "hit on a 3-tile perch"
	return ""


class NoiseLog:
	var got: Array = []   # [at, radius, source]
	func on_noise(at: Vector2, radius: float, _l: float, source: Node) -> void: got.append([at, radius, source])


## Landing on 1/2/3-tile furniture creaks once at his feet, radius furniture_creak_radius x
## noise_mult (x2 with a +100% modifier); landing on the bare floor doesn't.
func _perch_creak(tree: SceneTree) -> Variant:
	var log := NoiseLog.new()
	NoiseBus.noise.connect(log.on_noise)
	var err: String = await _creak_case(tree, log, 0, 1.0)
	for h in [1, 2, 3]:
		if err.is_empty(): err = await _creak_case(tree, log, h, 1.0)
	if err.is_empty():
		PlayerStats.add_modifier(&"noise_mult", 0.0, 2.0, "perch_test")
		err = await _creak_case(tree, log, 2, 2.0)
	NoiseBus.noise.disconnect(log.on_noise)
	return err


func _creak_case(tree: SceneTree, log: NoiseLog, h_tiles: int, mult: float) -> String:
	var root := Node2D.new()
	var keep := _holder
	_holder.add_child(root)
	_holder = root
	if h_tiles > 0:
		_furniture(h_tiles)
	else:
		_slab(-400, 1600, PERCH_FLOOR)
	var top := PERCH_FLOOR - h_tiles * 16
	var p := _perch_boy(Vector2(PERCH_X, top - 30))   # dropped from 30px above
	var heard := []
	p.creaked.connect(func(px): heard.append(px))
	var want: float = p.furniture_creak_radius * mult
	log.got.clear()
	var landed := false
	for i in 60:
		await tree.physics_frame
		if p.is_on_floor(): landed = true
	_holder = keep
	root.queue_free()
	await tree.physics_frame
	if not landed: return "%d tiles: never landed" % h_tiles
	var mine := log.got.filter(func(n): return is_instance_valid(n[2]) == false or n[2] is CharacterBody2D)
	if h_tiles == 0:
		return "" if mine.is_empty() and heard.is_empty() else "creaked on the bare floor (%s)" % [heard]
	if mine.size() != 1 or heard.size() != 1: return "%d tiles: %d creaks / %d noises, want 1" % [h_tiles, heard.size(), mine.size()]
	if absf(float(heard[0]) - h_tiles * 16) > 3.0: return "%d tiles: measured furniture %.1fpx" % [h_tiles, heard[0]]
	if absf(float(mine[0][1]) - want) > 0.5: return "%d tiles x%.1f: creak radius %.1f, want %.1f" % [h_tiles, mult, mine[0][1], want]
	if absf((mine[0][0] as Vector2).y - top) > 2.0: return "creak not at his feet (%s)" % mine[0][0]
	return ""


## End to end: a CALM walker idles under 2-tile furniture; the boy drops onto it, the creak
## sets it chasing, it reaches and catches him (no light, no sight).
func _perch_creak_wakes(tree: SceneTree) -> Variant:
	var furn := _furniture(2)
	var e := _under_walker(furn, false)
	e.sight_override = 0
	await tree.physics_frame
	var hp := PlayerStats.health
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 32 - 20))
	var w := _watch(e)
	for f in 150:
		w.frame = f
		await tree.physics_frame
		if PlayerStats.health < hp: break
	if w.started < 0: return "creak didn't lead to a reach (state %d, boy grounded %s)" % [e.state, p._grounded()]
	return "" if PlayerStats.health < hp else "reached but never caught (ended %s)" % [w.ended]


## vfx_creak hook: landing on furniture spawns the manifest vfx_creak one-shot at his feet and
## frees it after the last frame; a bare floor spawns none. Without the slot (art PR #40 not
## merged) nothing spawns and nothing errors.
func _perch_creak_vfx(tree: SceneTree) -> Variant:
	_furniture(2)
	var top := PERCH_FLOOR - 32
	var p := _perch_boy(Vector2(PERCH_X, top - 30))
	var has_art := AnimLibrary.has_slot("vfx_creak")
	var seen := false
	for i in 60:
		await tree.physics_frame
		var v := _holder.get_node_or_null("VfxCreak") as AnimatedSprite2D
		if v != null and not seen:
			seen = true
			if v.animation != &"vfx_creak": return "wrong anim %s" % v.animation
			if absf(v.global_position.y - top) > 2.0: return "vfx at y %.1f, furniture top %d" % [v.global_position.y, top]
			if v.sprite_frames.get_animation_loop(&"vfx_creak"): return "vfx_creak loops"
	if not has_art:
		return "" if not seen else "vfx spawned without a manifest slot"
	if not seen: return "no vfx_creak on landing on furniture"
	for i in 60:
		await tree.physics_frame
	if _holder.get_node_or_null("VfxCreak") != null: return "vfx_creak not freed after its last frame"
	if p == null: return "no boy"
	return ""

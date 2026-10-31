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
		["face_chasing_left_flips_right_does_not", _face_chase],
		["face_no_flicker_at_vx_zero_reach_faces_boy", _face_reach_still],
		["face_flip_keeps_art_pivot_on_feet", _face_flip_feet],
		["perch_height_measured_from_walker_feet_both_shapes", _perch_height_feet],
		["perch_2_tile_caught_walker_origin_at_feet", _perch_catch_walker_shape.bind(-14.0)],
		["perch_2_tile_caught_walker_centred", _perch_catch_walker_shape.bind(0.0)],
		["perch_3_tile_out_of_reach", _perch_out_of_reach],
		["rattle_starts_after_3s_unreachable_3_4_tiles_and_height_override", _rattle_start],
		["rattle_floater_never_rattles", _rattle_floater],
		["rattle_noise_each_rattle_pulls_other_enemy", _rattle_noise],
		["rattle_noise_cadence_tunable", _rattle_cadence],
		["rattle_shake_off_lands_on_walker_side_left", _rattle_shake.bind(-1, false)],
		["rattle_shake_off_lands_on_walker_side_right", _rattle_shake.bind(1, false)],
		["rattle_shake_off_beside_wall_lands_valid", _rattle_shake.bind(-1, true)],
		["rattle_cancels_when_boy_leaves_timers_reset", _rattle_cancel_leave],
		["rattle_cancels_on_stun_and_state_change", _rattle_cancel_stun],
		["rattle_camping_cycle_hop_off_and_back_still_rattles_and_shakes", _rattle_camp_cycle],
		["rattle_grace_resumes_progress_but_stun_still_resets", _rattle_grace_resume],
		["rattle_walker_200px_away_goes_straight_to_piece_base_both_sides", _rattle_far_walker],
		["rattle_real_levels_far_walker_both_sides_rattles_by_3_5s", _rattle_real_levels],
		["rattle_shake_wedge_gap_walker_side_blocked_goes_far_side", _rattle_wedge_far_side],
		["rattle_shake_no_free_landing_keeps_rattling_never_cancels", _rattle_no_landing],
		["rattle_landing_measured_from_cluster_edge_walker_inside_footprint", _rattle_cluster_landing],
		["rattle_cluster_both_sides_blocked_keeps_rattling_never_cancels", _rattle_cluster_blocked],
		["rattle_step_top_on_the_walkers_side_first", _rattle_step_rule.bind("ours")],
		["rattle_far_step_top_when_ours_is_blocked", _rattle_step_rule.bind("far")],
		["rattle_never_lands_on_a_3_tall_neighbour_top_floor_past_it", _rattle_step_rule.bind("tall_neighbour")],
		["rattle_step_beyond_reach_height_is_not_a_landing_floor_instead", _rattle_step_rule.bind("uncatchable")],
		["rattle_after_step_landing_the_perch_reach_catches_him", _rattle_step_rule.bind("reach")],
		["rattle_walker_flush_against_level_wall_lands_on_the_open_side", _rattle_level_wall.bind("flush")],
		["rattle_walker_pinned_in_a_gap_at_level_wall_lands_on_the_open_side", _rattle_level_wall.bind("gap")],
		["rattle_boy_resting_on_an_enemy_head_is_nudged_to_the_floor", _rattle_head_nudge],
		["rattle_vfx_freed_when_the_walker_is_freed_mid_rattle", _rattle_vfx_orphan],
		["rattle_watchdog_frees_wedged_boy_and_clears_immunity", _rattle_watchdog],
		["rattle_shake_touchdown_gives_control_and_hit_grace", _rattle_hit_grace],
		["rattle_claw_visual_offset_toward_piece_sign_correct_collision_fixed", _rattle_claw_offset],
		["rattle_wobble_manifest_steps_negated_when_flipped_collision_fixed", _rattle_wobble_test],
		["rattle_claw_to_furniture_offset_identical_flipped_vs_unflipped", _rattle_relative_offset],
		["rattle_vfx_on_furniture_top_freed_on_end", _rattle_vfx],
		["face_hysteresis_boy_wobbling_7px_no_flicker", _face_hysteresis],
		["stair_clears_off_perch_immunity_airborne_keeps_it", _stair_immunity],
		["perch_creak_on_furniture_scaled_by_noise_mult", _perch_creak],
		["perch_creak_wakes_calm_walker_below", _perch_creak_wakes],
		["perch_creak_vfx_hook_on_landing", _perch_creak_vfx],
		["sprite_feet_on_collider_feet_centred", _sprite_feet.bind(0.0)],
		["sprite_feet_on_collider_feet_origin_at_feet", _sprite_feet.bind(-14.0)],
		["sprite_feet_floater_every_slot", _sprite_feet_floater],
		["sprite_art_bottom_pixel_on_floor_centred", _sprite_floor.bind(0.0)],
		["sprite_art_bottom_pixel_on_floor_origin_at_feet", _sprite_floor.bind(-14.0)],
		["sprite_follows_collider_swapped_after_ready", _sprite_swapped_shape],
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
func _under_walker(furn: StaticBody2D, chase := true, woff := 0.0) -> CharacterBody2D:
	var e := _walker_feet(Vector2(PERCH_X - 40.0, PERCH_FLOOR), woff)
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


# --- sprite anchored to the real feet (QA: walkers floated 14px on #13 levels) --------------
## Manifest pivot = feet of the art. The node origin is NOT the feet when the collider is
## centred (feet 14px below), so the sprite offset = AnimLibrary.offset_for(slot) + origin->feet.

## Where the art's pivot lands in world space, measured from the sprite's actual offset.
func _pivot_world(e: CharacterBody2D, slot: String) -> Vector2:
	var spr: AnimatedSprite2D = e.get_node("Anim")
	var fs: Array = AnimLibrary.meta(slot).get("frame_size", [0, 0])
	return e.global_position + spr.position + spr.offset + AnimLibrary.pivot(slot) - Vector2(fs[0], fs[1]) * 0.5


## Lowest opaque row (inclusive) over every frame of the slot's strip, measured from the PNG.
func _art_bottom_row(slot: String) -> int:
	var m := AnimLibrary.meta(slot)
	var tex: Texture2D = load("res://" + str(m.path))
	var img := tex.get_image()
	var fs: Array = m.get("frame_size")
	var low := -1
	for f in int(m.get("frames", 1)):
		for y in range(int(fs[1]) - 1, -1, -1):
			var hit := false
			for x in int(fs[0]):
				if img.get_pixel(f * int(fs[0]) + x, y).a > 0.0:
					hit = true
					break
			if hit:
				low = maxi(low, y)
				break
	return low


func _slots_of(e: CharacterBody2D) -> Array:
	var out: Array = []
	for s in [e.anim_calm, e.anim_startle, e.chase_slot()]:
		if not str(s).is_empty() and AnimLibrary.has_slot(s):
			out.append(s)
	return out


func _sprite_feet(tree: SceneTree, off: float) -> Variant:
	var e := _walker_feet(Vector2(200, 100), off)
	await tree.physics_frame
	var want := _bottom(e)
	for slot in _slots_of(e):
		e._play(slot)
		var got := _pivot_world(e, slot)
		if got.distance_to(want) > 0.01:
			return "%s: art pivot at %s, collider feet at %s (off %.0f)" % [slot, got, want, off]
	return ""


func _sprite_feet_floater(tree: SceneTree) -> Variant:
	for off in [0.0, -14.0]:
		var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
		e.movement = e.MOVE_FLOAT
		var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 14; cs.shape = c
		cs.position = Vector2(0, off); cs.name = "Body"
		e.add_child(cs)
		_holder.add_child(e); e.global_position = Vector2(200, 100)
		await tree.physics_frame
		var want := _bottom(e)
		if not e.chase_slot().ends_with("_float"):
			return "floater chase slot is %s" % e.chase_slot()
		for slot in _slots_of(e):
			e._play(slot)
			var got := _pivot_world(e, slot)
			if got.distance_to(want) > 0.01:
				return "floater %s: art pivot at %s, collider feet at %s (off %.0f)" % [slot, got, want, off]
	return ""


## Real physics: the walker stands on a slab; the lowest opaque pixel of every frame of every
## slot is on the floor (within 0.5px of the physics rest margin, and the 1px the manifest pivot row 63 sinks in), never floating.
func _sprite_floor(tree: SceneTree, off: float) -> Variant:
	_slab(0, 600, 200)
	var e := _walker_feet(Vector2(300, 150), off)
	for i in 90:
		await tree.physics_frame
	if not e.is_on_floor(): return "walker not on floor"
	var floor_y := 200.0
	for slot in _slots_of(e):
		e._play(slot)
		var spr: AnimatedSprite2D = e.get_node("Anim")
		var fs: Array = AnimLibrary.meta(slot).get("frame_size")
		var bottom_edge := e.global_position.y + spr.position.y + spr.offset.y + float(_art_bottom_row(slot) + 1) - float(fs[1]) * 0.5
		var gap := bottom_edge - floor_y   # > 0 sinks in, < 0 floats
		if gap < -0.5 or gap > 1.5:
			return "%s: lowest art pixel edge %.2f vs floor %.2f (gap %.2f, off %.0f)" % [slot, bottom_edge, floor_y, gap, off]
	return ""


## The collider can be (re)built after _ready (tests, runtime generators): the sprite catches up.
func _sprite_swapped_shape(tree: SceneTree) -> Variant:
	var e := _walker_feet(Vector2(200, 100), -14.0)   # origin at the feet at _ready
	await tree.physics_frame
	await tree.physics_frame
	var cs: CollisionShape2D = e.get_node("Body")
	cs.position = Vector2(0, 0)                      # collider recentred: feet now 14px below the origin
	e.global_position -= Vector2(0, 14)
	for i in 3:
		await tree.physics_frame
	var got := _pivot_world(e, e.anim_calm)
	if got.distance_to(_bottom(e)) > 0.01:
		return "after swap art pivot %s vs feet %s" % [got, _bottom(e)]
	return ""


## Reach height is measured from the walker's real feet (the floor) to the boy's feet, whatever
## the walker's collider offset: 1 / 2 / 3 tiles read 16 / 32 / 48 against reach_height() 40.
func _perch_height_feet(tree: SceneTree) -> Variant:
	for woff in [0.0, -14.0]:
		for h in [1, 2, 3]:
			var furn := _furniture(h)
			var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - h * 16), -12.0)
			for i in 3: await tree.physics_frame
			var e := _under_walker(furn, false, woff)
			for i in 20: await tree.physics_frame
			var want: float = h * 16.0
			if absf(e.perch_height(p) - want) > 1.0:
				return "walker shape off %.0f, %d tiles: perch_height %.2f, want %.1f" % [woff, h, e.perch_height(p), want]
			if (e.perch_height(p) <= e.reach_height()) != (h <= 2):
				return "walker shape off %.0f, %d tiles: reach_height %.1f gives wrong in-reach" % [woff, h, e.reach_height()]
			p.free(); furn.free(); e.free()
	return ""


func _perch_catch_walker_shape(tree: SceneTree, woff: float) -> Variant:
	var furn := _furniture(2)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 32.0), -12.0)
	for i in 3: await tree.physics_frame
	var hp := PlayerStats.health
	var e := _under_walker(furn, true, woff)
	var w := _watch(e)
	var hit := -1
	for f in 120:
		w.frame = f
		await tree.physics_frame
		if PlayerStats.health < hp:
			hit = f
			break
	if w.started < 0: return "never started a reach (walker off %.0f)" % woff
	if hit < 0: return "no catch (walker off %.0f)" % woff
	if absf((hit - w.started) / 60.0 - e.reach_delay()) > 0.1: return "catch %.2fs after start, want %.2fs" % [(hit - w.started) / 60.0, e.reach_delay()]
	return ""


# --- sprite facing (QA: enemies never mirrored; chase art faces right, "flip_h for left") ----
func _face_chase(tree: SceneTree) -> Variant:
	_slab(0, 900, 200)
	for side in [-1, 1]:
		var e := _walker_feet(Vector2(450, 200), 0.0)
		var p := _boy(Vector2(450 + side * 250, 188), true)
		e.sight_override = 1
		e._enter_chase(9999)
		var spr: AnimatedSprite2D = e.get_node("Anim")
		var flips := 0
		var last := spr.flip_h
		for i in 40:
			await tree.physics_frame
			if spr.flip_h != last: flips += 1
			last = spr.flip_h
		if spr.flip_h != (side < 0): return "chasing a boy to the %s: flip_h %s" % ["left" if side < 0 else "right", spr.flip_h]
		if flips > 1: return "flip flickered %d times on a straight chase" % flips
		e.free(); p.free()
	return ""


## Standing under the boy in REACH (vx 0): faces him, and wobbling the boy a few px around the
## walker's x (inside the deadzone) never flips it.
func _face_reach_still(tree: SceneTree) -> Variant:
	var furn := _furniture(2)
	var p := _perch_boy(Vector2(PERCH_X - 26.0, PERCH_FLOOR - 32.0), -12.0)   # boy 20px left of the walker
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X - 6.0, PERCH_FLOOR), 0.0)
	e.add_collision_exception_with(furn)
	e.sight_override = 1
	e._enter_chase(9999)
	var spr: AnimatedSprite2D = e.get_node("Anim")
	var f := 0
	while e.state != e.State.REACH and f < 90:
		await tree.physics_frame
		f += 1
	if e.state != e.State.REACH: return "no reach (state %d)" % e.state
	for i in 3: await tree.physics_frame
	if not spr.flip_h: return "reaching a boy on its left: not flipped"
	var base := p.global_position
	var flips := 0
	var last := spr.flip_h
	for k in 24:
		p.global_position = base + Vector2(((k % 4) - 1.5) * 2.0, 0)   # wobble within the deadzone
		p.global_position.x = e.global_position.x + (3.0 if k % 2 == 0 else -3.0)
		await tree.physics_frame
		if e.state != e.State.REACH: break
		if spr.flip_h != last: flips += 1
		last = spr.flip_h
	if flips > 0: return "flipped %d times with the boy within the deadzone" % flips
	return ""


## flip_h on/off keeps the pivot on the feet and the lowest art pixel on the floor: puppet slots
## are x-symmetric about the pivot (offset.x = 0), so the mirror happens about the feet column.
func _face_flip_feet(tree: SceneTree) -> Variant:
	_slab(0, 600, 200)
	var e := _walker_feet(Vector2(300, 150), 0.0)
	for i in 90:
		await tree.physics_frame
	var spr: AnimatedSprite2D = e.get_node("Anim")
	for dir in [1, -1]:
		e.face_dir = dir
		for slot in _slots_of(e):
			e._play(slot)
			e._apply_flip()
			if spr.flip_h != (dir < 0): return "%s: flip_h %s for face_dir %d" % [slot, spr.flip_h, dir]
			if absf(spr.offset.x) > 0.01: return "%s: offset.x %.2f, mirror would move the feet column" % [slot, spr.offset.x]
			if absf(AnimLibrary.pivot(slot).x * 2.0 - float(AnimLibrary.meta(slot).frame_size[0])) > 0.01: return "%s pivot not centred" % slot
			var fs: Array = AnimLibrary.meta(slot).get("frame_size")
			var edge := e.global_position.y + spr.position.y + spr.offset.y + float(_art_bottom_row(slot) + 1) - float(fs[1]) * 0.5
			if edge - 200.0 < -0.5 or edge - 200.0 > 1.5: return "%s flipped %d: art bottom %.2f vs floor 200" % [slot, dir, edge]
			if _pivot_world(e, slot).distance_to(_bottom(e)) > 0.01: return "%s flipped %d: pivot off the feet" % [slot, dir]
	if e.art_faces_left("puppet_chase"): return "puppet_chase should face right"
	return ""


# --- rattle (PD "No safe camping"), QA follow-ups: stair immunity, facing hysteresis --------
## 3/4-tile piece with a visual (ColorRect child, like #13's placeholder), no walker exception:
## the walker can only stand beside it.
func _tall(h_tiles: int) -> StaticBody2D:
	var b := _furniture(h_tiles)
	var vis := ColorRect.new()
	vis.name = "Vis"
	vis.size = Vector2(64, h_tiles * 16)
	vis.position = -vis.size * 0.5
	b.add_child(vis)
	return b


## Boy on the piece, walker `side` (-1 left / +1 right) of it, chasing. {furn, p, e}.
func _rattle_rig(tree: SceneTree, h_tiles: int, side := -1, walker_dx := 60.0) -> Dictionary:
	var furn := _tall(h_tiles)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - h_tiles * 16))
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X + side * walker_dx, PERCH_FLOOR), 0.0)
	e.sight_override = 1
	e._enter_chase(9999)
	return {furn = furn, p = p, e = e}


class RattleLog:
	var started := 0
	var ended: Array = []
	var noises := 0
	var source: Node
	func on_start() -> void: started += 1
	func on_end(shaken: bool) -> void: ended.append(shaken)
	func on_noise(_at: Vector2, _r: float, _l: float, src: Node) -> void:
		if src == source: noises += 1


func _rlog(e: CharacterBody2D) -> RattleLog:
	var l := RattleLog.new()
	l.source = e
	e.rattle_started.connect(l.on_start)
	e.rattle_ended.connect(l.on_end)
	NoiseBus.noise.connect(l.on_noise)
	return l


## Frames from "he is out of reach beside the piece" to RATTLE.
func _frames_to_rattle(tree: SceneTree, e: CharacterBody2D, p: Node2D, max_frames := 420) -> Array:
	var blocked := -1
	for f in max_frames:
		await tree.physics_frame
		if blocked < 0 and e.rattle_blocked(p): blocked = f
		if e.state == e.State.RATTLE: return [blocked, f]
	return [blocked, -1]


func _rattle_start(tree: SceneTree) -> Variant:
	for h in [3, 4]:
		var rig: Dictionary = await _rattle_rig(tree, h)
		var e: CharacterBody2D = rig.e
		var r: Array = await _frames_to_rattle(tree, e, rig.p)
		if r[0] < 0 or r[1] < 0: return "%d-tile: never rattled (blocked %d, state %d)" % [h, r[0], e.state]
		var t: float = (r[1] - r[0]) / 60.0
		if t < 2.95 or t > 3.1: return "%d-tile: rattle %.3fs after he became unreachable, want 3.0" % [h, t]
		e.free(); rig.p.free(); rig.furn.free()
		await tree.process_frame
	# 2 tiles (32) but beyond a lowered reach_height: out of reach -> rattle too
	var rig2: Dictionary = await _rattle_rig(tree, 2)
	var e2: CharacterBody2D = rig2.e
	e2.perch_reach_height = 20.0
	var r2: Array = await _frames_to_rattle(tree, e2, rig2.p)
	if r2[1] < 0: return "2-tile piece with reach_height 20: never rattled"
	# a walker that CAN reach (2 tiles, walker under him) reaches, never rattles
	var furn := _furniture(2)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 32))
	for i in 3: await tree.physics_frame
	var e3 := _under_walker(furn)
	for f in 150:
		await tree.physics_frame
		if e3.state == e3.State.RATTLE: return "rattled a boy it can reach"
	return ""


func _rattle_floater(tree: SceneTree) -> Variant:
	var furn := _tall(3)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48))
	for i in 3: await tree.physics_frame
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	e.movement = &"float"
	var cs := CollisionShape2D.new(); var c := CircleShape2D.new(); c.radius = 14; cs.shape = c; e.add_child(cs)
	_holder.add_child(e); e.global_position = Vector2(PERCH_X - 60, PERCH_FLOOR - 40)
	e.side_scroll = true
	e.sight_override = 1
	e._enter_chase(9999)
	for f in 480:
		await tree.physics_frame
		if e.state == e.State.RATTLE: return "a floater rattled"
	if p.global_position.distance_to(e.global_position) > 300.0: return "floater test didn't engage"
	return ""


func _rattle_noise(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var log := _rlog(e)
	var other := _walker_feet(Vector2(PERCH_X + 450.0, PERCH_FLOOR), 0.0)   # calm, far, inside the radius
	other.sight_override = 0
	await tree.physics_frame
	if other.state != other.State.CALM: return "other walker not calm at start (%d)" % other.state
	for f in 420:
		await tree.physics_frame
		if not log.ended.is_empty(): break
	NoiseBus.noise.disconnect(log.on_noise)
	if log.ended.is_empty(): return "rattle never ended"
	if log.noises != 6: return "%d rattle noises in 3 s at one per 0.5 s loop, want 6" % log.noises
	if other.state != other.State.CHASE and other.state != other.State.SEARCH: return "a rattle noise did not pull the other walker (state %d)" % other.state
	return ""


func _rattle_cadence(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	e.rattle_noise_every = 1.0
	var log := _rlog(e)
	for f in 420:
		await tree.physics_frame
		if not log.ended.is_empty(): break
	NoiseBus.noise.disconnect(log.on_noise)
	if log.noises != 3: return "%d noises with rattle_noise_every 1.0 over 3 s, want 3" % log.noises
	return ""


## +3 s of rattling: the boy is shaken off onto the walker's side: lands on that floor, off the
## piece, not inside anything (optionally with a wall right behind the walker).
func _rattle_shake(tree: SceneTree, side: int, wall: bool) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3, side, 60.0)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	if wall:
		var w := StaticBody2D.new()
		w.collision_layer = PlayerStats.LAYER_WORLD
		w.collision_mask = 0
		var cs := CollisionShape2D.new(); var r := RectangleShape2D.new(); r.size = Vector2(16, 200); cs.shape = r
		w.add_child(cs)
		_holder.add_child(w)
		w.global_position = Vector2(PERCH_X + side * (60.0 + 14.0 + 30.0 + 8.0), PERCH_FLOOR - 100)   # a boy-wide gap behind the walker
	var log := _rlog(e)
	var shaken_frame := -1
	for f in 480:
		await tree.physics_frame
		if not log.ended.is_empty():
			shaken_frame = f
			break
	NoiseBus.noise.disconnect(log.on_noise)
	if shaken_frame < 0: return "never shaken off"
	if not log.ended[0]: return "rattle ended without a shake-off"
	for f in 150: await tree.physics_frame
	var feet := Enemy.body_feet(p)
	if absf(feet.y - PERCH_FLOOR) > 2.0: return "boy's feet at %s, want the floor %.0f (walker %s, wall %s)" % [feet, PERCH_FLOOR, e.global_position, wall]
	var edge := PERCH_X + side * 32.0
	if (feet.x - edge) * side < -1.0: return "boy at x %.1f is not on the walker's side (edge %.0f, side %d)" % [feet.x, edge, side]
	if (feet.x - edge) * side > 140.0: return "boy flew %.0f px from the edge" % absf(feet.x - edge)
	if p.test_move(p.global_transform, Vector2.ZERO): return "boy landed overlapping a solid"
	if p.is_shaken(): return "still shaken after landing"
	if absf(feet.y - PERCH_FLOOR) > 2.0 or not p._grounded(): return "boy didn't land"
	if e.state == e.State.RATTLE: return "walker still rattling after the shake"
	return ""


func _rattle_cancel_leave(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var vis: ColorRect = rig.furn.get_node("Vis")
	var base := vis.position.x
	var log := _rlog(e)
	var r: Array = await _frames_to_rattle(tree, e, p)
	if r[1] < 0: return "never rattled"
	for f in 40: await tree.physics_frame   # ~0.7 s in
	p.global_position = Vector2(PERCH_X + 120.0, PERCH_FLOOR - 1.0)   # off the far side, on the floor
	for f in 3: await tree.physics_frame
	NoiseBus.noise.disconnect(log.on_noise)
	if e.state == e.State.RATTLE: return "still rattling after the boy left"
	if log.ended != [false]: return "rattle_ended %s, want [false]" % [log.ended]
	if vis.position.x != base: return "furniture visual left displaced (%.1f vs %.1f)" % [vis.position.x, base]
	if e.rattle_wobble != 0.0 or e._rattle_clock != 0.0 or e._rattle_noise_n != 0: return "clock/wobble not reset"
	# a brief hop keeps the progress (QA #49 camping): back at once -> rattling again quickly
	p.global_position = Vector2(PERCH_X, PERCH_FLOOR - 50.0)
	var r2: Array = await _frames_to_rattle(tree, e, p)
	if r2[1] < 0: return "never rattled again"
	var t: float = (r2[1] - maxi(r2[0], 0)) / 60.0
	if t > 1.0: return "second rattle came %.2fs after he was back, want it resumed (grace)" % t
	return ""


func _rattle_cancel_stun(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var vis: ColorRect = rig.furn.get_node("Vis")
	var base := vis.position.x
	var log := _rlog(e)
	var r: Array = await _frames_to_rattle(tree, e, p)
	if r[1] < 0: return "never rattled"
	for f in 30: await tree.physics_frame
	e.on_hit_by_throw({})
	await tree.physics_frame
	if e.state != e.State.STUNNED: return "state %d after a throw, want STUNNED" % e.state
	if log.ended != [false]: return "stun: rattle_ended %s, want [false]" % [log.ended]
	if vis.position.x != base or e.rattle_wobble != 0.0: return "stun left the furniture wobbled"
	# back to the hunt after the stun: the 3 s count starts over
	var f0 := -1
	for f in 480:
		await tree.physics_frame
		if f0 < 0 and (e.state == e.State.CHASE or e.state == e.State.SEARCH): f0 = f
		if e.state == e.State.RATTLE:
			var t: float = (f - f0) / 60.0
			if f0 < 0 or t < 2.9: return "rattled %.2fs after the stun ended, want 3 s" % t
			# any other state change cancels too
			e._set_state(e.State.RETURN)
			await tree.physics_frame
			NoiseBus.noise.disconnect(log.on_noise)
			if log.ended != [false, false]: return "state change: rattle_ended %s" % [log.ended]
			return ""
	return "never rattled after the stun"


func _rattle_wobble_test(tree: SceneTree) -> Variant:
	var steps: Array = AnimLibrary.meta("puppet_rattle").get("furniture_wobble_px", [])
	if steps.size() != 6: return "manifest furniture_wobble_px is %s" % [steps]
	for side in [-1, 1]:
		var rig: Dictionary = await _rattle_rig(tree, 3, side)
		var e: CharacterBody2D = rig.e
		var p: CharacterBody2D = rig.p
		var furn: StaticBody2D = rig.furn
		var vis: ColorRect = furn.get_node("Vis")
		var spr: AnimatedSprite2D = e.get_node("Anim")
		var vbase := vis.position.x
		var bspr: AnimatedSprite2D = p._anim
		var bbase := bspr.position.x
		var fpos := furn.global_position
		var shape_pos := (furn.get_child(0) as CollisionShape2D).global_position
		var r: Array = await _frames_to_rattle(tree, e, p)
		if r[1] < 0: return "side %d: never rattled" % side
		var ppos := p.global_position
		var seen := {}
		for f in 40:
			await tree.physics_frame
			if e.state != e.State.RATTLE: break
			var idx: int = e._rattle_frame()
			var want := float(steps[idx]) * (-1.0 if spr.flip_h else 1.0)
			seen[idx] = true
			if e.rattle_wobble != want: return "side %d frame %d: wobble %.1f, want %.1f (flip %s)" % [side, idx, e.rattle_wobble, want, spr.flip_h]
			if absf(vis.position.x - (vbase + want)) > 1e-4: return "furniture visual off by %.2f" % (vis.position.x - vbase - want)
			if absf(bspr.position.x - (bbase + want)) > 1e-4: return "boy sprite off by %.2f" % (bspr.position.x - bbase - want)
			if furn.global_position != fpos or (furn.get_child(0) as CollisionShape2D).global_position != shape_pos: return "furniture collision moved"
			if p.global_position != ppos: return "boy body moved during the rattle"
		if seen.size() != 6: return "side %d: only frames %s seen" % [side, seen.keys()]
		if spr.flip_h != (side > 0): return "side %d: flip_h %s (walker on the right faces left)" % [side, spr.flip_h]
		e.free(); p.free(); furn.free()
		await tree.process_frame
	return ""


func _rattle_vfx(tree: SceneTree) -> Variant:
	if not AnimLibrary.has_slot("vfx_rattle"): return ""   # art not on this branch
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var r: Array = await _frames_to_rattle(tree, e, rig.p)
	if r[1] < 0: return "never rattled"
	await tree.physics_frame
	var v: AnimatedSprite2D = e.get_parent().get_node_or_null("VfxRattle")
	if v == null: return "no vfx_rattle while rattling"
	var top := Vector2(PERCH_X, PERCH_FLOOR - 48)
	if v.global_position.distance_to(top) > 1.5: return "vfx at %s, want the furniture top %s" % [v.global_position, top]
	if not v.is_playing() or not v.sprite_frames.get_animation_loop("vfx_rattle"): return "vfx not looping"
	e.on_hit_by_throw({})
	for f in 3: await tree.physics_frame
	if is_instance_valid(v) and not v.is_queued_for_deletion(): return "vfx_rattle not freed when the rattle ended"
	return ""


## QA: a boy wobbling +-7 px around a standing walker flipped it every frame (600 flips / 10 s).
func _face_hysteresis(tree: SceneTree) -> Variant:
	_slab(0, 900, 200)
	var e := _walker_feet(Vector2(450, 200), 0.0)
	var p := _boy(Vector2(450, 188), true)
	e.sight_override = 1
	e._enter_chase(9999)
	e.stun_time = 1000.0
	e.on_hit_by_throw({})   # stands still (STUNNED) while the facing rule still follows the boy
	var spr: AnimatedSprite2D = e.get_node("Anim")
	p.global_position = Vector2(400, 188)
	for i in 6: await tree.physics_frame
	var base_flip := spr.flip_h
	var flips: Array[int] = []
	var last := spr.flip_h
	for f in 600:
		p.global_position.x = e.global_position.x + (7.0 if f % 2 == 0 else -7.0)
		await tree.physics_frame
		if spr.flip_h != last: flips.append(f)
		last = spr.flip_h
	for i in range(1, flips.size()):
		if flips[i] - flips[i - 1] < 12: return "flipped twice within %d frames (min hold 0.2 s)" % (flips[i] - flips[i - 1])
	if flips.size() > 2: return "%d flips in 10 s wobbling +-7 px" % flips.size()
	# a real reversal still turns it, within a moment
	p.global_position.x = e.global_position.x + (140.0 if not spr.flip_h else -140.0)
	var turned := -1
	var was := spr.flip_h
	for f in 30:
		await tree.physics_frame
		if spr.flip_h != was:
			turned = f
			break
	if turned < 0: return "never turned to a boy 140 px on the other side"
	if turned > 15: return "turned after %d frames" % turned
	return ""


## QA: contact on a stair must hurt. _boy_off_perch (hopped off a perch, no contact hit while
## he's in the air) clears on stair entry and on landing.
func _stair_immunity(tree: SceneTree) -> Variant:
	var furn := _furniture(2)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 32))
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X - 300.0, PERCH_FLOOR), 0.0)
	for i in 3: await tree.physics_frame
	if not e._boy_off_perch: return "not marked perched while he stands on the piece"
	# airborne after the hop: still marked, so a touching walker doesn't hit him
	p.floor_override = 0
	p.global_position = e.global_position + Vector2(0, -18)
	p.velocity = Vector2.ZERO
	e.sight_override = 1
	e._enter_chase(9999)
	var hp := PlayerStats.health
	for i in 4: await tree.physics_frame
	if PlayerStats.health != hp or not e._boy_off_perch: return "airborne after the hop must keep the no-hit mark (hp %d, mark %s)" % [PlayerStats.health, e._boy_off_perch]
	# onto a stair: mark cleared, contact hits
	var st := _stair(Vector2(PERCH_X - 340.0, PERCH_FLOOR), Vector2(PERCH_X - 340.0, PERCH_FLOOR - 100.0))
	p.stair = st
	for i in 6: await tree.physics_frame
	if e._boy_off_perch: return "mark survived stair entry"
	if PlayerStats.health >= hp: return "contact on a stair did no damage (hp %d)" % PlayerStats.health
	# landing: mark cleared too
	p.stair = null
	p.floor_override = 1
	p.global_position.y = PERCH_FLOOR   # down on the floor (feet origin)
	p.velocity = Vector2.ZERO
	e._boy_off_perch = true
	for i in 3: await tree.physics_frame
	if e._boy_off_perch: return "mark survived landing on a floor (h %.1f, grounded %s, boy %s walker %s state %d)" % [e.perch_height(p), p._grounded(), p.global_position, e.global_position, e.state]
	return ""


## QA: the wobble is in the walker's facing frame (multiplied by its facing sign), so the offset
## between the claws and the furniture is the same flipped or not (raw screen-space wobble missed
## by 1-2 px on frames 0/2/4). Claw = walker feet x; offset measured toward its facing, per frame.
func _rattle_relative_offset(tree: SceneTree) -> Variant:
	var rel := {-1: {}, 1: {}}
	for side in [-1, 1]:
		var rig: Dictionary = await _rattle_rig(tree, 3, side)
		var e: CharacterBody2D = rig.e
		var vis: ColorRect = rig.furn.get_node("Vis")
		var spr: AnimatedSprite2D = e.get_node("Anim")
		var vbase := vis.position.x
		var r: Array = await _frames_to_rattle(tree, e, rig.p)
		if r[1] < 0: return "side %d: never rattled" % side
		var facing := -1.0 if spr.flip_h else 1.0
		var furn: StaticBody2D = rig.furn
		var gap0: float = (furn.global_position.x - e.global_position.x) * facing   # unwobbled, toward the walker's facing
		for f in 40:
			await tree.physics_frame
			if e.state != e.State.RATTLE: break
			var idx: int = e._rattle_frame()
			var gap: float = (vis.position.x - vbase + furn.global_position.x - e.global_position.x) * facing
			rel[side][idx] = snappedf(gap - gap0, 0.001)
		e.free(); rig.p.free(); rig.furn.free()
		await tree.process_frame
	if rel[-1].size() != 6 or rel[1].size() != 6: return "not all 6 frames seen (%s / %s)" % [rel[-1].keys(), rel[1].keys()]
	for idx in rel[-1]:
		if rel[-1][idx] != rel[1][idx]: return "frame %d: claw-to-furniture offset %.2f unflipped vs %.2f flipped" % [idx, rel[-1][idx], rel[1][idx]]
	return ""


# --- QA #49 fixes: camping, far-half, wedge, grace ---------------------------------------
## Boy on the piece for `top_s`, then dropped to the far floor for `off_s`, repeatedly (teleports,
## as QA's p_cycle): the walker (200 px away at first) must rattle and shake him off.
func _rattle_camp_cycle(tree: SceneTree) -> Variant:
	for pat in [[1.5, 1.0], [2.0, 1.5], [3.2, 0.8], [1.5, 2.0]]:
		var rig: Dictionary = await _rattle_rig(tree, 3, -1, 232.0)
		var e: CharacterBody2D = rig.e
		var p: CharacterBody2D = rig.p
		var log := _rlog(e)
		var cyc := 0
		var shaken_at := -1.0
		var t := 0.0
		var phase_left: float = pat[0]
		var on_top := true
		while t < 40.0 and shaken_at < 0.0:
			for i in 6: await tree.physics_frame
			t += 0.1
			phase_left -= 0.1
			if not log.ended.is_empty() and log.ended[-1]: shaken_at = t
			elif phase_left <= 0.0:
				on_top = not on_top
				phase_left = pat[0] if on_top else pat[1]
				if on_top:
					p.global_position = Vector2(PERCH_X, PERCH_FLOOR - 50.0)
				else:
					p.global_position = Vector2(PERCH_X + 70.0, PERCH_FLOOR - 1.0)   # far side, on the floor
				p.velocity = Vector2.ZERO
				cyc += 1
		NoiseBus.noise.disconnect(log.on_noise)
		if log.started == 0: return "pattern %s: never rattled in %.0fs (%d cycles)" % [pat, t, cyc]
		if shaken_at < 0.0: return "pattern %s: rattled %d times but never shaken off in 40s" % [pat, log.started]
		e.free(); rig.p.free(); rig.furn.free()
		await tree.process_frame
	return ""


## The brief hop keeps progress for RATTLE_RESUME_TIME; a stun / hit still resets everything.
func _rattle_grace_resume(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var r: Array = await _frames_to_rattle(tree, e, p)
	if r[1] < 0: return "never rattled"
	for f in 60: await tree.physics_frame   # 1 s in: 2 s left
	p.global_position = Vector2(PERCH_X + 120.0, PERCH_FLOOR - 1.0)
	for f in 3: await tree.physics_frame
	if e.state == e.State.RATTLE: return "still rattling"
	if absf(e._rattle_saved_left - 2.0) > 0.1: return "saved %.2fs of the rattle, want ~2" % e._rattle_saved_left
	if e._rattle_unreach < e.rattle_wait - 0.1: return "unreach count wiped (%.2f)" % e._rattle_unreach
	# decays slowly while he is away, never snaps to 0
	for f in 60: await tree.physics_frame
	if e._rattle_unreach < 1.5 or e._rattle_unreach > e.rattle_wait: return "off 1 s: unreach %.2f, want slow decay from 3" % e._rattle_unreach
	# gone for good: the grace lapses and the count drains
	for f in 600: await tree.physics_frame
	if e._rattle_resume_left > 0.0 or e._rattle_unreach > 0.01: return "grace/decay never ran out (%.2f)" % e._rattle_unreach
	# a stun in the grace window clears it
	p.global_position = Vector2(PERCH_X, PERCH_FLOOR - 50.0)
	var r2: Array = await _frames_to_rattle(tree, e, p)
	if r2[1] < 0: return "never rattled the second time"
	p.global_position = Vector2(PERCH_X + 120.0, PERCH_FLOOR - 1.0)
	for f in 3: await tree.physics_frame
	if e._rattle_resume_left <= 0.0: return "no grace after the hop"
	e.stun(1.0) if e.has_method(&"stun") else e._set_state(e.State.STUNNED)
	await tree.physics_frame
	if e._rattle_resume_left > 0.0 or e._rattle_unreach > 0.0: return "stun left rattle progress behind"
	return ""


## Walker 200 px from the piece on either side: straight to the base, rattle ~3 s after arriving.
func _rattle_far_walker(tree: SceneTree) -> Variant:
	for side in [-1, 1]:
		for h in [3, 4]:
			var rig: Dictionary = await _rattle_rig(tree, h, side, 232.0)
			var e: CharacterBody2D = rig.e
			var r: Array = await _frames_to_rattle(tree, e, rig.p, 600)
			if r[1] < 0: return "side %d h%d: never rattled (state %d at x %.0f)" % [side, h, e.state, e.global_position.x]
			if absf(e.global_position.x - PERCH_X) > 32.0 + 40.0 + 1.0: return "side %d h%d: rattling %.0f from the piece" % [side, h, absf(e.global_position.x - PERCH_X)]
			e.free(); rig.p.free(); rig.furn.free()
			await tree.process_frame
	return ""


## QA's far-half repros on real #13 levels (stage 2 seeds 0/2/3), walker 200 px out, both sides:
## rattle by ~3.5 s after the walker could arrive.
func _rattle_real_levels(tree: SceneTree) -> Variant:
	# QA repros (seed, stage, floor, x, w, h) - used while the generated layout still has that piece
	# (a generator change reshuffles layouts) - plus the two tallest pieces of a few seeds, so
	# the check keeps covering real layouts either way.
	var cases: Array = []
	for c in [[0, 2, 1, 122, 2, 4], [2, 2, 1, 148, 2, 3], [3, 2, 0, 201, 3, 3]]:
		if _layout_has_piece(int(c[0]), int(c[1]), c):
			cases.append(c)
	for sd in [0, 2, 3, 5]:
		var L: Dictionary = LevelGenerator.generate(sd, 2)
		var pieces: Array = []
		for fu in L.get("furniture", []):
			if int(fu.h) >= 3:
				pieces.append(fu)
		pieces.sort_custom(func(a, b): return int(a.h) > int(b.h) or (int(a.h) == int(b.h) and int(a.x) < int(b.x)))
		for k in mini(2, pieces.size()):
			var fu: Dictionary = pieces[k]
			cases.append([sd, 2, int(fu.floor), int(fu.x), int(fu.w), int(fu.h)])
	if cases.is_empty(): return "no real-level piece to test"
	var ran := 0
	for c in cases:
		for side in [-1, 1]:
			var r: Variant = await _real_level_case(tree, c, side)
			if r is String and not (r as String).is_empty():
				return "seed %d stage %d f%d x%d side %d: %s" % [c[0], c[1], c[2], c[3], side, r]
			if r is bool and r: ran += 1
	if ran < 4: return "only %d real-level cases had a valid walker spawn" % ran
	return ""


func _layout_has_piece(seed_: int, stage: int, c: Array) -> bool:
	var L: Dictionary = LevelGenerator.generate(seed_, stage)
	for fu in L.get("furniture", []):
		if int(fu.floor) == int(c[2]) and int(fu.x) == int(c[3]) and int(fu.w) == int(c[4]) and int(fu.h) == int(c[5]):
			return true
	return false


func _real_level_case(tree: SceneTree, c: Array, side: int) -> Variant:
	PlayerStats.reset(); GameState.reset(); FESignals.reset()
	var world := Node2D.new()
	_holder.add_child(world)
	var L: Dictionary = LevelGenerator.generate(int(c[0]), int(c[1]))
	var b := LevelGenerator.build(L, world)
	if b.is_empty():
		return "no level"
	var walker: CharacterBody2D = null
	for en in b.enemies:
		if walker == null and StringName(en.get("movement")) != &"float":
			walker = en
		else:
			en.get_parent().remove_child(en); en.queue_free()
	if walker == null:
		return "no walker"
	var fl := int(c[2])
	var floor_y := float(LevelValidator.surface_y(fl))
	var cx := (float(c[3]) + float(c[4]) * 0.5) * 16.0
	var half := float(c[4]) * 8.0
	var top := floor_y - int(c[5]) * 16.0
	var p: CharacterBody2D = b.player
	p.global_position = Vector2(cx, top - 2.0)
	walker.global_position = Vector2(cx + side * (half + 200.0), floor_y) - Vector2(0, float(walker.call("_foot")))
	walker.velocity = Vector2.ZERO
	for i in 12: await tree.physics_frame
	# A spawn spot over a floor hole (stair cutout / level edge) is not a case: the walker would fall.
	if not (walker.is_on_floor() and absf(Enemy.body_feet(walker).y - floor_y) < 3.0):
		world.queue_free()
		await tree.process_frame
		return false
	# A wall / stair hole / tall piece between them means a stair detour, not this case.
	if LevelNav.current != null and LevelNav.current.node_for(Enemy.body_feet(p)) != LevelNav.current.node_for(Enemy.body_feet(walker)):
		world.queue_free()
		await tree.process_frame
		return false
	walker.call("_enter_chase", 9999.0)
	var got := -1
	for f in 900:
		await tree.physics_frame
		if walker.state == walker.State.RATTLE:
			got = f
			break
	var base_frames := int((200.0 - 40.0) / walker.chase_speed * 60.0)   # frames to walk up to the piece
	var err := ""
	if got < 0:
		err = "never rattled in 15 s (walker %s state %d)" % [walker.global_position, walker.state]
	elif got > base_frames + int(3.5 * 60.0) + 30:
		err = "rattled after %.1f s (walk %.1f s + 3 s expected)" % [got / 60.0, base_frames / 60.0]
	world.queue_free()
	await tree.process_frame
	return err if not err.is_empty() else true


## Synthetic wedge (QA p_wedge): 48x48 piece, wall `gap` px from its edge, walker mid-gap.
func _wedge_rig(tree: SceneTree, gap: float, walls_both := false) -> Dictionary:
	var furn := _tall(3)
	var side := -1
	var wall_x := PERCH_X + side * (32.0 + gap + 8.0)
	var walls: Array = []
	for sd in ([-1, 1] if walls_both else [-1]):
		var w := StaticBody2D.new()
		w.collision_layer = PlayerStats.LAYER_WORLD
		w.collision_mask = 0
		var cs := CollisionShape2D.new(); var r := RectangleShape2D.new(); r.size = Vector2(16, 200); cs.shape = r
		w.add_child(cs)
		_holder.add_child(w)
		w.global_position = Vector2(PERCH_X + sd * (32.0 + gap + 8.0), PERCH_FLOOR - 100)
		walls.append(w)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48.0))
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X + side * (32.0 + gap * 0.5), PERCH_FLOOR), 0.0)
	e.sight_override = 1
	e._enter_chase(9999)
	return {furn = furn, p = p, e = e, walls = walls, wall_x = wall_x}


func _rattle_wedge_far_side(tree: SceneTree) -> Variant:
	for gap in [48.0, 56.0, 60.0, 68.0]:
		var rig: Dictionary = await _wedge_rig(tree, gap)
		var e: CharacterBody2D = rig.e
		var p: CharacterBody2D = rig.p
		var log := _rlog(e)
		var dirs := []
		p.shaken_off.connect(func(d: float) -> void: dirs.append(d))
		for f in 700:
			await tree.physics_frame
			if not dirs.is_empty(): break
		if dirs.is_empty(): return "gap %.0f: never shaken" % gap
		for f in 240: await tree.physics_frame
		NoiseBus.noise.disconnect(log.on_noise)
		var feet := Enemy.body_feet(p)
		if gap <= 60.0 and dirs[0] != 1.0: return "gap %.0f: shaken toward the blocked wedge side (%s)" % [gap, dirs[0]]
		if absf(feet.y - PERCH_FLOOR) > 2.0 or not p._grounded() or p.is_shaken(): return "gap %.0f: boy not on the floor after the shake (feet %s, shaken %s, air %s)" % [gap, feet, p.is_shaken(), not p._grounded()]
		if e._boy_off_perch: return "gap %.0f: immunity flag left set on the floor" % gap
		if p.test_move(p.global_transform, Vector2.ZERO): return "gap %.0f: boy landed inside a solid" % gap
		e.free(); p.free(); rig.furn.free()
		for w in rig.walls: w.free()
		await tree.process_frame
	return ""


## Neither side has a free landing: he stays rattling (noise every loop), is never cancelled and
## left safe on top; open a side and he is shaken to it.
func _rattle_no_landing(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _wedge_rig(tree, 48.0, true)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	# the far side is walled too, with a 20 px gap
	var log := _rlog(e)
	var dirs := []
	p.shaken_off.connect(func(d: float) -> void: dirs.append(d))
	# make the far side unusable: a second walker body parked in the far gap
	var blocker := _walker_feet(Vector2(PERCH_X + 32.0 + 24.0, PERCH_FLOOR), 0.0)
	blocker.add_collision_exception_with(e)
	for f in 60 * 9: await tree.physics_frame   # well past 3 s wait + 3 s rattle
	if e.state != e.State.RATTLE: return "walker left RATTLE (state %d) with no free landing" % e.state
	if not dirs.is_empty(): return "boy shaken into a blocked space"
	if not log.ended.is_empty(): return "rattle_ended fired (%s) with no free landing" % [log.ended]
	if log.noises < 8: return "only %d noises in 9 s: it must keep rattling every loop" % log.noises
	var feet := Enemy.body_feet(p)
	if absf(feet.y - (PERCH_FLOOR - 48.0)) > 2.0: return "boy left the piece top"
	# a spot opens: far blocker walks away
	blocker.free()
	rig.walls[1].free()
	for f in 60: await tree.physics_frame
	NoiseBus.noise.disconnect(log.on_noise)
	if dirs.is_empty(): return "boy not shaken once a spot opened"
	if dirs[0] != 1.0: return "shaken toward %s, want the open far side" % dirs[0]
	return ""


## A low piece (own WORLD body, bottom on the floor) x0..x1, h px tall.
func _low_piece(x0: float, x1: float, h: float) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = PlayerStats.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape2D.new(); var r := RectangleShape2D.new(); r.size = Vector2(x1 - x0, h); cs.shape = r
	b.add_child(cs)
	_holder.add_child(b); b.global_position = Vector2((x0 + x1) * 0.5, PERCH_FLOOR - h * 0.5)
	return b


## QA repro (seed 0 stage 1 f2 x171 w3 h3): walkers pass through LowFurniture, so one stands INSIDE
## the 3-tall piece's footprint; the old near-side landing was measured from its position (inside
## the piece) and a 1-tile step beside the far edge blocked the far side -> no free side, rattled
## forever. Landing is now measured from the outer edge of the whole cluster.
func _cluster_rig(tree: SceneTree, step_far := true, step_near := false) -> Dictionary:
	var furn := _tall(3)   # x 280..344, 48 tall
	var steps: Array = []
	if step_far: steps.append(_low_piece(344.0, 376.0, 16.0))
	if step_near: steps.append(_low_piece(248.0, 280.0, 16.0))
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48.0))
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X - 18.0, PERCH_FLOOR), 0.0)   # inside the footprint
	e.add_collision_exception_with(furn)
	for st in steps: e.add_collision_exception_with(st)
	e.sight_override = 1
	return {furn = furn, steps = steps, p = p, e = e}


## A solid box (world layer) x0..x1, y0..y1 (absolute).
func _box_at(x0: float, x1: float, y0: float, y1: float) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = PlayerStats.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape2D.new(); var r := RectangleShape2D.new(); r.size = Vector2(x1 - x0, y1 - y0); cs.shape = r
	b.add_child(cs)
	_holder.add_child(b); b.global_position = Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	return b


func _rattle_cluster_landing(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _cluster_rig(tree, true, false)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	e._rattle_piece = e._find_piece(p)
	if e._rattle_piece.is_empty(): return "no piece under the boy"
	# direct: both sides are free floor once measured from the cluster edge (376 / 280), not the walker
	if not e._landing_free(p, -1.0, true): return "near side not free with the walker inside the footprint"
	if not e._landing_free(p, 1.0, false): return "far side not free past the 1-tile step"
	var ce: Dictionary = e._cluster_edge(e._rattle_piece.rect, 1.0)
	if absf(float(ce.edge) - 376.0) > 0.5: return "cluster edge %.1f, want 376 (piece + step)" % float(ce.edge)
	# PD order: no near step, so the far STEP top (a 1-tile piece the reach catches), not the floor
	var plan: Dictionary = e._plan_landing(p, -1.0)
	if plan.is_empty() or not plan.step or plan.dir != 1.0: return "plan %s, want the far step top" % [plan]
	if absf(float(plan.y) - (PERCH_FLOOR - 16.0)) > 0.5: return "step top y %.1f" % float(plan.y)
	# full flow: the walker chases, rattles, and the boy is shaken off onto the step top
	var dirs := []
	p.shaken_off.connect(func(d: float) -> void: dirs.append(d))
	e._enter_chase(9999)
	for f in 60 * 9:
		await tree.physics_frame
		if not dirs.is_empty():
			break
	if dirs.is_empty(): return "never shaken off in 9 s (state %d)" % e.state
	for f in 120:   # until control returns
		await tree.physics_frame
		if not p.is_shaken(): break
	var feet := Enemy.body_feet(p)
	if absf(feet.y - (PERCH_FLOOR - 16.0)) > 2.5: return "boy not on the step top (feet y %.1f)" % feet.y
	if feet.x < 344.0 or feet.x > 376.0: return "boy at x %.1f, want on the step 344..376" % feet.x
	if p.is_shaken(): return "input lock still on after landing"
	return ""


func _rattle_cluster_blocked(tree: SceneTree) -> Variant:
	# step top roofed over, walls just past the step and just past the near edge: no spot at all
	var rig: Dictionary = await _cluster_rig(tree, true, false)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var wall := _low_piece(376.0, 392.0, 200.0)
	var wall2 := _low_piece(216.0, 264.0, 200.0)   # 16 px off the near edge: no boy-wide gap
	var roof := _box_at(344.0, 376.0, PERCH_FLOOR - 40.0, PERCH_FLOOR - 28.0)   # over the step top
	if wall2 == null or roof == null: return "rig"
	var log := _rlog(e)
	var dirs := []
	p.shaken_off.connect(func(d: float) -> void: dirs.append(d))
	e._enter_chase(9999)
	for f in 60 * 9: await tree.physics_frame
	if e.state != e.State.RATTLE: return "walker left RATTLE (state %d) with no free spot" % e.state
	if not dirs.is_empty(): return "shaken into a blocked space"
	if not log.ended.is_empty(): return "rattle_ended fired with no free spot"
	if log.noises < 6: return "only %d noises: it must keep rattling" % log.noises
	if absf(Enemy.body_feet(p).y - (PERCH_FLOOR - 48.0)) > 2.0: return "boy left the piece top"
	wall.free()   # floor past the step opens: rule 3
	for f in 60: await tree.physics_frame
	NoiseBus.noise.disconnect(log.on_noise)
	if dirs.is_empty(): return "not shaken once a spot opened"
	for f in 120: await tree.physics_frame
	if absf(Enemy.body_feet(p).y - PERCH_FLOOR) > 2.5: return "boy not on the floor after rule 3 (feet y %.1f)" % Enemy.body_feet(p).y
	return ""


## Until the first shake-off, then until control returns. Returns {shaken, feet, frames}.
func _shake_outcome(tree: SceneTree, e: CharacterBody2D, p: CharacterBody2D, max_s := 9) -> Dictionary:
	var dirs := []
	p.shaken_off.connect(func(d: float) -> void: dirs.append(d))
	e._enter_chase(9999)
	for f in 60 * max_s:
		await tree.physics_frame
		if not dirs.is_empty():
			break
	var out := {shaken = not dirs.is_empty(), feet = Vector2.ZERO, dir = 0.0 if dirs.is_empty() else dirs[0]}
	if dirs.is_empty():
		return out
	for f in 150:
		await tree.physics_frame
		if not p.is_shaken(): break
	for f in 3: await tree.physics_frame
	out.feet = Enemy.body_feet(p)
	return out


func _rattle_step_rule(tree: SceneTree, mode: String) -> Variant:
	var rig: Dictionary = await _cluster_rig(tree, false, false)   # tall 280..344, walker at 294 inside
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var near := _low_piece(248.0, 280.0, 32.0 if mode == "uncatchable" else 16.0)
	var far_h := 48.0 if mode == "tall_neighbour" else (32.0 if mode == "uncatchable" else 16.0)
	var far := _low_piece(344.0, 408.0 if mode == "tall_neighbour" else 376.0, far_h)
	if mode == "tall_neighbour":
		near.free(); near = null
	e.add_collision_exception_with(far)
	if near != null: e.add_collision_exception_with(near)
	if mode == "far":
		_box_at(248.0, 280.0, PERCH_FLOOR - 52.0, PERCH_FLOOR - 40.0)   # roofs the near step top
	if mode == "uncatchable":
		e.perch_reach_height = 24.0   # a 2-tile step is out of this walker's reach
	var log := _rlog(e)
	var rs := [-1]
	var reach := [-1]
	var caught := [-1]
	var base := [-1]
	e.reach_started.connect(func() -> void: if reach[0] < 0: reach[0] = Engine.get_physics_frames())
	e.reach_ended.connect(func(c: bool) -> void: if c and caught[0] < 0: caught[0] = Engine.get_physics_frames())
	var o: Dictionary = await _shake_outcome(tree, e, p)
	base[0] = Engine.get_physics_frames()
	if mode == "reach":
		for f in 120:
			await tree.physics_frame
			if caught[0] >= 0: break
	NoiseBus.noise.disconnect(log.on_noise)
	if not o.shaken: return "never shaken off"
	var feet: Vector2 = o.feet
	if p.is_shaken(): return "control not returned"
	match mode:
		"ours", "reach":
			if absf(feet.y - (PERCH_FLOOR - 16.0)) > 2.5 or feet.x < 248.0 or feet.x > 280.0:
				return "%s: want the walker's (near) step top x 248..280 y 384, got %s" % [mode, feet]
		"far":
			if absf(feet.y - (PERCH_FLOOR - 16.0)) > 2.5 or feet.x < 344.0 or feet.x > 376.0:
				return "far: want the far step top x 344..376 y 384, got %s" % [feet]
		"tall_neighbour":
			if absf(feet.y - PERCH_FLOOR) > 2.5 or (feet.x > 280.0 and feet.x < 408.0):
				return "tall neighbour: want the floor past the cluster (x < 280 or >= 408), got %s" % [feet]
		"uncatchable":
			if absf(feet.y - PERCH_FLOOR) > 2.5 or (feet.x > 248.0 and feet.x < 376.0):
				return "step beyond reach: want the floor past the cluster, got %s" % [feet]
	if mode == "reach":
		if reach[0] < 0: return "perch reach never started on the step"
		if caught[0] < 0: return "reach never landed on the step"
		var t := float(caught[0] - base[0]) / 60.0
		if t < 0.1 or t > 1.2: return "reach landed %.2f s after touchdown, want ~0.4-1.0" % t
	return ""


## Walker beside a 3-tall piece with a level wall (tall solid) behind / around it: the landing is
## the open side's floor, never the wall gap, never overlapping the walker or a solid.
func _rattle_level_wall(tree: SceneTree, mode: String) -> Variant:
	var furn := _tall(3)   # 280..344
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48.0))
	for i in 3: await tree.physics_frame
	var wall_x := 280.0 if mode == "flush" else 240.0   # wall right edge: flush, or a 40 px gap
	_box_at(wall_x - 40.0, wall_x, PERCH_FLOOR - 200.0, PERCH_FLOOR)
	var e := _walker_feet(Vector2(wall_x + 14.0 if mode == "gap" else PERCH_X - 18.0, PERCH_FLOOR), 0.0)
	e.add_collision_exception_with(furn)
	e.sight_override = 1
	var o: Dictionary = await _shake_outcome(tree, e, p)
	if not o.shaken: return "never shaken off (%s)" % mode
	var feet: Vector2 = o.feet
	if p.is_shaken() or absf(feet.y - PERCH_FLOOR) > 2.5: return "%s: not grounded on the floor, feet %s" % [mode, feet]
	if feet.x < 344.0: return "%s: landed on the wall side (x %.1f), want the open right side" % [mode, feet.x]
	if p.test_move(p.global_transform, Vector2.ZERO): return "%s: landed overlapping a solid" % mode
	if e._boy_on_enemy_head(p): return "%s: landed on an enemy body" % mode
	return ""


## Post-shake watchdog: a boy found resting on an enemy's head is moved to free floor, control back.
func _rattle_head_nudge(tree: SceneTree) -> Variant:
	var e := _walker_feet(Vector2(PERCH_X, PERCH_FLOOR), 0.0)
	e.sight_override = 0
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 28.0))   # feet on the walker's head
	_slab(0, 900, int(PERCH_FLOOR))
	p.set_physics_process(false)   # frozen there, as a soft-locked boy would be
	e._post_shake_t = 4.0
	for f in 3: await tree.physics_frame
	if not e._boy_on_enemy_head(p): return "setup: the boy is not resting on the walker (feet %s)" % [Enemy.body_feet(p)]
	for f in 60: await tree.physics_frame
	var feet := Enemy.body_feet(p)
	if absf(feet.y - PERCH_FLOOR) > 3.0: return "still off the floor after the nudge window (feet %s)" % [feet]
	if e._boy_on_enemy_head(p): return "still on the head"
	if absf(feet.x - e.global_position.x) < 14.0: return "overlapping the walker (boy x %.1f, walker %.1f)" % [feet.x, e.global_position.x]
	if p.test_move(p.global_transform, Vector2.ZERO): return "nudged into a solid"
	return ""


## The rattle vfx is a top_level sibling: freeing the walker mid-rattle must free it too.
func _rattle_vfx_orphan(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3)
	var e: CharacterBody2D = rig.e
	var parent := e.get_parent()
	if AnimLibrary.has_slot("vfx_rattle"):
		var r: Array = await _frames_to_rattle(tree, e, rig.p)
		if r[1] < 0: return "never rattled"
		await tree.physics_frame
		if parent.get_node_or_null("VfxRattle") == null: return "no vfx while rattling"
		e.free()   # mid-rattle (not through the state machine)
		await tree.physics_frame
		await tree.physics_frame
		if parent.get_node_or_null("VfxRattle") != null: return "VfxRattle orphaned after the walker was freed mid-rattle"
		return ""
	# art slot not on this branch: same ownership contract with a stand-in node
	var v := AnimatedSprite2D.new(); v.name = "VfxRattle"; v.top_level = true
	parent.add_child(v)
	e._rattle_vfx = v
	e.queue_free()
	for f in 3: await tree.physics_frame
	if is_instance_valid(v) and not v.is_queued_for_deletion(): return "stand-in VfxRattle orphaned after the walker was freed"
	return ""


func _rattle_watchdog(tree: SceneTree) -> Variant:
	var furn := _tall(3)
	var p := _perch_boy(Vector2(PERCH_X, PERCH_FLOOR - 48.0))
	for i in 3: await tree.physics_frame
	var e := _walker_feet(Vector2(PERCH_X - 60.0, PERCH_FLOOR), 0.0)
	e.sight_override = 1
	e._enter_chase(9999)
	# wedged mid-air: frozen, shaken and immune
	p.set_physics_process(false)
	p.floor_override = 0
	p.global_position += Vector2(0, -30)
	p.shake_off(-1.0)
	e._boy_off_perch = true
	for f in 15: await tree.physics_frame
	if not p.is_shaken() or not e._boy_off_perch: return "watchdog fired too early (0.25 s)"
	for f in 30: await tree.physics_frame
	if e._boy_off_perch: return "immunity still set after 0.75 s wedged"
	if p.is_shaken(): return "input lock still set after 0.75 s wedged"
	return ""


func _rattle_hit_grace(tree: SceneTree) -> Variant:
	var rig: Dictionary = await _rattle_rig(tree, 3, -1, 60.0)
	var e: CharacterBody2D = rig.e
	var p: CharacterBody2D = rig.p
	var land := -1
	var was_shaken := false
	var hp0 := PlayerStats.health
	var hit_at := -1
	for f in 900:
		await tree.physics_frame
		if p.is_shaken(): was_shaken = true
		elif was_shaken and land < 0: land = f
		if PlayerStats.health < hp0 and hit_at < 0: hit_at = f
		if hit_at >= 0: break
	if land < 0: return "never shaken and landed"
	if hit_at < 0: return "no hit after touchdown"
	if hit_at - land < int(e.shake_hit_grace * 60.0) - 2: return "hit %d frames after touchdown, want >= %d" % [hit_at - land, int(e.shake_hit_grace * 60.0)]
	if hit_at - land > 90: return "hit %d frames after touchdown: grace too long" % [hit_at - land]
	return ""


func _rattle_claw_offset(tree: SceneTree) -> Variant:
	for side in [-1, 1]:
		var rig: Dictionary = await _rattle_rig(tree, 3, side)
		var e: CharacterBody2D = rig.e
		var spr: AnimatedSprite2D = e.get("_spr")
		var x0 := spr.position.x
		var col0 := e.global_position
		var r: Array = await _frames_to_rattle(tree, e, rig.p)
		if r[1] < 0: return "never rattled"
		for f in 12: await tree.physics_frame
		var toward: int = -side   # the piece is on the opposite side of the walker's x
		var dx: float = (spr.position.x - x0) * toward
		if absf(dx - e.rattle_claw_px) > 0.01: return "side %d: sprite %.1f px toward the piece, want %.1f" % [side, dx, e.rattle_claw_px]
		if absf(e.global_position.x - col0.x) > 60.0: return "walker body moved"
		var cs: CollisionShape2D = e.get_node("Body")
		if absf(cs.position.x) > 0.01: return "collision shape displaced"
		e.free(); rig.p.free(); rig.furn.free()
		await tree.process_frame
	return ""

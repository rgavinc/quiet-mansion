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

extends RefCounted
## Enemy state machine, REAL physics (real frames, main.gd-sized colliders).
##  - after a hit the puppet backs off: no second hit within 1.5s, a standing boy
##    doesn't go 3 -> 0 from one puppet in under 4.5s (PD tuning note)
##  - side-scroll walker falls under gravity, stays on its slab, and climbs a Stair to
##    reach a boy on the next floor (QA #20); without a stair it can't reach him
##  - float type drifts straight through a slab to the next floor

var _holder: Node2D


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["hit_then_backoff_no_rehit_1_5s", _recover],
		["walker_gravity_and_stairs_to_next_floor", _walker_stairs],
		["walker_without_stairs_stays_on_floor", _walker_no_stairs],
		["float_crosses_floors_without_stairs", _floater],
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

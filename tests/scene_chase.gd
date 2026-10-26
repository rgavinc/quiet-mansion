extends RefCounted
## Real-physics walker chases across floors on generated levels (Lead, QA B1 / route gap).
## One case = one built level, one BE walker chasing a boy who stands still on the other end
## of a stair (up or down), the walker either at the far landing or directly above/below him
## ("aligned", QA's parked-under-the-boy case). Passes when the walker reaches the boy's floor
## and gets within REACH_PX of him before the route-length timeout. Cases run one at a time (enemies find the
## boy through the "player" group). Suite: run_async (a small fixed set incl. QA's repros);
## big matrix: tests/chase_sweep.gd (launcher, run with --fixed-fps 60).

const REACH_PX := 40.0
const SLACK_S := 10.0   # timeout = route length / chase_speed x 1.5 + this

## QA repro cases + a mix of stages / directions (kept small: the suite runs in real time).
const SUITE_CASES := [[1030, 2, 0, "up_aligned"], [1030, 2, 0, "down"], [11, 1, 0, "on_stair_lo"],
	[11, 1, 0, "on_stair_hi"], [1003, 3, 0, "down_aligned"], [11, 5, 0, "spawn"], [7, 4, 0, "up"]]


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var ran := 0
	for c in SUITE_CASES:
		var r: Dictionary = await run_case(tree, c[0], c[1], c[2], c[3])
		if r.get("skip", false):
			continue
		ran += 1
		if not r.ok:
			failures.append("chase %s: %s" % [str(c), r.why])
	for stg in [1, 5]:
		var frz: String = await stuck_check(tree, 11, stg)
		ran += 1
		if not frz.is_empty():
			failures.append("walkers frozen (QA B1, seed 11 stage %d): %s" % [stg, frz])
	return {"passed": ran - failures.size(), "total": ran, "failures": failures}


## QA B1 repro: every enemy of generate(11, 1) chasing (_enter_chase(9999)) for 600 frames:
## every walker that isn't on the boy already must move > 8px.
static func stuck_check(tree: SceneTree, seed_value: int, stage: int) -> String:
	PlayerStats.reset(); GameState.reset()
	var world := Node2D.new()
	tree.root.add_child(world)
	var b := LevelGenerator.build(LevelGenerator.generate(seed_value, stage), world)
	b.player.set_physics_process(false)
	await tree.physics_frame
	var start := {}
	for e in b.enemies:
		e.call("_enter_chase", 9999.0)
		start[e] = e.global_position
	for i in 600:
		await tree.physics_frame
		if GameState.game_over:
			break
	var frozen := []
	for e in b.enemies:
		if is_instance_valid(e) and StringName(e.get("movement")) != &"float" and e.global_position.distance_to(start[e]) <= 8.0:
			frozen.append(str(start[e]))
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset(); GameState.reset()
	return "" if frozen.is_empty() else "%d/%d walkers moved <= 8px: %s" % [frozen.size(), b.enemies.size(), ", ".join(frozen)]


## Case modes (one stair each): boy on the far landing of the other floor, walker at the near
## landing ("up"/"down") or directly under/over him ("up_aligned"/"down_aligned"); boy standing
## ON the stair line, walker on the lower / upper floor ("on_stair_lo"/"on_stair_hi"); and the
## level's own first walker at its real spawn, boy on this stair's landing on another floor
## ("spawn").
const MODES := ["up", "down", "up_aligned", "down_aligned", "on_stair_lo", "on_stair_hi", "spawn"]


## {ok, why, frames, skip}
static func run_case(tree: SceneTree, seed_value: int, stage: int, stair_i: int, mode: String) -> Dictionary:
	var L := LevelGenerator.generate(seed_value, stage)
	if stair_i >= L.stairs.size():
		return {skip = true}
	var s: Dictionary = L.stairs[stair_i]
	var d := signf(s.top.x - s.bottom.x)
	var segs: Dictionary = LevelValidator.floor_graph(L).segments
	var lo := int(s.from_floor)
	var hi := int(s.to_floor)
	var b: Vector2 = s.bottom
	var t: Vector2 = s.top
	var boy_at: Vector2
	var en_feet: Vector2
	match mode:
		"up", "up_aligned":
			boy_at = t + Vector2(d * 30.0, 0)
			en_feet = Vector2(boy_at.x if mode == "up_aligned" else b.x - d * 60.0, b.y)
		"down", "down_aligned":
			boy_at = b - Vector2(d * 30.0, 0)
			en_feet = Vector2(boy_at.x if mode == "down_aligned" else t.x + d * 60.0, t.y)
		"on_stair_lo":
			boy_at = b.lerp(t, 0.6)
			en_feet = Vector2(b.x - d * 120.0, b.y)
		"on_stair_hi":
			boy_at = b.lerp(t, 0.4)
			en_feet = Vector2(t.x + d * 90.0, t.y)
		"spawn":
			var sp := Vector2.INF
			for e in L.enemies:
				if StringName(e.movement) != &"float":
					sp = e.pos
					break
			if sp == Vector2.INF:
				return {skip = true}
			en_feet = sp
			var f := LevelValidator.floor_of(sp.y)
			boy_at = (t + Vector2(d * 30.0, 0)) if f != hi else (b - Vector2(d * 30.0, 0))
			if LevelValidator.floor_of(boy_at.y) == f:
				return {skip = true}
	var ef := LevelValidator.floor_of(en_feet.y)
	var hole := LevelValidator.stair_hole(s)
	if mode != "spawn" and (LevelValidator.node_at(segs, ef, en_feet.x) == "" or (ef == hi and en_feet.x > hole.x - 20.0 and en_feet.x < hole.y + 20.0)):
		return {skip = true}
	var nav := LevelNav.from_layout(L)
	if nav.next_waypoint(en_feet, boy_at).is_empty():
		return {skip = true}   # e.g. a gallery pocket between two openings: no way down by design
	return await run_at(tree, L, boy_at, en_feet, mode == "spawn")


## One chase on layout L: boy standing still at boy_at (feet), a BE walker with feet at en_feet.
static func run_at(tree: SceneTree, L: Dictionary, boy_at: Vector2, en_feet: Vector2, keep_spawn := false) -> Dictionary:
	PlayerStats.reset(); GameState.reset()
	var world := Node2D.new()
	tree.root.add_child(world)
	var b := LevelGenerator.build(L, world)
	var walker: CharacterBody2D = null
	for e in b.enemies:
		if walker == null and StringName(e.get("movement")) != &"float":
			walker = e
		else:
			e.get_parent().remove_child(e)   # out of the tree now: a queue_free'd enemy still gets
			e.queue_free()                    # one physics tick and can shove the boy off his spot
	if walker == null:
		world.queue_free()
		await tree.process_frame
		return {skip = true}
	var p: CharacterBody2D = b.player
	p.set_physics_process(false)
	p.global_position = boy_at
	if not keep_spawn:
		walker.global_position = en_feet - Vector2(0, float(walker.call("_foot")))
	walker.velocity = Vector2.ZERO
	# A few ticks so Area2D overlaps catch up with the teleports (the boy spawns at L.start; a
	# stale hitbox overlap would land a hit + 48px shove on the first chase frame).
	for i in 3:
		await tree.physics_frame
	walker.call("_enter_chase", 9999.0)
	var nav: LevelNav = b.nav
	var frames := 0
	var ok := false
	var timeout_s := route_len(nav, en_feet, boy_at) / maxf(float(walker.get("chase_speed")), 1.0) * 1.5 + SLACK_S
	var max_frames := int(timeout_s * 60.0)
	while frames < max_frames:
		await tree.physics_frame
		frames += 1
		if not is_instance_valid(walker) or GameState.game_over:
			break
		var feet: Vector2 = walker.global_position + Vector2(0, float(walker.call("_foot")))
		if nav.floor_of(feet) == nav.floor_of(boy_at) and absf(feet.x - boy_at.x) < REACH_PX and absf(feet.y - boy_at.y) < 8.0:
			ok = true
			break
	var why := ""
	if not ok:
		var at: Vector2 = walker.global_position if is_instance_valid(walker) else Vector2.INF
		why = "walker at %s (feet start %s) never reached boy %s in %.0fs (state %s, climbing %s, ledge_stopped %s)" % [
			at, en_feet, boy_at, timeout_s, walker.get("state") if is_instance_valid(walker) else -1,
			walker.get("climbing") if is_instance_valid(walker) else false, walker.get("ledge_stopped") if is_instance_valid(walker) else false]
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset(); GameState.reset()
	return {ok = ok, why = why, frames = frames, skip = false}


## Walking + climbing distance of LevelNav's route from a to b (px).
static func route_len(nav: LevelNav, a: Vector2, b: Vector2) -> float:
	var hops: Variant = nav.route(a, b)
	if hops == null:
		return 0.0
	var d := 0.0
	var cur := a
	for h in hops:
		d += absf(cur.x - (h.enter as Vector2).x) + (h.enter as Vector2).distance_to(h.exit)
		cur = h.exit
	return d + absf(cur.x - b.x)

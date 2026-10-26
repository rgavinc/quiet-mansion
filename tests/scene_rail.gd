extends RefCounted
## Scene-level, REAL physics (Lead, PRODUCT.md "Stair opening", QA-revised rail): on a built
## level with one stair rising right and one rising left (mirrored case):
##  (a) a boy-sized body (r 12, the boy's mask) and a walker (r 14, a walking Enemy's mask)
##      walking along the upper floor toward the opening's far edge, and the real boy jumping
##      at it, stay on the upper floor (the 64px rail wall); a floater (no WORLD mask) drifts
##      through; walking off the stair-top landing toward the opening is stopped by the near-edge
##      guard (LevelValidator.stair_rail_near) instead of dropping a floor.
##  (b') QA edge post: the boy on the stair just below x+9 (~61px up, t 0.38) spamming jump (52px
##      apex) under the slab / post bottom: not snagged, not knocked off the line, keeps climbing
##      to the top landing in the expected time.
##  (b) the real boy and a real BE walker climb the full stair up and down without being
##      blocked or snagged: they reach the other end within the expected time and stand there.

const WALK_FRAMES := 75
const SPEED := 140.0


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	PlayerStats.reset(); GameState.reset()
	var world := Node2D.new()
	tree.root.add_child(world)
	var L := _layout_with_both_directions()
	var built := LevelGenerator.build(L, world)
	for e in built.enemies:
		e.queue_free()
	await tree.physics_frame
	var picks := [L.stairs.filter(func(q): return q.top.x > q.bottom.x)[0], L.stairs.filter(func(q): return q.top.x < q.bottom.x)[0]]
	var checks := [["rail_blocks_walkers_and_boy_at_far_edge", _far_edge], ["boy_jumping_at_rail_cannot_fall_in", _boy_jump],
		["near_edge_stair_top_no_fall", _near_edge], ["boy_climbs_up_and_down_unsnagged", _boy_climb], ["boy_jumping_under_post_keeps_climbing", _boy_jump_on_stair], ["walker_climbs_up_and_down_unsnagged", _walker_climb]]
	for c in checks:
		for s in picks:
			var err: String = await c[1].call(tree, world, built, s)
			if not err.is_empty():
				failures.append("rail %s (%s stair x=%d): %s" % [c[0], "right" if s.top.x > s.bottom.x else "left", int(s.bottom.x), err])
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset(); GameState.reset()
	Engine.time_scale = 1.0
	return {"passed": checks.size() * 2 - failures.size(), "total": checks.size() * 2, "failures": failures}


func _layout_with_both_directions() -> Dictionary:
	for seed_value in 50:
		var L := LevelGenerator.generate(seed_value, 1)
		if L.stairs.any(func(q): return q.top.x > q.bottom.x) and L.stairs.any(func(q): return q.top.x < q.bottom.x):
			return L
	return {}


## x 40px on the slab side of the opening's far edge, and the direction into the opening.
func _far(s: Dictionary) -> Array:
	var h := LevelValidator.stair_hole(s)
	return [h.x - 40.0, 1.0] if s.top.x > s.bottom.x else [h.y + 40.0, -1.0]


func _far_edge(tree: SceneTree, world: Node, _b: Dictionary, s: Dictionary) -> String:
	var y := LevelValidator.surface_y(int(s.to_floor))
	var f := _far(s)
	for who in [["boy", 12.0, PlayerStats.LAYER_WORLD | PlayerStats.LAYER_ENEMY], ["walker", 14.0, PlayerStats.LAYER_WORLD | PlayerStats.LAYER_PLAYER]]:
		var end: Vector2 = await _walk(tree, world, Vector2(f[0], y - who[1]), f[1] * SPEED, who[1], who[2], true)
		if end.y > y - who[1] + 4.0:
			return "%s fell into the opening (ended at %s)" % [who[0], end]
	var fl: Vector2 = await _walk(tree, world, Vector2(f[0], y - 14.0), f[1] * SPEED, 14.0, PlayerStats.LAYER_PLAYER, false)
	if absf(fl.x - f[0]) < 100.0:
		return "floater blocked by the rail (reached x=%d)" % int(fl.x)
	return ""


func _near_edge(tree: SceneTree, world: Node, _b: Dictionary, s: Dictionary) -> String:
	var y := LevelValidator.surface_y(int(s.to_floor))
	var d := signf(s.top.x - s.bottom.x)
	var x0: float = s.top.x + d * 40.0   # on the top landing, walking back toward the opening
	for who in [["boy", 12.0, PlayerStats.LAYER_WORLD | PlayerStats.LAYER_ENEMY], ["walker", 14.0, PlayerStats.LAYER_WORLD | PlayerStats.LAYER_PLAYER]]:
		var end: Vector2 = await _walk(tree, world, Vector2(x0, y - who[1]), -d * SPEED, who[1], who[2], true)
		if end.y > y - who[1] + 4.0:
			return "%s walking off the top landing fell into the opening (ended at %s)" % [who[0], end]
	return ""


func _boy_jump(tree: SceneTree, _w: Node, built: Dictionary, s: Dictionary) -> String:
	var y := LevelValidator.surface_y(int(s.to_floor))
	var f := _far(s)
	var d := signf(s.top.x - s.bottom.x)
	# from the far slab toward the far-edge wall, and from the top landing toward the near guard
	for start in [[f[0] - f[1] * 40.0, f[1]], [s.top.x + d * 48.0, -d]]:
		var err: String = await _jump_run(tree, built.player, Vector2(start[0], y), start[1], y)
		if not err.is_empty():
			return err
	return ""


func _jump_run(tree: SceneTree, p: CharacterBody2D, at: Vector2, dir: float, y: float) -> String:
	p.state = p.State.NORMAL
	p.stair = null
	p.velocity = Vector2.ZERO
	p.global_position = at
	var act := &"move_right" if dir > 0.0 else &"move_left"
	Input.action_press(act)
	var lowest := -INF
	for i in 150:
		await tree.physics_frame
		p.jump()
		lowest = maxf(lowest, p.global_position.y)
	Input.action_release(act)
	for i in 30:
		await tree.physics_frame
	lowest = maxf(lowest, p.global_position.y)
	if lowest > y + 4.0:
		return "boy jumping %s from x=%d fell into the opening (lowest y %.1f, floor %.1f)" % [act, int(at.x), lowest, y]
	return ""


func _boy_climb(tree: SceneTree, _w: Node, built: Dictionary, s: Dictionary) -> String:
	var p: CharacterBody2D = built.player
	var st := _stair_node(built, s)
	if st == null:
		return "no Stair node"
	var budget := int(288.0 / PlayerStats.get_stat(&"climb_speed") * 60.0 / 3.0 * 1.4) + 10
	Engine.time_scale = 3.0
	for leg in [[0.0, &"move_up", s.top], [1.0, &"move_down", s.bottom]]:
		p.velocity = Vector2.ZERO
		p.global_position = st.point_at(leg[0])
		p.stair = st
		p.set("_stair_t", leg[0])
		p.set("_stair_approach", false)
		p.state = p.State.CLIMB
		Input.action_press(leg[1])
		var frames := 0
		while p.state == p.State.CLIMB and frames < budget:
			await tree.physics_frame
			frames += 1
		Input.action_release(leg[1])
		for i in 10:
			await tree.physics_frame
		if p.state == p.State.CLIMB or p.global_position.distance_to(leg[2]) > 16.0:
			Engine.time_scale = 1.0
			return "boy %s: blocked/snagged (at %s after %d frames, want %s)" % [leg[1], p.global_position, frames, leg[2]]
	Engine.time_scale = 1.0
	return ""


func _boy_jump_on_stair(tree: SceneTree, _w: Node, built: Dictionary, s: Dictionary) -> String:
	var p: CharacterBody2D = built.player
	var st := _stair_node(built, s)
	const T0 := 0.38
	p.velocity = Vector2.ZERO
	p.global_position = st.point_at(T0)
	p.stair = st
	p.set("_stair_t", T0)
	p.set("_stair_approach", false)
	p.state = p.State.CLIMB
	var at: Vector2 = p.global_position
	for i in 40:   # stand under the post and jump repeatedly
		p.jump()
		await tree.physics_frame
		if p.state != p.State.CLIMB or p.global_position.distance_to(at) > 0.5:
			return "jump knocked the boy off the stair (state %d, at %s, was %s)" % [p.state, p.global_position, at]
	var budget := int((1.0 - T0) * 288.0 / PlayerStats.get_stat(&"climb_speed") * 60.0 * 1.3) + 10
	Input.action_press(&"move_up")
	var frames := 0
	while p.state == p.State.CLIMB and frames < budget:
		p.jump()
		await tree.physics_frame
		frames += 1
		var on_line: Vector2 = st.point_at(float(p.get("_stair_t")))
		if p.state == p.State.CLIMB and p.global_position.distance_to(on_line) > 0.5:
			Input.action_release(&"move_up")
			return "boy pushed off the stair line at %s" % p.global_position
	Input.action_release(&"move_up")
	for i in 10:
		await tree.physics_frame
	if p.state == p.State.CLIMB or p.global_position.distance_to(s.top) > 16.0:
		return "boy snagged under the post (at %s after %d/%d frames, want %s)" % [p.global_position, frames, budget, s.top]
	return ""


func _walker_climb(tree: SceneTree, world: Node, built: Dictionary, s: Dictionary) -> String:
	var st := _stair_node(built, s)
	var def := StageTable.enemy_def("puppet_hand")
	var e: CharacterBody2D = load(def.script_path).new()
	e.set("def", def)
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	cs.shape = c
	e.add_child(cs)
	world.add_child(e)
	var foot: float = e.call("_foot")
	var budget := int(288.0 / float(e.get("climb_speed")) * 60.0 / 3.0 * 1.4) + 10
	var err := ""
	Engine.time_scale = 3.0
	for leg in [[s.bottom, s.top], [s.top, s.bottom]]:
		e.global_position = leg[0] - Vector2(0, foot)
		e.velocity = Vector2.ZERO
		e.call("_start_climb", leg[0], leg[0], leg[1], st)
		var frames := 0
		while e.get("climbing") and frames < budget:
			await tree.physics_frame
			frames += 1
		var feet: Vector2 = e.global_position + Vector2(0, foot)
		if e.get("climbing") or feet.distance_to(leg[1]) > 16.0:
			err = "walker %s->%s blocked/snagged (feet %s after %d frames)" % [leg[0], leg[1], feet, frames]
			break
	Engine.time_scale = 1.0
	e.queue_free()
	return err


func _stair_node(built: Dictionary, s: Dictionary) -> Node:
	for st in built.stairs:
		if st.global_position.distance_to(s.bottom) < 1.0:
			return st
	return null


func _walk(tree: SceneTree, world: Node, center: Vector2, vx: float, radius: float, mask: int, gravity: bool) -> Vector2:
	var b := CharacterBody2D.new()
	b.collision_layer = 0
	b.collision_mask = mask
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	b.add_child(cs)
	world.add_child(b)
	b.global_position = center
	for i in WALK_FRAMES:
		await tree.physics_frame
		b.velocity.x = vx
		b.velocity.y = (b.velocity.y + 980.0 / 60.0) if gravity else 0.0
		b.move_and_slide()
	var at := b.global_position
	b.queue_free()
	return at

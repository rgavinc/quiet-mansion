class_name ClimbSim
extends RefCounted
## REAL physics climb simulation (the actual player scene on a built level, 60 Hz): one
## "hop" = the boy standing still right against a piece's wall presses move + jump ONCE and must
## end up standing on the target top. Stat setups are the worst cases items allow
## (PlayerStats.stat_min of the speed, Heavy Vases' 0.7 carry cap, a vase in hand).
## Used by tests/scene_climb.gd (suite sample) and tests/climb_sweep.gd (50 seeds x 5 stages).

const R := 12.0              # LevelGenerator.PLAYER_RADIUS
const SETTLE := 12
const HOP_FRAMES := 75       # 1.25 s to get on top
const RELEASE_PX := 6.0      # feet this far over the piece's near edge: let go of the direction key
const OVER_FRAMES := 240     # walk off the far side and land on the floor

## Stat setups: [name, speed multiplier stat, Heavy Vases copies, carrying a vase]
const SETUPS := [
	["base", 1.0, 0, false],
	["carry0.7", 1.0, 3, true],       # Heavy Vases at its 0.7 cap, base move speed (98 px/s)
	["worst", 0.5, 3, true],          # move_speed at stat_min (70 px/s) and a vase in hand
]


## Applies a SETUPS row to the autoload stats and the player's hands. Jump velocity and gravity
## are pinned to their stat_min / BASE (no item changes them).
static func apply_setup(p: CharacterBody2D, setup: Array) -> void:
	PlayerStats.reset()
	GameState.reset()
	var ms := float(setup[1])
	if ms != 1.0:
		PlayerStats.add_modifier(&"move_speed", 0.0, ms, "climb_sim")
	PlayerStats.add_modifier(&"jump_velocity", 0.0, PlayerStats.stat_min(&"jump_velocity") / float(PlayerStats.BASE[&"jump_velocity"]), "climb_sim")
	for i in int(setup[2]):
		PlayerStats.grant_item(ItemDb.make("heavy_vases"))
	p.inventory.items.clear()
	if bool(setup[3]):
		p.inventory.add({id = "vase", slot = "vase_idle", throwable = true})


static func feet(p: CharacterBody2D) -> Vector2:
	return Enemy.body_feet(p)


## One hop. `dir` = +1 / -1 toward the wall at x = `wall_x` (a piece edge) from the surface at
## y = `from_y`; the target is standing on `to_y` with feet x in [x0, x1]. Returns {ok, frames, why}.
static func hop(tree: SceneTree, p: CharacterBody2D, dir: int, wall_x: float, from_y: float,
		to_y: float, x0: float, x1: float) -> Dictionary:
	p.state = p.State.NORMAL
	p.stair = null
	p.velocity = Vector2.ZERO
	p.global_position = Vector2(wall_x - dir * (R + 0.2), from_y - 20.0)   # origin; the feet sit below it
	p.global_position += Vector2(0.0, from_y - 0.5 - feet(p).y)   # feet 0.5px over the surface
	for i in SETTLE:
		await tree.physics_frame
	var f0 := feet(p)
	if absf(f0.y - from_y) > 1.5 or absf(p.velocity.y) > 30.0:
		return {ok = false, frames = 0, why = "not standing at the start (feet %s, want y %.1f)" % [f0, from_y]}
	var act := &"move_right" if dir > 0 else &"move_left"
	Input.action_press(act)
	p.jump()
	var airborne := false
	var n := 0
	var landed := false
	while n < HOP_FRAMES:
		await tree.physics_frame
		n += 1
		if (feet(p).x - wall_x) * dir >= RELEASE_PX:
			Input.action_release(act)   # over the edge: stop pushing (a player taps; holding flies past)
		if not p.is_on_floor():
			airborne = true
		elif airborne:
			landed = true
			break
	Input.action_release(act)
	for i in 4:
		await tree.physics_frame
	var f := feet(p)
	var ok := landed and absf(f.y - to_y) < 1.5 and f.x >= x0 and f.x <= x1
	return {ok = ok, frames = n, why = "" if ok else "landed=%s at feet %s (want y %.1f, x %.0f..%.0f) after %d frames" % [landed, f, to_y, x0, x1, n]}


## From a standing start on the top (already there), hold `dir` until grounded on the floor
## surface `floor_y` at feet x beyond `x_beyond` (in the walking direction).
static func walk_off(tree: SceneTree, p: CharacterBody2D, dir: int, floor_y: float, x_beyond: float) -> Dictionary:
	var act := &"move_right" if dir > 0 else &"move_left"
	Input.action_press(act)
	var n := 0
	var ok := false
	while n < OVER_FRAMES:
		await tree.physics_frame
		n += 1
		var f := feet(p)
		if absf(f.y - floor_y) < 1.5 and absf(p.velocity.y) < 30.0 and (f.x - x_beyond) * dir >= 0.0:
			ok = true
			break
	Input.action_release(act)
	return {ok = ok, frames = n, why = "" if ok else "did not walk off onto the floor (feet %s)" % [feet(p)]}


## The whole cluster (left step, tall piece, right step) climbed over in both directions: every
## hop is a standstill jump against the wall. Returns the error strings (empty = all climbed).
static func over_cluster(tree: SceneTree, p: CharacterBody2D, L: Dictionary, tall: Dictionary,
		left: Dictionary, right: Dictionary) -> PackedStringArray:
	var errs: PackedStringArray = []
	var f := int(tall.floor)
	var surf := float(LevelValidator.surface_y(f))
	var T := LevelValidator.furniture_span(tall)
	var A := LevelValidator.furniture_span(left)
	var B := LevelValidator.furniture_span(right)
	var th := surf - float(tall.h) * 16.0
	var ah := surf - float(left.h) * 16.0
	var bh := surf - float(right.h) * 16.0
	# left -> right
	var h1: Dictionary = await hop(tree, p, 1, A.x, surf, ah, A.x, A.y)
	if not h1.ok:
		errs.append("floor->left step: " + h1.why)
	else:
		var h2: Dictionary = await hop(tree, p, 1, T.x, ah, th, T.x, T.y)
		if not h2.ok:
			errs.append("left step->tall: " + h2.why)
		else:
			var w: Dictionary = await walk_off(tree, p, 1, surf, B.y + R)
			if not w.ok:
				errs.append("tall->over the right step to the floor: " + w.why)
	# right -> left
	var g1: Dictionary = await hop(tree, p, -1, B.y, surf, bh, B.x, B.y)
	if not g1.ok:
		errs.append("floor->right step: " + g1.why)
	else:
		var g2: Dictionary = await hop(tree, p, -1, T.y, bh, th, T.x, T.y)
		if not g2.ok:
			errs.append("right step->tall: " + g2.why)
		else:
			var w2: Dictionary = await walk_off(tree, p, -1, surf, A.x - R)
			if not w2.ok:
				errs.append("tall->over the left step to the floor: " + w2.why)
	return errs


## Builds seed/stage, then climbs every guaranteed piece's cluster (both directions) under each
## setup. Returns {errors, climbs, pieces}.
static func check_level(tree: SceneTree, seed_v: int, stage: int, setups: Array) -> Dictionary:
	Engine.time_scale = 1.0   # physics delta scales with it: the sim assumes 1/60 s steps
	var errs: PackedStringArray = []
	var climbs := 0
	var L := LevelGenerator.generate(seed_v, stage)
	var world := Node2D.new()
	tree.root.add_child(world)
	var built := LevelGenerator.build(L, world)
	for e in built.enemies:
		e.queue_free()
	for ex in tree.root.find_children("*", "Area2D", true, false):
		if ex.get_script() != null and str(ex.get_script().resource_path).ends_with("exit_zone.gd"):
			ex.queue_free()   # a climb that ends on the exit would win the stage and freeze the boy
	await tree.physics_frame
	var p: CharacterBody2D = built.player
	var pieces := LevelValidator.mountable_pieces(L)
	for setup in setups:
		apply_setup(p, setup)
		for fu in pieces:
			var st := LevelValidator.step_pieces(L, fu)
			if st.is_empty():
				errs.append("seed %d stage %d floor %d: guaranteed piece has no steps" % [seed_v, stage, int(fu.floor)])
				continue
			var e: PackedStringArray = await over_cluster(tree, p, L, fu, st.left, st.right)
			climbs += 1
			for m in e:
				errs.append("seed %d stage %d floor %d [%s]: %s" % [seed_v, stage, int(fu.floor), setup[0], m])
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset()
	GameState.reset()
	return {errors = errs, climbs = climbs, pieces = pieces.size()}


## Builds seed/stage and tries to climb every BLOCKER piece (taller than a jump and not a passable
## climb-over cluster: the floor graph treats it as a wall) from the floor on both sides, at the
## strongest jump (base stats, standstill jump against the wall). Every hop must FAIL to land on
## top. Returns {errors, hops, blockers}.
static func check_blockers(tree: SceneTree, seed_v: int, stage: int) -> Dictionary:
	Engine.time_scale = 1.0
	var errs: PackedStringArray = []
	var hops := 0
	var L := LevelGenerator.generate(seed_v, stage)
	var blockers := LevelValidator.blocker_pieces(L)
	if blockers.is_empty():
		return {errors = errs, hops = 0, blockers = 0}
	var world := Node2D.new()
	tree.root.add_child(world)
	var built := LevelGenerator.build(L, world)
	for e in built.enemies:
		e.queue_free()
	await tree.physics_frame
	var p: CharacterBody2D = built.player
	apply_setup(p, SETUPS[0])
	for b in blockers:
		var f := int(b.floor)
		var surf := float(LevelValidator.surface_y(f))
		var sp := LevelValidator.furniture_span(b)
		var top := surf - float(b.h) * 16.0
		for dir in [1, -1]:
			var wall_x: float = sp.x if dir > 0 else sp.y
			var r: Dictionary = await hop(tree, p, dir, wall_x, surf, top, sp.x, sp.y)
			hops += 1
			if r.ok:
				errs.append("seed %d stage %d floor %d: a blocker h%d at x=%d was climbed from the floor (dir %d)" % [seed_v, stage, f, int(b.h), int(sp.x), dir])
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset()
	GameState.reset()
	return {errors = errs, hops = hops, blockers = blockers.size()}


## Flat-world calibration of the harness itself: a free-standing box `h_px` tall, standstill hop.
## (Heights near the 52.24px apex are what the 2-tile step rule keeps every climb away from.)
static func flat_hop(tree: SceneTree, h_px: float, setup: Array) -> bool:
	var world := Node2D.new()
	tree.root.add_child(world)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	world.add_child(body)
	var fl := CollisionShape2D.new()
	var fr := RectangleShape2D.new()
	fr.size = Vector2(4000, 16)
	fl.shape = fr
	fl.position = Vector2(0, 8)
	body.add_child(fl)
	var box := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(48, h_px)
	box.shape = r
	box.position = Vector2(124, -h_px / 2.0)
	body.add_child(box)
	var p := CharacterBody2D.new()
	p.set_script(load("res://scripts/player/player_controller.gd"))
	LevelGenerator._circle(p, R)
	p.set("side_scroll", true)
	world.add_child(p)
	await tree.physics_frame
	apply_setup(p, setup)
	var res: Dictionary = await hop(tree, p, 1, 100.0, 0.0, -h_px, 100.0, 148.0)
	world.queue_free()
	await tree.process_frame
	PlayerStats.reset()
	GameState.reset()
	return res.ok

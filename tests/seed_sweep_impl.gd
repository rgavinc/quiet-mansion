extends RefCounted
## Implementation of tests/seed_sweep.gd (loaded at runtime by that launcher so the
## autoload identifiers BE scripts use, e.g. GameState, are registered before this compiles).
## Seed sweep (Lead): generate + validate N seeds per stage. Per seed it also checks the
## stage table's exact content budget (no short stages), >= 3 floors, exit off the start floor
## and that generating the same seed twice gives an identical layout. Every Nth seed also
## builds the level twice (identical node trees) and boots
## main.tscn with that seed for ~120 physics frames (boy walks toward the exit for half
## of it) and fails on any engine/script error, the boy leaving the level, or falling
## through a floor. Ends with the real-physics catch check (tests/scene_catch.gd).
##
##   godot --headless -s res://tests/seed_sweep.gd -- --seeds 1000 --stages 1-5
##   options: --stages 1,2 | 1-5   --boot-every 25   --frames 120   --first-seed 0   --catch 0|1

class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _m := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_m.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_m.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _log := ErrorCounter.new()


var tree: SceneTree


func start(t: SceneTree) -> void:
	tree = t
	OS.add_logger(_log)
	_run()


func _opts() -> Dictionary:
	var o := {seeds = 1000, stages = [1, 2, 3, 4, 5], boot_every = 25, frames = 120, first_seed = 0, catch = 1}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		var key := a[i].trim_prefix("--").get_slice("=", 0).replace("-", "_")
		var val := a[i].get_slice("=", 1) if "=" in a[i] else (a[i + 1] if i + 1 < a.size() else "")
		match key:
			"seeds", "boot_every", "frames", "first_seed", "catch":
				if val.is_valid_int():
					o[key] = int(val)
			"stages":
				var st := []
				for part in val.split(","):
					if "-" in part:
						for s in range(int(part.get_slice("-", 0)), int(part.get_slice("-", 1)) + 1):
							st.append(s)
					elif part.is_valid_int():
						st.append(int(part))
				if not st.is_empty():
					o.stages = st
	return o


func _run() -> void:
	var o := _opts()
	var ok := true
	print("=== Seed sweep: %d seeds x stages %s, boot every %d for %d frames ===" % [o.seeds, o.stages, o.boot_every, o.frames])
	for stage in o.stages:
		var want := StageTable.budget(stage)
		var valid := 0
		var rerolls := 0
		var max_rr := 0
		var fallbacks := 0
		var short := {enemies = 0, props = 0, gold = 0, chests = 0}
		var nondet := 0
		var boots := 0
		var boots_ok := 0
		var bad: Array[String] = []
		var t0 := Time.get_ticks_msec()
		for i in o.seeds:
			var s: int = o.first_seed + i
			var L := LevelGenerator.generate(s, stage)
			var errs := LevelValidator.validate(L)
			if int(L.floors) < 3:
				errs.append("%d floors" % L.floors)
			if LevelValidator.floor_of(L.exit.y) == LevelValidator.floor_of(L.start.y):
				errs.append("exit on the start floor")
			var got := {enemies = L.enemies.size(), props = L.props.size(), gold = L.gold.size(), chests = L.chests.size()}
			for k in short:
				if int(got[k]) < int(want[k]):
					short[k] += 1
					errs.append("short %s %d/%d" % [k, got[k], want[k]])
			if L.get("fallback", false):
				errs.append("retries exhausted, known-good layout used (%s)" % [L.get("reject_reasons", []).slice(-1)])
			if var_to_str(LevelGenerator.generate(s, stage)) != var_to_str(L):
				nondet += 1
				errs.append("layout differs when regenerated")
			if errs.is_empty():
				valid += 1
			else:
				bad.append("seed %d invalid: %s" % [s, errs[0]])
			rerolls += int(L.get("rerolls", 0))
			max_rr = maxi(max_rr, int(L.get("rerolls", 0)))
			fallbacks += 1 if L.get("fallback", false) else 0
			if o.boot_every > 0 and i % o.boot_every == 0:
				boots += 1
				var err: String = await _boot(s, stage, o.frames)
				if err.is_empty() and _build_sig(s, stage) != _build_sig(s, stage):
					nondet += 1
					err = "rebuild differs"
				if err.is_empty():
					boots_ok += 1
				else:
					bad.append("seed %d boot: %s" % [s, err])
		print("stage %d: %d/%d valid | rerolls %d total (avg %.2f, max %d) | fallbacks %d | short enemies %d props %d gold %d chests %d | nondeterministic %d | boots %d/%d clean | %d ms" % [
				stage, valid, o.seeds, rerolls, float(rerolls) / maxf(o.seeds, 1), max_rr, fallbacks,
				short.enemies, short.props, short.gold, short.chests, nondet,
				boots_ok, boots, Time.get_ticks_msec() - t0])
		for b in bad.slice(0, 20):
			printerr("FAIL: ", b)
		if not bad.is_empty():
			ok = false
	if int(o.catch) == 0:
		print("SWEEP %s" % ("PASS" if ok else "FAIL"))
		tree.quit(0 if ok else 1)
		return
	# Catch check: reuse BE's real-physics scene test rather than duplicating it.
	var n0 := _log.errors.size()
	var catch: Dictionary = await load("res://tests/scene_catch.gd").new().run_async(tree)
	var catch_ok: bool = int(catch.passed) == int(catch.total) and _log.errors.size() == n0
	print("catch check (scene_catch): %d/%d%s" % [catch.passed, catch.total, "" if catch_ok else " FAIL %s" % [catch.failures]])
	ok = ok and catch_ok
	print("SWEEP %s" % ("PASS" if ok else "FAIL"))
	tree.quit(0 if ok else 1)


## PRODUCT.md "Stair opening": every stair opening has its gallery rail wall on layer WORLD at
## LevelValidator.stair_rail_walls (far-edge wall + near-edge guard, 64px tall), the boy and every walker mask WORLD (blocked),
## floaters don't (drift through).
static func rail_check(built: Dictionary) -> String:
	var L: Dictionary = built.layout
	var level: Node = built.level
	var body := level.get_node_or_null("Rails") as StaticBody2D
	if body == null or not (body.collision_layer & PlayerStats.LAYER_WORLD):
		return "no Rails body on layer WORLD"
	var rects := []
	for c in body.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			rects.append(Rect2(c.position - c.shape.size / 2.0, c.shape.size))
	for s in L.stairs:
		var y := LevelValidator.surface_y(int(s.to_floor))
		for r in LevelValidator.stair_rail_walls(s):
			if not rects.any(func(q: Rect2): return is_equal_approx(q.position.x, r.x) and is_equal_approx(q.end.x, r.y) \
					and is_equal_approx(q.end.y, y) and q.size.y >= LevelValidator.RAIL_H_PX):
				return "stair at x=%d: missing rail wall %s at its opening" % [int(s.bottom.x), r]
	if not (built.player.collision_mask & PlayerStats.LAYER_WORLD):
		return "boy doesn't collide with the rail (mask)"
	for e in built.enemies:
		var walks: bool = StringName(e.get("movement")) != &"float"
		if walks != bool(e.collision_mask & PlayerStats.LAYER_WORLD):
			return "%s enemy %s rail collision (mask %d)" % [e.get("movement"), "ignores" if walks else "blocked by", e.collision_mask]
	return ""


## QA: enemies in the booted scene are exactly the stage table's count, every one a real
## EnemyDef-driven `Enemy` (type and movement from the table), no stand-ins or leftovers.
static func enemy_check(main: Node, L: Dictionary, stage: int) -> String:
	var want := int(StageTable.budget(stage).enemies)
	var got: Array = main.get_tree().get_nodes_in_group("enemies").filter(func(n): return main.is_ancestor_of(n))
	if got.size() != want or L.enemies.size() != want:
		return "%d enemy nodes / %d in layout, stage table says %d" % [got.size(), L.enemies.size(), want]
	for n in got:
		var d: Variant = n.get("def")
		if not (d is EnemyDef):
			return "enemy %s has no EnemyDef" % n.name
		var t: Dictionary = StageTable.ENEMY_TYPES.get(str(d.type_id), {})
		if t.is_empty() or n.get("movement") != t.movement or n.get("type_id") != d.type_id or int(t.min_stage) > stage:
			return "enemy %s def %s/%s doesn't match the table" % [n.name, d.type_id, n.get("movement")]
	return ""


func _boot(s: int, stage: int, frames: int) -> String:
	tree.root.get_node("PlayerStats").reset()
	tree.root.get_node("GameState").reset()
	var n0 := _log.errors.size()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("level_seed", s)
	main.set("stage", stage)
	tree.root.add_child(main)
	tree.current_scene = main
	var built: Dictionary = main.get("built")
	var err := ""
	if built == null or built.is_empty() or not is_instance_valid(built.get("player")):
		err = "level not built"
	else:
		var p: CharacterBody2D = built.player
		var L: Dictionary = built.layout
		var b: Rect2 = built.bounds
		err = enemy_check(main, L, stage)
		if err.is_empty():
			err = rail_check(built)
		var dir := "move_right" if L.exit.x > L.start.x else "move_left"
		for f in (frames if err.is_empty() else 0):
			if f == frames / 4:
				Input.action_press(dir)
			if f == frames * 3 / 4:
				Input.action_release(dir)
			await tree.physics_frame
			if not is_instance_valid(p):
				err = "player freed"
				break
			if not b.has_point(p.global_position):
				err = "player left the level at %s" % p.global_position
				break
		Input.action_release(dir)
		if err.is_empty() and is_instance_valid(p):
			var surf := LevelValidator.surface_y(LevelValidator.floor_of(p.global_position.y))
			if absf(p.global_position.y - surf) > 2.0 or not p.is_on_floor():
				err = "player not standing on a floor (y %.1f, surface %.1f)" % [p.global_position.y, surf]
	main.queue_free()
	tree.current_scene = null
	await tree.process_frame
	await tree.process_frame
	if _log.errors.size() > n0:
		err += (" | " if err else "") + "%d errors: %s" % [_log.errors.size() - n0, _log.errors[n0]]
	tree.root.get_node("PlayerStats").reset()
	tree.root.get_node("GameState").reset()
	return err


## Every node a build makes (path, type, script, position, hidden vase gold), sorted.
func _build_sig(s: int, stage: int) -> String:
	var w := Node2D.new()
	tree.root.add_child(w)
	LevelGenerator.build(LevelGenerator.generate(s, stage), w)
	var out := PackedStringArray()
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var line := "%s|%s|%s" % [w.get_path_to(n), n.get_class(), n.get_script().resource_path if n.get_script() else ""]
		if n is Node2D:
			line += "|%s" % (n as Node2D).position
		if "gold_inside" in n:   # (no WorldObject type ref: it needs autoloads at compile time)
			line += "|g%d" % int(n.get("gold_inside"))
		out.append(line)
		stack.append_array(n.get_children())
	w.free()
	out.sort()
	return "\n".join(out)

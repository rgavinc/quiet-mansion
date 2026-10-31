extends RefCounted
## Scene-level, REAL physics (Lead, QA determinism report on PR #13): the same seed loads the
## same level and the same motion. main.tscn is loaded twice per stage for seed 123456 (QA's
## seed) and every enemy's and the boy's global_position is compared on each of the first
## FRAMES physics frames (QA saw a puppet ~16px off ~3 frames after load). Nothing in level
## generation or enemy start-up may use unseeded randomness (main.gd's randomize() only rolls a
## seed when none is given; enemy_base's knock-kill randf() is a gameplay roll, not at load).
## Cross-process: tests/README.md "Determinism" (the same trace run twice in two processes).

const SEED := 123456
const FRAMES := 120


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var total := 0
	for st in StageTable.stage_count():
		var stage: int = st + 1
		var a: Array = await trace(tree, SEED, stage, FRAMES)
		var b: Array = await trace(tree, SEED, stage, FRAMES)
		total += 1
		var err := compare(a, b)
		if not err.is_empty():
			failures.append("determinism seed %d stage %d: %s" % [SEED, stage, err])
	return {"passed": total - failures.size(), "total": total, "failures": failures}


## Per physics frame: [[node path, global_position], ...] for every enemy and the boy.
static func trace(tree: SceneTree, seed_value: int, stage: int, frames: int) -> Array:
	PlayerStats.reset(); GameState.reset()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	m.set("level_seed", seed_value)
	m.set("stage", stage)
	tree.root.add_child(m)
	var built: Dictionary = m.get("built")
	var bodies: Array = (built.get("enemies", []) as Array) + [built.get("player")]
	var out := []
	for i in frames:
		await tree.physics_frame
		var row := []
		for n in bodies:
			if is_instance_valid(n):
				row.append([str(m.get_path_to(n)), (n as Node2D).global_position])
		out.append(row)
	tree.root.remove_child(m)
	m.queue_free()
	await tree.process_frame
	PlayerStats.reset(); GameState.reset()
	return out


static func compare(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "frame counts differ (%d vs %d)" % [a.size(), b.size()]
	for i in a.size():
		if (a[i] as Array).size() != (b[i] as Array).size():
			return "frame %d: %d vs %d bodies" % [i, a[i].size(), b[i].size()]
		for k in a[i].size():
			if a[i][k][0] != b[i][k][0] or (a[i][k][1] as Vector2).distance_to(b[i][k][1]) > 0.001:
				return "frame %d %s at %s vs %s %s" % [i, a[i][k][0], a[i][k][1], b[i][k][0], b[i][k][1]]
	return ""

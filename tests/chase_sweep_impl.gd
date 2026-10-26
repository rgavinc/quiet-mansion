extends RefCounted
## Implementation of tests/chase_sweep.gd (loaded at runtime: see that launcher).

var _tree: SceneTree


func start(tree: SceneTree) -> void:
	_tree = tree
	_go()


func _go() -> void:
	var a := OS.get_cmdline_user_args()
	var seeds := _range(a, "--seeds", "1000-1029")
	var stages := _range(a, "--stages", "1-3")
	var runner: GDScript = load("res://tests/scene_chase.gd")
	var n := 0
	var fails := 0
	var skipped := 0
	var frames_max := 0
	var t0 := Time.get_ticks_msec()
	for st in stages:
		for sd in seeds:
			var L: Dictionary = LevelGenerator.generate(sd, st)
			for i in L.stairs.size():
				for mode in runner.MODES:
					var r: Dictionary = await runner.run_case(_tree, sd, st, i, mode)
					if r.skip:
						skipped += 1
						continue
					n += 1
					frames_max = maxi(frames_max, r.frames)
					if not r.ok:
						fails += 1
						print("STUCK seed %d stage %d stair %d %s: %s" % [sd, st, i, mode, r.why])
	var frozen := 0
	for st in stages:
		for sd in [11]:
			var frz: String = await runner.stuck_check(_tree, sd, st)
			if not frz.is_empty():
				frozen += 1
				print("FROZEN seed %d stage %d: %s" % [sd, st, frz])
	fails += frozen
	print("chase sweep: %d cases, %d stuck, %d skipped, slowest %.1fs, %d ms" % [n, fails, skipped, frames_max / 60.0, Time.get_ticks_msec() - t0])
	_tree.quit(1 if fails > 0 else 0)


func _range(a: PackedStringArray, key: String, dflt: String) -> Array:
	var i := a.find(key)
	var v := a[i + 1] if i >= 0 and i + 1 < a.size() else dflt
	var out := []
	for part in v.split(","):
		if "-" in part:
			for k in range(int(part.split("-")[0]), int(part.split("-")[1]) + 1):
				out.append(k)
		else:
			out.append(int(part))
	return out

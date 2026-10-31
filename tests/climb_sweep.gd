extends SceneTree
## Physics climb sweep: seeds x 5 stages, every floor's guaranteed climb-over piece, climbed
## both ways by the actual player (standstill jumps) at base stats, Heavy Vases x0.7 + a vase in
## hand, and the minimum move speed + a vase in hand.
##   godot --headless --fixed-fps 60 -s res://tests/climb_sweep.gd -- [seeds=50]
## Exit code 1 on any failed climb.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seeds := 50
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			seeds = int(a.substr(6))
	var CS = load("res://tests/climb_sim.gd")   # autoloads resolve only after the tree is up
	var bad := 0
	var climbs := 0
	var t0 := Time.get_ticks_msec()
	for stage in range(1, 6):
		var sc := 0
		for sd in range(1, seeds + 1):
			var r: Dictionary = await CS.check_level(self, sd, stage, CS.SETUPS)
			sc += int(r.climbs)
			for e in r.errors:
				bad += 1
				if bad <= 20:
					print("FAIL ", e)
		climbs += sc
		print("stage %d: %d seeds, %d cluster climbs (both directions each), failures so far %d" % [stage, seeds, sc, bad])
	print("climb sweep: %d climbs, %d failed (%.0fs)" % [climbs, bad, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if bad > 0 else 0)

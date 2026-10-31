extends SceneTree
## Seed sweep (1000 seeds x 5 stages): layouts valid and never the fallback, tall share (3-4
## tiles) per stage within 15-20%... see TARGET below, every floor has a reachable 3-tile
## piece, no blocker piece climbable (kinematic rule + real-physics hops), and the generator's rejection count. Run in the background:
##   timeout 3000 godot --headless --fixed-fps 60 -s res://tests/levelgen_sweep.gd   (SWEEP_N=1000, SWEEP_CLIMB=20 seeds per stage of physics climbs)

const LO := 0.15
const HI := 0.20


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var G: GDScript = load("res://scripts/levelgen/level_generator.gd")
	var V: GDScript = load("res://scripts/levelgen/level_validator.gd")
	var n := int(OS.get_environment("SWEEP_N")) if OS.get_environment("SWEEP_N") != "" else 1000
	var CS: GDScript = load("res://tests/climb_sim.gd")
	var climb_n := int(OS.get_environment("SWEEP_CLIMB")) if OS.get_environment("SWEEP_CLIMB") != "" else 20
	var bad := 0
	for st in range(1, 6):
		var pieces := 0
		var tall := 0
		var h4 := 0
		var floors := 0
		var no_mount := 0
		var min_per_floor := 99
		var falls := 0
		var invalid := 0
		var att := 0
		var blk_levels := 0   # levels where a blocker can be climbed (LevelValidator.blocker_climb_errors)
		var blk_errs := 0
		var weak := 0   # guaranteed pieces without both steps / under the climb margin
		for sd in n:
			var L: Dictionary = G.generate(sd, st)
			att += int(L.get("rerolls", 0))
			if L.fallback:
				falls += 1
				continue
			if not (V.validate(L) as PackedStringArray).is_empty():
				invalid += 1
			var bc: PackedStringArray = V.blocker_climb_errors(L)
			blk_errs += bc.size()
			if not bc.is_empty():
				blk_levels += 1
				print("  BLOCKER CLIMB seed %d stage %d: %s" % [sd, st, bc[0]])
			var have := {}
			for fu in V.mountable_pieces(L):
				have[int(fu.floor)] = int(have.get(int(fu.floor), 0)) + 1
			for fu in V.mountable_pieces(L):
				var steps: Dictionary = V.step_pieces(L, fu)
				if steps.is_empty() or V.climb_margin_px(fu, steps) < V.MOUNT_MARGIN_PX:
					weak += 1
			for f in int(L.floors):
				floors += 1
				min_per_floor = mini(min_per_floor, int(have.get(f, 0)))
				if not have.has(f):
					no_mount += 1
			for fu in L.furniture:
				pieces += 1
				if int(fu.h) >= 3:
					tall += 1
				if int(fu.h) == 4:
					h4 += 1
		# REAL physics worst-case climb: the actual player, standstill jumps, worst stats + a vase
		var climbs := 0
		var climb_fail := 0
		var blk_hops := 0   # real-physics hops at blockers from the floor; every one must fail to land on top
		var blk_climbed := 0
		for sd in climb_n:
			var r: Dictionary = await CS.check_level(self, sd, st, CS.SETUPS)
			climbs += int(r.climbs)
			climb_fail += (r.errors as PackedStringArray).size()
			for e in r.errors:
				print("  CLIMB FAIL ", e)
		for sd in climb_n:
			var br: Dictionary = await CS.check_blockers(self, sd, st)
			blk_hops += int(br.hops)
			blk_climbed += (br.errors as PackedStringArray).size()
			for e in br.errors:
				print("  BLOCKER CLIMBED ", e)
		var share := float(tall) / maxf(pieces, 1)
		var ok := falls == 0 and invalid == 0 and no_mount == 0 and weak == 0 and climb_fail == 0 and blk_errs == 0 and blk_climbed == 0 and share >= LO and share <= HI
		if not ok:
			bad += 1
		print("%s stage %d: tall %d/%d = %.1f%% (h4 %d) | floors without a reachable 3-tile piece %d/%d (min per floor %d) | fallbacks %d invalid %d | rerolls/level %.2f | weak climb pieces %d | physics climbs %d failed %d | blocker climbs: %d in %d levels, physics blocker hops %d climbed %d" % [
				"OK  " if ok else "FAIL", st, tall, pieces, share * 100.0, h4, no_mount, floors, min_per_floor, falls, invalid, float(att) / n, weak, climbs, climb_fail, blk_errs, blk_levels, blk_hops, blk_climbed])
	print("SWEEP: %d of 5 stages failed (%d seeds each)" % [bad, n])
	quit(1 if bad > 0 else 0)

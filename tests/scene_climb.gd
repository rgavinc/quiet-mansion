extends RefCounted
## Scene suite (REAL physics, tests/climb_sim.gd): a small sample of the physics climb sweep.
## Every guaranteed climb-over piece (step, 3-tall, step) is climbed in both directions by the
## actual player at base stats, Heavy Vases carry slow x0.7 with a vase in hand, and the minimum
## move speed with a vase in hand, each hop a standstill jump against the wall (no run-up).
## Plus harness calibration in a flat world: a 32px step is climbed under every setup, a 60px box
## is not (so a "pass" means something).

const SAMPLE := [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [7, 3], [11, 5]]   # [seed, stage]


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var total := 0
	for sd in SAMPLE:
		var r: Dictionary = await ClimbSim.check_level(tree, int(sd[0]), int(sd[1]), ClimbSim.SETUPS)
		total += 1
		failures.append_array(r.errors)
		if int(r.climbs) < ClimbSim.SETUPS.size():
			failures.append("seed %d stage %d: only %d climbs ran" % [sd[0], sd[1], int(r.climbs)])
	for setup in ClimbSim.SETUPS:
		total += 2
		if not await ClimbSim.flat_hop(tree, 32.0, setup):
			failures.append("flat world: 32px step not climbed from a standstill [%s]" % setup[0])
		if await ClimbSim.flat_hop(tree, 60.0, setup):
			failures.append("flat world: a 60px box was 'climbed' [%s] (harness too lenient)" % setup[0])
	return {"passed": total - failures.size(), "total": total, "failures": failures}

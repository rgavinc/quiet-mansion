extends RefCounted
## Scene suite (REAL physics, tests/climb_sim.gd): a small sample of the physics climb sweep.
## Every guaranteed climb-over piece (step, 3-tall, step) is climbed in both directions by the
## actual player at base stats, Heavy Vases carry slow x0.7 with a vase in hand, and the minimum
## move speed with a vase in hand, each hop a standstill jump against the wall (no run-up).
## Plus harness calibration in a flat world: a 32px step is climbed under every setup, a 60px box
## is not (so a "pass" means something).

## [seed, stage, setup rows]: the full 50 seeds x 5 stages x 3 setups is tests/climb_sweep.gd
## (--fixed-fps 60; the suite runs in real time, so only a sample runs here).
const SAMPLE := [[1, 1, [2]], [3, 3, [2]], [5, 5, [2]], [2, 2, [0, 1]]]


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var total := 0
	for sd in SAMPLE:
		var r: Dictionary = await ClimbSim.check_level(tree, int(sd[0]), int(sd[1]), (sd[2] as Array).map(func(i): return ClimbSim.SETUPS[i]))
		total += 1
		failures.append_array(r.errors)
		if int(r.climbs) < (sd[2] as Array).size():
			failures.append("seed %d stage %d: only %d climbs ran" % [sd[0], sd[1], int(r.climbs)])
	# real physics: a blocker piece is never climbed from the floor (strongest jump, standstill)
	for sd in [[3, 3], [3, 4], [1, 5], [30, 5]]:
		var br: Dictionary = await ClimbSim.check_blockers(tree, int(sd[0]), int(sd[1]))
		total += 1
		failures.append_array(br.errors)
		if int(br.hops) < 2:
			failures.append("seed %d stage %d: no blocker hops ran" % [sd[0], sd[1]])
	for setup in ClimbSim.SETUPS:
		total += 2
		if not await ClimbSim.flat_hop(tree, 32.0, setup):
			failures.append("flat world: 32px step not climbed from a standstill [%s]" % setup[0])
		if await ClimbSim.flat_hop(tree, 60.0, setup):
			failures.append("flat world: a 60px box was 'climbed' [%s] (harness too lenient)" % setup[0])
	return {"passed": total - failures.size(), "total": total, "failures": failures}

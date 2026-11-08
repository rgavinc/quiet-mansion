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
	for sd in [[3, 4], [44, 4], [36, 5], [57, 5]]:
		var br: Dictionary = await ClimbSim.check_blockers(tree, int(sd[0]), int(sd[1]))
		total += 1
		failures.append_array(br.errors)
		if int(br.hops) < 2:
			failures.append("seed %d stage %d: no blocker hops ran" % [sd[0], sd[1]])
	# QA probe: step 16px, a 32px gap, a bare 64px piece: a running jump off the step top DOES climb it at
	# every stat setup (the harness sees a real climb), and a gap past the validator's reach does not
	for setup in ClimbSim.SETUPS:
		total += 3
		# QA seed 74 stage 5 floor 3: the 1-tall is a 48px-wide cluster step, 32px from the 4-tall
		if not await ClimbSim.step_gap_climbs(tree, setup, 48.0, 16.0, 32.0, 64.0):
			failures.append("flat world: seed 74 case (48px-wide 1-tall, 32px gap, 4-tall) not climbed [%s]" % setup[0])
		if not await ClimbSim.step_gap_climbs(tree, setup, 32.0, 16.0, 32.0, 64.0):
			failures.append("flat world: QA step + 32px gap + 4-tall not climbed [%s] (the probe is a real climb)" % setup[0])
		var far_gap := ceilf(LevelValidator.blocker_reach(48.0) / 16.0) * 16.0 + 16.0
		if await ClimbSim.step_gap_climbs(tree, setup, 32.0, 16.0, far_gap, 64.0):
			failures.append("flat world: a 4-tall %dpx past a step (beyond the validator's reach) was climbed [%s]" % [int(far_gap), setup[0]])
	for setup in ClimbSim.SETUPS:
		total += 2
		if not await ClimbSim.flat_hop(tree, 32.0, setup):
			failures.append("flat world: 32px step not climbed from a standstill [%s]" % setup[0])
		if await ClimbSim.flat_hop(tree, 60.0, setup):
			failures.append("flat world: a 60px box was 'climbed' [%s] (harness too lenient)" % setup[0])
	return {"passed": total - failures.size(), "total": total, "failures": failures}

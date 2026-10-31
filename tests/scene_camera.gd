extends RefCounted
## FE camera rig + seed readout on REAL built levels (main.tscn) and a scripted tall level:
##  - camera limits equal the generated level's bounds (centred only on an axis where the level is
##    smaller than the screen), on several seeds and stages
##  - the rig snaps on a new level and eases afterwards
##  - the view never leaves the limits, through a stair climb and with the flashlight nudge pressed
##    into each edge (Camera2D applies `offset` after its limit clamp, so this needs the rig)
##  - the flashlight nudge held into a wall eases in (no hard stop: peak acceleration <= 1.5x the
##    normal follow peak) on several seeds and stages
##  - the seed readout matches the run seed + stage and hides under every end screen

const VIEW := Vector2(1280, 720)
const LEVELS := [[1, 1], [7, 2], [1003, 3], [123456, 4], [42, 5]]   # [seed, stage]
const EPS := 0.01


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["limits_equal_level_bounds_on_seeds_and_stages", _limits_on_levels],
		["rig_snaps_on_stage_start_then_eases", _snap_then_ease],
		["nudge_at_every_edge_stays_inside_limits", _nudge_edges],
		["nudge_held_into_a_wall_eases_in_without_a_hard_stop", _nudge_eases_into_walls],
		["stair_climb_on_real_level_stays_inside_limits", _real_stair],
		["stair_climb_tall_level_glides_inside_limits", _tall_stair],
		["seed_readout_matches_run_and_hides_under_end_screens", _readout],
	]
	for c in checks:
		var err: String = await c[1].call(tree)
		if not err.is_empty():
			failures.append("camera %s: %s" % [c[0], err])
	_reset()
	return {"passed": checks.size() - failures.size(), "total": checks.size(), "failures": failures}


func _reset() -> void:
	for a in [&"move_up", &"move_down", &"move_left", &"move_right"]:
		Input.action_release(a)
	PlayerStats.reset()
	GameState.reset()
	var bus := UiArt.bus()
	if bus:
		bus.set("run_seed", -1)
		bus.select_enemy(null)


## A real main.tscn level, current scene, a few frames in.
func _boot(tree: SceneTree, level_seed: int, stage: int, frames: int = 2) -> Node:
	_reset()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	m.set("level_seed", level_seed)
	m.set("stage", stage)
	tree.root.add_child(m)
	tree.current_scene = m
	for i in frames:
		await tree.process_frame
	return m


func _unload(tree: SceneTree, m: Node) -> void:
	tree.current_scene = null
	m.queue_free()
	await tree.process_frame
	await tree.process_frame


func _rig(m: Node) -> CameraRig:
	return m.get_node("World/WorldOverlay/CameraRig") as CameraRig


func _inside(cam: Camera2D) -> String:
	var c := cam.get_screen_center_position()
	var lim := CameraRig.camera_limits(cam)
	var half := CameraRig.view_size(cam) / 2.0
	if c.x - half.x < lim.position.x - EPS or c.x + half.x > lim.end.x + EPS \
			or c.y - half.y < lim.position.y - EPS or c.y + half.y > lim.end.y + EPS:
		return "view centre %s (half %s) outside limits %s" % [c, half, lim]
	return ""


func _limits_on_levels(tree: SceneTree) -> String:
	for lv in LEVELS:
		var m: Node = await _boot(tree, lv[0], lv[1])
		var err := ""
		var built: Dictionary = m.get("built")
		var cam := tree.root.get_viewport().get_camera_2d()
		var b: Rect2 = built.bounds
		var want := CameraRig.limits_for(b, VIEW)
		if cam == null:
			err = "no current camera"
		elif CameraRig.camera_limits(cam) != want:
			err = "limits %s, want %s (bounds %s)" % [CameraRig.camera_limits(cam), want, b]
		elif _rig(m).bounds != b or _rig(m).bounds_source != &"level_nav":
			err = "rig bounds %s (%s) differ from the built level's %s" % [_rig(m).bounds, _rig(m).bounds_source, b]
		elif cam.position_smoothing_enabled:
			err = "built-in smoothing must be off (the rig follows)"
		if err.is_empty():
			var lim := CameraRig.camera_limits(cam)
			for axis in [0, 1]:
				if b.size[axis] >= VIEW[axis] and (lim.position[axis] != b.position[axis] or lim.end[axis] != b.end[axis]):
					err = "axis %d: level covers the screen, limits %s must equal bounds %s" % [axis, lim, b]
		if err.is_empty():
			err = _inside(cam)
		await _unload(tree, m)
		if not err.is_empty():
			return "seed %d stage %d: %s" % [lv[0], lv[1], err]
	return ""


func _snap_then_ease(tree: SceneTree) -> String:
	var m: Node = await _boot(tree, 1, 1, 1)   # one frame: the rig has just adopted the camera
	var err := ""
	var rig := _rig(m)
	var p: Node2D = m.get("built").player
	var cam := tree.root.get_viewport().get_camera_2d()
	var want := CameraRig.clamp_center(p.global_position, rig.limits, VIEW)
	if rig.center.distance_to(want) > 6.0 or cam.get_screen_center_position().distance_to(rig.center) > EPS:
		err = "stage start must snap: centre %s, screen %s, boy %s -> %s" % [rig.center, cam.get_screen_center_position(), p.global_position, want]
	if err.is_empty() and rig.velocity != Vector2.ZERO:
		err = "no velocity after a snap"
	if err.is_empty():
		# Mid-level, the boy jumps 1000px: the view eases (no snap) and arrives later.
		var before := rig.center
		p.global_position += Vector2(1000, 0)
		p.velocity = Vector2.ZERO
		await tree.process_frame
		var step := rig.center.distance_to(before)
		if step > 40.0 or step < 0.01:
			err = "mid-level the view must ease, moved %.1fpx in a frame" % step
		for i in 120:
			await tree.process_frame
		var goal := CameraRig.clamp_center(p.global_position, rig.limits, VIEW)
		if err.is_empty() and rig.center.distance_to(goal) > 1.0:
			err = "view should settle on the boy: %s vs %s" % [rig.center, goal]
		if err.is_empty():
			p.global_position += Vector2(400, 0)
			rig.snap()
			if rig.center.distance_to(CameraRig.clamp_center(p.global_position, rig.limits, VIEW)) > 0.01:
				err = "snap() must jump to the boy"
	await _unload(tree, m)
	if not err.is_empty():
		return err
	# A new run builds a new camera: it snaps again, whatever the old one was doing.
	var m2: Node = await _boot(tree, 99, 2, 1)
	var p2: Node2D = m2.get("built").player
	var r2 := _rig(m2)
	if r2.center.distance_to(CameraRig.clamp_center(p2.global_position, r2.limits, VIEW)) > 6.0:
		err = "new run / stage 2 camera did not snap: %s" % r2.center
	await _unload(tree, m2)
	return err


func _fake_enemy(tree: SceneTree, at: Vector2) -> Node2D:
	var e := Node2D.new()
	e.global_position = at
	tree.root.add_child(e)
	return e


## Flashlight nudge toward an enemy far outside each edge of the level.
func _nudge_edges(tree: SceneTree) -> String:
	var m: Node = await _boot(tree, 1, 1)
	var built: Dictionary = m.get("built")
	var b: Rect2 = built.bounds
	var p: CharacterBody2D = built.player
	var cam := tree.root.get_viewport().get_camera_2d()
	var rig := _rig(m)
	var bus := UiArt.bus()
	var err := ""
	# [boy position, enemy position, axis that must not nudge past the wall, label]
	var cases := [
		["left wall", Vector2(b.position.x + 40, p.global_position.y), Vector2(b.position.x - 900, p.global_position.y)],
		["right wall", Vector2(b.end.x - 40, p.global_position.y), Vector2(b.end.x + 900, p.global_position.y)],
		["ceiling", p.global_position, Vector2(p.global_position.x, b.position.y - 900)],
		["floor", p.global_position, Vector2(p.global_position.x, b.end.y + 900)],
	]
	for c in cases:
		p.global_position = c[1]
		p.velocity = Vector2.ZERO
		rig.snap()
		var e := _fake_enemy(tree, c[2])
		bus.select_enemy(e)
		var max_off := Vector2.ZERO
		for i in 90:
			await tree.process_frame
			err = _inside(cam)
			if not err.is_empty():
				err = "%s, frame %d: %s" % [c[0], i, err]
				break
			max_off = max_off.max((cam.get_screen_center_position() - rig.follow_goal()).abs())
			if cam.offset != Vector2.ZERO:
				err = "%s, frame %d: the rig keeps Camera2D.offset at 0, got %s" % [c[0], i, cam.offset]
				break
		bus.select_enemy(null)
		e.queue_free()
		if not err.is_empty():
			break
		for i in 60:   # let the nudge ease back before the next case
			await tree.process_frame
	# Away from a wall the nudge still works (not just clamped to zero everywhere).
	if err.is_empty():
		p.global_position = Vector2(b.get_center().x, p.global_position.y)
		p.velocity = Vector2.ZERO
		rig.snap()
		var e2 := _fake_enemy(tree, Vector2(b.get_center().x + 900, p.global_position.y))
		bus.select_enemy(e2)
		for i in 90:
			await tree.process_frame
		var lean := cam.get_screen_center_position().x - rig.follow_goal().x
		if lean < 8.0:
			err = "mid-level nudge toward an enemy should still lean the view, lean %.1f" % lean
		if err.is_empty():
			err = _inside(cam)
		bus.select_enemy(null)
		e2.queue_free()
	await _unload(tree, m)
	return err


## Seeds/stages the wall-ease test walks (QA's repro first: seed 1 stage 1).
const EASE_LEVELS := [[1, 1], [7, 2], [1003, 3], [42, 5]]
## Walking speed (px/s) the boy is scripted at. The camera is critically damped, so its peak
## acceleration scales with this; a slower walk would only make the check easier.
const EASE_WALK := 140.0
## The view's per-frame acceleration with the nudge held into a wall may be at most this multiple
## of the same walk with no nudge (the normal follow peak). The old after-the-fact clamp stopped
## the view dead in one frame: ~5.5x.
const EASE_MAX_RATIO := 1.5


## Stand 700px inside a wall for 2s, then walk the boy into it and stand there; `nudge` = a (fake)
## enemy far beyond that wall is selected the whole time (so the nudge is fully on when the boy
## walks into the wall). Returns {accel, err}: `accel` = the largest
## per-frame change of the view's centre velocity (px/s^2), `err` = the first view-outside-limits.
func _ease_run(tree: SceneTree, built: Dictionary, rig: CameraRig, side: int, nudge: bool) -> Dictionary:
	var b: Rect2 = built.bounds
	var p: CharacterBody2D = built.player
	var cam := tree.root.get_viewport().get_camera_2d()
	var bus := UiArt.bus()
	var dt := 1.0 / 60.0
	var wall_x := b.position.x if side < 0 else b.end.x
	var y := p.global_position.y
	var x := wall_x - side * 700.0   # 700px inside the wall
	var stop_x := wall_x + (40.0 if side < 0 else -40.0)
	p.global_position = Vector2(x, y)
	p.velocity = Vector2.ZERO
	bus.select_enemy(null)
	for i in 90:   # an earlier run's nudge eases away
		await tree.process_frame
	rig.snap()
	var e: Node2D = null
	if nudge:
		e = _fake_enemy(tree, Vector2(wall_x + side * 900.0, y))
		bus.select_enemy(e)
	var prev := cam.get_screen_center_position().x
	var prev_v := 0.0
	var accel := 0.0
	var err := ""
	for i in 540:
		if i >= 120 and (stop_x - x) * side > 0.0:   # stand 2s first: the nudge is fully on before the walk
			x += side * EASE_WALK * dt
			x = maxf(x, stop_x) if side < 0 else minf(x, stop_x)
		p.global_position = Vector2(x, y)
		p.velocity = Vector2.ZERO
		await tree.process_frame
		var c := cam.get_screen_center_position().x
		var v := (c - prev) / dt
		if i > 0:   # frame 0 only measures the rig's own start, from the snap
			accel = maxf(accel, absf(v - prev_v) / dt)
		prev = c
		prev_v = v
		if err.is_empty():
			err = _inside(cam)
			if not err.is_empty():
				err = "frame %d: %s" % [i, err]
	bus.select_enemy(null)
	if e != null:
		e.queue_free()
	return {accel = accel, err = err}


## Nudge held into each wall of real levels: the combined view must ease into the wall (its
## acceleration stays within EASE_MAX_RATIO of the un-nudged walk) and never leave the limits.
func _nudge_eases_into_walls(tree: SceneTree) -> String:
	for lv in EASE_LEVELS:
		var m: Node = await _boot(tree, lv[0], lv[1])
		var built: Dictionary = m.get("built")
		var rig := _rig(m)
		var err := ""
		# Only the camera is under test: no enemy may catch the boy, no exit may end the stage and no
		# furniture may shove him while he is walked (teleported) to each wall.
		(built.player as CharacterBody2D).set_physics_process(false)
		for grp in [&"enemies", &"puppets", &"exit"]:
			for n in tree.get_nodes_in_group(grp):
				n.queue_free()
		await tree.process_frame
		for side in [-1, 1]:
			var base: Dictionary = await _ease_run(tree, built, rig, side, false)
			var held: Dictionary = await _ease_run(tree, built, rig, side, true)
			var label := "seed %d stage %d %s wall" % [lv[0], lv[1], "left" if side < 0 else "right"]
			if not base.err.is_empty() or not held.err.is_empty():
				err = "%s: %s" % [label, base.err if not base.err.is_empty() else held.err]
			elif base.accel < 1.0:
				err = "%s: no baseline follow acceleration measured (%.2f)" % [label, base.accel]
			elif held.accel > EASE_MAX_RATIO * base.accel:
				err = "%s: nudge held into the wall peaks at %.0f px/s^2, %.2fx the normal follow peak (%.0f), limit %.1fx" \
						% [label, held.accel, held.accel / base.accel, base.accel, EASE_MAX_RATIO]
			if not err.is_empty():
				break
		await _unload(tree, m)
		if not err.is_empty():
			return err
	return ""


## The real boy climbing a real generated stair: the view stays inside the limits every frame
## and never moves faster than the boy. (Generated levels are shorter than one screen, so the
## camera is pinned vertically here; the tall-level test covers the vertical follow.)
func _real_stair(tree: SceneTree) -> String:
	var m: Node = await _boot(tree, 1, 1)
	var built: Dictionary = m.get("built")
	var p: CharacterBody2D = built.player
	var cam := tree.root.get_viewport().get_camera_2d()
	var rig := _rig(m)
	var err := ""
	var L: Dictionary = built.layout
	var s: Dictionary = L.stairs[0]
	var st: Node = null
	for n in built.stairs:
		if n.global_position.distance_to(s.bottom) < 1.0:
			st = n
	if st == null:
		await _unload(tree, m)
		return "no Stair node"
	var budget := int(288.0 / PlayerStats.get_stat(&"climb_speed") * 60.0 * 1.4) + 30
	p.velocity = Vector2.ZERO
	p.global_position = st.point_at(0.0)
	p.stair = st
	p.set("_stair_t", 0.0)
	p.set("_stair_approach", false)
	p.state = p.State.CLIMB
	rig.snap()
	Input.action_press(&"move_up")
	var frames := 0
	var prev := rig.center
	var max_step := 0.0
	while p.state == p.State.CLIMB and frames < budget:
		await tree.physics_frame
		frames += 1
		err = _inside(cam)
		if not err.is_empty():
			err = "climb frame %d: %s" % [frames, err]
			break
		max_step = maxf(max_step, rig.center.distance_to(prev))
		prev = rig.center
	Input.action_release(&"move_up")
	if err.is_empty() and p.state == p.State.CLIMB:
		err = "boy never finished the climb in %d frames" % budget
	if err.is_empty() and max_step > 3.0:
		err = "view lurched %.1fpx in one frame on a stair (climb speed 90px/s = 1.5px/frame)" % max_step
	await _unload(tree, m)
	return err


## A 10-floor level (taller than the screen) and a scripted boy climbing 3 stairs in a row:
## the view follows vertically, glides (no lurch: start from rest, never faster than the boy,
## never an abrupt velocity change), stays inside the limits with a nudge pulling up, and settles.
func _tall_stair(tree: SceneTree) -> String:
	var nav := LevelNav.new()
	nav.layout = {floors = 10, width_tiles = 250}
	var saved := LevelNav.current
	LevelNav.current = nav
	var world := Node2D.new()
	tree.root.add_child(world)
	var boy := Node2D.new()
	boy.add_to_group(&"player")
	world.add_child(boy)
	var cam := Camera2D.new()
	cam.enabled = true
	boy.add_child(cam)
	var bus := UiArt.bus()
	var nudge = load("res://scripts/ui/camera_nudge.gd").new()
	nudge.bus = bus
	world.add_child(nudge)
	var rig := CameraRig.new()
	world.add_child(rig)
	var b := LevelValidator.level_bounds(nav.layout)
	var err := ""
	boy.global_position = Vector2(800, 0)   # floor 0 surface
	await tree.process_frame
	await tree.process_frame
	if CameraRig.camera_limits(cam) != b:
		err = "tall level limits %s should equal bounds %s" % [CameraRig.camera_limits(cam), b]
	if err.is_empty() and (rig.center.y < b.end.y - 360.0 - 1.0 and rig.center.distance_to(CameraRig.clamp_center(boy.global_position, rig.limits, VIEW)) > 1.0):
		err = "tall level: start must snap to the boy (%s)" % rig.center
	# Climb: 90px/s along a stair that rises 160px over 144px, 3 stairs with a short walk between.
	var enemy := _fake_enemy(tree, Vector2(800, -3000))   # pulls the nudge up the whole time
	bus.select_enemy(enemy)
	var vy_max_boy := 90.0 * 160.0 / sqrt(160.0 * 160.0 + 144.0 * 144.0)
	var dt := 1.0 / 60.0
	var prev := rig.center
	var prev_v := 0.0
	var max_dy := 0.0
	var max_dv := 0.0
	var first_dy := -1.0
	var moved := false
	for stair_i in 3:
		for f in int(sqrt(160.0 * 160.0 + 144.0 * 144.0) / 90.0 * 60.0):
			boy.global_position += Vector2(90.0 * 144.0 / sqrt(160.0 * 160.0 + 144.0 * 144.0), -vy_max_boy) * dt
			await tree.process_frame
			err = _inside(cam)
			if not err.is_empty():
				break
			var dy := rig.center.y - prev.y
			if first_dy < 0.0:
				first_dy = absf(dy)
			max_dy = maxf(max_dy, absf(dy))
			max_dv = maxf(max_dv, absf(dy / dt - prev_v))
			prev_v = dy / dt
			prev = rig.center
			moved = moved or absf(dy) > 0.05
		if not err.is_empty():
			break
		for f in 45:   # walk along the landing
			boy.global_position += Vector2(140.0 * dt, 0)
			await tree.process_frame
			err = _inside(cam)
			if not err.is_empty():
				break
			var dy2 := rig.center.y - prev.y
			max_dy = maxf(max_dy, absf(dy2))
			max_dv = maxf(max_dv, absf(dy2 / dt - prev_v))
			prev_v = dy2 / dt
			prev = rig.center
		if not err.is_empty():
			break
	if err.is_empty():
		if not moved:
			err = "the view never followed the boy up the stairs"
		elif first_dy > 1.0:
			err = "view lurched %.2fpx on the first climb frame" % first_dy
		elif max_dy > vy_max_boy * dt * 1.05:
			err = "view moved %.2fpx in a frame, faster than the boy (%.2f)" % [max_dy, vy_max_boy * dt]
		elif max_dv > 25.0:
			err = "view velocity jumped %.1fpx/s in one frame (lurch)" % max_dv
	if err.is_empty():
		# A floor-sized step (a stair handing over to the next floor, a respawn): the view glides
		# there at no more than its speed cap, from rest.
		await tree.create_timer(1.5).timeout
		prev = rig.center
		boy.global_position.y -= 160.0
		var step_max := 0.0
		var step_first := -1.0
		for i in 60:
			await tree.process_frame
			var d := absf(rig.center.y - prev.y)
			if step_first < 0.0:
				step_first = d
			step_max = maxf(step_max, d)
			prev = rig.center
			err = _inside(cam)
			if not err.is_empty():
				break
		if err.is_empty() and step_first > 2.0:
			err = "a 160px floor step moved the view %.2fpx on its first frame (lurch)" % step_first
		elif err.is_empty() and step_max > 420.0 * dt + 0.01:
			err = "a 160px floor step moved the view %.2fpx in a frame, over the speed cap" % step_max
	if err.is_empty():
		for i in 240:
			await tree.process_frame
		var goal := CameraRig.clamp_center(boy.global_position + rig.nudge_offset(), rig.limits, VIEW)   # nudge still held
		if rig.center.distance_to(goal) > 1.0:
			err = "view should settle on the boy (+ nudge) at the top: %s vs %s" % [rig.center, goal]
		if err.is_empty():
			err = _inside(cam)
	bus.select_enemy(null)
	enemy.queue_free()
	world.queue_free()
	LevelNav.current = saved
	await tree.process_frame
	return err


func _readout(tree: SceneTree) -> String:
	for lv in [[123456, 2], [7, 5]]:
		var m: Node = await _boot(tree, lv[0], lv[1])
		var err := ""
		var bus := UiArt.bus()
		var ro: Label = m.get_node("HUD/HudRoot/SeedReadout")
		var want := "seed %d · stage %d" % [bus.get_run_seed(), bus.get_stage()]
		if ro.text != want or want != "seed %d · stage %d" % [lv[0], lv[1]]:
			err = "text '%s', want '%s' (run seed %d, stage %d)" % [ro.text, want, lv[0], lv[1]]
		elif not ro.is_visible_in_tree():
			err = "readout should show during play"
		elif ro.get_global_rect().position.x > 40.0 or ro.get_global_rect().end.y < 600.0 or ro.get_global_rect().size.x > 260.0:
			err = "readout should sit small in the bottom-left, rect %s" % ro.get_global_rect()
		if err.is_empty():
			for name in ["GameOver", "Shop", "WinScreen"]:
				var sc: UiScreen = m.get_node(name)
				sc.open()
				var hidden := not ro.is_visible_in_tree()
				sc.close()
				if not hidden:
					err = "readout must hide under %s" % name
					break
				if not ro.is_visible_in_tree():
					err = "readout must return after %s closes" % name
					break
		await _unload(tree, m)
		if not err.is_empty():
			return "seed %d stage %d: %s" % [lv[0], lv[1], err]
	return ""

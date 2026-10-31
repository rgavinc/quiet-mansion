extends RefCounted
## FE camera rig + seed readout, pure/unit side (the scene side, real built levels, is
## scene_camera.gd): clamp math, smoothing, bounds fallback, readout text.


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["limits_equal_bounds_when_level_covers_screen", test_limits_equal_bounds],
		["limits_centre_a_level_smaller_than_the_screen", test_limits_small_level],
		["clamp_center_keeps_screen_inside_limits", test_clamp_center],
		["clamp_offset_keeps_centre_plus_offset_inside", test_clamp_offset],
		["smooth_damp_converges_without_overshoot_or_lurch", test_smooth_damp],
		["bounds_fall_back_to_tilemap_then_dev_room", test_bounds_fallback],
		["bounds_come_from_level_nav_layout", test_bounds_level_nav],
		["seed_readout_text_format", test_readout_text],
		["rig_and_readout_disconnect_on_exit_tree", test_disconnect],
	]
	for c in checks:
		var err: String = c[1].call()
		if not err.is_empty():
			failures.append("%s: %s" % [c[0], err])
	return {"passed": checks.size() - failures.size(), "total": checks.size(), "failures": failures}


const VIEW := Vector2(1280, 720)


func test_limits_equal_bounds() -> String:
	var b := Rect2(0, -480, 1296, 496)   # taller than nothing, wider than the screen
	var big := Rect2(-16, -800, 2000, 1000)
	var l := CameraRig.limits_for(big, VIEW)
	if l != big:
		return "limits %s should equal bounds %s when the level covers the screen" % [l, big]
	var l2 := CameraRig.limits_for(b, VIEW)
	if l2.position.x != b.position.x or l2.end.x != b.end.x:
		return "wide level: x limits %s should equal bounds %s" % [l2, b]
	return ""


func test_limits_small_level() -> String:
	var b := Rect2(0, -160, 800, 176)   # smaller than the screen on both axes
	var l := CameraRig.limits_for(b, VIEW)
	if l.size.x < VIEW.x or l.size.y < VIEW.y:
		return "limits %s smaller than the screen" % l
	if not l.encloses(b):
		return "limits %s must enclose the level %s" % [l, b]
	if absf(l.get_center().x - b.get_center().x) > 1.0 or absf(l.get_center().y - b.get_center().y) > 1.0:
		return "limits %s should be centred on the level %s" % [l, b]
	var c := CameraRig.clamp_center(Vector2(-5000, 5000), l, VIEW)
	var c2 := CameraRig.clamp_center(Vector2(5000, -5000), l, VIEW)
	if c.distance_to(c2) > 2.0:
		return "a level smaller than the screen must pin the view centre (%s vs %s)" % [c, c2]
	return ""


func test_clamp_center() -> String:
	var lim := Rect2(0, -500, 3000, 1000)
	var c := CameraRig.clamp_center(Vector2(-100, -900), lim, VIEW)
	if c != Vector2(640, -140):
		return "top-left corner centre should be (640,-140), got %s" % c
	c = CameraRig.clamp_center(Vector2(9000, 900), lim, VIEW)
	if c != Vector2(2360, 140):
		return "bottom-right corner centre wrong: %s" % c
	var mid := Vector2(1500, 0)
	if CameraRig.clamp_center(mid, lim, VIEW) != mid:
		return "an inside centre must not move"
	return ""


func test_clamp_offset() -> String:
	var lim := Rect2(0, -500, 3000, 1000)
	# Centre already at the left wall (x=640): an offset toward the wall is cut to 0, away is free.
	var c := Vector2(640, 0)
	if CameraRig.clamp_offset(c, Vector2(-48, 0), lim, VIEW) != Vector2.ZERO:
		return "nudge into the left wall must be 0"
	if CameraRig.clamp_offset(c, Vector2(48, 0), lim, VIEW) != Vector2(48, 0):
		return "nudge away from the wall must pass"
	# 10px from the wall: only 10px of nudge is allowed.
	var o := CameraRig.clamp_offset(Vector2(650, 0), Vector2(-48, 0), lim, VIEW)
	if absf(o.x + 10.0) > 0.001:
		return "10px from the wall allows 10px, got %s" % o
	# Vertical: a view exactly one screen tall allows no vertical nudge at all.
	var flat := Rect2(0, 0, 3000, 720)
	if CameraRig.clamp_offset(Vector2(1500, 360), Vector2(0, 40), flat, VIEW) != Vector2.ZERO:
		return "no vertical room, no vertical nudge"
	return ""


func test_smooth_damp() -> String:
	var pos := 0.0
	var vel := 0.0
	var dt := 1.0 / 60.0
	var last := 0.0
	var max_step := 0.0
	var first_step := -1.0
	for i in 600:
		var r := CameraRig.smooth_damp(pos, 400.0, vel, 0.36, 420.0, dt)
		pos = r[0]
		vel = r[1]
		if pos > 400.0 + 0.001:
			return "overshot to %f" % pos
		if pos < last - 0.0001:
			return "went backwards"
		if first_step < 0.0:
			first_step = pos - last
		max_step = maxf(max_step, pos - last)
		last = pos
	if absf(pos - 400.0) > 0.5:
		return "should settle on the target, at %f" % pos
	# A 400px step must not lurch: the first frame moves little (starts from rest) and no frame
	# exceeds the speed cap.
	if first_step > 2.0:
		return "first frame of a step moved %.2fpx (lurch)" % first_step
	if max_step > 420.0 * dt + 0.01:
		return "a frame moved %.2fpx, over the %.2f cap" % [max_step, 420.0 * dt]
	return ""


func test_bounds_fallback() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var saved := LevelNav.current
	LevelNav.current = null
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var err := ""
	var r := CameraRig.level_bounds_for(tree)
	if r[1] != &"room" or r[0] != Rect2(0, 0, 1280, 720):
		err = "no level, no tilemap: want the 1280x720 room, got %s" % [r]
	if err.is_empty():
		var tm := TileMapLayer.new()
		var ts := TileSet.new()
		ts.tile_size = Vector2i(16, 16)
		tm.tile_set = ts
		var src := TileSetAtlasSource.new()
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		src.texture = ImageTexture.create_from_image(img)
		src.texture_region_size = Vector2i(16, 16)
		src.create_tile(Vector2i.ZERO)
		ts.add_source(src, 0)
		holder.add_child(tm)
		tm.set_cell(Vector2i(2, 3), 0, Vector2i.ZERO)
		tm.set_cell(Vector2i(9, 7), 0, Vector2i.ZERO)
		r = CameraRig.level_bounds_for(tree)
		if r[1] != &"tilemap" or r[0] != Rect2(32, 48, 128, 80):
			err = "tilemap used rect: want (32,48,128,80), got %s" % [r]
	holder.queue_free()
	LevelNav.current = saved
	return err


func test_bounds_level_nav() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var saved := LevelNav.current
	for pair in [[1, 1], [7, 2], [1003, 3], [42, 5]]:
		var L := LevelGenerator.generate(pair[0], pair[1])
		LevelNav.current = LevelNav.from_layout(L)
		var r := CameraRig.level_bounds_for(tree)
		if r[1] != &"level_nav" or r[0] != LevelValidator.level_bounds(L):
			LevelNav.current = saved
			return "seed %d stage %d: bounds %s, want LevelValidator.level_bounds %s" % [pair[0], pair[1], r, LevelValidator.level_bounds(L)]
	LevelNav.current = saved
	return ""


func test_readout_text() -> String:
	var S = load("res://scripts/ui/seed_readout.gd")
	if S.text_for(123456, 2) != "seed 123456 · stage 2":
		return "got '%s'" % S.text_for(123456, 2)
	if S.text_for(-1, 1) != "":
		return "no seed must give no text"
	return ""


func test_disconnect() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = load("res://scripts/ui/fe_signals.gd").new()
	tree.root.add_child(bus)
	var r: Label = load("res://scripts/ui/seed_readout.gd").new()
	r.bus = bus
	tree.root.add_child(r)
	var err := ""
	if not bus.is_connected(&"stage_started", r._on_stage):
		err = "readout should listen to stage_started while in the tree"
	tree.root.remove_child(r)
	if err.is_empty() and bus.is_connected(&"stage_started", r._on_stage):
		err = "readout must disconnect on _exit_tree"
	r.free()
	bus.free()
	return err

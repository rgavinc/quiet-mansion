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
		["default_camera_zoom_is_3", test_default_zoom],
		["limits_and_clamp_use_viewport_over_zoom", test_zoomed_view_limits],
		["arrows_fire_for_chasers_outside_the_zoomed_view", test_arrows_zoomed_view],
		["default_camera_floor_y_is_0_7", test_default_floor_y],
		["follow_offset_places_the_floor_at_the_knob", test_follow_offset],
		["limits_pad_below_so_bottom_floor_can_hold_framing", test_limits_pad_for_floor_y],
		["arrows_use_the_true_framed_view", test_arrows_framed_view],
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

func test_default_zoom() -> String:
	var fresh := HudSkin.new()
	if not is_equal_approx(fresh.camera_zoom, 3.0):
		return "HudSkin.camera_zoom default should be 3.0, got %s" % fresh.camera_zoom
	var loaded := HudSkin.load_default()
	if not is_equal_approx(loaded.camera_zoom, 3.0):
		return "load_default camera_zoom should be 3.0, got %s" % loaded.camera_zoom
	if not is_equal_approx(CameraRig.zoom_from_skin(fresh), 3.0):
		return "zoom_from_skin should read the knob"
	var zero := HudSkin.new()
	zero.camera_zoom = 0.0
	if CameraRig.zoom_from_skin(zero) <= 0.0:
		return "zoom_from_skin must never return 0"
	return ""


func test_zoomed_view_limits() -> String:
	# 1280x720 at zoom 3 → world view ≈ 426.67 × 240. One floor is 160px, so the view
	# shows one floor plus 40px of the floors above and below.
	var view := Vector2(1280, 720) / 3.0
	if absf(view.y - 240.0) > 0.01:
		return "zoom 3 world view height should be 240, got %s" % view
	var tall := Rect2(0, -480, 2000, 496)   # typical 3-4 floor stage: taller than 240, wider than 427
	var l := CameraRig.limits_for(tall, view)
	if l != tall:
		return "when the level covers the zoomed view, limits %s should equal bounds %s" % [l, tall]
	var c := CameraRig.clamp_center(Vector2(-100, 900), l, view)
	var want := Vector2(l.position.x + view.x / 2.0, l.end.y - view.y / 2.0)
	if c.distance_to(want) > 0.01:
		return "bottom-left clamp at zoom 3: %s, want %s" % [c, want]
	# A level smaller than the zoomed view is still centred and pins the view.
	var tiny := Rect2(100, 100, 80, 80)
	var lt := CameraRig.limits_for(tiny, view)
	if lt.size.x < view.x - 0.01 or lt.size.y < view.y - 0.01:
		return "tiny level limits %s smaller than the zoomed view %s" % [lt, view]
	var a := CameraRig.clamp_center(Vector2(-9999, -9999), lt, view)
	var b := CameraRig.clamp_center(Vector2(9999, 9999), lt, view)
	if a.distance_to(b) > 2.0:
		return "tiny level must pin the zoomed view centre (%s vs %s)" % [a, b]
	return ""


## A chaser one floor away is on-screen at zoom 1 (half-height 360) and off the
## zoomed view at zoom 3 (half-height 120), so it must get an arrow at 3 and lose
## it when zoom returns to 1. Same for a horizontal chaser just outside the zoomed width.
func test_arrows_zoomed_view() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = load("res://scripts/ui/fe_signals.gd").new()
	tree.root.add_child(bus)
	var skin := HudSkin.new()
	skin.camera_zoom = 3.0
	var cam := Camera2D.new()
	cam.enabled = true
	cam.zoom = Vector2(3, 3)
	tree.root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector2.ZERO
	cam.force_update_scroll()
	var boy := Node2D.new()
	boy.add_to_group(&"player")
	tree.root.add_child(boy)
	boy.global_position = Vector2.ZERO
	var arrows = load("res://scripts/ui/offscreen_arrows.gd").new()
	arrows.skin = skin
	arrows.bus = bus
	tree.root.add_child(arrows)
	var floor_e := Node2D.new()
	tree.root.add_child(floor_e)
	floor_e.global_position = Vector2(0, -160)   # one floor above
	var near_e := Node2D.new()
	tree.root.add_child(near_e)
	near_e.global_position = Vector2(80, 0)   # on-screen even at zoom 3 (half-width ≈ 213)
	bus.report_chase(floor_e, true)
	bus.report_chase(near_e, true)
	# Let the current camera settle into the canvas transform.
	# _process of arrows is what we call ourselves.
	arrows._process(0.0)
	var ids := func() -> Array:
		return arrows.arrows.map(func(x): return x["enemy"])
	var err := ""
	if not ids.call().has(floor_e):
		err = "chaser one floor away must get an arrow at zoom 3, got %s" % [ids.call()]
	if err.is_empty() and ids.call().has(near_e):
		err = "nearby same-floor chaser must not get an arrow while on the zoomed view"
	# Zoom 1: the floor-away chaser is now inside the 720px view, arrow should go.
	if err.is_empty():
		cam.zoom = Vector2.ONE
		cam.force_update_scroll()
		arrows._process(0.0)
		if ids.call().has(floor_e):
			err = "at zoom 1 the same one-floor chaser is on-screen and must lose its arrow"
	# Restore zoom 3: arrow returns. Also a chaser just past the zoomed half-width.
	if err.is_empty():
		cam.zoom = Vector2(3, 3)
		cam.force_update_scroll()
		var side_e := Node2D.new()
		tree.root.add_child(side_e)
		side_e.global_position = Vector2(300, 0)   # 300 > 1280/3/2 ≈ 213, < 640
		bus.report_chase(side_e, true)
		arrows._process(0.0)
		if not ids.call().has(floor_e) or not ids.call().has(side_e):
			err = "zoom 3 must arrow a one-floor chaser and a just-off-horizontal chaser, got %s" % [ids.call()]
		if err.is_empty() and ids.call().has(near_e):
			err = "on-view chaser must stay un-arrowed"
		side_e.free()
	for n in [arrows, cam, boy, floor_e, near_e, bus]:
		if is_instance_valid(n):
			n.free()
	return err


func test_default_floor_y() -> String:
	var fresh := HudSkin.new()
	if not is_equal_approx(fresh.camera_floor_y, 0.7):
		return "HudSkin.camera_floor_y default should be 0.7, got %s" % fresh.camera_floor_y
	var loaded := HudSkin.load_default()
	if not is_equal_approx(loaded.camera_floor_y, 0.7):
		return "load_default camera_floor_y should be 0.7, got %s" % loaded.camera_floor_y
	if not is_equal_approx(CameraRig.floor_y_of(fresh), 0.7):
		return "floor_y_of should read the knob"
	var wild := HudSkin.new()
	wild.camera_floor_y = 2.5
	if not is_equal_approx(CameraRig.floor_y_of(wild), 1.0):
		return "floor_y_of must clamp to 0..1, got %s" % CameraRig.floor_y_of(wild)
	return ""


func test_follow_offset() -> String:
	var view := Vector2(1280, 720) / 3.0   # 240 px tall
	var off := CameraRig.follow_offset(view, 0.7)
	# Camera shifts up by 0.2 * 240 = 48 px so the target sits at 70% down.
	if off.x != 0.0 or absf(off.y - (0.5 - 0.7) * view.y) > 0.01:
		return "floor_y 0.7 offset should be (0, -48), got %s" % off
	if CameraRig.follow_offset(view, 0.5) != Vector2.ZERO:
		return "floor_y 0.5 (centre) must be a zero offset"
	# A boy at y=0 with this offset: the floor is at 70% of the unclamped view.
	var centre := Vector2(0, 0) + off
	var floor_ratio := (0.0 - (centre.y - view.y / 2.0)) / view.y
	if absf(floor_ratio - 0.7) > 0.001:
		return "unclamped floor should sit at 0.7 of the view, got %s" % floor_ratio
	return ""


func test_limits_pad_for_floor_y() -> String:
	var view := Vector2(1280, 720) / 3.0
	var b := Rect2(0, -480, 2000, 496)   # taller and wider than the zoomed view
	var centred := CameraRig.limits_for(b, view, 0.5)
	if centred != b:
		return "floor_y 0.5 must not pad: got %s, want bounds %s" % [centred, b]
	var framed := CameraRig.limits_for(b, view, 0.7)
	if framed.position.x != b.position.x or framed.end.x != b.end.x:
		return "framing must not change x limits: %s vs %s" % [framed, b]
	if framed.position.y != b.position.y:
		return "floor_y 0.7 must not pad the top: %s vs %s" % [framed, b]
	var want_end := b.end.y + (1.0 - 0.7) * view.y
	if absf(framed.end.y - want_end) > 1.0:
		return "floor_y 0.7 should pad the bottom to %s, got %s" % [want_end, framed.end.y]
	# Boy on the bottom floor (at bounds.end): the framed centre stays inside, and
	# the unpadded limits would have pinned him to the bottom edge of the view.
	var boy := Vector2(1000, b.end.y)
	var off := CameraRig.follow_offset(view, 0.7)
	var c := CameraRig.clamp_center(boy + off, framed, view)
	var ratio := (boy.y - (c.y - view.y / 2.0)) / view.y
	if absf(ratio - 0.7) > 0.02:
		return "padded limits should keep the bottom-floor boy at ~0.7, got %s (centre %s)" % [ratio, c]
	var old := CameraRig.clamp_center(boy + off, centred, view)
	var old_ratio := (boy.y - (old.y - view.y / 2.0)) / view.y
	if old_ratio < 0.85:
		return "unpadded limits should still pin the boy near the bottom (got %s); the pad is what fixes it" % old_ratio
	# And the view stays inside the padded limits.
	if c.y - view.y / 2.0 < framed.position.y - 0.01 or c.y + view.y / 2.0 > framed.end.y + 0.01:
		return "framed view at the bottom floor left the padded limits"
	return ""


## With the camera shifted up for floor_y framing, arrows must follow the true
## (canvas-transform) view: a chaser in the newly visible slice above is on-screen,
## and one past the tighter bottom edge gets an arrow.
func test_arrows_framed_view() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = load("res://scripts/ui/fe_signals.gd").new()
	tree.root.add_child(bus)
	var view := Vector2(1280, 720) / 3.0
	var off := CameraRig.follow_offset(view, 0.7)
	var cam := Camera2D.new()
	cam.enabled = true
	cam.zoom = Vector2(3, 3)
	tree.root.add_child(cam)
	cam.make_current()
	cam.global_position = off   # framed: boy at (0,0) sits at 70% down
	cam.force_update_scroll()
	var boy := Node2D.new()
	boy.add_to_group(&"player")
	tree.root.add_child(boy)
	boy.global_position = Vector2.ZERO
	var arrows = load("res://scripts/ui/offscreen_arrows.gd").new()
	arrows.skin = HudSkin.new()
	arrows.bus = bus
	tree.root.add_child(arrows)
	# One floor up: at zoom 3 with no framing this was off-screen (half-height 120);
	# with floor_y 0.7, 168 px are visible above the boy, so -160 is on-screen.
	var above := Node2D.new()
	tree.root.add_child(above)
	above.global_position = Vector2(0, -160)
	# Past the new bottom of the view (boy + 0.3 * 240 = 72).
	var below := Node2D.new()
	tree.root.add_child(below)
	below.global_position = Vector2(0, 120)
	bus.report_chase(above, true)
	bus.report_chase(below, true)
	arrows._process(0.0)
	var ids := func() -> Array:
		return arrows.arrows.map(func(x): return x["enemy"])
	var err := ""
	if ids.call().has(above):
		err = "chaser one floor up is inside the framed view and must not get an arrow"
	elif not ids.call().has(below):
		err = "chaser past the framed view's bottom must get an arrow, got %s" % [ids.call()]
	for n in [arrows, cam, boy, above, below, bus]:
		if is_instance_valid(n):
			n.free()
	return err

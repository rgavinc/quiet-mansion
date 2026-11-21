extends RefCounted
## Visible world rect: off-screen checks follow the live camera zoom.
## At zoom 1 the result matches the old 1280×720 half-extents; at zoom 3 a
## point inside that old rect but outside the zoomed view is off-screen.
## Flashlight reach and Cracked Mirror drain use the same helper.

const DT := 1.0 / 60.0
const META := &"zoom_offscreen_test"
const OLD := Vector2(1280, 720)
var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["no_camera_matches_old_1280x720", test_no_camera],
		["zoom_1_matches_old_rect_when_centred", test_zoom_1],
		["zoom_3_inside_old_rect_is_off_screen", test_zoom_3],
		["visible_rect_respects_camera_limits", test_limits],
		["visible_rect_handles_vector2_zoom", test_vector_zoom],
		["flashlight_reach_uses_visible_rect", test_flashlight],
		["cracked_mirror_drain_uses_visible_rect", test_mirror_drain],
	]
	var passed := 0
	for item in checks:
		_clean()
		var r: Variant = item[1].call()
		var err: String = r if r is String else "script error (check returned %s)" % [r]
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	_clean()
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	if root == null:
		return
	for c in root.get_children():
		if c.has_meta(META):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()


func _add(n: Node, at := Vector2.ZERO) -> Node:
	n.set_meta(META, true)
	root.add_child(n)
	if n is Node2D:
		(n as Node2D).global_position = at
	return n


func _cam(at: Vector2, zoom: Vector2, limits: Rect2 = Rect2()) -> Camera2D:
	var cam := Camera2D.new()
	_add(cam, at)
	cam.zoom = zoom
	if limits.size != Vector2.ZERO:
		cam.limit_left = int(limits.position.x)
		cam.limit_top = int(limits.position.y)
		cam.limit_right = int(limits.end.x)
		cam.limit_bottom = int(limits.end.y)
		cam.limit_enabled = true
	cam.make_current()
	cam.force_update_scroll()
	return cam


func _current() -> Camera2D:
	var vp := root.get_viewport()
	return vp.get_camera_2d() if vp else null


## Run `fn` with no current camera, then restore whatever was current.
func _without_camera(fn: Callable) -> String:
	var cam := _current()
	var was := false
	if cam != null:
		was = cam.enabled
		cam.enabled = false
	var err: String = fn.call()
	if cam != null and is_instance_valid(cam):
		cam.enabled = was
		if was:
			cam.make_current()
	return err


func _old_off(p: Vector2, center: Vector2) -> bool:
	var d := (p - center).abs()
	return d.x > OLD.x * 0.5 or d.y > OLD.y * 0.5


func _samples(center: Vector2) -> Array:
	# [point, label] — includes exact old edges and a mid point used at zoom 3.
	return [
		[center, "centre"],
		[center + Vector2(OLD.x * 0.5, 0.0), "right edge 640"],
		[center + Vector2(0.0, OLD.y * 0.5), "bottom edge 360"],
		[center + Vector2(OLD.x * 0.5 + 1.0, 0.0), "past right 641"],
		[center + Vector2(0.0, OLD.y * 0.5 + 1.0), "past bottom 361"],
		[center + Vector2(300.0, 0.0), "mid 300 x (inside old, outside zoom 3)"],
		[center + Vector2(0.0, -160.0), "one floor up (inside old, outside zoom 3)"],
		[center + Vector2(80.0, 0.0), "near 80 x (on-screen at zoom 3)"],
	]


func test_no_camera() -> Variant:
	return _without_camera(func() -> String:
		if _current() != null:
			return "expected no current camera"
		var c := Vector2(100, 200)
		var r := PlayerStats.visible_world_rect(c)
		if r.position != c - OLD * 0.5 or r.size != OLD:
			return "fallback rect %s, want 1280x720 around %s" % [r, c]
		for s in _samples(c):
			var p: Vector2 = s[0]
			var got := PlayerStats.is_off_screen(p, c)
			var want := _old_off(p, c)
			if got != want:
				return "%s: is_off_screen=%s, old=%s (p=%s c=%s)" % [s[1], got, want, p, c]
		return ""
	)


func test_zoom_1() -> Variant:
	var c := Vector2(100, 200)
	_cam(c, Vector2.ONE)
	var r := PlayerStats.visible_world_rect(c)
	if not r.size.is_equal_approx(OLD):
		return "zoom 1 view size %s, want %s" % [r.size, OLD]
	if not r.get_center().is_equal_approx(c):
		return "zoom 1 view centre %s, want %s" % [r.get_center(), c]
	for s in _samples(c):
		var p: Vector2 = s[0]
		var got := PlayerStats.is_off_screen(p, c)
		var want := _old_off(p, c)
		if got != want:
			return "%s: zoom 1 is_off_screen=%s, old=%s (p=%s)" % [s[1], got, want, p]
	return ""


func test_zoom_3() -> Variant:
	var c := Vector2(100, 200)
	_cam(c, Vector2(3, 3))
	var r := PlayerStats.visible_world_rect(c)
	var want_size := OLD / Vector2(3, 3)
	if not r.size.is_equal_approx(want_size):
		return "zoom 3 view size %s, want %s" % [r.size, want_size]
	if not r.get_center().is_equal_approx(c):
		return "zoom 3 view centre %s, want camera %s" % [r.get_center(), c]
	var mid: Vector2 = c + Vector2(300, 0)
	var floor_up: Vector2 = c + Vector2(0, -160)
	var near: Vector2 = c + Vector2(80, 0)
	if _old_off(mid, c) or _old_off(floor_up, c):
		return "setup: mid/floor should be inside the old 1280x720 rect"
	if not PlayerStats.is_off_screen(mid, c):
		return "point 300px right (inside old rect) should be off-screen at zoom 3"
	if not PlayerStats.is_off_screen(floor_up, c):
		return "point one floor up (160px, inside old rect) should be off-screen at zoom 3"
	if PlayerStats.is_off_screen(near, c):
		return "point 80px right should stay on-screen at zoom 3"
	if PlayerStats.is_off_screen(c, c):
		return "camera centre should be on-screen"
	return ""


func test_limits() -> Variant:
	# Camera at the origin, but limits are the 1280x720 room, so the view is
	# pushed to the room centre. A point just left of 0 is off-screen.
	var cam := _cam(Vector2.ZERO, Vector2.ONE, Rect2(0, 0, 1280, 720))
	var r := PlayerStats.visible_world_rect(Vector2.ZERO)
	if not r.get_center().is_equal_approx(Vector2(640, 360)):
		return "limited view centre %s, want (640, 360); screen_center=%s" % [r.get_center(), cam.get_screen_center_position()]
	if not r.position.is_equal_approx(Vector2.ZERO) or not r.size.is_equal_approx(OLD):
		return "limited view %s, want Rect2(0,0,1280,720)" % r
	if not PlayerStats.is_off_screen(Vector2(-10, 360), Vector2.ZERO):
		return "point left of the limited view should be off-screen"
	if PlayerStats.is_off_screen(Vector2(10, 360), Vector2.ZERO):
		return "point just inside the limited view should be on-screen"
	return ""


func test_vector_zoom() -> Variant:
	var c := Vector2(200, 200)
	_cam(c, Vector2(2, 1))
	var r := PlayerStats.visible_world_rect(c)
	var want := Vector2(OLD.x / 2.0, OLD.y)
	if not r.size.is_equal_approx(want):
		return "vector zoom view size %s, want %s" % [r.size, want]
	var side := c + Vector2(400, 0)   # 400 > 320, < 640
	var down := c + Vector2(0, 300)   # 300 < 360
	if not PlayerStats.is_off_screen(side, c):
		return "400px right should be off-screen at zoom (2, 1)"
	if PlayerStats.is_off_screen(down, c):
		return "300px down should stay on-screen at zoom (2, 1) (y unzoomed)"
	return ""


func test_flashlight() -> Variant:
	var c := Vector2(100, 100)
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	_add(p, c)
	p.aim_dir = Vector2.RIGHT
	var near := c + Vector2(80, 0)     # in cone, on-screen at zoom 3
	var mid := c + Vector2(250, 0)     # in light_range (260), off-screen at zoom 3 (250 > 213)
	if mid.distance_to(c) > PlayerStats.get_stat(&"light_range"):
		return "setup: mid point must be inside light_range"
	var err := _without_camera(func() -> String:
		if not p.lights(near) or not p.lights(mid):
			return "no camera: both points should be lit at zoom-1 fallback"
		return ""
	)
	if not err.is_empty():
		return err
	_cam(c, Vector2.ONE)
	if not p.lights(near) or not p.lights(mid):
		return "zoom 1: both points should be lit (cone unchanged)"
	_cam(c, Vector2(3, 3))
	if not p.lights(near):
		return "zoom 3: 80px point in the cone should stay lit"
	if p.lights(mid):
		return "zoom 3: 250px point is in light_range but off the zoomed view, so it must not be lit"
	return ""


func _drain_at(at: Vector2) -> float:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e, at)
	e.sight_override = 0
	e.tick(0.0)
	e.hear_noise()
	e._track_left = 0.0
	e.chase_speed = 0.0
	for i in 30:
		e.tick(DT)
	var lost: float = 1.0 - float(e.memory)
	if is_instance_valid(e) and e.get_parent():
		e.get_parent().remove_child(e)
		e.free()
	return lost


func test_mirror_drain() -> Variant:
	var c := Vector2(100, 100)
	var mid := c + Vector2(300, 0)   # on-screen at zoom 1, off-screen at zoom 3
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	_add(p, c)

	_cam(c, Vector2.ONE)
	if p == null:
		return "player missing"
	# Enemy.is_off_screen at zoom 1: mid is on-screen.
	var e1: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e1, mid)
	e1.sight_override = 0
	e1.tick(0.0)
	if e1.is_off_screen():
		return "zoom 1: 300px enemy should be on-screen"
	e1.get_parent().remove_child(e1)
	e1.free()

	var z1_plain := _drain_at(mid)
	PlayerStats.grant_item(ItemDb.make("cracked_mirror"))
	var z1_mirror := _drain_at(mid)
	if z1_plain <= 0.0:
		return "zoom 1: no drain"
	if absf(z1_mirror / z1_plain - 1.0) > 0.001:
		return "zoom 1: on-screen drain changed x%.3f with the mirror (want x1.0)" % (z1_mirror / z1_plain)
	PlayerStats.reset()

	_cam(c, Vector2(3, 3))
	var e3: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e3, mid)
	e3.sight_override = 0
	e3.tick(0.0)
	if not e3.is_off_screen():
		return "zoom 3: 300px enemy should be off-screen"
	e3.get_parent().remove_child(e3)
	e3.free()

	var z3_plain := _drain_at(mid)
	PlayerStats.grant_item(ItemDb.make("cracked_mirror"))
	var z3_mirror := _drain_at(mid)
	if z3_plain <= 0.0:
		return "zoom 3: no drain"
	if absf(z3_mirror / z3_plain - 1.4) > 0.02:
		return "zoom 3: off-screen drain x%.3f with the mirror, want 1.4" % (z3_mirror / z3_plain)
	return ""

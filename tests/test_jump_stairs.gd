extends RefCounted
## Jump + stairs (Lead's floor spec: 160px floors, gravity 980, jump 320 -> ~52px).

var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["jump_height_clears_prop_not_floor", test_jump_height],
		["no_jump_in_air", test_no_air_jump],
		["no_jump_while_picking_up", test_no_jump_pickup],
		["stairs_climb_to_next_floor", test_climb],
		["stairs_descend", test_descend],
		["topdown_mode_ignores_gravity", test_topdown],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		_clean()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"js_test"):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()


func _add(n: Node, at: Vector2) -> Node:
	n.set_meta(&"js_test", true)
	root.add_child(n)
	n.global_position = at
	return n


func _player(at := Vector2(100, 300)) -> CharacterBody2D:
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	p.side_scroll = true
	return _add(p, at)


## Integrates position by hand (no physics server step in tests); floor at start y.
func _sim_jump(p: CharacterBody2D) -> float:
	var floor_y := p.global_position.y
	var dt := 1.0 / 120.0
	p.floor_override = 1
	p.jump()
	p.tick(dt, Vector2.ZERO)
	p.floor_override = 0
	var peak := 0.0
	for i in 240:
		p.global_position += p.velocity * dt
		peak = maxf(peak, floor_y - p.global_position.y)
		if p.global_position.y >= floor_y and p.velocity.y > 0.0:
			break
		p.tick(dt, Vector2.ZERO)
	return peak


func test_jump_height() -> String:
	var h := _sim_jump(_player())
	if h < 32.0: return "jump %.1fpx can't clear a 32px prop" % h
	if h >= 160.0: return "jump %.1fpx reaches the next floor" % h
	return "" if absf(h - 52.0) < 6.0 else "jump %.1fpx, spec ~52" % h


func test_no_air_jump() -> String:
	var p := _player()
	p.floor_override = 0
	p.velocity = Vector2.ZERO
	p.jump(); p.tick(1.0 / 60.0, Vector2.ZERO)
	return "" if p.velocity.y >= 0.0 else "jumped in mid-air"


func test_no_jump_pickup() -> String:
	var p := _player()
	p.state = p.State.PICKUP
	p.floor_override = 1
	p.jump(); p.tick(1.0 / 60.0, Vector2.ZERO)
	return "" if p.velocity.y >= 0.0 else "jumped during pickup"


func _stair() -> Stair:
	var s: Stair = load("res://scripts/world/stair.gd").new()
	s.bottom = Vector2(0, 0)
	s.top = Vector2(96, -160)
	return _add(s, Vector2(100, 300))


func test_climb() -> String:
	var s := _stair()
	var p := _player(Vector2(100, 300))
	p.floor_override = 1
	p.tick(1.0 / 60.0, Vector2(0, -1))
	if p.state != p.State.CLIMB: return "did not start climbing"
	for i in 600:
		p.tick(1.0 / 60.0, Vector2(0, -1))
		if p.state != p.State.CLIMB: break
	if p.state == p.State.CLIMB: return "never reached top"
	return "" if p.global_position.distance_to(s.global_top()) < 2.0 else "ended at %s" % p.global_position


func test_descend() -> String:
	var s := _stair()
	var p := _player(s.global_top())
	p.floor_override = 1
	for i in 600:
		p.tick(1.0 / 60.0, Vector2(0, 1))
		if i > 0 and p.state != p.State.CLIMB: break
	return "" if p.global_position.distance_to(s.global_bottom()) < 2.0 else "ended at %s" % p.global_position


func test_topdown() -> String:
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	_add(p, Vector2(100, 100))
	p.floor_override = 0
	p.tick(0.5, Vector2.ZERO)
	return "" if p.velocity == Vector2.ZERO else "top-down player fell"

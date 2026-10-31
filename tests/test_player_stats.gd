extends RefCounted
## PlayerStats — Back End unit checks (QA owns acceptance).


func _make() -> Node:
	var s: Node = load("res://scripts/autoload/player_stats.gd").new()
	s.reset()
	return s


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["three_hits_dies", test_three_hits_dies],
		["no_damage_after_run_over", test_no_hit_after_run_over],
		["run_over_flag_win_death_reset", test_run_over_flag],
		["modifier_add_mul", test_modifier_add_mul],
		["remove_by_source", test_remove_by_source],
		["max_health_item", test_max_health_item],
		["gold_spend", test_gold_spend],
		["invuln_blocks_double_hit", test_invuln],
		["rejects_bad_values", test_bad_values],
		["invuln_expires_by_game_time", test_invuln_expires],
		["stat_floors", test_stat_floors],
		["stat_max_min_absolute_caps", test_stat_caps_abs],
		["input_bindings", test_bindings],
		["input_actions", test_input_actions],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func test_three_hits_dies() -> String:
	var s := _make()
	var dead := [false]
	s.died.connect(func() -> void: dead[0] = true)
	s.take_hit(1, true); s.take_hit(1, true)
	if dead[0]: s.free(); return "died after 2 hits"
	s.take_hit(1, true)
	var ok: bool = dead[0] and s.health == 0
	s.free()
	return "" if ok else "did not die on 3rd hit"


func test_modifier_add_mul() -> String:
	var s := _make()
	s.add_modifier(&"pickup_time", -0.2)
	s.add_modifier(&"pickup_time", 0.0, 0.5)
	var v: float = s.get_stat(&"pickup_time")
	s.free()
	return "" if is_equal_approx(v, 0.4) else "pickup_time want 0.4 got %s" % v


func test_remove_by_source() -> String:
	var s := _make()
	s.add_modifier(&"light_detect_mult", 0.0, 0.5, "dim_lens")
	s.remove_modifiers_from("dim_lens")
	var v: float = s.get_stat(&"light_detect_mult")
	s.free()
	return "" if is_equal_approx(v, 1.0) else "want 1.0 got %s" % v


func test_max_health_item() -> String:
	var s := _make()
	s.add_modifier(&"max_health", 1.0, 1.0, "heart")
	var ok: bool = s.max_health() == 4 and s.health == 4
	s.free()
	return "" if ok else "max_health item failed"


func test_gold_spend() -> String:
	var s := _make()
	s.add_gold(10)
	if s.try_spend(11): s.free(); return "overspent"
	var ok: bool = s.try_spend(10) and s.gold == 0
	s.free()
	return "" if ok else "spend failed"


func test_input_actions() -> String:
	for a in ["jump", "flashlight_toggle", "interact", "inv_next", "inv_prev", "move_left", "move_right"]:
		if not InputMap.has_action(a):
			return "missing input action %s" % a
	return ""


func test_invuln() -> String:
	var s := _make()
	var first: bool = s.take_hit()
	var second: bool = s.take_hit()
	var ok: bool = first and not second and s.health == 2
	s.free()
	return "" if ok else "second hit inside invuln_time landed"


func test_bad_values() -> String:
	var s := _make()
	s.take_hit(-2, true)
	s.add_gold(-5)
	var spent: bool = s.try_spend(-5)
	var ok: bool = s.health == 3 and s.gold == 0 and not spent
	s.free()
	return "" if ok else "bad values changed state"


func _bound(action: String, pred: Callable) -> bool:
	for e in InputMap.action_get_events(action):
		if pred.call(e):
			return true
	return false


func test_bindings() -> String:
	if not _bound("jump", func(e): return e is InputEventKey and e.physical_keycode == KEY_SPACE):
		return "jump not on Space"
	if not _bound("flashlight_toggle", func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT):
		return "flashlight not on RMB"
	if not _bound("interact", func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		return "interact not on LMB"
	if not _bound("inv_next", func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		return "inv_next not on wheel down"
	if not _bound("inv_prev", func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_UP):
		return "inv_prev not on wheel up"
	for pair in [["move_left", KEY_A], ["move_right", KEY_D], ["move_up", KEY_W], ["move_down", KEY_S],
			["move_left", KEY_LEFT], ["move_right", KEY_RIGHT]]:
		var code: int = pair[1]
		if not _bound(pair[0], func(e): return e is InputEventKey and e.physical_keycode == code):
			return "%s not on %s" % [pair[0], OS.get_keycode_string(code)]
	return ""


func test_invuln_expires() -> String:
	var s := _make()
	s.take_hit()
	s._process(0.5)
	if s.take_hit(): s.free(); return "hit landed at 0.5s of 1.0s invuln"
	s._process(0.6)
	var ok: bool = s.take_hit()
	s.free()
	return "" if ok else "invuln never expired"


func test_stat_floors() -> String:
	var s := _make()
	s.add_modifier(&"max_health", -5.0, 1.0, "curse")
	s.add_modifier(&"pickup_time", -2.0, 1.0, "curse")
	var ok: bool = s.max_health() >= 1 and s.health >= 1 and s.get_stat(&"pickup_time") > 0.0
	s.free()
	return "" if ok else "stats went below floors"


func test_no_hit_after_run_over() -> String:
	PlayerStats.reset(); GameState.reset()
	GameState.on_reach_exit()   # win / stage clear: run over
	var died := [false]
	var cb := func(): died[0] = true
	PlayerStats.died.connect(cb)
	var landed := PlayerStats.take_hit(3, true)
	PlayerStats.died.disconnect(cb)
	var hp := PlayerStats.health
	GameState.reset(); PlayerStats.reset()
	if landed or hp != 3: return "hit landed after run over (hp %d)" % hp
	if died[0]: return "died emitted after run over"
	return ""


func test_run_over_flag() -> String:
	GameState.reset(); PlayerStats.reset()
	GameState.on_reach_exit()
	if GameState.run_over: return "plain stage exit set run_over"
	GameState.reset()
	GameState.end_run_won()
	if not GameState.run_over: return "win did not set run_over"
	if PlayerStats.take_hit(1, true): return "hit landed after win"
	GameState.reset()
	if GameState.run_over: return "reset did not clear run_over"
	PlayerStats.take_hit(3, true)
	var ok := GameState.run_over
	GameState.reset(); PlayerStats.reset()
	return "" if ok else "death did not set run_over"


## Lead (#13): stat_max / stat_min return the bound in the stat's own units (STAT_BOUNDS rows are absolute; BASE when unbounded).
func test_stat_caps_abs() -> String:
	var ps: Script = load("res://scripts/autoload/player_stats.gd")
	for st in ps.STAT_BOUNDS:
		if not ps.BASE.has(st):
			continue
		var b: Array = ps.STAT_BOUNDS[st]
		if not is_equal_approx(ps.stat_max(st), float(b[1])) or not is_equal_approx(ps.stat_min(st), float(b[0])):
			return "%s: cap %s..%s vs bound %s" % [st, ps.stat_min(st), ps.stat_max(st), b]
	if not is_equal_approx(ps.stat_max(&"move_speed"), 280.0) or not is_equal_approx(ps.stat_min(&"move_speed"), 70.0):
		return "move_speed caps %s..%s, want 70..280" % [ps.stat_min(&"move_speed"), ps.stat_max(&"move_speed")]
	for st in ps.BASE:
		if not ps.STAT_BOUNDS.has(st) and (ps.stat_max(st) != float(ps.BASE[st]) or ps.stat_min(st) != float(ps.BASE[st])):
			return "unbounded %s should return BASE" % st
	return ""

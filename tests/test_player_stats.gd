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
		["modifier_add_mul", test_modifier_add_mul],
		["remove_by_source", test_remove_by_source],
		["max_health_item", test_max_health_item],
		["gold_spend", test_gold_spend],
		["invuln_blocks_double_hit", test_invuln],
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

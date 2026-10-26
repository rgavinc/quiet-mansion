extends RefCounted
## GameState acceptance — Quiet Mansion round 1.


func _make_state() -> Node:
	return load("res://scripts/autoload/game_state.gd").new()


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["enemy_count_is_live_no_constant", test_puppet_count],
		["reach_exit_wins", test_reach_exit_wins],
		["caught_loses", test_caught_loses],
		["game_over_lock", test_game_over_lock],
		["alert_count_is_live_no_cap", test_alert_caps_at_three],
		["reset", test_reset],
	]
	var passed := 0
	for item in checks:
		var res: Variant = item[1].call()
		var err: String = res if res is String else "script error (no result)"
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


## No hardcoded enemy count (PD: alerts derive from live enemies, not PUPPET_COUNT = 3).
func test_puppet_count() -> Variant:
	var s := _make_state()
	var has_const := "PUPPET_COUNT" in s or (s.get_script() as Script).get_script_constant_map().has("PUPPET_COUNT")
	var root := (Engine.get_main_loop() as SceneTree).root
	var es: Array = []
	for i in 4:
		var e: Node = load("res://scripts/enemies/puppet_hand.gd").new()
		root.add_child(e)
		es.append(e)
	if has_const or not s.has_method(&"enemy_count"):
		for e in es: e.free()
		s.free()
		return "PUPPET_COUNT still defined / no live enemy_count()"
	var n: int = s.enemy_count()
	es[0].free()
	var n2: int = s.enemy_count()
	for e in es.slice(1): e.free()
	s.free()
	if n != 4: return "enemy_count %d with 4 live enemies" % n
	return "" if n2 == 3 else "freed enemy still counted (%d)" % n2


func test_reach_exit_wins() -> String:
	var s := _make_state()
	var hit := [false]
	s.reached_exit.connect(func() -> void: hit[0] = true)
	s.on_reach_exit()
	if not hit[0] or not s.game_over:
		s.free(); return "expected exit win"
	s.free(); return ""


func test_caught_loses() -> String:
	var s := _make_state()
	var hit := [false]
	s.died.connect(func() -> void: hit[0] = true)
	s.on_caught()
	if not hit[0] or not s.game_over:
		s.free(); return "expected caught lose"
	s.free(); return ""


func test_game_over_lock() -> String:
	var s := _make_state()
	s.on_caught()
	var exits := [0]
	var deaths := [0]
	s.reached_exit.connect(func() -> void: exits[0] += 1)
	s.died.connect(func() -> void: deaths[0] += 1)
	s.on_reach_exit()
	s.on_caught()
	s.register_alert()
	if exits[0] != 0 or deaths[0] != 0 or s.alerted_puppets != 0:
		s.free(); return "state mutated after game over"
	s.free(); return ""


func test_alert_caps_at_three() -> Variant:
	var s := _make_state()
	var root := (Engine.get_main_loop() as SceneTree).root
	var es: Array = []
	var got := [-1]
	s.puppet_alerted.connect(func(n: int) -> void: got[0] = n)
	for i in 5:
		var e: Node = load("res://scripts/enemies/puppet_hand.gd").new()
		root.add_child(e)
		if e.has_method(&"hear_noise"): e.hear_noise()   # CHASE
		es.append(e)
		s.register_alert()
	var n: int = s.alerted_puppets
	var live: int = got[0]
	var after := -1
	var gone := -1
	if es[0].has_method(&"_enter_return"): es[0]._enter_return()
	if s.has_method(&"chasing_count"): after = s.chasing_count()
	for e in es: e.free()
	if s.has_method(&"chasing_count"): gone = s.chasing_count()
	s.free()
	if n != 5: return "want 5 chasing (no cap) got %s" % n
	if live != 5: return "puppet_alerted sent %s" % live
	if after != 4: return "gave-up enemy still counted (%d)" % after
	return "" if gone == 0 else "freed enemies still counted (%d)" % gone


func test_reset() -> String:
	var s := _make_state()
	s.register_alert()
	s.on_caught()
	s.reset()
	if s.game_over or s.alerted_puppets != 0:
		s.free(); return "reset failed"
	s.free(); return ""

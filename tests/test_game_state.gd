extends RefCounted
## GameState acceptance — Quiet Mansion round 1.


func _make_state() -> Node:
	return load("res://scripts/autoload/game_state.gd").new()


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["puppet_count", test_puppet_count],
		["reach_exit_wins", test_reach_exit_wins],
		["caught_loses", test_caught_loses],
		["game_over_lock", test_game_over_lock],
		["alert_caps_at_three", test_alert_caps_at_three],
		["reset", test_reset],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func test_puppet_count() -> String:
	var s := _make_state()
	if s.PUPPET_COUNT != 3:
		var msg := "PUPPET_COUNT want 3 got %s" % s.PUPPET_COUNT
		s.free(); return msg
	s.free(); return ""


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


func test_alert_caps_at_three() -> String:
	var s := _make_state()
	for i in 5:
		s.register_alert()
	if s.alerted_puppets != 3:
		var msg := "want alerted 3 got %s" % s.alerted_puppets
		s.free(); return msg
	s.free(); return ""


func test_reset() -> String:
	var s := _make_state()
	s.register_alert()
	s.on_caught()
	s.reset()
	if s.game_over or s.alerted_puppets != 0:
		s.free(); return "reset failed"
	s.free(); return ""

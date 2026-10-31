extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Quiet Mansion QA — round 1 ===")
	var total_passed := 0
	var total_checks := 0
	var all_fail: PackedStringArray = []
	for path in ["res://tests/test_game_state.gd", "res://tests/test_provenance.gd", "res://tests/test_player_stats.gd", "res://tests/test_fe_ui.gd", "res://tests/test_anim_library.gd", "res://tests/test_pickup_throw.gd", "res://tests/test_jump_stairs.gd", "res://tests/test_enemy_fsm.gd", "res://tests/test_items.gd", "res://tests/test_item_behaviors.gd", "res://tests/test_levelgen.gd"]:
		var script: Script = load(path)
		if script == null:
			printerr("FAIL: load ", path)
			quit(1)
			return
		var suite: RefCounted = script.new()
		var result: Dictionary = suite.run_all()
		total_passed += int(result["passed"])
		total_checks += int(result["total"])
		for f in result["failures"]:
			all_fail.append(f)
			printerr("FAIL: ", f)
	# Scene suites: real physics frames (await).
	for path in ["res://tests/scene_catch.gd", "res://tests/scene_enemy.gd", "res://tests/scene_rail.gd",
			"res://tests/scene_chase.gd", "res://tests/scene_determinism.gd"]:
		var ss: RefCounted = load(path).new()
		var r: Dictionary = await ss.run_async(self)
		total_passed += int(r["passed"])
		total_checks += int(r["total"])
		for f in r["failures"]:
			all_fail.append(f)
			printerr("FAIL: ", f)
	print("Result: %d / %d passed" % [total_passed, total_checks])
	if all_fail.size() > 0:
		quit(1)
		return
	print("ACCEPTANCE round 1 bar: GREEN")
	quit(0)

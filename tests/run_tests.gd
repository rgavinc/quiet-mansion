extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Quiet Mansion QA — round 1 ===")
	var total_passed := 0
	var total_checks := 0
	var all_fail: PackedStringArray = []
	for path in ["res://tests/test_game_state.gd", "res://tests/test_provenance.gd"]:
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
	print("Result: %d / %d passed" % [total_passed, total_checks])
	if all_fail.size() > 0:
		quit(1)
		return
	print("ACCEPTANCE round 1 bar: GREEN")
	quit(0)

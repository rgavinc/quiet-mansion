extends SceneTree
## Full layout-hash sweep: 200 seeds x 5 stages must match the PR #13 (f9b44d7) fixture exactly
## (the furniture / stage look work must never touch layouts, collision or validator hashes).
##   timeout 600 godot --headless -s res://tests/look_hash_sweep.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bad: PackedStringArray = (load("res://tests/look_hash.gd") as GDScript).check(200)
	print("LOOK HASH SWEEP: %d mismatches over 200 seeds x 5 stages" % bad.size())
	for b in bad.slice(0, 10):
		printerr("MISMATCH ", b)
	quit(1 if not bad.is_empty() else 0)

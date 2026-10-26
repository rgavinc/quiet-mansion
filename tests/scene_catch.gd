extends RefCounted
## Scene-level, REAL physics: main.gd-sized colliders, real frames. An enraged puppet
## must reach a standing boy and take a heart within 3 seconds.

func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var err: String = await _chase_takes_heart(tree)
	if not err.is_empty():
		failures.append("puppet_catch_real_physics: " + err)
	return {"passed": 1 - failures.size(), "total": 1, "failures": failures}


func _chase_takes_heart(tree: SceneTree) -> String:
	PlayerStats.reset(); GameState.reset()
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	var pc := CollisionShape2D.new(); var c1 := CircleShape2D.new(); c1.radius = 12; pc.shape = c1; p.add_child(pc)
	holder.add_child(p); p.global_position = Vector2(100, 100)
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	var ec := CollisionShape2D.new(); var c2 := CircleShape2D.new(); c2.radius = 14; ec.shape = c2; e.add_child(ec)
	holder.add_child(e); e.global_position = Vector2(220, 100)
	e._alert()
	var frames := 0
	var closest := 1e9
	while frames < 300:  # first hit within 3 s, then keep chasing to check bodies stay solid
		await tree.physics_frame
		frames += 1
		closest = minf(closest, e.global_position.distance_to(p.global_position))
		if frames == 180 and PlayerStats.health == 3: break
	var hp := PlayerStats.health
	var gap := e.global_position.distance_to(p.global_position)
	holder.queue_free()
	await tree.process_frame
	PlayerStats.reset(); GameState.reset()
	if hp == 3: return "no hit in 3s (gap %.1fpx)" % gap
	if closest < 20.0: return "puppet overlapped the boy (closest %.2fpx)" % closest
	return ""

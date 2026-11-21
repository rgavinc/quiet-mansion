extends SceneTree
## Headless stage-1 gold / obstacle screenshot. Not part of the game.
##   godot --headless --fixed-fps 60 --path . -s res://tools/capture_pickups.gd -- --tag=after --seed=3 --stage=1

const OUT_DIR := "res://docs/previews"


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var tag := "after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
	change_scene_to_file("res://scenes/main.tscn")
	for i in 24:
		await process_frame
	RenderingServer.force_draw()

	var player := get_first_node_in_group("player") as Node2D
	var golds := get_nodes_in_group("gold")
	var obstacles: Array = []
	for n in get_nodes_in_group("obstacles"):
		var sc: Script = n.get_script()
		if sc and str(sc.resource_path).ends_with("obstacle.gd"):
			obstacles.append(n)
	print("CAPTURE gold=%d obstacles=%d player=%s" % [golds.size(), obstacles.size(), player])

	_save("%s/stage1_seed3_full_%s.png" % [OUT_DIR, tag])

	var focus: Node2D = null
	if golds.size() > 0 and golds[0] is Node2D:
		focus = golds[0]
	elif obstacles.size() > 0 and obstacles[0] is Node2D:
		focus = obstacles[0]
	if player and focus:
		_frame(player, focus)
		for i in 16:
			await process_frame
		RenderingServer.force_draw()
		_save("%s/stage1_seed3_pickups_%s.png" % [OUT_DIR, tag])

	# Prefer an obstacle on the same floor as the gold we just framed.
	var obs: Node2D = null
	if focus:
		var best := 1e12
		for n in obstacles:
			if n is Node2D:
				var d: float = absf((n as Node2D).global_position.y - focus.global_position.y)
				var dist: float = (n as Node2D).global_position.distance_to(focus.global_position)
				if d < 24.0 and dist < best:
					best = dist
					obs = n
	if obs == null and obstacles.size() > 0 and obstacles[0] is Node2D:
		obs = obstacles[0]
	if player and obs:
		_frame(player, obs)
		for i in 12:
			await process_frame
		RenderingServer.force_draw()
		_save("%s/stage1_seed3_obstacles_%s.png" % [OUT_DIR, tag])

	print("CAPTURE_DONE ", tag)
	quit()


func _frame(player: Node2D, focus: Node2D) -> void:
	player.global_position = focus.global_position + Vector2(-48, -8)
	if "velocity" in player:
		player.velocity = Vector2.ZERO
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.zoom = Vector2(3, 3)
		cam.position_smoothing_enabled = false
		cam.reset_smoothing()
		cam.force_update_scroll()
	if player.has_method("toggle_light") and player.has_method("light_on"):
		if not player.light_on():
			player.toggle_light()
		var light := player.get_node_or_null("Flashlight") as Node2D
		if light:
			light.rotation = 0.0
		if "aim_dir" in player:
			player.aim_dir = Vector2.RIGHT


func _save(res_path: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	img.save_png(path)
	print("CAPTURE_SAVED ", path, " ", img.get_width(), "x", img.get_height())

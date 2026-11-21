extends RefCounted
## FE dark-stage glints on REAL built levels (main.tscn): the overlay node exists, is active on
## dark stages and silent on bright ones, only ever draws for puppets outside the light, and the
## seed readout keeps its high-contrast style in the real HUD.

const SC := preload("res://tests/scene_camera.gd")


func run_async(tree: SceneTree) -> Dictionary:
	var failures: PackedStringArray = []
	var helper := SC.new()
	var checks := [
		["dark_stage_draws_only_unlit_puppets", _dark_stage],
		["bright_stage_draws_nothing", _bright_stage],
		["real_hud_readout_is_opaque_outlined", _readout],
	]
	for c in checks:
		var err: String = await c[1].call(tree, helper)
		if not err.is_empty():
			failures.append("glints %s: %s" % [c[0], err])
	helper._reset()
	return {"passed": checks.size() - failures.size(), "total": checks.size(), "failures": failures}


func _dg(m: Node) -> Node2D:
	return m.get_node("World/WorldOverlay/OverlayLayer/DarkGlints") as Node2D


func _dark_stage(tree: SceneTree, h: RefCounted) -> String:
	var m: Node = await h._boot(tree, 7, 5, 4)
	var err := ""
	var dg := _dg(m)
	var enemies := tree.get_nodes_in_group("enemies")
	if dg == null:
		err = "DarkGlints missing from WorldOverlay"
	elif not dg.darkness_active():
		err = "stage 5 should be a dark stage"
	elif enemies.is_empty():
		err = "fixture: stage 5 seed 7 has enemies"
	else:
		# Unlit puppets: one plan entry set each; lit ones: none. Compare against the light query.
		var want_unlit := 0
		for e in enemies:
			var a := e.get_node_or_null("Anim") as AnimatedSprite2D
			if a != null and e.visible and not e.is_queued_for_deletion() and not dg.is_lit(a.global_position):
				want_unlit += 1
		var plan: Dictionary = dg.plan()
		if plan.silhouettes.size() != want_unlit:
			err = "silhouettes %d, unlit puppets %d" % [plan.silhouettes.size(), want_unlit]
		elif want_unlit == 0 and not plan.glints.is_empty():
			err = "glints drawn with every puppet lit"
		elif plan.glints.size() > 2 * want_unlit:
			err = "more than two glints per unlit puppet"
		for g in plan.glints:
			if not (g.slot in ["vfx_eye_glint", "vfx_eye_glint_calm"]):
				err = "unexpected glint slot %s" % g.slot
	await h._unload(tree, m)
	return err


func _bright_stage(tree: SceneTree, h: RefCounted) -> String:
	var m: Node = await h._boot(tree, 1, 1, 4)
	var err := ""
	var dg := _dg(m)
	if dg == null:
		err = "DarkGlints missing"
	elif dg.darkness_active():
		err = "stage 1 must not be active"
	elif not (dg.plan().glints.is_empty() and dg.last_draw.glints.is_empty() and dg.last_draw.silhouettes.is_empty()):
		err = "stage 1 drew something"
	await h._unload(tree, m)
	return err


func _readout(tree: SceneTree, h: RefCounted) -> String:
	var m: Node = await h._boot(tree, 7, 5)
	var ro: Label = m.get_node("HUD/HudRoot/SeedReadout")
	var err := ""
	if ro.get_theme_color("font_color").a < 1.0:
		err = "readout text alpha %.2f, want fully opaque" % ro.get_theme_color("font_color").a
	elif ro.get_theme_constant("outline_size") < 4 or ro.get_theme_color("font_outline_color").a < 1.0:
		err = "readout lacks its dark outline"
	await h._unload(tree, m)
	return err

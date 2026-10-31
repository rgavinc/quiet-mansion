extends RefCounted
## LevelGenerator / LevelValidator / LevelNav / StageTable (docs/LEVELGEN.md). Lead owns.

var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["deterministic_same_seed", test_deterministic],
		["different_seeds_differ", test_seeds_differ],
		["stage1_layouts_valid", test_stage1_valid],
		["all_stages_generate_valid", test_all_stages],
		["stage_table_walk_only_until_4", test_movement_tiers],
		["stairs_join_adjacent_floors", test_stair_floors],
		["rejects_unreachable_exit", test_reject_unreachable],
		["rejects_bad_stair_floors", test_reject_bad_stair],
		["stairs_are_15_tile_diagonals_with_landings", test_stair_shape],
		["rejects_wrong_stair_run", test_reject_stair_run],
		["rejects_blocked_stair_landings", test_reject_stair_landing],
		["rejects_overlapping_stairs", test_reject_stair_overlap],
		["rooms_fit_a_stair", test_rooms_fit_stair],
		["stair_placement_matches_design_doc", test_stair_placement],
		["rejects_objects_over_slab_cutout", test_reject_cutout],
		["rejects_stair_off_tile_edges", test_reject_stair_tile_edge],
		["route_never_crosses_slab_cutout", test_cutout_splits_floor],
		["build_cuts_slab_and_paints_atlas", test_build_cutout],
		["stage_count_is_table_size", test_stage_count],
		["rejects_layout_off_stage_table", test_reject_off_table],
		["rejects_loot_on_stair_landings", test_reject_loot_on_landing],
		["enemies_are_enemydefs_at_table_count", test_enemy_defs],
		["stair_openings_have_gallery_rails", test_gallery_rails],
		["fallbacks_match_stage_table_and_are_only_last_resort", test_fallback_table],
		["rejects_enemy_near_start", test_reject_enemy_near],
		["rejects_enemy_within_a_screen_any_floor", test_reject_enemy_other_floor],
		["rejects_enemy_on_start_screen", test_reject_enemy_on_screen],
		["line_of_sight_blocked_by_walls", test_los],
		["rejects_exit_on_start_floor", test_reject_exit_same_floor],
		["rejects_fewer_than_3_floors", test_reject_two_floors],
		["rejects_prop_without_jump_lane", test_reject_prop_lane],
		["prop_jump_clears_with_player_physics", test_prop_jump],
		["rejects_overlapping_objects", test_reject_overlap],
		["rejects_short_content_budget", test_reject_budget],
		["stage1_size_and_floors", test_stage1_shape],
		["identical_rebuild_per_seed", test_build_deterministic],
		["main_respects_fe_seed_and_stage", test_main_fe_contract],
		["rejects_out_of_bounds", test_reject_oob],
		["rejects_tall_jump_only_path", test_reject_tall_block],
		["rejects_empty_or_null", test_reject_empty],
		["fallback_is_valid", test_fallback_valid],
		["fallback_after_zero_attempts", test_fallback_zero],
		["fallback_on_impossible_params", test_fallback_impossible],
		["nav_routes_via_stairs", test_nav_route],
		["nav_target_on_stair_climbs_that_stair", test_nav_on_stair],
		["nav_never_gives_up_across_floors", test_nav_cross_floor],
		["rejects_unreachable_walker", test_reject_unreachable_walker],
		["stair_upper_entry_only_from_top_landing", test_stair_upper_entry],
		["stair_trigger_never_inside_the_floor_above", test_stair_band_trigger],
		["nav_routes_by_distance_not_stair_count", test_nav_distance_route],
		["rails_cannot_be_cleared_by_capped_running_jumps", test_rail_jump_rule],
		["rejects_furniture_a_capped_jump_clears_a_rail_from", test_reject_furniture_rail],
		["gold_floor_and_worst_roll_vs_cheapest_shop_item", test_gold_floor],
		["layouts_are_deterministic_across_two_runs", test_layout_determinism],
		["sprite_choice_never_changes_the_layout", test_sprite_stream_separate],
		["sprite_row0_sits_on_the_collision_top_for_all_slots", test_sprite_row0_on_collision_top],
		["tall_piece_mount_rule", test_mount_rule],
		["every_floor_has_a_reachable_climbable_piece", test_floors_have_mountable],
		["nav_target_on_a_tall_piece_routes_directly_from_either_side", test_nav_on_piece],
		["furniture_falls_back_to_rects_without_slots", test_furniture_fallback],
		["furniture_sprites_by_height_class_separate_stream", test_furniture_sprites],
		["furniture_slot_art_matches_collision_height", test_furniture_art_contract],
		["stage_look_table_applied_darker_and_colder", test_stage_look],
		["build_survives_bad_input", test_build_bad_input],
		["build_creates_level_nodes", test_build_nodes],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		_clean()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"lg_test"):
			root.remove_child(c)
			c.free()
	LevelNav.current = null
	PlayerStats.reset()
	GameState.reset()


func _strip(L: Dictionary) -> String:
	var d := L.duplicate(true)
	d.erase("reject_reasons")
	return var_to_str(d)


func test_deterministic() -> String:
	for s in [0, 1, 42, 99991]:
		if _strip(LevelGenerator.generate(s, 1)) != _strip(LevelGenerator.generate(s, 1)):
			return "seed %d produced two different layouts" % s
	return ""


func test_seeds_differ() -> String:
	return "" if _strip(LevelGenerator.generate(1, 1)) != _strip(LevelGenerator.generate(2, 1)) else "seeds 1 and 2 identical"


func test_stage1_valid() -> String:
	for s in 40:
		var L := LevelGenerator.generate(s, 1)
		var e := LevelValidator.validate(L)
		if not e.is_empty():
			return "seed %d: %s" % [s, e[0]]
		if L.enemies.size() != StageTable.budget(1).enemies:
			return "seed %d: stage 1 enemies %d" % [s, L.enemies.size()]
	return ""


func test_stage1_shape() -> String:
	for s in 40:
		var L := LevelGenerator.generate(s, 1)
		if int(L.floors) < 3:
			return "seed %d: %d floors" % [s, L.floors]
		if absi(int(L.width_tiles) - 240) > 8:
			return "seed %d: %d tiles wide, want ~240 (3 screens)" % [s, L.width_tiles]
		if LevelValidator.floor_of(L.exit.y) == LevelValidator.floor_of(L.start.y):
			return "seed %d: exit on the start floor" % s
		if L.budget != StageTable.budget(1):
			return "seed %d: budget %s" % [s, L.budget]
	return ""


func test_all_stages() -> String:
	for st in range(1, StageTable.stage_count() + 1):
		for s in 5:
			var e := LevelValidator.validate(LevelGenerator.generate(s, st))
			if not e.is_empty():
				return "stage %d seed %d: %s" % [st, s, e[0]]
	return ""


func test_movement_tiers() -> String:
	for st in range(1, StageTable.stage_count() + 1):
		for id in StageTable.params(st).enemy_weights:
			var mv := StageTable.movement_for(id)
			if st <= 3 and mv != &"walk":
				return "stage %d has %s enemy %s" % [st, mv, id]
	for s in 30:
		for st in [1, 2, 3]:
			for e in LevelGenerator.generate(s, st).enemies:
				if e.movement != &"walk":
					return "stage %d seed %d rolled a %s enemy" % [st, s, e.movement]
	var floats := 0
	for id in StageTable.params(5).enemy_weights:
		floats += 1 if StageTable.movement_for(id) == &"float" else 0
	return "" if floats > 0 else "stage 5 has no float tier"


func test_stair_floors() -> String:
	for s in 20:
		var L := LevelGenerator.generate(s, 5)
		for st in L.stairs:
			if int(st.to_floor) != int(st.from_floor) + 1 or int(st.to_floor) >= int(L.floors):
				return "seed %d stair %d->%d" % [s, st.from_floor, st.to_floor]
			if not is_equal_approx(st.top.y - st.bottom.y, -160.0):
				return "stair rises %s, not one floor" % (st.bottom.y - st.top.y)
	return ""


func _has(errs: PackedStringArray, needle: String) -> bool:
	for e in errs:
		if needle in e:
			return true
	return false


func test_reject_unreachable() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.stairs = []
	return "" if _has(LevelValidator.validate(L), "exit not reachable") else "stairless 2-floor layout passed"


func test_reject_bad_stair() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.stairs[0].to_floor = 3
	if not _has(LevelValidator.validate(L), "doesn't exist"):
		return "stair to a missing floor passed"
	L = LevelGenerator.fallback_layout(1)
	L.stairs[0].from_floor = 1
	L.stairs[0].to_floor = 0
	return "" if _has(LevelValidator.validate(L), "adjacent") else "reversed stair passed"


func test_reject_enemy_near() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.enemies[0].pos = L.start + Vector2(200, 0)
	return "" if _has(LevelValidator.validate(L), "too close to start") else "enemy 200px from start passed"


func test_reject_enemy_other_floor() -> String:
	# 1100px away, two floors up: still within one screen of the start
	var L := LevelGenerator.fallback_layout(1)
	L.enemies[0].pos = Vector2(L.start.x + 1050, LevelValidator.surface_y(2))
	return "" if _has(LevelValidator.validate(L), "too close to start") else "enemy within a screen on another floor passed"


func test_reject_enemy_on_screen() -> String:
	# 4 floors: top-floor corner of the start view is > 1280px away but still on screen
	var L := LevelGenerator.fallback_layout(3)
	var p := Vector2(1260, LevelValidator.surface_y(3))
	if p.distance_to(L.start) < 1280.0:
		return "test point too close (%d)" % p.distance_to(L.start)
	L.enemies[0].pos = p
	return "" if _has(LevelValidator.validate(L), "on screen") else "on-screen enemy passed"


func test_los() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var a := Vector2(100, 0)
	var b := Vector2(1000, 0)
	if not LevelValidator.in_line_of_sight(L, a, b):
		return "doorways should not block sight"
	L.walls[1].doorway = false
	if LevelValidator.in_line_of_sight(L, a, b):
		return "solid wall should block sight"
	return "" if not LevelValidator.in_line_of_sight(L, a, Vector2(1000, -160)) else "other floor should not be in sight"


func test_reject_exit_same_floor() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.exit = Vector2(L.exit.x, 0)
	return "" if _has(LevelValidator.validate(L), "exit is on the start floor") else "exit on start floor passed"


func test_reject_two_floors() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.floors = 2
	return "" if _has(LevelValidator.validate(L), "floors 2 outside") else "2-floor level passed"


func test_reject_prop_lane() -> String:
	var L := LevelGenerator.fallback_layout(1)
	# hard against a doorway wall: can't jump it (lintel), so walking through would break it
	L.props[0].pos = Vector2(40 * 16 + 40, LevelValidator.surface_y(LevelValidator.floor_of(L.props[0].pos.y)))
	if not _has(LevelValidator.validate(L), "no jump lane"):
		return "prop next to a doorway passed"
	L = LevelGenerator.fallback_layout(1)
	var q: Vector2 = L.props[0].pos
	L.props.append({type = "vase", pos = q + Vector2(30, 0)})   # two props closer than a jump
	L.budget.props += 1
	return "" if _has(LevelValidator.validate(L), "no jump lane") else "back-to-back props passed"


func test_prop_jump() -> String:
	var ps := root.get_node("PlayerStats")
	var sp: float = ps.get_stat(&"move_speed")
	var jv: float = ps.get_stat(&"jump_velocity")
	var g: float = ps.get_stat(&"gravity")
	var v := Vase.new()
	var touch := v.touch_radius
	v.free()
	if not LevelValidator.prop_jump_clears(sp, jv, g, touch):
		return "player can't jump a prop within PROP_LANE (%d px)" % LevelValidator.PROP_LANE
	if LevelValidator.prop_jump_clears(sp, jv * 0.3, g, touch):
		return "a tiny hop shouldn't clear a prop"
	return ""


func test_reject_overlap() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.gold[0].pos = L.enemies[0].pos + Vector2(6, -4)
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "gold on an enemy passed"
	L = LevelGenerator.fallback_layout(1)
	L.enemies[1].pos = L.stairs[0].bottom + Vector2(-20, 0)
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "enemy on a stair passed"
	L = LevelGenerator.fallback_layout(1)
	L.enemies[1].pos = L.exit + Vector2(10, 0)
	return "" if _has(LevelValidator.validate(L), "overlaps") else "enemy on the exit passed"


func test_reject_budget() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.props.pop_back()
	if not _has(LevelValidator.validate(L), "budget"):
		return "short props passed"
	L = LevelGenerator.fallback_layout(1)
	L.enemies.pop_back()
	return "" if _has(LevelValidator.validate(L), "budget") else "short enemies passed"


func test_reject_oob() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.props.append({type = "vase", pos = Vector2(-50, 0)})
	if not _has(LevelValidator.validate(L), "out of bounds"):
		return "prop at x=-50 passed"
	L = LevelGenerator.fallback_layout(1)
	L.exit = Vector2(200, -900)
	return "" if _has(LevelValidator.validate(L), "out of bounds") else "exit above the roof passed"


func test_reject_tall_block() -> String:
	var L := LevelGenerator.fallback_layout(1)
	# a 2-wide block on the ground floor between start and the only up-stair, somewhere clear
	var sx: float = L.stairs[0].bottom.x
	for tx in range(6, int(sx / 16.0) - 6):
		var T := L.duplicate(true)
		T.furniture.append({floor = 0, x = tx, w = 2, h = 2})   # jumpable
		if not LevelValidator.validate(T).is_empty():
			continue
		T.furniture[-1].h = 4   # 4 tiles: can't be jumped or climbed
		return "" if _has(LevelValidator.validate(T), "exit not reachable") else "4-tile block on the only path passed"
	return "no clear spot for the test block"


func test_reject_empty() -> String:
	for bad in [null, {}, {"floors": 2}, [], "x"]:
		if LevelValidator.validate(bad).is_empty():
			return "%s passed" % [bad]
	return ""


func test_fallback_valid() -> String:
	for st in range(1, 6):
		var e := LevelValidator.validate(LevelGenerator.fallback_layout(st))
		if not e.is_empty():
			return "stage %d fallback: %s" % [st, e[0]]
	return ""


func test_fallback_zero() -> String:
	var L := LevelGenerator.generate(5, 1, {max_attempts = 0})
	return "" if L.fallback and LevelValidator.validate(L).is_empty() else "no fallback with 0 attempts"


func test_fallback_impossible() -> String:
	# every interior wall solid and no stairs: the top floor can never be reached
	var L := LevelGenerator.generate(5, 1, {params = {solid_wall_chance = 1.0, stairs_per_link = [0, 0], furniture_chance = 1.0, tall_furniture_chance = 1.0}})
	if not L.fallback:
		# the repair pass may still connect it; then it must be valid
		return "" if LevelValidator.validate(L).is_empty() else "invalid layout returned"
	if int(L.rerolls) != LevelGenerator.MAX_ATTEMPTS or L.reject_reasons.size() != LevelGenerator.MAX_ATTEMPTS:
		return "fallback after %d rerolls" % L.rerolls
	return "" if LevelValidator.validate(L).is_empty() else "fallback invalid"


## Route gap (QA, PR #13): the boy on a stair (mid-climb) used to map to the floor below or above,
## so walkers parked directly under / over him. A target on stair si routes to si's nearer
## landing and climbs si, from either floor.
func test_nav_on_stair() -> String:
	for sd in [1003, 1030, 11]:
		for st in [1, 3, 5]:
			var L := LevelGenerator.generate(sd, st)
			var nav := LevelNav.from_layout(L)
			for i in L.stairs.size():
				var s: Dictionary = L.stairs[i]
				for t in [0.3, 0.7]:
					var on: Vector2 = (s.bottom as Vector2).lerp(s.top, t)
					if nav.stair_at(on) != i:
						return "seed %d stage %d: stair_at(%s) = %d, want %d" % [sd, st, on, nav.stair_at(on), i]
					for end in [s.bottom, s.top]:
						var d := 1.0 if end == s.bottom else -1.0
						var a: Vector2 = end - Vector2(signf((s.top as Vector2).x - (s.bottom as Vector2).x) * d * 40.0, 0)
						if nav.route(a, end) == null or not (nav.route(a, end) as Array).is_empty():
							continue   # 40px off the landing isn't the landing's segment here
						var wp := nav.next_waypoint(a, on)
						if wp.get("stair") != s or not wp.has("stair_to"):
							return "seed %d stage %d stair %d: from %s to on-stair %s gave %s" % [sd, st, i, a, on, wp]
	return ""


## Whenever a route exists and the floors differ, next_waypoint is a stair hop (never {} / a park).
func test_nav_cross_floor() -> String:
	for sd in 10:
		for st in [1, 3, 5]:
			var L := LevelGenerator.generate(sd, st)
			var nav := LevelNav.from_layout(L)
			var g := LevelValidator.floor_graph(L)
			var pts: Array = [L.start, L.exit]
			for e in L.enemies:
				pts.append(e.pos)
			for a in pts:
				for b in pts:
					if nav.floor_of(a) == nav.floor_of(b) or nav.route(a, b) == null:
						continue
					var wp := nav.next_waypoint(a, b)
					if not wp.has("stair_to"):
						return "seed %d stage %d: %s -> %s (floors %d -> %d) gave %s" % [sd, st, a, b, nav.floor_of(a), nav.floor_of(b), wp]
	return ""


## Walkers must spawn where they can walk to the boy: a walker in a sealed segment is rejected.
func test_reject_unreachable_walker() -> String:
	for sd in 40:
		for st in [3, 4, 5]:
			var L := LevelGenerator.generate(sd, st)
			var g := LevelValidator.floor_graph(L)
			var reach := LevelValidator.reachable_from(g, LevelValidator.node_at(g.segments, LevelValidator.floor_of(L.start.y), L.start.x))
			for f in g.segments:
				for seg in g.segments[f]:
					var mid: float = ((seg as Vector2).x + (seg as Vector2).y) * 0.5
					if reach.has(LevelValidator.node_at(g.segments, f, mid)):
						continue
					for e in L.enemies:
						if StringName(e.movement) != &"float":
							var T := L.duplicate(true)
							for e2 in T.enemies:
								if e2.pos == e.pos:
									e2.pos = Vector2(mid, LevelValidator.surface_y(f))
									break
							return "" if _has(LevelValidator.validate(T), "not reachable from the start") else "walker in sealed segment %s:%s passed" % [f, seg]
	return "no level with a sealed segment found (test needs another seed range)"


## QA B2: on the upper floor a LevelStair accepts only the top-landing side, never the gallery
## behind the far wall; lower floor and stair line unchanged (BE Stair).
func test_stair_upper_entry() -> String:
	for s in LevelGenerator.fallback_layout(1).stairs + LevelGenerator.generate(1003, 3).stairs:
		var b: Vector2 = s.bottom
		var t: Vector2 = s.top
		var d := signf(t.x - b.x)
		if not LevelStair.upper_entry_ok(b, t, t + Vector2(d * 20.0, 0)):
			return "top landing refused for %s" % [s]
		if LevelStair.upper_entry_ok(b, t, t - Vector2(d * 200.0, 0)):
			return "gallery side accepted for %s" % [s]
		if not LevelStair.upper_entry_ok(b, t, b - Vector2(d * 10.0, 0)):
			return "lower floor refused for %s" % [s]
	return ""


func test_nav_route() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var nav := LevelNav.from_layout(L)
	var wp := nav.next_waypoint(L.start, L.exit)
	if not wp.has("stair_to") or wp.point != L.stairs[0].bottom or wp.stair_to != L.stairs[0].top:
		return "start->exit should go to the stair bottom first: %s" % wp
	var down := nav.next_waypoint(L.exit, L.start)
	if down.get("point") != L.stairs[-1].top:
		return "exit->start should go to the last stair's top: %s" % down
	var same := nav.next_waypoint(L.start, Vector2(400, 0))
	if same.has("stair_to") or same.get("point") != Vector2(400, 0):
		return "same-floor route should be direct: %s" % same
	var r: Variant = nav.route(L.start, L.exit)
	if not (r is Array) or (r as Array).size() != int(L.floors) - 1:
		return "route length %s" % [r]
	L.stairs = []
	if not LevelNav.from_layout(L).next_waypoint(L.start, L.exit).is_empty():
		return "unreachable target should give {}"
	return ""


func test_build_bad_input() -> String:
	if not LevelGenerator.build({}, null).is_empty():
		return "null world should give {}"
	var w := Node2D.new()
	w.set_meta(&"lg_test", true)
	root.add_child(w)
	var b := LevelGenerator.build({"floors": 99}, w)   # invalid -> fallback
	if b.is_empty() or b.player == null or LevelNav.current == null:
		return "invalid layout didn't build the fallback"
	return ""


func test_build_nodes() -> String:
	var w := Node2D.new()
	w.set_meta(&"lg_test", true)
	root.add_child(w)
	var L := LevelGenerator.generate(3, 1)
	var b := LevelGenerator.build(L, w)
	if b.stairs.size() != L.stairs.size() or b.enemies.size() != L.enemies.size():
		return "node counts don't match layout"
	if not b.player.get("side_scroll"):
		return "player not side_scroll"
	for st in b.stairs:
		if not st.is_in_group("stairs") or st.to_floor != st.from_floor + 1:
			return "stair node wrong"
	for e in b.enemies:
		if e.get_meta("movement", &"") != &"walk":
			return "enemy movement meta missing"
	if LevelNav.current != b.nav:
		return "LevelNav.current not set"
	w.free()
	return "" if LevelNav.current == null else "LevelNav.current outlived its level"


## Signature of every node a build makes (type, script, position, hidden vase gold).
func _build_sig(seed_value: int, stage: int) -> String:
	var w := Node2D.new()
	w.set_meta(&"lg_test", true)
	root.add_child(w)
	LevelGenerator.build(LevelGenerator.generate(seed_value, stage), w)
	var out := PackedStringArray()
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var line := "%s|%s|%s" % [n.get_class(), n.get_script().resource_path if n.get_script() else "", w.get_path_to(n)]
		if n is Node2D:
			line += "|%s" % (n as Node2D).position
		if n is WorldObject:
			line += "|g%d" % n.gold_inside
		out.append(line)
		stack.append_array(n.get_children())
	w.free()
	out.sort()
	return "\n".join(out)


func test_build_deterministic() -> String:
	for st in [1, 5]:
		for s in [3, 77]:
			var a := _build_sig(s, st)
			var b := _build_sig(s, st)
			if a != b:
				return "stage %d seed %d built differently twice" % [st, s]
	return ""


## FE #16 contract: level_seed/stage set on the instance win; -1 rolls a seed; stage past the
## table plays the last stage; no capped "/ 3" alert text.
func test_main_fe_contract() -> String:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var cases := [[4242, 2, 2], [-1, 1, 1], [77, 7, StageTable.stage_count()]]
	for c in cases:
		var m := packed.instantiate()
		m.set("level_seed", c[0])
		m.set("stage", c[1])
		root.add_child(m)
		var L: Dictionary = m.get("layout")
		var got_seed: int = m.get("level_seed")
		var got_stage: int = m.get("stage")
		m.free()
		LevelNav.current = null
		root.get_node("GameState").reset()
		if c[0] >= 0 and got_seed != c[0]:
			return "FE seed %d overridden -> %d" % [c[0], got_seed]
		if got_seed < 0:
			return "-1 should roll a seed"
		if got_stage != c[1]:
			return "FE stage %d overridden -> %d" % [c[1], got_stage]
		if int(L.stage) != c[2]:
			return "stage %d built layout stage %d" % [c[1], L.stage]
	if "/ 3" in FileAccess.get_file_as_string("res://scripts/map/main.gd"):
		return "capped alert text still in main.gd"
	return ""


func test_stair_shape() -> String:
	if LevelValidator.STAIR_RUN_PX != 240.0 or LevelValidator.STAIR_LANDING_PX != 48.0 or LevelValidator.STAIR_FOOTPRINT_PX != 336.0:
		return "stair numbers changed (run 240, landing 48, footprint 336)"
	for st in range(1, 6):
		for sd in 25:
			var L := LevelGenerator.generate(sd, st)
			for s in L.stairs:
				if absf(s.top.x - s.bottom.x) != 240.0 or s.bottom.y - s.top.y != 160.0:
					return "stage %d seed %d stair %s->%s not 240x160" % [st, sd, s.bottom, s.top]
				var sp := LevelValidator.stair_span(s)
				if sp.y - sp.x != 336.0:
					return "footprint %s" % sp
				var land: Array = LevelValidator.stair_landings(s)
				for k in 2:
					if land[k].b - land[k].a != 48.0:
						return "landing %s" % land[k]
				# bottom landing lies away from the run, top landing beyond the top point
				var d := signf(s.top.x - s.bottom.x)
				if signf(land[0].a + 24.0 - s.bottom.x) != -d or signf(land[1].a + 24.0 - s.top.x) != d:
					return "landings on the wrong side"
				for o in LevelValidator.occupants(L):
					if o.what != "stair" and o.floor in [int(s.from_floor), int(s.to_floor)] and o.b > sp.x and o.a < sp.y:
						return "stage %d seed %d: %s on a stair footprint" % [st, sd, o.what]
	return ""


func test_reject_stair_run() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.stairs[0].top.x = L.stairs[0].bottom.x - 64.0   # the old steep 4-tile stair
	return "" if _has(LevelValidator.validate(L), "must be 240px") else "4-tile stair passed"


func test_reject_stair_landing() -> String:
	var s: Dictionary = LevelGenerator.fallback_layout(1).stairs[0]
	var land: Array = LevelValidator.stair_landings(s)
	# a puppet on the top landing
	var L := LevelGenerator.fallback_layout(1)
	L.enemies[0].pos = Vector2((land[1].a + land[1].b) / 2.0, LevelValidator.surface_y(int(s.to_floor)))
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "puppet on the top landing passed"
	# a vase on the bottom landing
	L = LevelGenerator.fallback_layout(1)
	L.props[0].pos = Vector2((land[0].a + land[0].b) / 2.0, LevelValidator.surface_y(int(s.from_floor)))
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "prop on the bottom landing passed"
	# a doorway under a landing
	L = LevelGenerator.fallback_layout(1)
	L.walls.append({floor = int(s.to_floor), x = int(land[1].a / 16.0) + 1, doorway = true})
	return "" if _has(LevelValidator.validate(L), "blocked by a wall, doorway") else "doorway on a landing passed"


func test_reject_stair_overlap() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var s: Dictionary = L.stairs[0].duplicate()
	s.bottom += Vector2(-96, 0)
	s.top += Vector2(-96, 0)
	L.stairs.append(s)
	return "" if _has(LevelValidator.validate(L), "overlaps") else "overlapping stairs passed"


func test_rooms_fit_stair() -> String:
	for st in range(1, 6):
		for sd in 25:
			for r in LevelGenerator.generate(sd, st).rooms:
				if int(r.x1) - int(r.x0) < 24:
					return "stage %d seed %d room %d tiles" % [st, sd, int(r.x1) - int(r.x0)]
	var L := LevelGenerator.fallback_layout(1)
	L.rooms[0].x1 = 20
	return "" if _has(LevelValidator.validate(L), "24-40") else "20-tile room passed"


## docs/DESIGN.md: leftmost tile x; bottom = x+3 (lower floor), top = x+18 (upper floor);
## cutout x+9..x+17 rising right, columns mirrored (x+3..x+11) rising left.
func test_stair_placement() -> String:
	var dirs := {}
	for st in range(1, 6):
		for sd in 25:
			for s in LevelGenerator.generate(sd, st).stairs:
				var x := LevelValidator.stair_x(s)
				var right: bool = s.top.x > s.bottom.x
				dirs[right] = true
				var bx := (x + 3) * 16.0 if right else (x + 18) * 16.0
				var tx := (x + 18) * 16.0 if right else (x + 3) * 16.0
				if s.bottom.x != bx or s.top.x != tx:
					return "stage %d seed %d stair x=%d ends %s/%s" % [st, sd, x, s.bottom.x, s.top.x]
				var h := LevelValidator.stair_hole(s)
				var hx := (x + 9) * 16.0 if right else (x + 3) * 16.0
				if h.x != hx or h.y - h.x != 144.0:
					return "stage %d seed %d hole %s (want %d..%d)" % [st, sd, h, int(hx), int(hx) + 144]
	return "" if dirs.size() == 2 else "stairs only rise one way"


func test_reject_cutout() -> String:
	var s: Dictionary = LevelGenerator.fallback_layout(1).stairs[0]
	var h := LevelValidator.stair_hole(s)
	var at := Vector2((h.x + h.y) / 2.0, LevelValidator.surface_y(int(s.to_floor)))
	var L := LevelGenerator.fallback_layout(1)
	L.props[0].pos = at
	if not _has(LevelValidator.validate(L), "slab cutout"):
		return "prop over the cutout passed"
	L = LevelGenerator.fallback_layout(1)
	L.enemies[0].pos = at
	return "" if _has(LevelValidator.validate(L), "slab cutout") else "enemy over the cutout passed"


func test_reject_stair_tile_edge() -> String:
	var L := LevelGenerator.fallback_layout(1)
	L.stairs[0].bottom.x += 8.0
	L.stairs[0].top.x += 8.0
	return "" if _has(LevelValidator.validate(L), "tile left edges") else "half-tile stair passed"


## The cutout is a blocker: the upper floor splits at it, and the only way between the
## halves is not across the hole.
func test_cutout_splits_floor() -> String:
	for sd in 10:
		var L := LevelGenerator.generate(sd, 1)
		var g := LevelValidator.floor_graph(L)
		for s in L.stairs:
			var h := LevelValidator.stair_hole(s)
			var tf := int(s.to_floor)
			var a := LevelValidator.node_at(g.segments, tf, h.x - 1.0)
			var b := LevelValidator.node_at(g.segments, tf, h.y + 1.0)
			if LevelValidator.node_at(g.segments, tf, (h.x + h.y) / 2.0) != "":
				return "seed %d: walkable floor inside the cutout %s" % [sd, h]
			if a != "" and a == b:
				return "seed %d: one segment spans the cutout %s" % [sd, h]
	return ""


func test_build_cutout() -> String:
	var w := Node2D.new()
	w.set_meta(&"lg_test", true)
	root.add_child(w)
	var L := LevelGenerator.generate(3, 1)
	LevelGenerator.build(L, w)
	var geo := w.get_node_or_null("Level/Geometry")
	if geo == null:
		w.free()
		return "no Level/Geometry"
	for s in L.stairs:
		var h := LevelValidator.stair_hole(s)
		var y := float(LevelValidator.surface_y(int(s.to_floor))) + 8.0
		for c in geo.get_children():
			if c is CollisionShape2D:
				var r := Rect2(c.position - c.shape.size / 2.0, c.shape.size)
				if r.has_point(Vector2((h.x + h.y) / 2.0, y)):
					w.free()
					return "slab collision over the cutout %s" % h
	var err := ""
	if UiArt.texture("tiles_stage1") != null:
		for n in ["TilesBack", "TilesStairs", "TilesFront"]:
			var l := w.get_node_or_null("Level/" + n) as TileMapLayer
			if l == null or l.get_used_cells().is_empty():
				err = "atlas layer %s missing or empty" % n
	w.free()
	return err


func test_stage_count() -> String:
	if StageTable.STAGE_COUNT != StageTable.STAGES.size() or StageTable.stage_count() != StageTable.STAGE_COUNT:
		return "STAGE_COUNT != STAGES.size()"
	return "" if load("res://scripts/ui/fe_signals.gd").MAX_STAGES == StageTable.STAGE_COUNT else "FE MAX_STAGES not from StageTable"


## QA dry-run findings: the stage table is the source of truth, checked by the validator.
func test_reject_off_table() -> String:
	var L := LevelGenerator.generate(4, 1)
	L.width_tiles = 96
	if not _has(LevelValidator.validate(L), "outside the table"):
		return "96-tile stage 1 passed"
	L = LevelGenerator.generate(4, 3)
	L.floors = 3   # stage 3 is 4 floors
	if not _has(LevelValidator.validate(L), "needs 4 floors"):
		return "3-floor stage 3 passed"
	L = LevelGenerator.generate(4, 5)
	L.budget = {enemies = 3, props = 7, gold = 0, chests = 0}   # a shrunken budget can't pass
	L.enemies = L.enemies.slice(0, 3)
	L.props = L.props.slice(0, 7)
	L.gold = []
	L.chests = []
	if not _has(LevelValidator.validate(L), "!= stage table"):
		return "under-budget stage 5 passed"
	# a layout claiming a smaller safe radius still gets the table's 1280px
	L = LevelGenerator.generate(4, 1)
	L.safe_radius = 300.0
	L.enemies[0].pos = L.start + Vector2(683, 0)
	if not _has(LevelValidator.validate(L), "too close to start"):
		return "puppet 683px from spawn passed"
	# enemy types: float before stage 4, movement not the table's, unknown ids
	L = LevelGenerator.generate(4, 2)
	L.enemies[0].type = "t4"
	L.enemies[0].movement = &"float"
	if not _has(LevelValidator.validate(L), "min_stage"):
		return "float enemy at stage 2 passed"
	L = LevelGenerator.generate(4, 1)
	L.enemies[0].movement = &"float"
	if not _has(LevelValidator.validate(L), "movement"):
		return "puppet_hand with float movement passed"
	L = LevelGenerator.generate(4, 1)
	L.enemies[0].type = "placeholder"
	return "" if _has(LevelValidator.validate(L), "not in StageTable") else "unknown enemy type passed"


## Chests and gold may not sit on a landing, the step run, or the cutout.
func test_reject_loot_on_landing() -> String:
	var s: Dictionary = LevelGenerator.fallback_layout(1).stairs[0]
	var land: Array = LevelValidator.stair_landings(s)
	var L := LevelGenerator.fallback_layout(1)
	L.chests[0].pos = Vector2((land[0].a + land[0].b) / 2.0, LevelValidator.surface_y(int(s.from_floor)))
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "chest on the bottom landing passed"
	L = LevelGenerator.fallback_layout(1)
	L.gold[0].pos = Vector2((land[1].a + land[1].b) / 2.0, LevelValidator.surface_y(int(s.to_floor)))
	if not _has(LevelValidator.validate(L), "overlaps"):
		return "gold on the top landing passed"
	L = LevelGenerator.fallback_layout(1)
	L.props[0].pos = Vector2(s.bottom.x + signf(s.top.x - s.bottom.x) * 64.0, LevelValidator.surface_y(int(s.from_floor)))
	return "" if _has(LevelValidator.validate(L), "overlaps") else "prop on the stair steps passed"


## Built enemies: exactly the table count, each a BE Enemy carrying a table EnemyDef.
func test_enemy_defs() -> String:
	var check: Callable = load("res://tests/seed_sweep_impl.gd").enemy_check
	for st in [1, 4, 5]:
		var w := Node2D.new()
		w.set_meta(&"lg_test", true)
		root.add_child(w)
		var L := LevelGenerator.generate(11, st)
		var b := LevelGenerator.build(L, w)
		var err: String = check.call(w, L, st)
		if err.is_empty() and b.enemies.size() != int(StageTable.STAGES[st].enemies):
			err = "build returned %d enemies" % b.enemies.size()
		w.free()
		if not err.is_empty():
			return "stage %d: %s" % [st, err]
	var d := StageTable.enemy_def("t5")
	if d.movement != &"float" or d.min_stage != 5 or not ResourceLoader.exists(d.script_path):
		return "t5 EnemyDef wrong"
	return ""


## PRODUCT.md "Stair opening" (QA-revised): every opening (both directions) has a world-collision
## wall at its far edge (px 144 rising right / 192 rising left from the stair's left edge, on the
## slab), RAIL_H_PX (96px) tall, clearing the jump apex at the stat cap by >= 16px; the validator checks its placement; built rails match on every stage; the rail is painted from the atlas (stair_gallery_rail or the
## stair_rail_cap fallback).
## Highest jump any item combo can produce, via PlayerStats.stat_max(jump_velocity) / stat_min(gravity).
static func max_jump_apex() -> float:
	return LevelValidator.max_jump_apex()


func test_gallery_rails() -> String:
	var check: Callable = load("res://tests/seed_sweep_impl.gd").rail_check
	for st in range(1, StageTable.STAGE_COUNT + 1):
		var L := LevelGenerator.generate(3, st)
		for s in L.stairs:
			var h := LevelValidator.stair_hole(s)
			var r := LevelValidator.stair_rail(s)
			var x0 := LevelValidator.stair_x(s) * 16.0
			var want := Vector2(x0 + 138.0, x0 + 144.0) if s.top.x > s.bottom.x else Vector2(x0 + 192.0, x0 + 198.0)
			if r != want:
				return "stage %d stair x=%d: rail wall %s != far-edge span %s" % [st, int(s.bottom.x), r, want]
			if r.y > h.x + 0.01 and r.x < h.y - 0.01:
				return "rail wall over the opening"
			var n := LevelValidator.stair_rail_near(s)
			var want_n := Vector2(x0 + 266.0, x0 + 272.0) if s.top.x > s.bottom.x else Vector2(x0 + 64.0, x0 + 70.0)
			if n != want_n:
				return "stage %d stair x=%d: near guard %s != %s" % [st, int(s.bottom.x), n, want_n]
	var apex := max_jump_apex()
	if LevelValidator.RAIL_H_PX < apex + 16.0:
		return "rail collider %dpx < max jump apex %.1fpx + 16" % [int(LevelValidator.RAIL_H_PX), apex]
	for st in range(1, StageTable.STAGE_COUNT + 1):
		var L := LevelGenerator.generate(3, st)
		var w := Node2D.new()
		root.add_child(w)
		var b := LevelGenerator.build(L, w)
		var err: String = check.call(b)
		if err.is_empty() and (b.rails as Array).size() != 2 * L.stairs.size():
			err = "%d rail walls for %d stairs (want 2 each)" % [(b.rails as Array).size(), L.stairs.size()]
		if err.is_empty() and st == 1:
			var stairs_layer := b.level.get_node_or_null("TilesStairs") as TileMapLayer
			if stairs_layer != null:
				var s0: Dictionary = L.stairs[0]
				var hole := LevelValidator.stair_hole(s0)
				var row := int(LevelValidator.surface_y(int(s0.to_floor)) / 16.0) - 1
				for c in range(int(hole.x / 16.0), int(hole.y / 16.0)):
					if stairs_layer.get_cell_source_id(Vector2i(c, row)) < 0:
						err = "rail not painted at tile %d" % c
						break
		w.free()
		if not err.is_empty():
			return "stage %d: %s" % [st, err]
	var rp := LevelSkin.rail_piece()
	if not (rp.name in [LevelSkin.GALLERY_RAIL, LevelSkin.GALLERY_RAIL_FALLBACK]) or (rp.piece as Array).size() != 4:
		return "rail atlas piece %s" % rp
	return ""


## The 5 known-good layouts follow their stage table exactly, pass the validator, and are
## never reached by real seeds (generate marks them `fallback`, which the sweep fails on).
func test_fallback_table() -> String:
	for st in range(1, StageTable.STAGE_COUNT + 1):
		var L := LevelGenerator.fallback_layout(st)
		var P := StageTable.params(st)
		var wt: Array = P.width_tiles
		if int(L.floors) != int(P.floors) or int(L.width_tiles) < int(wt[0]) or int(L.width_tiles) > int(wt[1]):
			return "stage %d fallback %d floors x %d tiles" % [st, L.floors, L.width_tiles]
		if L.enemies.size() != int(P.enemies) or L.props.size() != int(P.props) or L.gold.size() != int(P.gold_piles) or L.chests.size() != int(P.chests):
			return "stage %d fallback under budget" % st
		for e in L.enemies:
			if e.pos.distance_to(L.start) < 1280.0:
				return "stage %d fallback puppet %dpx from spawn" % [st, int(e.pos.distance_to(L.start))]
		if not LevelValidator.validate(L).is_empty():
			return "stage %d fallback: %s" % [st, LevelValidator.validate(L)[0]]
		for sd in 20:
			if LevelGenerator.generate(sd, st).fallback:
				return "stage %d seed %d hit the fallback" % [st, sd]
	return ""


## QA #13 b1: off the stair line, the trigger never covers the floor above the stair's top
## (its slab and above), the upper band only from the top landing side, the lower band as BE's.
func test_stair_band_trigger() -> String:
	var b := Vector2(0, 0)
	var t := Vector2(240, -192)
	var above := Vector2(260, -192 - 40)   # standing on the floor above (to_floor + 1) isn't possible here: rise = 192
	if LevelStair.contains_pts(b, t, Vector2(250, t.y - 192 + 10), false, true):
		return "a boy on the slab one rise above the top counted as inside"
	if LevelStair.contains_pts(b, t, above - Vector2(0, 200), false, true):
		return "a point two rises above the top counted as inside"
	if not LevelStair.contains_pts(b, t, t + Vector2(20, 0), false, false):
		return "top landing refused"
	if LevelStair.contains_pts(b, t, t - Vector2(120, 0), false, true):
		return "gallery side of the opening accepted"
	if not LevelStair.contains_pts(b, t, b - Vector2(10, 0), false, true):
		return "lower floor refused (BE trigger)"
	return ""


## QA #13 b4: the route is the shortest by walked distance, not the fewest stairs.
func test_nav_distance_route() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var far: Dictionary = L.stairs[0]   # at the right end, floor 0 -> 1
	var tl := LevelValidator.TILE
	var near := {from_floor = 0, to_floor = 1,
			bottom = Vector2(5 * tl, 0.0), top = Vector2(20 * tl, LevelValidator.surface_y(1))}
	L.stairs = [far, near]   # far listed first: a BFS / tie-break by index would pick it
	var nav := LevelNav.from_layout(L)
	var a := Vector2(3 * tl, 0.0)
	var b := Vector2(24 * tl, LevelValidator.surface_y(1))
	var r: Variant = nav.route(a, b)
	if not (r is Array) or (r as Array).size() != 1 or (r as Array)[0].stair != near:
		return "route did not take the near stair: %s" % [r]
	var d := nav.route_distance(a, b)
	if d >= absf(a.x - (far.bottom as Vector2).x):
		return "route_distance %.0f not shorter than walking to the far stair" % d
	return ""


## b2/b3: a capped running jump from the floor never clears a rail, and `rail_keepout` is positive
## for every furniture height a jump can leave, 0 only when the surface is too high to need it.
func test_rail_jump_rule() -> String:
	if LevelValidator.rail_keepout(0.0) > 0.0:
		return "a capped jump from the floor clears the rail (apex %.1f vs rail %.0f)" % [LevelValidator.max_jump_apex(), LevelValidator.RAIL_H_PX]
	for h in range(1, 5):
		var ko := LevelValidator.rail_keepout(h * LevelValidator.TILE)
		if ko <= 0.0:
			continue
		if ko < LevelValidator.rail_jump_reach(h * LevelValidator.TILE):
			return "keepout %.0f shorter than the jump reach at h%d" % [ko, h]
	for st in range(1, StageTable.STAGE_COUNT + 1):
		for sd in 40:
			var errs := LevelValidator.rail_jump_errors(LevelGenerator.generate(sd, st))
			if not errs.is_empty():
				return "stage %d seed %d: %s" % [st, sd, errs[0]]
	return ""


func test_reject_furniture_rail() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var s: Dictionary = L.stairs[0]
	var rw := LevelValidator.stair_rail_walls(s)[0]
	var tl := LevelValidator.TILE
	var h := 2   # h1 can't reach the rail height at capped stats (apex 52 + 16 < 80); h2 can
	var ko := LevelValidator.rail_keepout(h * tl)
	if ko <= 0.0:
		return "no keepout for h2"
	var fx := int(floorf((rw.x - 3 * tl) / tl))   # a 2-wide block 1 tile from the rail wall
	L.furniture.append({floor = int(s.to_floor), x = fx, w = 2, h = h})
	if LevelValidator.rail_jump_errors(L).is_empty():
		return "furniture next to a rail passed the capped-jump rule"
	return ""


## PD gold floor: stage 1 floor piles total >= 6 whatever the roll; every stage's worst-roll total
## (floor piles; vases and chests add 0 at worst) is >= the cheapest offer its shop can show.
func test_gold_floor() -> String:
	if StageTable.gold_floor_min(StageTable.params(1)) < 6:
		return "stage 1 gold floor %d < 6" % StageTable.gold_floor_min(StageTable.params(1))
	for st in range(1, StageTable.STAGE_COUNT + 1):
		var cheap := StageTable.cheapest_shop_price(st)
		for sd in 60:
			var L := LevelGenerator.generate(sd, st)
			var w := StageTable.worst_roll_gold(L)
			if w < cheap or w < StageTable.gold_floor_min(StageTable.params(st)):
				return "stage %d seed %d worst-roll gold %d vs cheapest %d" % [st, sd, w, cheap]
	var L := LevelGenerator.fallback_layout(1)
	if StageTable.worst_roll_gold(L) < 6:
		return "stage 1 fallback floor gold %d" % StageTable.worst_roll_gold(L)
	L.gold[0].amount = 0
	L.gold[1].amount = 0
	return "" if _has(LevelValidator.validate(L), "gold floor") else "a layout under the gold floor passed"


# --- furniture sprites + per-stage look (lead/furniture-stage-look) ---

func test_layout_determinism() -> String:
	for st in range(1, 6):
		for sd in [0, 1, 7, 23, 1009]:
			if LookHash.hash_of(sd, st) != LookHash.hash_of(sd, st):
				return "seed %d stage %d differs between two runs" % [sd, st]
			var a := LevelGenerator.generate(sd, st)
			var b := LevelGenerator.generate(sd, st)
			if _strip(a) != _strip(b):
				return "seed %d stage %d layout dictionaries differ" % [sd, st]
	return ""


## The sprite picks use their own RNG stream (FurnitureSkin.rng_for): whatever art is in the
## manifest, the layout (and so collision, enemies, loot) is byte-identical.
func test_sprite_stream_separate() -> String:
	for st in [1, 3, 5]:
		for sd in [3, 11, 40]:
			FurnitureSkin.slots_override = null
			var real := LookHash.hash_of(sd, st)
			FurnitureSkin.slots_override = {}
			var none := LookHash.hash_of(sd, st)
			FurnitureSkin.slots_override = {1: ["vase_idle"], 2: ["vase_idle", "vase_thrown"], 3: ["vase_idle"], 4: ["vase_idle"]}
			var fake := LookHash.hash_of(sd, st)
			FurnitureSkin.slots_override = null
			if real != none or real != fake:
				return "seed %d stage %d layout depends on the furniture slots" % [sd, st]
	return ""


## All 8 real slots (furniture_h{1..4}_{a,b}): the frame is h*16 tall, its top opaque row is
## row 0, and as painted that row sits exactly on the collision top (surface - h*16). ONE pivot
## rule: the frame's bottom edge stands on the floor surface (the manifest pivot is not used).
func test_sprite_row0_on_collision_top() -> String:
	var seen := 0
	for h in range(1, 5):
		for suffix in ["a", "b"]:
			var slot := "furniture_h%d_%s" % [h, suffix]
			if UiArt.texture(slot) == null:
				continue   # art not in the manifest (yet): the fallback test covers it
			seen += 1
			var fs := FurnitureSkin.frame_size(slot)
			if int(fs.y) != h * 16:
				return "%s is %dpx tall, want %d" % [slot, fs.y, h * 16]
			var img := UiArt.texture(slot).get_image()
			var top := -1
			for y in int(fs.y):
				for x in int(fs.x):
					if img.get_pixel(x, y).a > 0.0:
						top = y
						break
				if top >= 0:
					break
			if top != 0:
				return "%s: first opaque row is %d, want 0" % [slot, top]
			var L := {stage = 1, build_seed = 1, furniture = [{floor = 1, x = 10, w = int(fs.x) / 16, h = h}]}
			FurnitureSkin.slots_override = {h: [slot]}
			var lvl := Node2D.new()
			lvl.set_meta(&"lg_test", true)
			root.add_child(lvl)
			FurnitureSkin.paint(lvl, L, [])
			FurnitureSkin.slots_override = null
			var sp := lvl.get_node(FurnitureSkin.ROOT).get_child(0) as Sprite2D
			var world_top := sp.position.y + sp.offset.y + top   # world y of the first opaque row
			var want := LevelValidator.surface_y(1) - h * 16.0
			if not is_equal_approx(world_top, want):
				return "%s: row 0 at y=%s, collision top at y=%s" % [slot, world_top, want]
	return "" if seen == 0 or seen == 8 else "only %d of the 8 furniture slots exist" % seen


func test_mount_rule() -> String:
	# kinematic cap: one climb of <= 32px keeps >= 16px of the 52.24px apex; 48 / 64 do not
	if not LevelValidator.can_mount(32.0) or LevelValidator.can_mount(48.0) or LevelValidator.can_mount(64.0):
		return "can_mount: 32px should be climbable at the caps, 48px and 64px not"
	var L := LevelGenerator.fallback_layout(1)
	var tx := -1
	for x in range(8, int(L.stairs[0].bottom.x / 16.0) - 14):
		var T := L.duplicate(true)
		_append_cluster(T, x, 2, 2, 1)
		if LevelValidator.validate(T).is_empty() and LevelValidator.mount_passable(T, T.furniture[1]):
			tx = x
			break
	if tx < 0:
		return "no clear spot for a stepped 3-tile cluster"
	var T := L.duplicate(true)
	_append_cluster(T, tx, 2, 2, 1)
	var segs_before: int = LevelValidator.segments(L)[0].size()
	if LevelValidator.segments(T)[0].size() != segs_before:
		return "a climbable stepped cluster split the floor"
	if LevelValidator.mountable_pieces(T).size() != 1:
		return "stepped 3-tile piece not counted as mountable"
	var st := LevelValidator.step_pieces(T, T.furniture[1])
	if st.is_empty() or LevelValidator.max_single_climb_px(T.furniture[1], st) > 32.0 or LevelValidator.climb_margin_px(T.furniture[1], st) < 16.0:
		return "cluster climb is over 32px / margin under 16px"
	# the steps (h1, h2) themselves are always walk-over
	if LevelValidator.segments(T)[0].size() != segs_before:
		return "steps split the floor"
	# a bare 3-tile piece (no steps) is a 48px jump with ~4px of apex left: blocks like a tall piece
	var B := L.duplicate(true)
	B.furniture.append({floor = 0, x = tx + 2, w = 2, h = 3})
	if LevelValidator.mount_passable(B, B.furniture[0]) or LevelValidator.segments(B)[0].size() != segs_before + 1 \
			or not LevelValidator.mountable_pieces(B).is_empty():
		return "a 3-tile piece without steps must block and not count as mountable"
	# one step only: still a blocker (the far side would be a 48px drop-climb)
	var O := T.duplicate(true)
	O.furniture.remove_at(2)
	if LevelValidator.mount_passable(O, O.furniture[1]):
		return "a 3-tile piece with one step counted as climbable"
	# 3-tile steps are not steps
	var H := T.duplicate(true)
	H.furniture[0].h = 3
	if LevelValidator.mount_passable(H, H.furniture[1]):
		return "a 3-tile 'step' counted"
	# 4 tiles: never climbable, always a blocker
	T.furniture[1].h = 4
	if LevelValidator.segments(T)[0].size() != segs_before + 1 or not LevelValidator.mountable_pieces(T).is_empty():
		return "a 4-tile piece must block and not count as mountable"
	# stepped 3 tiles with a wall closer than the 2-tile run: blocks like a tall piece
	T.furniture[1].h = 3
	T.walls.append({floor = 0, x = tx + 7, doorway = false})
	if LevelValidator.mount_passable(T, T.furniture[1]):
		return "stepped 3-tile piece near a wall counted as climbable"
	return ""


## [left step (wl x hl), 3-tall piece (2 wide), right step (wr x hr)] touching, from tile x.
func _append_cluster(T: Dictionary, x: int, wl: int, hl: int, hr: int) -> void:
	T.furniture.append({floor = 0, x = x, w = wl, h = hl})
	T.furniture.append({floor = 0, x = x + wl, w = 2, h = 3})
	T.furniture.append({floor = 0, x = x + wl + 2, w = 2, h = hr})


func test_floors_have_mountable() -> String:
	for st in range(1, 6):
		for sd in range(12):
			var L := LevelGenerator.generate(sd, st)
			if L.fallback:
				return "seed %d stage %d fell back" % [sd, st]
			var errs := LevelValidator.mountable_floor_errors(L)
			if not errs.is_empty():
				return "seed %d stage %d: %s" % [sd, st, errs[0]]
			if not LevelValidator.validate(L).is_empty():
				return "seed %d stage %d invalid: %s" % [sd, st, LevelValidator.validate(L)[0]]
	return ""


## QA: a boy on top of / inside a tall piece used to map to the segment on its LEFT, so a walker
## on the right detoured via stairs. Either side now walks straight to the piece.
func test_nav_on_piece() -> String:
	var L := LevelGenerator.fallback_layout(1)
	var tx := -1
	for x in range(10, int(L.stairs[0].bottom.x / 16.0) - 10):
		var T := L.duplicate(true)
		T.furniture.append({floor = 0, x = x, w = 2, h = 4})
		if LevelValidator.segments(T)[0].size() == LevelValidator.segments(L)[0].size() + 1:
			tx = x
			break
	if tx < 0:
		return "no spot for a blocking piece"
	L.furniture.append({floor = 0, x = tx, w = 2, h = 4})
	var nav := LevelNav.from_layout(L)
	var y := LevelValidator.surface_y(0)
	var boy := Vector2((tx + 1) * 16.0, y - 64.0)   # standing on top of the piece
	for dx in [-80.0, 80.0, -200.0, 200.0]:
		var walker := Vector2(boy.x + dx, y)
		var r: Variant = nav.route(walker, boy)
		if r == null or not (r as Array).is_empty():
			return "walker %.0fpx from the piece: route %s, want a direct walk" % [dx, r]
		var wp := nav.next_waypoint(walker, boy)
		if wp.has("stair_to") or wp.get("point") != boy:
			return "walker %.0fpx from the piece: waypoint %s" % [dx, wp]
	return ""


func _build_at(seed_value: int, stage: int) -> Dictionary:
	var w := Node2D.new()
	w.set_meta(&"lg_test", true)
	root.add_child(w)
	var b := LevelGenerator.build(LevelGenerator.generate(seed_value, stage), w)
	b.world = w
	return b


func _seed_with_furniture(stage: int) -> int:
	for sd in 60:
		if LevelGenerator.generate(sd, stage).furniture.size() >= 3:
			return sd
	return -1


func _furn_rects(level: Node) -> Array:
	var out: Array = []
	for body in ["LowFurniture", "Geometry"]:
		for c in level.get_node(body).get_children():
			if c is ColorRect and (c as ColorRect).color == LevelGenerator.C_FURN:
				out.append(c)
	return out


func _collision_sig(level: Node) -> String:
	var out := PackedStringArray()
	for body in ["LowFurniture", "Geometry", "Rails"]:
		for c in level.get_node(body).get_children():
			if c is CollisionShape2D:
				out.append("%s|%s|%s" % [body, c.position, (c.shape as RectangleShape2D).size])
	out.sort()
	return "\n".join(out)


func test_furniture_fallback() -> String:
	var sd := _seed_with_furniture(1)
	if sd < 0:
		return "no stage 1 seed with furniture"
	FurnitureSkin.slots_override = {}
	var b := _build_at(sd, 1)
	FurnitureSkin.slots_override = null
	var n: int = b.layout.furniture.size()
	var sprites: int = b.level.get_node(FurnitureSkin.ROOT).get_child_count()
	var rects: Array = _furn_rects(b.level).filter(func(r): return r.visible)
	b.world.free()
	if sprites != 0:
		return "%d sprites with no slots" % sprites
	if rects.size() != n:
		return "%d visible placeholder rects for %d pieces" % [rects.size(), n]
	# the real manifest has no furniture_h* slots yet (or, once Designer lands them, builds fine)
	var b2 := _build_at(sd, 1)
	var ok: bool = b2.level.get_node(FurnitureSkin.ROOT).get_child_count() + _furn_rects(b2.level).filter(func(r): return r.visible).size() == n
	b2.world.free()
	return "" if ok else "manifest build lost a furniture piece"


func test_furniture_sprites() -> String:
	var sd := _seed_with_furniture(1)
	if sd < 0:
		return "no stage 1 seed with furniture"
	FurnitureSkin.slots_override = {}
	var plain := _build_at(sd, 1)
	var plain_sig := _collision_sig(plain.level)
	plain.world.free()
	# vase_idle is 32x32: stands in for art that fits any piece (2-3 tiles wide)
	FurnitureSkin.slots_override = {1: ["vase_idle"], 2: ["vase_idle", "vase_thrown"], 3: ["vase_idle"], 4: ["vase_idle", "missing_slot"]}
	var b := _build_at(sd, 1)
	var L: Dictionary = b.layout
	var picks := FurnitureSkin.choose(L)
	var picks2 := FurnitureSkin.choose(L)
	var sig := _collision_sig(b.level)
	var root_n: Node = b.level.get_node(FurnitureSkin.ROOT)
	var err := ""
	if var_to_str(picks) != var_to_str(picks2):
		err = "picks are not deterministic"
	elif root_n.get_child_count() != L.furniture.size():
		err = "%d sprites for %d pieces" % [root_n.get_child_count(), L.furniture.size()]
	elif sig != plain_sig:
		err = "collision changed with sprites"
	else:
		var rects := _furn_rects(b.level)
		for r in rects:
			if r.visible:
				err = "placeholder rect still visible under a sprite"
		for i in L.furniture.size():
			var fu: Dictionary = L.furniture[i]
			var sp := root_n.get_node("Furniture_%d" % i) as Sprite2D
			if not (sp.get_meta(&"slot") in FurnitureSkin.slots_for_height(int(fu.h))):
				err = "piece %d (h%d) got slot %s" % [i, fu.h, sp.get_meta(&"slot")]
			var want := Vector2((float(fu.x) + float(fu.w) * 0.5) * 16.0, LevelValidator.surface_y(int(fu.floor)))
			var fs := FurnitureSkin.frame_size(str(sp.get_meta(&"slot")))
			var tl := sp.position + sp.offset   # top-left of the drawn frame
			if not sp.position.is_equal_approx(want) or not tl.is_equal_approx(want - Vector2(fs.x * 0.5, fs.y)):
				err = "piece %d at %s (top-left %s), want bottom-centre %s" % [i, sp.position, tl, want]
	b.world.free()
	# exact width preferred (vase_idle 32 wide, exit door 48 wide); none exact -> any of the class
	FurnitureSkin.slots_override = {1: ["vase_idle", "exit_door_stage1"]}
	if FurnitureSkin.candidates(1, 2) != ["vase_idle"] or FurnitureSkin.candidates(1, 3) != ["exit_door_stage1"] \
			or FurnitureSkin.candidates(1, 5).size() != 2:
		err = "width preference wrong"
	FurnitureSkin.slots_override = null
	return err


## Contract for the REAL furniture_h* slots (vacuous until Designer's art is in the manifest):
## 1-3 tiles wide, frame height == height class x 16 (sprite = collision box height), bottom-centre
## pivot, top opaque row is row 0 (the walkable top = collision top).
func test_furniture_art_contract() -> String:
	for h in range(1, 5):
		for slot in FurnitureSkin.slots_for_height(h):
			var fs := FurnitureSkin.frame_size(slot)
			if fs.x < 16 or fs.x > 48 or int(fs.x) % 16 != 0:
				return "%s is %dpx wide (want 1-3 whole tiles)" % [slot, fs.x]
			if int(fs.y) != h * 16:
				return "%s is %dpx tall, collision height is %d" % [slot, fs.y, h * 16]
			var pv := AnimLibrary.pivot(slot)
			if absf(pv.x - fs.x * 0.5) > 1.0 or absf(pv.y - fs.y) > 1.0:
				return "%s pivot %s is not bottom-centre of %s" % [slot, pv, fs]
			var img := UiArt.texture(slot).get_image()
			var top := -1
			for y in int(fs.y):
				for x in int(fs.x):
					if img.get_pixel(x, y).a > 0.0:
						top = y
						break
				if top >= 0:
					break
			if top != 0:
				return "%s top opaque row is %d (want 0 = the collision top)" % [slot, top]
	return ""


func test_stage_look() -> String:
	var prev_lum := 99.0
	var prev_cold := -99.0
	for st in range(1, StageTable.STAGE_COUNT + 1):
		var look := StageTable.look(st)
		var b := _build_at(3, st)
		var amb := b.level.get_node_or_null(StageLook.AMBIENT_NODE) as CanvasModulate
		var err := ""
		if amb == null:
			err = "stage %d has no ambient CanvasModulate" % st
		elif not amb.color.is_equal_approx(look.ambient):
			err = "stage %d ambient %s != table %s" % [st, amb.color, look.ambient]
		else:
			for n in StageLook.TILE_LAYERS:
				var l := b.level.get_node_or_null(n) as CanvasItem
				if l and not l.modulate.is_equal_approx(look.tint):
					err = "stage %d %s tint %s != table %s" % [st, n, l.modulate, look.tint]
			var beam := b.player.get_node_or_null("Flashlight/Beam") as PointLight2D
			if beam == null:
				err = "no flashlight beam"
			elif not is_equal_approx(beam.energy, float(beam.get_meta(&"base_energy")) * float(look.flashlight_energy)):
				err = "stage %d beam energy %f" % [st, beam.energy]
		b.world.free()
		if not err.is_empty():
			return err
		var a: Color = look.ambient
		var lum := 0.299 * a.r + 0.587 * a.g + 0.114 * a.b
		var cold := a.b / a.r   # blue share rises stage over stage
		if lum >= prev_lum or cold <= prev_cold:
			return "stage %d is not darker AND colder than the stage before" % st
		prev_lum = lum
		prev_cold = cold
	if StageTable.look(1).ambient.r <= StageTable.look(1).ambient.b:
		return "stage 1 ambient is not warm"
	var l5: Color = StageTable.look(5).ambient
	if l5.r > 0.1 or l5.g > 0.1 or l5.b > 0.15 or float(StageTable.look(5).flashlight_energy) <= 1.0:
		return "stage 5 is not near-black with a boosted flashlight"
	if StageTable.look(9).ambient != StageTable.look(5).ambient or StageTable.look(0).ambient != StageTable.look(1).ambient:
		return "look() does not clamp the stage"
	return ""

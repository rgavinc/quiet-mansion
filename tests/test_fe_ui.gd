extends RefCounted
## Front End HUD/overlay checks against the FESignals placeholder adapter.
## Each test builds its own adapter instance so it never depends on autoloads.

const FE := "res://scripts/ui/fe_signals.gd"


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["hearts_follow_health_and_max", test_hearts],
		["gold_counter_updates", test_gold],
		["inventory_empty_safe", test_inventory_empty],
		["inventory_scroll_wraps", test_inventory_wrap],
		["ring_color_lookup_default", test_ring_colors],
		["ring_single_selection", test_ring_single],
		["ring_persists_light_off_with_glow", test_ring_light_off],
		["startle_only_from_be_reports_once_per_enemy", test_startle],
		["pickup_gauge_hides_on_cancel", test_pickup_cancel],
		["offscreen_arrow_clamps_to_edge", test_edge_point],
		["camera_nudge_is_capped", test_nudge],
		["throw_line_blocked_by_wall", test_throw_block],
		["input_actions_exist", test_input_actions],
		["throw_line_only_when_holding_and_ringed", test_throw_rule],
		["pickup_gauge_shows_on_be_start_fill_is_be_progress", test_pickup_threshold],
		["real_player_tap_never_shows_gauge_hold_does", test_pickup_tap],
		["flashlight_is_toggle_ring_persists", test_flashlight_toggle],
		["startle_meter_hides_when_light_off", test_startle_meter_light],
		["freed_selected_lit_chasing_enemy_is_cleared_without_errors", test_enemy_freed],
		["main_scene_has_new_hud_overlay_watermark", test_main_scene],
		["ui_art_resolves_manifest_slots", test_ui_art_slots],
		["fe_scripts_no_hardcoded_art_paths", test_no_art_paths],
		["hearts_gold_wired_to_player_stats", test_player_stats_wiring],
		["game_over_shows_on_died_and_pauses", test_game_over],
		["game_over_fallback_panel_when_art_slot_missing", test_game_over_fallback],
		["shop_opens_on_exit_buy_deducts_rejects_insufficient", test_shop_buy],
		["shop_uses_be_shop_roll_stock_and_buy", test_shop_be_interface],
		["shop_empty_item_source_no_errors", test_shop_empty],
		["shop_ui_clear_of_merchant", test_shop_layout],
		["shop_shows_full_stock_clamped_1_to_4", test_shop_full_stock],
		["shop_4_longest_fit_panel_with_message", test_shop_four_fit],
		["shop_letter_tile_square_rarity_rim", test_shop_letter_tile],
		["shop_initials_fixed_sample", test_initials_sample],
		["gold_coin_icon_shows_face_not_sliver", test_coin_face],
		["alert_count_scales_past_3", test_alert_scales],
		["alert_count_follows_chase_reports", test_alert_follows_reports],
		["arrows_for_offscreen_reported_chasers", test_arrows_from_reports],
		["stage_banner_shows_and_fades", test_stage_banner],
		["main_scene_has_screens", test_main_screens],
		["game_over_new_run_fresh_stage1_new_seed", test_new_run],
		["game_over_retry_seed_fresh_stage1_same_run_seed", test_retry_seed],
		["retry_seed_uses_run_seed_not_stage_seed", test_retry_uses_run_seed],
		["next_stage_keeps_run_seed_and_stats", test_next_stage_keeps_run],
		["exit_on_stage_5_opens_win_not_shop", test_win_on_last_stage],
		["exit_on_stages_1_to_4_opens_shop", test_shop_on_stages_1_to_4],
		["win_double_trigger_never_advances", test_win_double_trigger],
		["win_new_run_resets_to_stage1_fresh", test_win_new_run],
		["continue_drops_held_props_keeps_gold_hearts_items", test_continue_carry_over],
		["end_latch_win_then_died_only_win", test_latch_win_then_died],
		["end_latch_died_then_exit_only_game_over", test_latch_died_then_exit],
		["end_latch_same_frame_both_orders", test_latch_same_frame],
		["end_latch_cleared_by_new_run_and_retry", test_latch_cleared],
		["win_calls_gamestate_end_run_won_and_respects_run_over", test_win_end_run_won],
		["owned_items_strip_follows_items_changed", test_owned_strip_updates],
		["owned_items_strip_shows_charges", test_owned_strip_charges],
		["arrow_hidden_beyond_reveal_distance_shown_inside", test_arrow_reveal_distance],
		["minimap_visible_only_with_has_minimap", test_minimap_visibility],
		["lure_hint_legacy_held_lure_without_pocket_api", test_lure_hint],
		["lure_hint_exactly_tap_throws_lure", test_lure_hint_pocket],
		["lure_pocket_pips_follow_lures_changed", test_lure_pocket],
		["lure_pocket_sits_right_of_hand_slots_in_hud", test_lure_pocket_hud],
		["lure_widgets_disconnect_on_exit_no_errors", test_lure_widgets_exit_tree],
		["owned_strip_music_box_no_double_charges_with_pocket", test_owned_strip_pocket],
		["hud_mounts_items_strip_minimap_and_hint", test_hud_items_widgets],
		["items_widgets_disconnect_on_exit_no_tree_errors", test_items_widgets_exit_tree],
		["owned_items_strip_stacks_duplicates", test_owned_strip_stacks],
		["owned_items_strip_30_items_wraps_inside_1020", test_owned_strip_wraps],
		["minimap_dots_clamped_and_chase_end_immediate", test_minimap_clamp_and_chase_end],
		["hud_hidden_while_end_screen_open", test_hud_hidden_end_screen],
	]
	var passed := 0
	if _be_enemy_reports():   # BE PR #26 present (trial merge / after it lands)
		checks.append_array([
			["be_enemy_startle_counted_once", test_be_startle_once],
			["be_enemy_chase_reports_drive_count_and_arrows", test_be_chase_reports],
		])
	if _item_db() != null:   # BE PR #27 present
		checks.append(["shop_initials_unique_for_itemdb", test_initials_itemdb])
	if _pocket_api():   # BE PR #41 (lure pocket) present
		checks.append_array([
			["lure_hint_real_player_stats_through_throw_and_refill", test_lure_pocket_real_stats],
			["lure_pocket_pips_real_player_stats", test_lure_pocket_pips_real_stats],
		])
	if _global_script("LevelNav") != null:   # Lead's PR #13 (generated level) present
		checks.append(["minimap_reads_generated_level_floors", test_minimap_level_nav])
	for item in checks:
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _bus() -> Node:
	var b: Node = load(FE).new()
	_root().add_child(b)
	return b


func _mount(script_path: String, bus: Node) -> Node:
	var n: Node = load(script_path).new()
	n.set("bus", bus)
	_root().add_child(n)
	return n


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()


func test_hearts() -> String:
	var b := _bus()
	var hud := _mount("res://scripts/ui/health_gold_hud.gd", b)
	var err := ""
	b.set_health(2, 3)
	if hud.heart_count() != 3 or hud.filled_hearts() != 2:
		err = "expected 3 hearts / 2 filled, got %d / %d" % [hud.heart_count(), hud.filled_hearts()]
	b.set_health(4, 4)
	if err.is_empty() and (hud.heart_count() != 4 or hud.filled_hearts() != 4):
		err = "max 4 → expected 4/4, got %d / %d" % [hud.heart_count(), hud.filled_hearts()]
	_cleanup([hud, b])
	return err


func test_gold() -> String:
	var b := _bus()
	var hud := _mount("res://scripts/ui/health_gold_hud.gd", b)
	b.set_gold(37)
	var err := "" if hud.gold_text() == "37" else "gold label '%s'" % hud.gold_text()
	_cleanup([hud, b])
	return err


func test_inventory_empty() -> String:
	var b := _bus()
	var inv := _mount("res://scripts/ui/inventory_strip.gd", b)
	var err := ""
	b.set_items([])
	b.cycle_item(1)
	b.cycle_item(-1)
	if inv.slot_count() != 1 or inv.selected_index() != -1 or b.selected_index != -1:
		err = "empty strip should show 1 dim slot, none selected"
	if err.is_empty() and not b.selected_item().is_empty():
		err = "selected_item() on empty should be {}"
	_cleanup([inv, b])
	return err


func test_inventory_wrap() -> String:
	var b := _bus()
	var inv := _mount("res://scripts/ui/inventory_strip.gd", b)
	b.set_items([{"slot": "vase", "name": "Vase", "throwable": true}, {"slot": "key", "name": "Key"}, {"slot": "coin", "name": "Coin"}])
	var err := ""
	if inv.slot_count() != 3 or inv.selected_index() != 0:
		err = "3 items → selected 0 (got %d slots, sel %d)" % [inv.slot_count(), inv.selected_index()]
	b.cycle_item(-1)
	if err.is_empty() and inv.selected_index() != 2:
		err = "prev from 0 should wrap to 2, got %d" % inv.selected_index()
	b.cycle_item(1)
	if err.is_empty() and inv.selected_index() != 0:
		err = "next from 2 should wrap to 0"
	_cleanup([inv, b])
	return err


func test_ring_colors() -> String:
	var skin := HudSkin.load_default()
	if skin.ring_color_for("puppet_hand") != skin.ring_colors["puppet_hand"]:
		return "puppet_hand colour not from lookup"
	if skin.ring_color_for("no_such_enemy") != skin.ring_default:
		return "unknown id should use ring_default"
	return ""


func test_ring_single() -> String:
	var b := _bus()
	var ring := _mount("res://scripts/ui/selection_ring.gd", b)
	var a := Node2D.new(); _root().add_child(a)
	var c := Node2D.new(); c.set_meta("enemy_type", "puppet_hand"); _root().add_child(c)
	b.select_enemy(a)
	b.select_enemy(c)
	var err := ""
	if ring.target != c or b.selected_enemy != c:
		err = "selection should move to the second enemy"
	elif ring.color != HudSkin.load_default().ring_color_for("puppet_hand"):
		err = "ring colour should follow enemy type"
	_cleanup([ring, a, c, b])
	return err


func test_ring_light_off() -> String:
	var b := _bus()
	var ring := _mount("res://scripts/ui/selection_ring.gd", b)
	var e := Node2D.new(); _root().add_child(e)
	b.select_enemy(e)
	b.set_flashlight(false)
	var glow := ring.get_node("DarkGlow") as PointLight2D
	var err := ""
	if not ring.visible or ring.target != e:
		err = "ring must persist with light off"
	elif glow.energy <= 0.0:
		err = "selected enemy needs faint glow with light off"
	b.set_flashlight(true)
	if err.is_empty() and glow.energy != 0.0:
		err = "glow should be off while the flashlight is on"
	_cleanup([ring, e, b])
	return err


## BE (Enemy._tick_startle, PR #26) reports startle itself. FE must store exactly
## what was reported — once per enemy — and never integrate on top (double count).
func test_startle() -> String:
	var b := _bus()
	var e := Node2D.new(); _root().add_child(e)
	var f := Node2D.new(); _root().add_child(f)
	var emits := {}   # instance id -> Array of reported values seen on startle_progress
	b.startle_progress.connect(func(en, v):
		var id: int = en.get_instance_id()
		if not emits.has(id): emits[id] = []
		emits[id].append(v))
	b.startle_time = 1.0
	b.report_lit(e, true)
	b.report_lit(f, true)
	b._process(1.0)   # a lit second passing alone must not move startle (no FE integration)
	var err := ""
	if b.get_startle(e) != 0.0 or not emits.is_empty():
		err = "FE integrated startle on its own: %f, emits %s" % [b.get_startle(e), emits]
	# BE-style frames: Enemy reports 0.1 per frame for e, 0.05 for f; FE ticks in between.
	for k in range(1, 11):
		b.report_startle(e, k * 0.1)
		b.report_startle(f, k * 0.05)
		b._process(0.1)
	var ee: Array = emits.get(e.get_instance_id(), [])
	if err.is_empty() and (ee.size() != 10 or absf(ee[-1] - 1.0) > 0.0001):
		err = "e: want 10 emits ending at 1.0 (one per BE report), got %s" % [ee]
	if err.is_empty() and absf(b.get_startle(e) - 1.0) > 0.0001:
		err = "e startle should be exactly BE's 1.0, got %f" % b.get_startle(e)
	if err.is_empty() and absf(b.get_startle(f) - 0.5) > 0.0001:
		err = "f startle should be exactly BE's 0.5 (counted once), got %f" % b.get_startle(f)
	b.report_lit(f, false)   # beam left f: BE reports the reset; FE doesn't write startle
	if err.is_empty() and absf(b.get_startle(f) - 0.5) > 0.0001:
		err = "report_lit(false) must not overwrite BE's startle"
	b.report_startle(f, 0.0)
	if err.is_empty() and b.get_startle(f) != 0.0:
		err = "BE reset report should zero f"
	b.set_flashlight(false)
	if err.is_empty() and b.get_startle(e) != 0.0:
		err = "light off should hide/reset the displayed startle"
	_cleanup([e, f, b])
	return err


func test_pickup_cancel() -> String:
	var b := _bus()
	var g := _mount("res://scripts/ui/pickup_gauge.gd", b)
	b.report_pickup_started(null)
	b.report_pickup_progress(0.4)
	var err := ""
	if not g.visible or absf(g.progress - 0.4) > 0.001:
		err = "gauge should show 0.4 while channeling"
	b.report_pickup_cancelled()
	if err.is_empty() and g.active:
		err = "gauge should stop on cancel"
	g._process(1.0)
	if err.is_empty() and g.visible:
		err = "gauge should hide after cancel"
	_cleanup([g, b])
	return err


func test_edge_point() -> String:
	var Arrows = load("res://scripts/ui/offscreen_arrows.gd")
	var vp := Rect2(0, 0, 1280, 720)
	var r: Array = Arrows.edge_point(vp, Vector2(3000, 360), 30.0)
	var p: Vector2 = r[0]
	if absf(p.x - 1250.0) > 0.5 or absf(p.y - 360.0) > 0.5:
		return "right edge point wrong: %s" % p
	if absf(float(r[1])) > 0.01:
		return "should point right (angle 0)"
	return ""


func test_nudge() -> String:
	var Nudge = load("res://scripts/ui/camera_nudge.gd")
	var o: Vector2 = Nudge.target_offset(Vector2.ZERO, Vector2(2000, 0), 0.12, 48.0)
	if absf(o.length() - 48.0) > 0.01 or o.x <= 0.0:
		return "offset should cap at 48 toward enemy, got %s" % o
	var small: Vector2 = Nudge.target_offset(Vector2.ZERO, Vector2(100, 0), 0.12, 48.0)
	if absf(small.x - 12.0) > 0.01:
		return "offset should be 12 at 100px, got %s" % small
	return ""


func test_throw_block() -> String:
	var Line = load("res://scripts/ui/throw_line.gd")
	var holder := Node2D.new()
	_root().add_child(holder)
	var wall := StaticBody2D.new()
	wall.position = Vector2(5000, 5000)
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new(); rs.size = Vector2(20, 200)
	cs.shape = rs
	wall.add_child(cs)
	holder.add_child(wall)
	var space := holder.get_world_2d().direct_space_state
	var empty_rids: Array[RID] = []
	var hit: Dictionary = Line.ray_block(space, Vector2(4800, 5000), Vector2(5200, 5000), empty_rids, 0xFFFFFFFF)
	var clear: Dictionary = Line.ray_block(space, Vector2(4800, 4700), Vector2(5200, 4700), empty_rids, 0xFFFFFFFF)
	var err := ""
	if hit.is_empty():
		err = "ray through wall should be blocked"
	elif not clear.is_empty():
		err = "ray above wall should be clear"
	_cleanup([holder])
	return err


func test_input_actions() -> String:
	for a in ["jump", "flashlight_toggle", "interact", "inv_next", "inv_prev"]:
		if not InputMap.has_action(a):
			return "missing input action %s" % a
	return ""


func test_throw_rule() -> String:
	var b := _bus()
	var line := _mount("res://scripts/ui/throw_line.gd", b)
	var e := Node2D.new(); _root().add_child(e)
	var err := ""
	# empty hands, nothing ringed
	if line.should_show():
		err = "hidden with empty hands and no ring"
	b.select_enemy(e)
	if err.is_empty() and line.should_show():
		err = "hidden with empty hands even when ringed"
	b.set_items([{"slot": "key", "name": "Key"}])   # holding (any item)
	b.select_item(0)
	if err.is_empty() and not line.should_show():
		err = "shown when holding something and an enemy is ringed"
	b.select_enemy(null)
	if err.is_empty() and (line.should_show() or b.can_throw()):
		err = "hidden when holding but nothing ringed (tap does nothing)"
	b.select_enemy(e)
	b.set_items([])
	if err.is_empty() and line.should_show():
		err = "hidden again once hands are empty"
	_cleanup([line, e, b])
	return err


func test_pickup_threshold() -> String:
	# BE only sends pickup_started after its tap threshold, so the gauge shows at once.
	var b := _bus()
	var g := _mount("res://scripts/ui/pickup_gauge.gd", b)
	var err := ""
	b.report_pickup_started(null)
	if not g.visible:
		err = "gauge must show immediately on pickup_started (no extra FE delay)"
	b.report_pickup_progress(0.3)
	if err.is_empty() and absf(g.progress - 0.3) > 0.001:
		err = "fill should be BE's reported progress 0.3, got %f" % g.progress
	g._process(5.0)   # time passing alone must not move the fill
	if err.is_empty() and absf(g.progress - 0.3) > 0.001:
		err = "fill advanced on its own clock (%f); it must follow BE progress only" % g.progress
	b.report_pickup_progress(1.0)
	b.report_pickup_completed()
	g._process(1.0)
	if err.is_empty() and g.visible:
		err = "gauge should hide after complete"
	_cleanup([g, b])
	return err


func test_pickup_tap() -> String:
	# Real BE player_controller + real FESignals: a tap never starts a pickup, a hold
	# shows the gauge on the very tick BE starts it, and the fill mirrors BE's progress.
	var fe: Node = _root().get_node("FESignals")
	var ps: Node = _root().get_node("PlayerStats")
	fe.reset(); ps.reset()
	var g := _mount("res://scripts/ui/pickup_gauge.gd", fe)
	var p: CharacterBody2D = load("res://scripts/player/player_controller.gd").new()
	_root().add_child(p)
	p.global_position = Vector2(100, 100)
	var v: Node2D = load("res://scripts/world/vase.gd").new()
	v.set("break_on_touch", false)
	v.set("gold_inside", 0)
	_root().add_child(v)
	v.global_position = Vector2(120, 100)
	var starts: Array = []
	fe.pickup_started.connect(func(_t): starts.append(true))
	var dt := 1.0 / 60.0
	var tap: float = ps.get_stat(&"tap_threshold")
	var err := ""
	p.interact_pressed()
	var t := 0.0
	while t < tap * 0.5:
		p.tick(dt, Vector2.ZERO); g._process(dt); t += dt
		if g.visible: err = "gauge visible during a tap"
	p.interact_released()
	g._process(dt)
	if err.is_empty() and (g.visible or not starts.is_empty()):
		err = "a tap must never start a pickup or show the gauge"
	# The tap knocked that vase over (empty hands), so set out a fresh one to hold on.
	var v2: Node2D = load("res://scripts/world/vase.gd").new()
	v2.set("break_on_touch", false)
	v2.set("gold_inside", 0)
	_root().add_child(v2)
	v2.global_position = Vector2(120, 100)
	if err.is_empty():
		p.interact_pressed()
		t = 0.0
		var shown_at := -1.0
		while t < tap + 0.3:
			p.tick(dt, Vector2.ZERO); g._process(dt); t += dt
			if g.visible and shown_at < 0.0: shown_at = t
		if shown_at < 0.0:
			err = "hold never showed the gauge"
		elif shown_at < tap - 0.0001 or shown_at > tap + 2.0 * dt:
			err = "gauge should appear right at BE's pickup start (~%.2fs), was %.3fs" % [tap, shown_at]
		elif absf(g.progress - p.pickup_progress) > 0.001:
			err = "fill %f != BE pickup_progress %f" % [g.progress, p.pickup_progress]
		p.interact_released()
	_cleanup([g, p, v, v2])
	fe.reset(); ps.reset()
	return err


func test_flashlight_toggle() -> String:
	var b := _bus()
	var ring := _mount("res://scripts/ui/selection_ring.gd", b)
	var e := Node2D.new(); _root().add_child(e)
	b.select_enemy(e)
	var seen: Array = []
	b.flashlight_toggled.connect(func(on): seen.append(on))
	var err := ""
	b.toggle_flashlight()   # click → off
	if b.flashlight_on or not ring.visible or ring.target != e:
		err = "first click turns light off; ring stays"
	b.toggle_flashlight()   # click → on
	if err.is_empty() and (not b.flashlight_on or not ring.visible):
		err = "second click turns light back on; ring stays"
	if err.is_empty() and seen != [false, true]:
		err = "toggled signal sequence %s" % [seen]
	b.set_flashlight(true)  # same state again: no extra signal
	if err.is_empty() and seen.size() != 2:
		err = "setting the same state must not re-emit"
	_cleanup([ring, e, b])
	return err


func test_player_stats_wiring() -> String:
	var ps: Node = load("res://scripts/autoload/player_stats.gd").new()
	_root().add_child(ps)
	var b := _bus()
	var hud := _mount("res://scripts/ui/health_gold_hud.gd", b)
	b.wire_player_stats(ps)
	var err := ""
	if not b.is_stats_wired():
		err = "wire_player_stats should connect"
	ps.take_hit(1)
	if err.is_empty() and (b.health != ps.health or hud.filled_hearts() != ps.health or hud.heart_count() != ps.max_health()):
		err = "hearts should follow PlayerStats: %d/%d vs hud %d/%d" % [ps.health, ps.max_health(), hud.filled_hearts(), hud.heart_count()]
	ps.add_gold(12)
	if err.is_empty() and (b.gold != ps.gold or hud.gold_text() != str(ps.gold)):
		err = "gold should follow PlayerStats (%d), hud '%s'" % [ps.gold, hud.gold_text()]
	if err.is_empty() and absf(b.startle_time - ps.get_stat(&"light_startle_time")) > 0.0001:
		err = "startle_time should come from PlayerStats"
	_cleanup([hud, b, ps])
	return err


func test_startle_meter_light() -> String:
	var b := _bus()
	var e := Node2D.new(); _root().add_child(e)
	var m: Node = load("res://scripts/ui/startle_meter.gd").new()
	m.set("bus", b)
	m.set("target", e)
	_root().add_child(m)
	b.startle_progress.connect(func(en, p): if en == e: m.set_progress(p))
	b.report_lit(e, true)
	b.report_startle(e, 0.4)   # BE Enemy reports
	m._process(0.0)
	var err := ""
	if not m.visible or m.progress <= 0.0:
		err = "meter should show while lit with the light on"
	b.set_flashlight(false)   # what BE player_controller calls on RMB
	if err.is_empty() and (m.visible or m.progress != 0.0):
		err = "meter must hide and reset as soon as the light turns off"
	m._process(0.0)
	if err.is_empty() and m.visible:
		err = "meter must stay hidden with the light off"
	_cleanup([m, e, b])
	return err


func test_main_scene() -> String:
	var ps: PackedScene = load("res://scenes/main.tscn")
	if ps == null:
		return "main.tscn failed to load"
	var st := ps.get_state()
	var names: PackedStringArray = []
	for i in st.get_node_count():
		names.append(str(st.get_node_path(i)))
	for want in ["./HUD", "./World/WorldOverlay", "./AIWatermark", "./AIWatermark/WatermarkLabel"]:
		if not want in names:
			return "main.tscn missing %s (has %s)" % [want, names]
	var src := FileAccess.get_file_as_string("res://scripts/map/main.gd")
	if src.contains("knock nearby") or src.contains("Space/RMB") or src.contains("AlertHud"):
		return "old text HUD / knock hint still in main.gd"
	var want_hint := "Space jump · RMB flashlight on/off · hold LMB pick up · tap LMB throw/knock · scroll items"
	if not src.contains(want_hint):
		return "new hint text missing from main.gd"
	return ""


func test_ui_art_slots() -> String:
	UiArt.clear_cache()
	for slot in ["floor_dark", "flashlight_blob"]:
		if UiArt.texture(slot) == null:
			return "slot %s should resolve through the manifest" % slot
	if UiArt.texture("no_such_slot_xyz") != null:
		return "unknown slot must return null (placeholder path)"
	return ""


func test_no_art_paths() -> String:
	var files := ["res://scripts/map/main.gd", "res://scripts/player/flashlight.gd"]
	var d := DirAccess.open("res://scripts/ui")
	for f in d.get_files():
		if f.ends_with(".gd"):
			files.append("res://scripts/ui/" + f)
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		if src.contains("res://assets/art/") or src.contains("res://assets/replace_me/"):
			return "%s hard-codes an art path; use a manifest slot" % f
	return ""



class _ErrCount extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		errors.append("%s:%d %s %s" % [file, line, code, rationale])


## QA #18: kill a selected + lit + chasing enemy; nothing may log an error, and every
## FE entry for it (selection, lit, startle, chase, chase memory, meter) is cleared.
func test_enemy_freed() -> String:
	var b := _bus()
	var ov: Node2D = load("res://scenes/ui/world_overlay.tscn").instantiate()
	ov.set("bus", b)
	_root().add_child(ov)
	var arrows := _mount("res://scripts/ui/offscreen_arrows.gd", b)
	var cam := Camera2D.new(); _root().add_child(cam); cam.make_current()
	var e := Node2D.new(); e.add_to_group("puppets"); _root().add_child(e)
	e.global_position = Vector2(5000, 5000)   # off-screen so an arrow is drawn
	b.set_items([{"id": "vase", "slot": "vase", "name": "Vase", "throwable": true}])
	b.select_item(0)
	b.select_enemy(e)
	b.report_lit(e, true)
	b.report_startle(e, 0.3)
	b.report_chase(e, true)
	b.report_chase_memory(e, 0.6)
	var ring: Node2D = ov.get("ring")
	var nudge: Node = ov.get("camera_nudge")
	var line: Node2D = ov.get("throw_line")
	var tick := func():
		b._process(0.1)
		ring._process(0.1)
		nudge._process(0.1)
		arrows._process(0.1)
		line._physics_process(0.1)
		for m in ov.get("layer").get_children():
			if m.get_script() == load("res://scripts/ui/startle_meter.gd") and is_instance_valid(m):
				m._process(0.1)
	tick.call(); tick.call()
	var err := ""
	if not ring.visible or b.get_startle(e) <= 0.0 or arrows.arrows.is_empty() or ov.meter_for(e) == null:
		err = "setup: ring, startle, arrow and meter should all be live before the kill"
	var log := _ErrCount.new()
	OS.add_logger(log)
	var id := e.get_instance_id()
	e.free()   # killed
	for i in 5:
		tick.call()
	OS.remove_logger(log)
	if err.is_empty() and not log.errors.is_empty():
		err = "errors after enemy freed: %s" % [log.errors]
	if err.is_empty() and (b.get_selected_enemy() != null or b.selected_enemy != null):
		err = "selection not cleared"
	if err.is_empty() and (not b.chasing.is_empty() or b.chase_memory.has(id)):
		err = "chase entries not cleared"
	if err.is_empty() and (b._lit.has(id) or b.startle.has(id)):
		err = "lit/startle entries not cleared"
	if err.is_empty() and (ring.visible or line.visible or not arrows.arrows.is_empty()):
		err = "ring/throw line/arrow still showing for a dead enemy"
	if err.is_empty() and b.can_throw():
		err = "can_throw must be false with no live ringed enemy"
	_cleanup([ov, arrows, cam, b])
	return err


# --- Screens / shop / alerts / banner (fe/screens-shop) ----------------------
func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _stats_bus() -> Array:
	var ps: Node = load("res://scripts/autoload/player_stats.gd").new()
	_root().add_child(ps)
	var b := _bus()
	b.wire_player_stats(ps)
	return [ps, b]


func _reset_world() -> void:
	_tree().paused = false
	var gs := _root().get_node_or_null(^"GameState")
	if gs:
		gs.reset()


func test_game_over() -> String:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	var go := _mount("res://scripts/ui/game_over.gd", b)
	var err := ""
	ps.add_gold(7)
	if go.is_open() or go.visible:
		err = "game over must start hidden"
	var guard := 0
	while ps.health > 0 and guard < 20:
		ps.set("_invuln_left", 0.0)
		ps.take_hit(1)
		guard += 1
	if err.is_empty() and not go.is_open():
		err = "game over should open on PlayerStats.died"
	if err.is_empty() and not _tree().paused:
		err = "game over must pause the tree"
	if err.is_empty() and go.process_mode != Node.PROCESS_MODE_ALWAYS:
		err = "screen must keep processing while paused"
	if err.is_empty() and (go.root as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
		err = "screen must capture the mouse"
	if err.is_empty() and (go.gold_label.text.strip_edges() != "7 gold" or not go.stage_label.text.contains("1")):
		err = "stage/gold wrong: '%s' '%s'" % [go.stage_label.text, go.gold_label.text]
	if err.is_empty() and go.seed_label.visible:
		err = "seed field must hide when the level has no seed"
	var panel: Control = go.root.find_child("TextPanel", true, false)
	if err.is_empty() and (panel == null or panel.anchor_left < 0.5):
		err = "game-over text must sit on the right half"
	if err.is_empty() and (go.retry_button == null or go.new_run_button == null):
		err = "needs New run and Retry seed"
	if err.is_empty() and (go.new_run_button.text != "New run" or go.retry_button.text != "Retry seed"):
		err = "button labels: '%s' '%s'" % [go.new_run_button.text, go.retry_button.text]
	if err.is_empty() and go.new_run_button.get_index() > go.retry_button.get_index():
		err = "New run must be the primary (first) button"
	if err.is_empty() and not go.retry_button.disabled:
		err = "Retry seed must be disabled when the level has no seed"
	go.close()
	if err.is_empty() and _tree().paused:
		err = "closing must unpause"
	_cleanup([go, b, ps])
	_reset_world()
	return err


func test_game_over_fallback() -> String:
	var b := _bus()
	var go: Node = load("res://scripts/ui/game_over.gd").new()
	go.set("bus", b)
	var sk := HudSkin.new()
	sk.game_over_slot = "no_such_slot"
	sk.coin_slot = "no_such_coin"
	go.set("skin", sk)
	var log := _ErrCount.new()
	OS.add_logger(log)
	_root().add_child(go)
	b.player_died.emit()
	OS.remove_logger(log)
	var err := ""
	if go.has_art or go.root.find_child("TextPanel", true, false) is not PanelContainer:
		err = "missing art slot should fall back to the themed panel"
	if err.is_empty() and not log.errors.is_empty():
		err = "errors: %s" % str(log.errors)
	_cleanup([go, b])
	_reset_world()
	return err


func test_shop_buy() -> String:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	var gs := _root().get_node_or_null(^"GameState")
	if gs == null:
		_cleanup([b, ps])
		return "GameState autoload missing"
	b.wire_game_state(gs)
	b._shop = RefCounted.new()   # no roll_stock: skip BE's real Shop, use the stub below
	b.shop_stub = func(_n, _s, _sd): return [
		{"id": "a", "display_name": "Soft Shoes", "description": "", "icon_slot": "item_icon_soft_shoes", "price": 6, "rarity": "common"},
		{"id": "b", "display_name": "Bright Bulb", "description": "", "icon_slot": "no_icon", "price": 8, "rarity": "rare"},
		{"id": "c", "display_name": "Minimap", "description": "", "icon_slot": "item_icon_minimap", "price": 3, "rarity": "rare"},
		{"id": "d", "display_name": "Extra", "description": "", "icon_slot": "", "price": 1, "rarity": "common"},
	]
	ps.add_gold(10)
	var shop := _mount("res://scripts/ui/shop.gd", b)
	var err := ""
	gs.on_reach_exit()   # REAL exit hook → FESignals.stage_cleared → shop
	if not shop.is_open():
		err = "shop should open on GameState.reached_exit"
	if err.is_empty() and not _tree().paused:
		err = "shop must pause the tree"
	if err.is_empty() and shop.offers.size() != 4:
		err = "default offer count should be 4 (whole stock), got %d" % shop.offers.size()
	if err.is_empty() and not shop.buy_index(0):
		err = "buy with enough gold should succeed"
	if err.is_empty() and ps.gold != 4:
		err = "gold should drop 10→4 via PlayerStats.try_spend, got %d" % ps.gold
	if err.is_empty() and (not shop.is_sold(0) or shop.buy_index(0)):
		err = "bought offer must be sold out and not re-buyable"
	if err.is_empty() and shop.buy_index(1):
		err = "buy with insufficient gold (8 > 4) must be rejected"
	if err.is_empty() and (ps.gold != 4 or shop.is_sold(1)):
		err = "rejected buy must not change gold/sold state"
	if err.is_empty() and not shop.message.text.contains("Not enough"):
		err = "rejected buy should give feedback"
	shop._on_continue()
	if err.is_empty() and (shop.is_open() or _tree().paused):
		err = "Continue must close + unpause"
	if err.is_empty() and b.stage != 2:
		err = "Continue should advance the stage counter, got %d" % b.stage
	_cleanup([shop, b, ps])
	_reset_world()
	return err


class _FakeItem extends Resource:
	var id := "x"
	var display_name := "Lucky Coin"
	var description := "More gold."
	var icon_slot := "item_icon_lucky_coin"
	var price := 5
	var rarity := "epic"
	var applied := 0
	func apply() -> void: applied += 1
	func remove() -> void: applied -= 1


class _FakeShop extends RefCounted:
	var ps: Node
	var rolled := []
	var items := []
	func roll_stock(stage: int, run_seed: int) -> Array:
		rolled = [stage, run_seed]
		return items
	func buy(item) -> bool:
		if not ps.try_spend(item.price):
			return false
		item.apply()
		return true


func test_shop_be_interface() -> String:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	var fs := _FakeShop.new()
	fs.ps = ps
	var it := _FakeItem.new()
	fs.items = [it, _FakeItem.new()]
	b._shop = fs
	b.stage = 4
	var offers: Array = b.get_shop_offer(3)
	var err := ""
	if fs.rolled != [4, -1]:
		err = "should call Shop.roll_stock(stage, seed), got %s" % str(fs.rolled)
	if err.is_empty() and (offers.size() != 2 or offers[0].display_name != "Lucky Coin" or offers[0].price != 5 or offers[0].icon_slot != "item_icon_lucky_coin" or offers[0].item != it):
		err = "offer must mirror Item fields: %s" % str(offers)
	ps.add_gold(6)
	if err.is_empty() and (not b.buy_offer(offers[0]) or ps.gold != 1 or it.applied != 1):
		err = "buy_offer should go through Shop.buy (gold %d applied %d)" % [ps.gold, it.applied]
	if err.is_empty() and b.buy_offer(offers[1]):
		err = "Shop.buy rejection must propagate"
	_cleanup([b, ps])
	return err


func test_shop_empty() -> String:
	var b := _bus()
	b._shop = RefCounted.new()   # no roll_stock and no stub: an empty item source
	var log := _ErrCount.new()
	OS.add_logger(log)
	var shop := _mount("res://scripts/ui/shop.gd", b)
	b.stage_cleared.emit(1)
	var bought: bool = shop.buy_index(0)
	shop._on_continue()
	OS.remove_logger(log)
	var err := ""
	if bought:
		err = "nothing to buy in an empty shop"
	if err.is_empty() and (shop.offers.size() != 0 or shop.message.text.is_empty()):
		err = "empty source should show a message"
	if err.is_empty() and not log.errors.is_empty():
		err = "errors: %s" % str(log.errors)
	_cleanup([shop, b])
	_reset_world()
	return err


func test_shop_layout() -> String:
	var b := _bus()
	var shop := _mount("res://scripts/ui/shop.gd", b)
	shop.open_shop()
	shop._layout_merchant()
	var band: Vector2 = shop.merchant_band()
	var err := ""
	var vw: float = shop.root.size.x
	if vw <= 0.0:
		err = "screen root has no size"
	var expected: float = vw * 0.5 + (shop.skin.merchant_x - 160.0) * (vw / 320.0)
	if err.is_empty() and absf((band.x + band.y) * 0.5 - expected) > 2.0:
		err = "merchant should stand at backdrop x=172 (%.0f), got %.0f" % [expected, (band.x + band.y) * 0.5]
	for n in ["OffersPanel", "InfoPanel"]:
		var p: Control = shop.root.find_child(n, true, false)
		var r := p.get_global_rect()
		if err.is_empty() and r.position.x < band.y and r.end.x > band.x:
			err = "%s %s overlaps merchant band %s" % [n, str(r), str(band)]
	_cleanup([shop, b])
	_reset_world()
	return err


class _Chaser extends Node2D:
	var enraged := false


func test_alert_scales() -> String:
	var b := _bus()
	var hud := _mount("res://scripts/ui/alert_hud.gd", b)
	var es: Array = []
	for i in 12:
		var e := _Chaser.new()
		e.add_to_group("puppets")
		e.enraged = i < 7
		_root().add_child(e)
		es.append(e)
	hud.refresh()
	var err := ""
	if b.enemy_total() != 12 or b.chasing_count() != 0:
		err = "`enraged` must not be polled: want 0 / 12, got %d / %d" % [b.chasing_count(), b.enemy_total()]
	if err.is_empty() and hud.label.text != "Chasing 0 / 12":
		err = "label '%s'" % hud.label.text
	for i in 12:
		b.report_chase(es[i], true)   # only BE reports count
	hud.refresh()
	if err.is_empty() and hud.label.text != "Chasing 12 / 12":
		err = "reported count should reach 12, label '%s'" % hud.label.text
	for i in 13:
		var e := _Chaser.new(); e.add_to_group("enemies"); _root().add_child(e); es.append(e)
		b.report_chase(e, true)
	hud.refresh()
	if err.is_empty() and hud.label.text != "Chasing 25 / 25":
		err = "should scale past the pip cap, label '%s'" % hud.label.text
	es[0].free()
	hud.refresh()
	if err.is_empty() and hud.label.text != "Chasing 24 / 24":
		err = "freed enemies drop out, label '%s'" % hud.label.text
	es.remove_at(0)
	_cleanup(es + [hud, b])
	return err


## Chase count = BE report_chase only: several chasers add up, a give-up
## (report_chase false) drops it, duplicates don't double count; HUD follows the signal.
func test_alert_follows_reports() -> String:
	var b := _bus()
	var hud := _mount("res://scripts/ui/alert_hud.gd", b)
	var es: Array = []
	for i in 5:
		var e := _Chaser.new(); e.add_to_group("enemies"); _root().add_child(e); es.append(e)
	var err := ""
	for i in 3:
		b.report_chase(es[i], true)
	if b.chasing_count() != 3 or hud.label.text != "Chasing 3 / 5":
		err = "3 reported chasers: count %d, label '%s'" % [b.chasing_count(), hud.label.text]
	b.report_chase(es[0], true)   # BE re-reporting the same chaser
	if err.is_empty() and b.chasing_count() != 3:
		err = "duplicate report double counted: %d" % b.chasing_count()
	b.report_chase(es[1], false)   # gave up (RETURN)
	if err.is_empty() and (b.chasing_count() != 2 or hud.label.text != "Chasing 2 / 5"):
		err = "give-up should drop to 2: count %d, label '%s'" % [b.chasing_count(), hud.label.text]
	b.report_chase(es[1], false)
	if err.is_empty() and b.chasing_count() != 2:
		err = "second give-up changed the count"
	es[4].enraged = true   # legacy flag without a report: ignored
	if err.is_empty() and b.chasing_count() != 2:
		err = "unreported enraged enemy counted"
	b.report_chase(es[0], false); b.report_chase(es[2], false)
	if err.is_empty() and (b.chasing_count() != 0 or hud.label.text != "Chasing 0 / 5"):
		err = "all gave up: count %d, label '%s'" % [b.chasing_count(), hud.label.text]
	_cleanup(es + [hud, b])
	return err


## Arrows = off-screen enemies BE reported chasing; gauge = reported chase memory.
func test_arrows_from_reports() -> String:
	var b := _bus()
	var arrows := _mount("res://scripts/ui/offscreen_arrows.gd", b)
	var cam := Camera2D.new(); _root().add_child(cam); cam.make_current()
	var mk := func(at: Vector2) -> Node2D:
		var e := _Chaser.new(); e.add_to_group("enemies"); _root().add_child(e)
		e.global_position = at
		return e
	var a: Node2D = mk.call(Vector2(5000, 0))     # reported, off-screen
	var u: Node2D = mk.call(Vector2(-5000, 0))    # enraged but never reported
	var on: Node2D = mk.call(cam.get_screen_center_position())   # reported, on-screen
	var n: Node2D = mk.call(Vector2(0, 5000))     # reported, no memory yet
	u.enraged = true
	b.report_chase(a, true); b.report_chase_memory(a, 0.4)
	b.report_chase(on, true); b.report_chase_memory(on, 0.9)
	arrows._process(0.1)
	var err := ""
	if arrows.arrows.size() != 1 or arrows.arrows[0]["enemy"] != a:
		err = "want exactly one arrow (reported off-screen chaser), got %s" % [arrows.arrows.map(func(x): return x["enemy"])]
	if err.is_empty() and absf(arrows.arrows[0]["ratio"] - 0.4) > 0.0001:
		err = "gauge should be BE memory 0.4, got %f" % arrows.arrows[0]["ratio"]
	b.report_chase_memory(a, 0.15)   # draining in SEARCH
	arrows._process(0.1)
	if err.is_empty() and absf(arrows.arrows[0]["ratio"] - 0.15) > 0.0001:
		err = "gauge should follow the memory report, got %f" % arrows.arrows[0]["ratio"]
	b.report_chase(n, true)
	arrows._process(0.1)
	if err.is_empty() and arrows.arrows.size() != 2:
		err = "second off-screen chaser should add an arrow"
	for x in arrows.arrows:
		if err.is_empty() and x["enemy"] == n and x["ratio"] != 1.0:
			err = "no memory report yet → full gauge, got %f" % x["ratio"]
	b.report_chase(a, false); b.report_chase(n, false)   # gave up
	arrows._process(0.1)
	if err.is_empty() and not arrows.arrows.is_empty():
		err = "arrows should go away on give-up reports"
	_cleanup([a, u, on, n, arrows, cam, b])
	return err


func test_stage_banner() -> String:
	var b := _bus()
	var bn: Node = load("res://scripts/ui/stage_banner.gd").new()
	bn.set("bus", b)
	bn.set("autoplay", false)
	_root().add_child(bn)
	var err := ""
	b.announce_stage(3)
	if bn.title.text != "Stage 3":
		err = "banner should show 'Stage 3', got '%s'" % bn.title.text
	bn._tween.custom_step(0.3)
	if err.is_empty() and not bn.is_showing():
		err = "banner should be visible after fade-in"
	bn._tween.custom_step(10.0)
	if err.is_empty() and bn.is_showing():
		err = "banner should fade out and hide"
	_cleanup([bn, b])
	return err


func test_main_screens() -> String:
	var st: SceneState = (load("res://scenes/main.tscn") as PackedScene).get_state()
	var names := []
	for i in st.get_node_count():
		names.append(str(st.get_node_name(i)))
	for n in ["HUD", "GameOver", "Shop", "WinScreen", "AIWatermark"]:
		if not names.has(n):
			return "main.tscn missing %s" % n
	var hud: CanvasLayer = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	_root().add_child(hud)
	var err := ""
	for n in ["AlertHud", "StageBanner"]:
		var c: Control = hud.find_child(n, true, false)
		if c == null:
			err = "HUD missing %s" % n
		elif c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			err = "%s must stay mouse-ignore" % n
	_cleanup([hud])
	return err


# --- No continues: New run / Retry seed ----------------------------------------
const FAKE_LEVEL := "res://tests/fixtures/fake_level.tscn"


## A run in progress: dying on `at_stage` of run seed `rs` with gold, an item
## modifier and an inventory item. Returns [ps, bus, game_over].
func _dying_run(rs: int, at_stage: int, level_seed: int = -1) -> Array:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	b.swap_deferred = false
	var lvl: Node = load(FAKE_LEVEL).instantiate()
	lvl.set("level_seed", rs if level_seed < 0 else level_seed)
	lvl.set("stage", at_stage)
	_root().add_child(lvl)
	_tree().current_scene = lvl
	b.stage = at_stage
	var go := _mount("res://scripts/ui/game_over.gd", b)
	ps.add_gold(25)
	ps.add_modifier(&"max_health", 1.0, 1.0, "extra_heart")   # a bought item
	ps.add_modifier(&"move_speed", 20.0, 1.0, "soft_shoes")
	b.set_items([{id = "vase", slot = "vase", name = "Vase", throwable = true}])
	var guard := 0
	while ps.health > 0 and guard < 20:
		ps.set("_invuln_left", 0.0)
		ps.take_hit(1)
		guard += 1
	return [ps, b, go]


func _fresh_run_err(ps: Node, b: Node) -> String:
	var lvl: Node = _tree().current_scene
	if lvl == null or lvl.scene_file_path != FAKE_LEVEL:
		return "level was not re-instanced"
	if int(lvl.get("stage")) != 1 or b.get_stage() != 1:
		return "must restart at stage 1 (got %s / %d)" % [lvl.get("stage"), b.get_stage()]
	if ps.health != 3 or ps.max_health() != 3 or b.health != 3 or b.max_health != 3:
		return "hearts must be 3/3 (stats %d/%d, hud %d/%d)" % [ps.health, ps.max_health(), b.health, b.max_health]
	if ps.gold != 0 or b.gold != 0:
		return "gold must be 0 (stats %d, hud %d)" % [ps.gold, b.gold]
	if not is_equal_approx(ps.get_stat(&"move_speed"), float(ps.BASE[&"move_speed"])):
		return "item modifiers must be cleared"
	if not b.items.is_empty():
		return "inventory must be empty"
	if _tree().paused:
		return "new run must be unpaused"
	return ""


func _end_run(nodes: Array) -> void:
	var cur := _tree().current_scene
	_tree().current_scene = null
	if is_instance_valid(cur):
		cur.free()
	_cleanup(nodes)
	_reset_world()


func test_new_run() -> String:
	var r := _dying_run(4242, 3)
	var ps: Node = r[0]
	var b: Node = r[1]
	var go: Node = r[2]
	var err := ""
	if not go.is_open():
		err = "game over should be open"
	if err.is_empty() and (go.seed_label.text != "Run seed 4242" or go.retry_button.disabled):
		err = "should show run seed 4242 with Retry seed enabled (got '%s')" % go.seed_label.text
	if err.is_empty():
		go.new_run_button.pressed.emit()
		err = _fresh_run_err(ps, b)
	if err.is_empty():
		var s := int(_tree().current_scene.get("level_seed"))
		if s < 0 or s == 4242:
			err = "New run must roll a new seed (got %d)" % s
		elif b.get_run_seed() != s:
			err = "run seed must become the new level's seed (%d vs %d)" % [b.get_run_seed(), s]
	_end_run([go, b, ps])
	return err


func test_retry_seed() -> String:
	var r := _dying_run(4242, 3)
	var ps: Node = r[0]
	var b: Node = r[1]
	var go: Node = r[2]
	go.retry_button.pressed.emit()
	var err := _fresh_run_err(ps, b)
	if err.is_empty() and int(_tree().current_scene.get("level_seed")) != 4242:
		err = "Retry seed must replay seed 4242 (got %s)" % _tree().current_scene.get("level_seed")
	if err.is_empty() and b.get_run_seed() != 4242:
		err = "run seed must stay 4242"
	if err.is_empty() and go.is_open():
		err = "game over should close"
	_end_run([go, b, ps])
	return err


## Even if a level reported a per-stage seed, Retry seed uses the run's stage-1 seed.
func test_retry_uses_run_seed() -> String:
	var r := _dying_run(4242, 4, 9999)
	var ps: Node = r[0]
	var b: Node = r[1]
	var go: Node = r[2]
	var err := ""
	# Run seed was captured at stage 1 before the death; simulate that.
	if err.is_empty():
		b.run_seed = 4242
		go.show_for_run()
		if go.seed_label.text != "Run seed 4242":
			err = "game over must show the run seed, got '%s'" % go.seed_label.text
	if err.is_empty():
		go.retry_button.pressed.emit()
		err = _fresh_run_err(ps, b)
	if err.is_empty() and int(_tree().current_scene.get("level_seed")) != 4242:
		err = "Retry seed used the stage seed %s, not run seed 4242" % _tree().current_scene.get("level_seed")
	_end_run([go, b, ps])
	return err


func test_next_stage_keeps_run() -> String:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	b.swap_deferred = false
	b.run_seed = -1
	var lvl: Node = load(FAKE_LEVEL).instantiate()
	lvl.set("level_seed", 5151)
	_root().add_child(lvl)
	_tree().current_scene = lvl
	ps.add_gold(9)
	ps.set("_invuln_left", 0.0)
	ps.take_hit(1)
	b.next_stage()
	var cur: Node = _tree().current_scene
	var err := ""
	if cur == lvl or int(cur.get("stage")) != 2 or int(cur.get("level_seed")) != 5151:
		err = "next stage must be stage 2 of run seed 5151 (got %s / %s)" % [cur.get("stage"), cur.get("level_seed")]
	if err.is_empty() and (ps.gold != 9 or b.gold != 9 or ps.health != 2 or b.health != 2):
		err = "Continue must keep hearts/gold (stats %d/%d, hud %d/%d)" % [ps.health, ps.gold, b.health, b.gold]
	if err.is_empty() and b.get_run_seed() != 5151:
		err = "run seed must persist across stages"
	_end_run([b, ps])
	return err


# --- Win screen / run length / carry-over ----------------------------------------
## A run on `at_stage` of run seed `rs` with screens mounted and the bus wired to
## the real GameState. Returns [ps, bus, shop, win, gs].
func _run_at(rs: int, at_stage: int) -> Array:
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	b.swap_deferred = false
	var gs := _root().get_node(^"GameState")
	gs.reset()
	b.wire_game_state(gs)
	var lvl: Node = load(FAKE_LEVEL).instantiate()
	lvl.set("level_seed", rs)
	lvl.set("stage", at_stage)
	_root().add_child(lvl)
	_tree().current_scene = lvl
	b.stage = at_stage
	var shop := _mount("res://scripts/ui/shop.gd", b)
	var win := _mount("res://scripts/ui/win_screen.gd", b)
	return [ps, b, shop, win, gs]


func test_win_on_last_stage() -> String:
	var r := _run_at(7070, 5)
	var b: Node = r[1]
	var shop: Node = r[2]
	var win: Node = r[3]
	var gs: Node = r[4]
	var err := ""
	if b.MAX_STAGES != 5:
		err = "MAX_STAGES must be 5 (docs/PRODUCT.md)"
	r[0].add_gold(40)
	gs.on_reach_exit()
	if err.is_empty() and not win.is_open():
		err = "stage 5 exit must open the win screen"
	if err.is_empty() and shop.is_open():
		err = "stage 5 exit must NOT open the shop"
	if err.is_empty() and not _tree().paused:
		err = "win screen must pause the tree"
	if err.is_empty() and (win.process_mode != Node.PROCESS_MODE_ALWAYS or (win.root as Control).mouse_filter != Control.MOUSE_FILTER_STOP):
		err = "win screen must keep processing and capture the mouse"
	if err.is_empty() and (win.seed_label.text != "Run seed 7070" or win.gold_label.text.strip_edges() != "40 gold"):
		err = "win must show run seed + gold (got '%s' '%s')" % [win.seed_label.text, win.gold_label.text]
	if err.is_empty() and (win.new_run_button == null or win.new_run_button.text != "New run"):
		err = "win needs a New run button"
	var panel: Control = win.root.find_child("TextPanel", true, false)
	if err.is_empty() and (panel == null or panel.anchor_left < 0.5):
		err = "win text must sit on the right half"
	# Slot order: win_screen_art (not merged yet) → game_over_art styling → panel.
	if err.is_empty():
		var want := "win_screen_art" if UiArt.texture("win_screen_art") else ("game_over_art" if UiArt.texture("game_over_art") else "")
		if win.art_slot != want:
			err = "win art slot want '%s' got '%s'" % [want, win.art_slot]
	win.close()
	_end_run([win, shop, b, r[0]])
	return err


func test_shop_on_stages_1_to_4() -> String:
	var r := _run_at(3131, 1)
	var b: Node = r[1]
	var shop: Node = r[2]
	var win: Node = r[3]
	var gs: Node = r[4]
	var err := ""
	# Play the whole run through the real Continue button: 1 → 2 → 3 → 4 → 5.
	for s in range(1, 5):
		if int(_tree().current_scene.get("stage")) != s:
			err = "expected stage %d, level is on %s" % [s, _tree().current_scene.get("stage")]
			break
		gs.on_reach_exit()
		if not shop.is_open() or win.is_open():
			err = "stage %d exit must open the shop, not the win screen" % s
			break
		shop.continue_button.pressed.emit()
		if int(_tree().current_scene.get("level_seed")) != 3131:
			err = "stage %d must keep the run seed" % (s + 1)
			break
	if err.is_empty():
		gs.on_reach_exit()
		if not win.is_open() or shop.is_open():
			err = "after 4 shops, the stage 5 exit must open the win screen"
	win.close()
	_end_run([win, shop, b, r[0]])
	return err


func test_win_double_trigger() -> String:
	var r := _run_at(4040, 5)
	var b: Node = r[1]
	var shop: Node = r[2]
	var win: Node = r[3]
	var gs: Node = r[4]
	var lvl: Node = _tree().current_scene
	var opened := [0]
	win.opened.connect(func(): opened[0] += 1)
	gs.on_reach_exit()
	gs.on_reach_exit()          # GameState guard
	gs.reset()
	gs.on_reach_exit()          # past GameState's guard → FE guard
	b.on_reached_exit()
	b.next_stage()              # e.g. a stale Continue
	b._swap_scene(4040, 6, false)   # nothing may ever load stage 6
	var err := ""
	if _tree().current_scene != lvl or int(lvl.get("stage")) != 5 or b.get_stage() != 5:
		err = "double trigger advanced the run (stage %d)" % b.get_stage()
	if err.is_empty() and opened[0] != 1:
		err = "win screen opened %d times" % opened[0]
	if err.is_empty() and shop.is_open():
		err = "shop opened after the win"
	win.close()
	_end_run([win, shop, b, r[0]])
	return err


func test_win_new_run() -> String:
	var r := _run_at(5555, 5)
	var ps: Node = r[0]
	var b: Node = r[1]
	var shop: Node = r[2]
	var win: Node = r[3]
	var gs: Node = r[4]
	ps.add_gold(60)
	ps.add_modifier(&"max_health", 1.0, 1.0, "extra_heart")
	ps.add_modifier(&"move_speed", 20.0, 1.0, "soft_shoes")
	b.set_items([{id = "vase", slot = "vase", name = "Vase", throwable = true}])
	gs.on_reach_exit()
	var err := "" if win.is_open() else "win screen should be open"
	if err.is_empty():
		win.new_run_button.pressed.emit()
		err = _fresh_run_err(ps, b)
	if err.is_empty():
		var s := int(_tree().current_scene.get("level_seed"))
		if s < 0 or s == 5555 or b.get_run_seed() != s:
			err = "New run must roll a new run seed (got %d, run %d)" % [s, b.get_run_seed()]
	if err.is_empty() and (win.is_open() or b.is_run_won()):
		err = "new run must close the win screen and clear the won state"
	if err.is_empty():
		gs.on_reach_exit()
		if not shop.is_open() or win.is_open():
			err = "stage 1 of the new run must go to the shop again"
	shop.close()
	_end_run([win, shop, b, ps])
	return err


func test_continue_carry_over() -> String:
	var r := _run_at(2626, 2)
	var ps: Node = r[0]
	var b: Node = r[1]
	var shop: Node = r[2]
	var win: Node = r[3]
	var gs: Node = r[4]
	ps.add_gold(30)
	ps.add_modifier(&"max_health", 1.0, 1.0, "extra_heart")   # bought item: 4 max
	ps.set("_invuln_left", 0.0)
	ps.take_hit(1)                                            # 3 / 4
	var inv: Node = _tree().current_scene.get_node(^"Player/Inventory")
	inv.add({id = "vase", slot = "vase", name = "Vase", throwable = true})
	b.set_items(inv.items)
	gs.on_reach_exit()
	shop.continue_button.pressed.emit()
	var lvl: Node = _tree().current_scene
	var err := ""
	if int(lvl.get("stage")) != 3:
		err = "Continue must load stage 3"
	var new_inv: Node = lvl.get_node_or_null(^"Player/Inventory")
	if err.is_empty() and (new_inv == null or new_inv == inv or not new_inv.items.is_empty() or not b.items.is_empty()):
		err = "held props must be dropped on Continue"
	if err.is_empty() and (ps.gold != 30 or b.gold != 30):
		err = "gold must carry over (stats %d, hud %d)" % [ps.gold, b.gold]
	if err.is_empty() and (ps.health != 3 or ps.max_health() != 4 or b.health != 3 or b.max_health != 4):
		err = "hearts + bought max-heart item must carry over (stats %d/%d, hud %d/%d)" % [ps.health, ps.max_health(), b.health, b.max_health]
	_end_run([win, shop, b, ps])
	return err


# --- Single end-of-run latch (QA blocker on 0ed2324) -----------------------------
## _run_at + a mounted game-over screen. Returns [ps, bus, shop, win, gs, go].
func _end_run_at(rs: int, at_stage: int) -> Array:
	var r := _run_at(rs, at_stage)
	r.append(_mount("res://scripts/ui/game_over.gd", r[1]))
	return r


func _kill(ps: Node) -> void:
	if ps.health > 0:
		ps.take_hit(ps.health, true)


## "" when exactly `want` ("win" / "go") is the only open end screen and the shop is shut.
func _only_open(r: Array, want: String) -> String:
	var shop: Node = r[2]
	var win: Node = r[3]
	var go: Node = r[5]
	if shop.is_open():
		return "shop must stay closed after the run ended"
	if want == "win" and (not win.is_open() or go.is_open()):
		return "want only the win screen (win %s, game over %s)" % [win.is_open(), go.is_open()]
	if want == "go" and (not go.is_open() or win.is_open()):
		return "want only game over (game over %s, win %s)" % [go.is_open(), win.is_open()]
	return ""


func _close_all(r: Array) -> void:
	for i in [2, 3, 5]:
		if r[i].is_open():
			r[i].close()
	_end_run([r[5], r[3], r[2], r[1], r[0]])


func test_latch_win_then_died() -> String:
	var r := _end_run_at(9191, 5)
	var ps: Node = r[0]
	var b: Node = r[1]
	var gs: Node = r[4]
	gs.on_reach_exit()
	var err := _only_open(r, "win")
	if err.is_empty():
		# A hit lands after the win (pre-#21 take_hit still kills): hearts irrelevant.
		_kill(ps)
		err = _only_open(r, "win")
	if err.is_empty():
		# Even with BE's flag cleared, the FE latch alone blocks every other end event.
		gs.reset()
		b.on_player_died()
		b.player_died.emit()          # direct emit (demo K key path)
		gs.on_reach_exit()
		err = _only_open(r, "win")
	if err.is_empty() and b.run_end_kind() != &"won":
		err = "latch should be 'won', got '%s'" % b.run_end_kind()
	_close_all(r)
	return err


func test_latch_died_then_exit() -> String:
	var err := ""
	for at in [2, 5]:   # shop stage and the last (win) stage
		var r := _end_run_at(8181, at)
		var ps: Node = r[0]
		var b: Node = r[1]
		var gs: Node = r[4]
		_kill(ps)
		err = _only_open(r, "go")
		if err.is_empty():
			gs.reset()                # past GameState's own guard
			gs.on_reach_exit()
			b.on_reached_exit()
			b.next_stage()
			err = _only_open(r, "go")
		if err.is_empty() and int(_tree().current_scene.get("stage")) != at:
			err = "run advanced after death"
		_close_all(r)
		if not err.is_empty():
			return "stage %d: %s" % [at, err]
	return err


func test_latch_same_frame() -> String:
	# Death then exit in the same frame → only game over.
	var r := _end_run_at(7171, 5)
	r[1].on_player_died()
	r[4].on_reach_exit()
	var err := _only_open(r, "go")
	_close_all(r)
	if not err.is_empty():
		return "died→exit: " + err
	# Exit then death in the same frame → only win (BE flag set, and FE latch).
	r = _end_run_at(7171, 5)
	r[4].on_reach_exit()
	_kill(r[0])
	r[1].on_player_died()
	err = _only_open(r, "win")
	_close_all(r)
	if not err.is_empty():
		return "exit→died: " + err
	# Direct screen calls in both orders: the screens themselves respect the latch.
	r = _end_run_at(7171, 5)
	r[5].show_for_run()
	r[3].show_for_run()
	err = _only_open(r, "go")
	_close_all(r)
	if not err.is_empty():
		return "screens go→win: " + err
	r = _end_run_at(7171, 5)
	r[3].show_for_run()
	r[5].show_for_run()
	err = _only_open(r, "win")
	_close_all(r)
	return "" if err.is_empty() else "screens win→go: " + err


func test_latch_cleared() -> String:
	var r := _end_run_at(6161, 5)
	var ps: Node = r[0]
	var b: Node = r[1]
	var win: Node = r[3]
	var gs: Node = r[4]
	var go: Node = r[5]
	var err := ""
	gs.on_reach_exit()
	win.new_run_button.pressed.emit()          # win → New run
	if b.is_run_over() or win.is_open():
		err = "New run must clear the latch"
	if err.is_empty():
		_kill(ps)                               # a later death works again
		err = _only_open(r, "go")
	if err.is_empty():
		go.retry_button.pressed.emit()          # game over → Retry seed
		if b.is_run_over() or go.is_open():
			err = "Retry seed must clear the latch"
	if err.is_empty():
		_tree().current_scene.set("stage", 5)   # jump to the last stage of the retry
		gs.on_reach_exit()                      # a later win works again
		err = _only_open(r, "win")
	if err.is_empty():
		win.new_run_button.pressed.emit()
		_kill(ps)
		err = _only_open(r, "go")
	_close_all(r)
	return err


## A PR #22-shaped GameState (run_over + end_run_won) without touching the BE file.
func _fake_gs22() -> Node:
	var src := GDScript.new()
	src.source_code = """extends Node
signal reached_exit
var game_over := false
var run_over := false
var won_calls := 0
func on_reach_exit() -> void:
	if game_over:
		return
	game_over = true
	reached_exit.emit()
func end_run_won() -> void:
	won_calls += 1
	game_over = true
	run_over = true
func reset() -> void:
	game_over = false
	run_over = false
"""
	src.reload()
	var gs: Node = src.new()
	_root().add_child(gs)
	return gs


func test_win_end_run_won() -> String:
	var err := ""
	# 1) Stage 5 win → the win screen opens AND tells BE (end_run_won, once).
	var pb := _stats_bus()
	var ps: Node = pb[0]
	var b: Node = pb[1]
	b.swap_deferred = false
	var gs := _fake_gs22()
	b.wire_game_state(gs)
	var lvl: Node = load(FAKE_LEVEL).instantiate()
	lvl.set("stage", 5)
	_root().add_child(lvl)
	_tree().current_scene = lvl
	var win := _mount("res://scripts/ui/win_screen.gd", b)
	var go := _mount("res://scripts/ui/game_over.gd", b)
	gs.on_reach_exit()
	if not win.is_open():
		err = "win screen should open"
	if err.is_empty() and (gs.won_calls != 1 or not gs.run_over):
		err = "win must call GameState.end_run_won() once (calls %d)" % gs.won_calls
	if err.is_empty():
		win.show_for_run()           # re-show: no second call
		b.on_player_died()
		if gs.won_calls != 1 or go.is_open():
			err = "re-show / late death must not re-notify or open game over"
	# 2) Stage 1–4 exits never call it (a normal exit is not a run end).
	if err.is_empty():
		win.new_run_button.pressed.emit()
		gs.on_reach_exit()           # stage 1 of the new run
		if gs.won_calls != 1 or win.is_open() or gs.run_over:
			err = "a stage 1 exit must not end the run (calls %d)" % gs.won_calls
	# 3) BE run_over (e.g. a BE-side death) with the FE latch free → exit + death ignored.
	if err.is_empty():
		b.reset()
		gs.reset()
		gs.run_over = true
		b.on_reached_exit()
		b.on_player_died()
		if win.is_open() or go.is_open() or b.is_run_over():
			err = "FE must respect GameState.run_over"
	for n in [win, go]:
		if n.is_open():
			n.close()
	_end_run([go, win, b, ps, gs])
	return err


# --- Real BE Enemy (PR #26) → FESignals autoload. Registered only when the enemy
# FSM that reports startle/chase is present, so this branch also runs before #26.
const ENEMY_BASE := "res://scripts/enemies/enemy_base.gd"


func _be_enemy_reports() -> bool:
	if not ResourceLoader.exists(ENEMY_BASE):
		return false
	var names: Array = (load(ENEMY_BASE) as Script).get_script_method_list().map(func(m): return m["name"])
	return names.has("_tick_startle") and names.has("is_chasing") and names.has("hear_noise")


func _be_add(n: Node, at: Vector2) -> Node:
	_root().add_child(n)
	n.global_position = at
	return n


func _be_reset(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()


func _be_puppet(at: Vector2):
	var e = load("res://scripts/enemies/puppet_hand.gd").new()
	_be_add(e, at)
	e.sight_override = 1
	e.tick(0.0)
	return e


## Real puppet lit for 0.5 s while FESignals ticks too: FE startle must equal the
## enemy's own value (≈0.5), not BE + FE integration (≈1.0) — counted once.
func test_be_startle_once() -> String:
	_be_reset([])
	var p: Node = _be_add(load("res://scripts/player/player_controller.gd").new(), Vector2(100, 100))
	var e = _be_puppet(Vector2(300, 100))
	var f = _be_puppet(Vector2(320, 100))
	e.lit_override = 1
	f.lit_override = 1
	FESignals.set_flashlight(true)
	FESignals.report_lit(e, true)   # what player_controller sends for beam hits
	FESignals.report_lit(f, true)
	var dt := 1.0 / 60.0
	for i in 30:
		e.tick(dt); f.tick(dt)
		FESignals._process(dt)
	var err := ""
	for x in [e, f]:
		if err.is_empty() and absf(FESignals.get_startle(x) - x.startle) > 0.0001:
			err = "FE startle %.3f != enemy %.3f (double counted)" % [FESignals.get_startle(x), x.startle]
		if err.is_empty() and absf(FESignals.get_startle(x) - 0.5) > 0.05:
			err = "startle after 0.5 s lit should be ~0.5, got %.3f" % FESignals.get_startle(x)
	e.lit_override = 0
	e.tick(dt); FESignals._process(dt)
	if err.is_empty() and FESignals.get_startle(e) != 0.0:
		err = "beam left: BE's reset report should zero FE startle, got %f" % FESignals.get_startle(e)
	if err.is_empty() and absf(FESignals.get_startle(f) - f.startle) > 0.0001:
		err = "other enemy's startle disturbed"
	_be_reset([e, f, p])
	return err


## Real puppets: several chase (noise) → count/arrows from reports; one gives up →
## count drops and its arrow goes; live count matches GameState, no cap.
func test_be_chase_reports() -> String:
	_be_reset([])
	var hud := _mount("res://scripts/ui/alert_hud.gd", FESignals)
	var arrows := _mount("res://scripts/ui/offscreen_arrows.gd", FESignals)
	var cam := Camera2D.new(); _root().add_child(cam); cam.make_current()
	var p: Node = _be_add(load("res://scripts/player/player_controller.gd").new(), Vector2(100, 100))
	var es: Array = []
	for i in 5:
		es.append(_be_puppet(Vector2(4000 + i * 40, 100)))   # off-screen
	var err := ""
	for i in 4:
		es[i].hear_noise()
	if FESignals.chasing_count() != 4 or GameState.chasing_count() != 4:
		err = "4 chasing: FE %d, GameState %d" % [FESignals.chasing_count(), GameState.chasing_count()]
	if err.is_empty() and (FESignals.enemy_total() != 5 or hud.label.text != "Chasing 4 / 5"):
		err = "HUD '%s' total %d" % [hud.label.text, FESignals.enemy_total()]
	arrows._process(0.1)
	if err.is_empty() and arrows.arrows.size() != 4:
		err = "want 4 arrows for off-screen chasers, got %d" % arrows.arrows.size()
	# es[0] loses the boy and gives up (memory drains → RETURN → report_chase false).
	var g = es[0]
	g.sight_override = 0
	g._track_left = 0.0
	var dt := 1.0 / 60.0
	var t := 0.0
	var min_ratio := 1.0
	while g.is_chasing() and t < 30.0:
		g.tick(dt); t += dt
		if FESignals.chasing.has(g):
			min_ratio = minf(min_ratio, FESignals.get_chase_memory(g))
	if err.is_empty() and g.is_chasing():
		err = "puppet never gave up"
	if err.is_empty() and min_ratio >= 1.0:
		err = "chase memory never drained in FE (no report_chase_memory)"
	if err.is_empty() and (FESignals.chasing_count() != 3 or hud.label.text != "Chasing 3 / 5"):
		err = "give-up should drop to 3: %d, '%s'" % [FESignals.chasing_count(), hud.label.text]
	arrows._process(0.1)
	if err.is_empty() and (arrows.arrows.size() != 3 or arrows.arrows.any(func(x): return x["enemy"] == g)):
		err = "gave-up puppet's arrow should go (arrows %d)" % arrows.arrows.size()
	_cleanup([hud, arrows, cam])
	_be_reset(es + [p])
	return err


# --- Shop: 4 cards, letter tiles, coin (fe/shop-4) ----------------------------
const LONG_SAMPLE := [
	{"id": "l1", "display_name": "Grandfather's Watch", "rarity": "rare", "price": 15, "icon_slot": "",
		"description": "Puppets need +0.5 s of light to startle. Ticks loudly: noise carries 10% farther, and every step you take is a little easier to hear."},
	{"id": "l2", "display_name": "Shadow Cloak", "rarity": "legendary", "price": 26, "icon_slot": "",
		"description": "Noise carries 40% less far and light is noticed 40% slower. Light reaches 25% less far and the beam is a little narrower."},
	{"id": "l3", "display_name": "Dim Filter", "rarity": "common", "price": 6, "icon_slot": "",
		"description": "A softer beam: puppets take 40% longer to notice it. Light reaches 20% less far, so you see less of the hall ahead."},
	{"id": "l4", "display_name": "Night Eyes", "rarity": "uncommon", "price": 15, "icon_slot": "",
		"description": "Puppets take much longer to notice your light (x0.6). Beam 10 degrees narrower, and the edges of rooms stay dark."},
]


## BE's ItemDb script (PR #27) via the global class list, or null.
func _item_db() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "ItemDb":
			var db = load(str(c.get("path", "")))
			return db if db is Script and "ITEMS" in db else null
	return null


## The 4 items with the longest descriptions: BE's real ones when ItemDb is there.
func _longest_offers() -> Array:
	var db := _item_db()
	if db == null:
		return LONG_SAMPLE.duplicate(true)
	var rows: Array = []
	for r in db.ITEMS:
		rows.append({"id": str(r.id), "display_name": str(r.name), "description": str(r.desc),
			"icon_slot": "", "price": int(r.price), "rarity": str(r.rarity)})
	rows.sort_custom(func(x, y): return str(x.description).length() > str(y.description).length())
	return rows.slice(0, 4)


## Lays out containers synchronously (tests don't wait for deferred sorts).
func _settle(n: Node) -> void:
	for _pass in 4:
		var stack: Array = [n]
		while not stack.is_empty():
			var c: Node = stack.pop_front()
			if c is Container:
				c.notification(Container.NOTIFICATION_SORT_CHILDREN)
			stack.append_array(c.get_children())


func _open_shop_with(items: Array, gold := 0) -> Array:
	var b := _bus()
	var fs := _FakeShop.new()
	fs.items = items
	b._shop = fs
	b.gold = gold
	var shop := _mount("res://scripts/ui/shop.gd", b)
	shop.open_shop()
	shop._layout_merchant()
	_settle(shop)
	return [shop, b]


func test_shop_full_stock() -> String:
	var err := ""
	for pair in [[4, 4], [2, 2], [7, 4], [1, 1]]:
		var items: Array = []
		for i in pair[0]:
			items.append({"id": "i%d" % i, "display_name": "Item %d" % i, "price": 1, "rarity": "common"})
		var sb := _open_shop_with(items)
		if err.is_empty() and sb[0].cards.size() != pair[1]:
			err = "stock of %d should show %d cards, got %d" % [pair[0], pair[1], sb[0].cards.size()]
		_cleanup(sb)
	_reset_world()
	return err


func test_shop_four_fit() -> String:
	var sb := _open_shop_with(_longest_offers(), 0)
	var shop: Node = sb[0]
	var err := ""
	var panel: Control = shop.root.find_child("OffersPanel", true, false)
	var frame_h: float = shop.root.size.y - panel.offset_top + panel.offset_bottom   # anchored height
	if shop.cards.size() != 4:
		err = "want 4 cards, got %d" % shop.cards.size()
	shop.buy_index(0)   # 0 gold → "Not enough gold for …"
	_settle(shop)
	var msg: Label = shop.message
	if err.is_empty() and not msg.text.begins_with("Not enough gold"):
		err = "message '%s'" % msg.text
	if err.is_empty() and panel.get_combined_minimum_size().y > frame_h + 0.5:
		err = "4 long cards + message need %.0f px, frame has %.0f" % [panel.get_combined_minimum_size().y, frame_h]
	var pr := panel.get_global_rect().grow(0.5)
	if err.is_empty() and absf(panel.size.y - frame_h) > 0.5:
		err = "OffersPanel grew past its frame: %.0f vs %.0f" % [panel.size.y, frame_h]
	for c in shop.cards:
		if err.is_empty() and not pr.encloses(c.get_global_rect()):
			err = "%s %s outside OffersPanel %s" % [c.name, str(c.get_global_rect()), str(pr)]
		var d: Label = c.find_child("Desc", true, false)
		if err.is_empty() and (d.max_lines_visible != 2 or d.get_visible_line_count() > 2):
			err = "%s description should be capped at 2 lines" % c.name
		if err.is_empty() and not c.tooltip_text.contains(d.text):
			err = "%s tooltip should carry the full description" % c.name
	var last: Control = shop.cards[-1]
	if err.is_empty() and (not msg.is_visible_in_tree() or msg.size.y < 1.0 or not pr.encloses(msg.get_global_rect())):
		err = "message %s not visible inside OffersPanel %s" % [str(msg.get_global_rect()), str(pr)]
	if err.is_empty() and msg.get_global_rect().position.y < last.get_global_rect().end.y:
		err = "message overlaps the last card"
	var band: Vector2 = shop.merchant_band()
	for n in ["OffersPanel", "InfoPanel"]:
		var r: Rect2 = shop.root.find_child(n, true, false).get_global_rect()
		if err.is_empty() and r.position.x < band.y and r.end.x > band.x:
			err = "%s %s overlaps merchant band %s" % [n, str(r), str(band)]
	_cleanup(sb)
	_reset_world()
	return err


func test_shop_letter_tile() -> String:
	var sb := _open_shop_with(_longest_offers().slice(0, 2) + [
		{"id": "bp", "display_name": "Big Pockets", "price": 10, "rarity": "uncommon", "icon_slot": "no_such_icon", "description": "x"}])
	var shop: Node = sb[0]
	var err := ""
	var c: Control = shop.cards[2]
	var tile: Control = c.find_child("Icon", true, false)
	if not tile is Panel:
		err = "missing icon should give a letter tile, got %s" % tile.get_class()
	if err.is_empty() and (absf(tile.size.x - tile.size.y) > 0.5 or tile.size.x < 63.0):
		err = "tile should be a 64 px square, got %s (card %s)" % [str(tile.size), str(c.size)]
	var l: Label = tile.find_child("Initials", true, false)
	if err.is_empty() and l.text != "BP":
		err = "initials '%s', want BP" % l.text
	var rim: Color = shop.skin.rarity_colors["uncommon"]
	var sbx := tile.get_theme_stylebox(&"panel") as StyleBoxFlat
	if err.is_empty() and (sbx == null or not sbx.border_color.is_equal_approx(rim) or not rim.is_equal_approx(Color("#5fd08a"))):
		err = "rim should be Designer's uncommon #5fd08a"
	var nm: Label = c.find_child("Name", true, false)
	if err.is_empty() and not nm.get_theme_color(&"font_color").is_equal_approx(rim):
		err = "name colour should match the rarity rim"
	_cleanup(sb)
	_reset_world()
	return err


func test_initials_sample() -> String:
	var S = load("res://scripts/ui/shop.gd")
	var want := {"Big Pockets": "BP", "Grandfather's Watch": "GW", "Minimap": "MI", "Sneakers": "SN",
		"Soft Shoes": "SS", "  extra   heart ": "EH", "X": "X", "": "?"}
	for k in want:
		if S.initials(k) != want[k]:
			return "initials('%s') = '%s', want '%s'" % [k, S.initials(k), want[k]]
	var u: Dictionary = S.unique_initials(PackedStringArray(["Spring Socks", "Soft Shoes", "Bright Bulb"]))
	var u2: Dictionary = S.unique_initials(PackedStringArray(["Soft Shoes", "Bright Bulb", "Spring Socks"]))
	if u != {"Soft Shoes": "SS", "Spring Socks": "SO", "Bright Bulb": "BB"} or u != u2:
		return "clash should give SS / SO regardless of order, got %s / %s" % [u, u2]
	return ""


func test_initials_itemdb() -> String:
	var S = load("res://scripts/ui/shop.gd")
	var names: PackedStringArray = []
	for r in _item_db().ITEMS:
		names.append(str(r.name))
	var u: Dictionary = S.unique_initials(names)
	var seen := {}
	for n in names:
		var t: String = u.get(n, "")
		if t.length() != 2:
			return "'%s' → '%s' is not two letters" % [n, t]
		if seen.has(t):
			return "'%s' and '%s' both → %s" % [seen[t], n, t]
		seen[t] = n
	return "" if seen.size() == names.size() else "%d names, %d tiles" % [names.size(), seen.size()]


func test_coin_face() -> String:
	var skin := HudSkin.load_default()
	if UiArt.frames(skin.coin_slot) == null:
		return ""   # no coin art: the drawn circle is used
	var holder: Control = UiScreen.coin_icon(skin.coin_slot, 28)
	var err := ""
	var face: TextureRect = holder.get_node_or_null("Face")
	if face == null:
		err = "coin should be a static face frame, not the spin loop"
	else:
		var img := face.texture.get_image()
		var cols := 0
		for x in img.get_width():
			for y in img.get_height():
				if img.get_pixel(x, y).a > 0.5:
					cols += 1
					break
		if cols < img.get_width() * 0.6:
			err = "coin face only %d/%d px wide (sliver)" % [cols, img.get_width()]
	holder.free()
	return err


# --- Items HUD: owned strip, reveal arrows, minimap, lure hint -------------------------
func _global_script(cls: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == cls:
			return load(str(c.get("path", ""))) as Script
	return null


func _fresh_stats() -> Node:
	var ps: Node = load("res://scripts/autoload/player_stats.gd").new()
	_root().add_child(ps)
	return ps


func _mount_with_stats(path: String, ps: Node, bus: Node = null) -> Node:
	var n: Node = load(path).new()
	n.set("stats", ps)
	if bus != null:
		n.set("bus", bus)
	_root().add_child(n)
	return n


func test_owned_strip_updates() -> String:
	var ps := _fresh_stats()
	var strip := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps)
	var err := ""
	if not strip.entries.is_empty() or strip.visible:
		err = "no items -> empty, hidden strip"
	var db := _item_db()
	var sack: Object = db.make("greedy_sack")
	var odd: Object = db.make("minimap")
	odd.icon_slot = "no_such_icon_slot"   # forces the letter-tile fallback
	ps.grant_item(sack)
	if err.is_empty() and (strip.entries.size() != 1 or strip.entries[0].id != "greedy_sack"):
		err = "grant -> items_changed -> 1 entry, got %s" % [strip.entries]
	ps.grant_item(odd)
	if err.is_empty() and strip.entries.map(func(e): return e.id) != ["greedy_sack", "minimap"]:
		err = "second grant should append, got %s" % [strip.entries]
	if err.is_empty() and not strip.visible:
		err = "strip should show once something is owned"
	if err.is_empty():
		var t0 := strip.tiles[0].get_node_or_null(^"Tile/Icon") as TextureRect
		if t0 == null or t0.texture == null:
			err = "icon_slot with manifest art -> Icon texture"
	if err.is_empty():
		var lab := strip.tiles[1].get_node_or_null(^"Tile/Initials") as Label
		var want: String = load("res://scripts/ui/shop.gd").initials("Minimap")
		if lab == null or lab.text != want:
			err = "missing icon -> shop letter tile '%s', got %s" % [want, lab.text if lab else "none"]
		elif lab.get_theme_color(&"font_color") != HudSkin.load_default().rarity_colors["uncommon"]:
			err = "letter tile should use the rarity palette colour"
		else:
			var sb := (strip.tiles[1].get_node(^"Tile") as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxFlat
			if sb == null or sb.border_color != HudSkin.load_default().rarity_colors["uncommon"]:
				err = "tile rim should be the rarity colour"
	ps.reset()
	if err.is_empty() and (not strip.entries.is_empty() or strip.visible):
		err = "reset -> items_changed([]) -> empty, hidden"
	_cleanup([strip, ps])
	return err


func _pips(strip: Node, i: int) -> Control:
	return strip.tiles[i].get_node_or_null(^"Charges/Pips") as Control


func test_owned_strip_charges() -> String:
	var ps := _fresh_stats()
	var strip := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps)
	var db := _item_db()
	var bulb: Object = db.make("flash_bulb")
	var foot: Object = db.make("rabbits_foot")
	var plain: Object = db.make("sneakers")
	for it in [bulb, foot, plain]:
		ps.grant_item(it)
	var err := ""
	if strip.entries.size() != 3:
		err = "want 3 entries, got %d" % strip.entries.size()
	for i in 2:
		var p := _pips(strip, i) if err.is_empty() else null
		if err.is_empty() and (p == null or p.total != 1 or p.left != 1):
			err = "%s: one full pip (1/1) at start" % strip.entries[i].id
	if err.is_empty() and strip.tiles[2].get_node_or_null(^"Charges") != null:
		err = "max_charges 0 -> no pip row"
	bulb.use_charge()   # Flash Bulb fired: Item re-emits items_changed
	if err.is_empty() and (strip.entries[0].charges != 0 or _pips(strip, 0).left != 0):
		err = "use_charge -> pip empties, got %s" % [strip.entries[0]]
	if err.is_empty() and _pips(strip, 1).left != 1:
		err = "other items' charges unaffected"
	foot.set_charges(0)   # heart save spent
	if err.is_empty() and _pips(strip, 1).left != 0:
		err = "set_charges(0) -> Rabbit's Foot pip empties"
	ps.begin_stage(null)   # refill
	if err.is_empty() and (_pips(strip, 0).left != 1 or _pips(strip, 1).left != 1):
		err = "begin_stage refills -> pips full again"
	# a multi-charge item shows the count too
	foot.max_charges = 3
	foot.set_charges(2)
	if err.is_empty():
		var n := strip.tiles[1].get_node_or_null(^"Charges/Count") as Label
		if n == null or n.text != "2/3" or _pips(strip, 1).total != 3:
			err = "max 3 -> 3 pips + '2/3' count"
	_cleanup([strip, ps])
	return err


class _RevealStats extends Node:
	var dist := INF
	func arrow_reveal_distance() -> float:
		return dist


func test_arrow_reveal_distance() -> String:
	var b := _bus()
	var arrows := _mount("res://scripts/ui/offscreen_arrows.gd", b)
	var fake := _RevealStats.new(); _root().add_child(fake)
	arrows.stats = fake
	var cam := Camera2D.new(); _root().add_child(cam); cam.make_current()
	var boy := Node2D.new(); boy.add_to_group("player"); _root().add_child(boy)
	boy.global_position = cam.get_screen_center_position()
	var near := _Chaser.new(); _root().add_child(near)
	near.global_position = boy.global_position + Vector2(1000, 0)   # off-screen, inside 1280
	var far := _Chaser.new(); _root().add_child(far)
	far.global_position = boy.global_position + Vector2(-3000, 0)   # off-screen, beyond 1280
	b.report_chase(near, true); b.report_chase(far, true)
	var ids := func() -> Array: return arrows.arrows.map(func(x): return x["enemy"])
	var err := ""
	arrows._process(0.1)
	if ids.call().size() != 2:
		err = "INF reveal (no Cracked Mirror) -> both arrows, got %d" % ids.call().size()
	fake.dist = 1280.0
	arrows._process(0.1)
	if err.is_empty() and ids.call() != [near]:
		err = "reveal 1280 -> only the chaser within 1280, got %s" % [ids.call()]
	far.global_position = boy.global_position + Vector2(-1200, 0)   # closes in
	arrows._process(0.1)
	if err.is_empty() and ids.call().size() != 2:
		err = "chaser moving inside reveal distance -> arrow appears"
	var bare := Node.new(); _root().add_child(bare)
	arrows.stats = bare   # no arrow_reveal_distance(): has_method guard -> INF
	far.global_position = boy.global_position + Vector2(-3000, 0)
	arrows._process(0.1)
	if err.is_empty() and ids.call().size() != 2:
		err = "stats without arrow_reveal_distance -> all arrows"
	b.report_chase(near, false); b.report_chase(far, false)
	_cleanup([arrows, fake, bare, cam, boy, near, far, b])
	return err


func test_minimap_visibility() -> String:
	var ps := _fresh_stats()
	var b := _bus()
	var mm := _mount_with_stats("res://scripts/ui/minimap.gd", ps, b)
	var boy := Node2D.new(); boy.add_to_group("player"); _root().add_child(boy)
	boy.global_position = Vector2(200, 300)
	var ex := Node2D.new(); ex.add_to_group("exit"); _root().add_child(ex)
	ex.global_position = Vector2(1100, 100)
	var ch := _Chaser.new(); _root().add_child(ch); ch.global_position = Vector2(900, 500)
	var err := ""
	mm._process(1.0)
	if mm.visible or not mm.snapshot.is_empty():
		err = "no Minimap item -> hidden, no work"
	var item: Object = _item_db().make("minimap")
	ps.grant_item(item)   # stat minimap = 1 -> items_changed
	if err.is_empty() and not mm.visible:
		err = "has_minimap() true -> visible immediately"
	b.report_chase(ch, true)
	mm._process(1.0)   # 10 Hz tick
	if err.is_empty():
		var s: Dictionary = mm.snapshot
		if s.get("player") != boy.global_position or s.get("exit") != ex.global_position:
			err = "snapshot should carry player + exit, got %s" % [s]
		elif s.chasers != [ch.global_position]:
			err = "reported chaser -> red dot, got %s" % [s.chasers]
		elif s.bands.is_empty() or not (s.bounds as Rect2).has_point(boy.global_position):
			err = "bounds/bands should cover the level, got %s" % [s]
	b.report_chase(ch, false)
	mm._process(1.0)
	if err.is_empty() and not mm.snapshot.chasers.is_empty():
		err = "chase ended -> no red dot"
	ps.reset()
	if err.is_empty() and mm.visible:
		err = "item gone -> hidden"
	_cleanup([mm, boy, ex, ch, b, ps])
	return err


func test_minimap_level_nav() -> String:
	var Nav := _global_script("LevelNav")
	var Gen := _global_script("LevelGenerator")
	if Gen == null:
		return "LevelGenerator missing alongside LevelNav"
	var L: Dictionary = Gen.fallback_layout(1)
	var prev = Nav.get("current")
	Nav.set("current", Nav.from_layout(L))
	var ps := _fresh_stats()
	ps.grant_item(_item_db().make("minimap"))
	var b := _bus()
	var mm := _mount_with_stats("res://scripts/ui/minimap.gd", ps, b)
	mm._process(1.0)
	var s: Dictionary = mm.snapshot
	var err := ""
	if s.get("source") != "level_nav":
		err = "generated level -> LevelNav source, got %s" % s.get("source")
	elif s.bands.size() != int(L.floors):
		err = "one band per floor: want %d, got %d" % [int(L.floors), s.bands.size()]
	elif s.stairs.size() != (L.stairs as Array).size():
		err = "stairs should be drawn"
	Nav.set("current", prev)
	_cleanup([mm, b, ps])
	return err


## Fake of BE PR #41's lure-pocket API on PlayerStats (what the hint and pips read).
class _FakePocket extends Node:
	signal lures_changed(charges: int, max: int)
	var charges := 0
	var max_n := 0
	var tap := false
	func lure_charges() -> int:
		return charges
	func lure_max() -> int:
		return max_n
	func tap_throws_lure() -> bool:
		return tap
	func set_pocket(c: int, m: int) -> void:
		charges = c
		max_n = m
		lures_changed.emit(c, m)


## Stand-in for the live player PlayerStats.tap_throws_lure() asks.
class _FakePlayer extends Node:
	var tap := true
	func tap_would_throw_lure() -> bool:
		return tap


func _pocket_api() -> bool:
	var ps := _fresh_stats()
	var ok := ps.has_method(&"tap_throws_lure") and ps.has_method(&"lure_max") and ps.has_signal(&"lures_changed")
	ps.free()
	return ok


## Without BE #41's pocket API (a stats node with none of it) the hint keeps the legacy
## behaviour: a held lure dict selected.
func test_lure_hint() -> String:
	var b := _bus()
	var bare := Node.new(); _root().add_child(bare)
	var hint: Node = load("res://scripts/ui/lure_hint.gd").new()
	hint.set("bus", b)
	hint.set("stats", bare)
	_root().add_child(hint)
	var err := ""
	if hint.text != "tap: throw lure":
		err = "exact text 'tap: throw lure', got '%s'" % hint.text
	if err.is_empty() and hint.visible:
		err = "empty hands -> hidden"
	var vase := {id = "vase_1", slot = "vase", name = "Vase", throwable = true}
	var lure := {id = "music_box_lure_1", slot = "music_box_world", name = "Music Box", throwable = true, lure = true}
	b.set_items([vase, lure])
	b.select_item(0)
	if err.is_empty() and hint.visible:
		err = "holding a vase -> hidden"
	b.select_item(1)
	if err.is_empty() and not hint.visible:
		err = "legacy: Music Box selected -> visible"
	b.set_items([vase])   # thrown
	if err.is_empty() and hint.visible:
		err = "lure thrown -> hidden"
	_cleanup([hint, bare, b])
	return err


## With the pocket API the hint is EXACTLY tap_throws_lure(), whatever the hands hold.
func test_lure_hint_pocket() -> String:
	var b := _bus()
	var fake := _FakePocket.new(); _root().add_child(fake)
	var hint: Node = load("res://scripts/ui/lure_hint.gd").new()
	hint.set("bus", b)
	hint.set("stats", fake)
	_root().add_child(hint)
	var err := ""
	if hint.text != "tap: throw lure":
		err = "exact text, got '%s'" % hint.text
	if err.is_empty() and hint.visible:
		err = "tap_throws_lure false -> hidden"
	fake.charges = 1; fake.max_n = 1; fake.tap = true
	fake.lures_changed.emit(1, 1)
	if err.is_empty() and not hint.visible:
		err = "lures_changed with tap_throws_lure true -> visible (hands empty, no lure item held)"
	fake.tap = false
	fake.lures_changed.emit(1, 1)
	if err.is_empty() and hint.visible:
		err = "tap_throws_lure false (e.g. hands full / prop in reach) -> hidden even with a lure left"
	# a held lure dict no longer matters once the pocket API exists
	b.set_items([{id = "l", slot = "music_box_world", name = "Music Box", lure = true}])
	b.select_item(0)
	if err.is_empty() and hint.visible:
		err = "a legacy held lure must not show it when tap_throws_lure() is false"
	# inventory / ring changes re-check
	fake.tap = true
	b.set_items([{id = "v", slot = "vase", name = "Vase", throwable = true}])
	if err.is_empty() and not hint.visible:
		err = "inventory_changed -> re-check -> visible"
	fake.tap = false
	b.select_item(0)
	if err.is_empty() and hint.visible:
		err = "inventory_selected -> re-check -> hidden"
	# per frame: the knock reach flips tap_throws_lure() without any signal
	fake.tap = true
	hint._process(0.016)
	if err.is_empty() and not hint.visible:
		err = "per-frame re-check while a lure is left -> visible"
	fake.tap = false
	hint._process(0.016)
	if err.is_empty() and hint.visible:
		err = "per-frame re-check -> hidden"
	fake.tap = true
	fake.charges = 0
	hint._process(0.016)
	fake.charges = 1
	hint._process(0.016)
	if err.is_empty() and not hint.visible:
		err = "visible again once a lure is back"
	fake.tap = false   # BE's tap_throws_lure() is false with an empty pocket
	fake.set_pocket(0, 1)   # last lure thrown
	if err.is_empty() and hint.visible:
		err = "last lure thrown -> hidden"
	_cleanup([hint, fake, b])
	return err


## Against the real PlayerStats (needs PR #41): grant a Music Box, begin a stage with a live
## player, and the hint follows tap_throws_lure() through a throw and a refill.
func test_lure_pocket_real_stats() -> String:
	var ps := _fresh_stats()
	var b := _bus()
	var player := _FakePlayer.new(); _root().add_child(player)
	var hint: Node = load("res://scripts/ui/lure_hint.gd").new()
	hint.set("bus", b)
	hint.set("stats", ps)
	_root().add_child(hint)
	var box: Object = _item_db().make("music_box")
	ps.grant_item(box)
	ps.begin_stage(player)
	var err := ""
	if ps.lure_charges() != 1 or ps.lure_max() != 1:
		err = "setup: pocket %d/%d, want 1/1" % [ps.lure_charges(), ps.lure_max()]
	if err.is_empty() and not hint.visible:
		err = "Music Box owned, stage begun, tap would throw -> visible"
	player.tap = false   # hands full / a prop in knock reach
	hint._process(0.016)
	if err.is_empty() and hint.visible:
		err = "tap would knock instead -> hidden"
	player.tap = true
	hint._process(0.016)
	if err.is_empty() and not hint.visible:
		err = "knock reach cleared -> visible"
	box.use_charge()   # the lure was thrown
	if err.is_empty() and hint.visible:
		err = "pocket empty -> hidden"
	ps.begin_stage(player)
	if err.is_empty() and not hint.visible:
		err = "next stage refills the lure -> visible"
	_cleanup([hint, player, b, ps])
	return err


func test_lure_pocket() -> String:
	var fake := _FakePocket.new(); _root().add_child(fake)
	var pocket: Node = load("res://scripts/ui/lure_pocket.gd").new()
	pocket.set("stats", fake)
	_root().add_child(pocket)
	var err := ""
	var pips := pocket.get_node_or_null(^"Pips")
	if pips == null:
		return "no Pips node"
	if pocket.visible:
		err = "lure_max() == 0 -> hidden"
	fake.set_pocket(2, 3)
	if err.is_empty() and (not pocket.visible or pips.total != 3 or pips.left != 2 or pips.dots() != 3):
		err = "2/3 -> visible, 3 pips, 2 filled; got total %d left %d" % [pips.total, pips.left]
	if err.is_empty() and (pips.lit(0) != true or pips.lit(1) != true or pips.lit(2) != false):
		err = "filled pips are the left-most ones"
	if err.is_empty() and pocket.get_node(^"Count").visible:
		err = "up to 5 pips: no number"
	if err.is_empty() and pocket.get_node_or_null(^"Tile/Icon") == null and pocket.get_node_or_null(^"Tile/Initials") == null:
		err = "pocket tile needs the Music Box icon or its letter fallback"
	if err.is_empty() and pips.get_combined_minimum_size().y < 11.0:
		err = "pips must be >= 11 px"
	fake.set_pocket(1, 3)   # a throw
	if err.is_empty() and pips.left != 1:
		err = "throw -> 1 filled"
	fake.set_pocket(3, 3)   # refill
	if err.is_empty() and pips.left != 3:
		err = "refill -> 3 filled"
	fake.set_pocket(0, 3)
	if err.is_empty() and (pips.left != 0 or not pocket.visible):
		err = "spent pocket stays shown with empty pips"
	fake.set_pocket(4, 8)   # more than fit: one pip + n/max
	if err.is_empty() and (pips.dots() != 1 or not pocket.get_node(^"Count").visible or pocket.get_node(^"Count").text != "4/8"):
		err = "8 lures -> 1 pip + '4/8'"
	fake.set_pocket(0, 0)
	if err.is_empty() and pocket.visible:
		err = "max back to 0 -> hidden"
	# stats without the pocket API (no #41): hidden, no errors
	var bare := Node.new(); _root().add_child(bare)
	var p2: Node = load("res://scripts/ui/lure_pocket.gd").new()
	p2.set("stats", bare)
	_root().add_child(p2)
	if err.is_empty() and p2.visible:
		err = "no pocket API -> hidden"
	_cleanup([pocket, p2, fake, bare])
	return err


## Real PlayerStats (needs #41): the pips are lure_max() copies with lure_charges() filled.
func test_lure_pocket_pips_real_stats() -> String:
	var ps := _fresh_stats()
	var pocket: Node = load("res://scripts/ui/lure_pocket.gd").new()
	pocket.set("stats", ps)
	_root().add_child(pocket)
	var err := ""
	if pocket.visible:
		err = "no Music Box -> hidden"
	var a: Object = _item_db().make("music_box")
	var b2: Object = _item_db().make("music_box")
	ps.grant_item(a)
	ps.begin_stage(null)
	var pips := pocket.get_node(^"Pips")
	if err.is_empty() and (not pocket.visible or pips.total != 1 or pips.left != 1):
		err = "1 box -> 1/1"
	ps.grant_item(b2)
	if err.is_empty() and (pips.total != 2 or pips.left != 2):
		err = "second box bought -> 2 pips, 2 filled (a new copy starts full), got %d/%d" % [pips.left, pips.total]
	ps.begin_stage(null)
	if err.is_empty() and pips.left != 2:
		err = "begin_stage refills -> 2/2"
	a.use_charge()
	if err.is_empty() and (pips.left != 1 or pips.total != 2):
		err = "one throw -> 1/2"
	_cleanup([pocket, ps])
	return err


func test_lure_pocket_hud() -> String:
	var fake := _FakePocket.new(); _root().add_child(fake)
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	hud.stats = fake
	_root().add_child(hud)
	var err := ""
	var pocket := hud.get_node_or_null(^"HudRoot/LurePocket")
	if pocket == null:
		_cleanup([hud, fake])
		return "HUD missing LurePocket"
	if pocket.anchor_strip != hud.inventory or not hud.inventory.has_method(&"slots_rect"):
		err = "pocket should sit beside the inventory strip"
	if err.is_empty() and hud.lure_hint.get("stats") != fake:
		err = "HUD passes its stats to the lure hint too"
	if err.is_empty() and pocket.visible:
		err = "no lures -> pocket hidden"
	fake.set_pocket(1, 1)
	var strip := _FakeStrip.new()   # hand row at x 500..620, y 640..684
	pocket.anchor_strip = strip
	pocket._process(0.016)
	if err.is_empty() and not pocket.visible:
		err = "1/1 -> shown"
	if err.is_empty() and absf(pocket.position.x - (620.0 + pocket.GAP)) > 0.5:
		err = "pocket x should be hand row's right edge + gap, got %s" % pocket.position
	if err.is_empty() and pocket.position.y + pocket.size.y > 684.5:
		err = "pocket must not hang below the hand slots, got %s" % pocket.position
	# the whole HUD still ignores the mouse (pocket never eats clicks)
	if err.is_empty() and (pocket.mouse_filter != Control.MOUSE_FILTER_IGNORE or pocket.get_node(^"Tile").mouse_filter != Control.MOUSE_FILTER_IGNORE):
		err = "pocket must be mouse-ignore"
	_cleanup([hud, fake, strip])
	return err


class _FakeStrip extends Control:
	func slots_rect() -> Rect2:
		return Rect2(500, 640, 120, 44)


## Lure widgets (QA B1 pattern): connected only while in the tree; after leaving it (and being
## freed) BE signals log no errors and leave no connections.
func test_lure_widgets_exit_tree() -> String:
	var fake := _FakePocket.new(); _root().add_child(fake)
	var b := _bus()
	var hint: Node = load("res://scripts/ui/lure_hint.gd").new()
	hint.set("bus", b); hint.set("stats", fake)
	_root().add_child(hint)
	var pocket: Node = load("res://scripts/ui/lure_pocket.gd").new()
	pocket.set("stats", fake)
	_root().add_child(pocket)
	var widgets := [hint, pocket]
	var err := ""
	if _conns_into(fake, &"lures_changed", widgets) != 2:
		err = "setup: both widgets listen to lures_changed while in the tree, got %d" % _conns_into(fake, &"lures_changed", widgets)
	var log := _ErrLog.new()
	OS.add_logger(log)
	for w in widgets:
		_root().remove_child(w)
	var left := _conns_into(fake, &"lures_changed", widgets)
	for sig in [&"inventory_changed", &"inventory_selected"]:
		left += _conns_into(b, sig, widgets)
	if err.is_empty() and left != 0:
		err = "%d orphan connections after leaving the tree" % left
	fake.set_pocket(1, 2)
	b.set_items([{id = "l", slot = "x", name = "X", lure = true}])
	for w in widgets:
		w.free()
	fake.set_pocket(0, 2)
	b.set_items([])
	OS.remove_logger(log)
	if err.is_empty() and not log.errors.is_empty():
		err = "errors after the lure widgets left the tree: %s" % [log.errors.slice(0, 3)]
	# moved, not freed: re-entering reconnects exactly once
	var p2: Node = load("res://scripts/ui/lure_pocket.gd").new()
	p2.set("stats", fake)
	_root().add_child(p2)
	_root().remove_child(p2)
	_root().add_child(p2)
	if err.is_empty() and _conns_into(fake, &"lures_changed", [p2]) != 1:
		err = "re-entering the tree should reconnect exactly once"
	_cleanup([p2, fake, b])
	return err


class _PlainStats extends Node:
	signal items_changed(items: Array)
	var owned_items: Array = []


## Music Box in owned_items (BE keeps it there): with the pocket API its tile stays but its
## charges show only in the pocket; without it, it is an ordinary charged item.
func test_owned_strip_pocket() -> String:
	var db := _item_db()
	var err := ""
	var fake := _FakePocket.new(); _root().add_child(fake)
	var plain := _PlainStats.new(); _root().add_child(plain)
	var box: Object = db.make("music_box")
	var bulb: Object = db.make("flash_bulb")
	plain.owned_items = [box, bulb]
	# legacy: no pocket API -> pips as before
	var strip := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", plain)
	var box_tile: Control = strip.tiles[0] if strip.entries[0].id == "music_box" else strip.tiles[1]
	if box_tile.get_node_or_null(^"Charges") == null:
		err = "without the pocket API the Music Box keeps its charge pips"
	_cleanup([strip])
	# pocket API present: the tile stays, the charges move out
	if err.is_empty():
		var ps2 := _PlainStats2.new(); _root().add_child(ps2)
		ps2.owned_items = [box, bulb]
		var s2 := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps2)
		var ids: Array = s2.entries.map(func(e): return e.id)
		if not ids.has("music_box") or s2.tiles.size() != 2:
			err = "Music Box keeps its tile, got %s" % [ids]
		var bi := ids.find("music_box")
		var ti: Control = s2.tiles[bi]
		if err.is_empty() and (ti.get_node_or_null(^"Charges") != null or ti.get_node_or_null(^"Tile").self_modulate.a < 0.99):
			err = "with the pocket, Music Box tile shows no pips and no spent fade"
		box.charges = 0   # spent: still nothing on the tile (the pocket shows it)
		s2.refresh()
		ti = s2.tiles[s2.entries.map(func(e): return e.id).find("music_box")]
		if err.is_empty() and (ti.get_node_or_null(^"Charges") != null or ti.get_node_or_null(^"Tile").self_modulate.a < 0.99):
			err = "a spent Music Box must not fade/pip on the strip when the pocket shows it"
		var bt: Control = s2.tiles[s2.entries.map(func(e): return e.id).find("flash_bulb")]
		if err.is_empty() and bt.get_node_or_null(^"Charges") == null:
			err = "other charged items keep their pips"
		_cleanup([s2, ps2])
	# real PlayerStats (needs #41): same, end to end, and two copies still stack on one tile
	if err.is_empty() and _pocket_api():
		var ps := _fresh_stats()
		var s3 := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps)
		ps.grant_item(db.make("music_box"))
		ps.grant_item(db.make("music_box"))
		ps.begin_stage(null)
		var t3: Control = s3.tiles[0]
		if s3.entries.size() != 1 or s3.entries[0].count != 2 or t3.get_node_or_null(^"Charges") != null:
			err = "real: 2 Music Boxes -> one x2 tile, no pips, got %s" % [s3.entries]
		_cleanup([s3, ps])
	_cleanup([fake, plain])
	return err


## _PlainStats plus the pocket API (only the has_method signal matters to the strip).
class _PlainStats2 extends _PlainStats:
	func lure_max() -> int:
		return 1


func test_hud_items_widgets() -> String:
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	_root().add_child(hud)
	var err := ""
	for n in ["OwnedItems", "Minimap", "LureHint", "LurePocket"]:
		if hud.get_node_or_null(NodePath("HudRoot/" + n)) == null:
			err = "HUD missing %s" % n
	_cleanup([hud])
	return err


## Captures engine/script errors pushed while it's registered (OS.add_logger, Godot 4.5+).
class _ErrLog extends Logger:
	var errors: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])
	func _log_message(_message: String, _error: bool) -> void:
		pass


## Connections on `sig` of `src` whose target is `w` or one of its descendants.
func _conns_into(src: Object, sig: StringName, widgets: Array) -> int:
	var n := 0
	if src == null or not src.has_signal(sig):
		return 0
	for c in src.get_signal_connection_list(sig):
		var o: Object = (c.callable as Callable).get_object()
		for w in widgets:
			if is_instance_valid(w) and o != null and (o == w or (o is Node and (w as Node).is_ancestor_of(o))):
				n += 1
	return n


## QA B1: own Minimap -> stage change (old HUD leaves the tree, later freed) -> BE emits
## items_changed / stat_changed / chase / inventory signals: no errors, no connections left.
func test_items_widgets_exit_tree() -> String:
	var ps := _fresh_stats()
	var b := _bus()
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	hud.stats = ps
	_root().add_child(hud)
	var mm := _mount_with_stats("res://scripts/ui/minimap.gd", ps, b)
	var strip := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps)
	var hint := _mount("res://scripts/ui/lure_hint.gd", b)
	var widgets := [hud, mm, strip, hint]
	ps.grant_item(_item_db().make("minimap"))
	var err := ""
	if not mm.visible:
		err = "setup: minimap should be visible"
	if err.is_empty() and _conns_into(ps, &"items_changed", widgets) == 0:
		err = "setup: widgets should listen to items_changed while in the tree"
	var log := _ErrLog.new()
	OS.add_logger(log)
	for w in widgets:
		_root().remove_child(w)   # stage change: the old level (and its HUD) leaves the tree
	var left := 0
	for sig in [&"items_changed", &"stat_changed"]:
		left += _conns_into(ps, sig, widgets)
	for sig in [&"chase_changed", &"inventory_changed", &"inventory_selected"]:
		left += _conns_into(b, sig, widgets)
	if err.is_empty() and left != 0:
		err = "%d orphan connections after leaving the tree" % left
	var ch := _Chaser.new(); _root().add_child(ch)
	var bulb: Object = _item_db().make("flash_bulb")
	var emit_all := func() -> void:
		ps.begin_stage(null)
		ps.grant_item(_item_db().make("sneakers"))
		bulb.use_charge()
		b.report_chase(ch, true); b.report_chase(ch, false)
		b.set_items([{id = "l", slot = "music_box_world", name = "Music Box", lure = true}])
		b.select_item(0)
	ps.grant_item(bulb)
	emit_all.call()
	for w in widgets:
		w.free()
	emit_all.call()
	OS.remove_logger(log)
	if err.is_empty() and not log.errors.is_empty():
		err = "errors after the HUD left the tree: %s" % [log.errors.slice(0, 3)]
	# re-entering the tree reconnects (a HUD that's moved, not freed, keeps working)
	var mm2 := _mount_with_stats("res://scripts/ui/minimap.gd", ps, b)
	_root().remove_child(mm2)
	_root().add_child(mm2)
	if err.is_empty() and (_conns_into(ps, &"items_changed", [mm2]) != 1 or not mm2.visible):
		err = "re-entering the tree should reconnect exactly once"
	_cleanup([mm2, ch, b, ps])
	return err


func test_owned_strip_stacks() -> String:
	var ps := _fresh_stats()
	var strip := _mount_with_stats("res://scripts/ui/owned_items_strip.gd", ps)
	var db := _item_db()
	var bulbs: Array = []
	for i in 3:
		bulbs.append(db.make("flash_bulb"))
		ps.grant_item(bulbs[i])
	ps.grant_item(db.make("sneakers"))
	ps.grant_item(db.make("sneakers"))
	ps.grant_item(db.make("minimap"))
	var err := ""
	if strip.entries.map(func(e): return [e.id, e.count]) != [["flash_bulb", 3], ["sneakers", 2], ["minimap", 1]]:
		err = "duplicates should stack in first-owned order, got %s" % [strip.entries.map(func(e): return [e.id, e.count])]
	if err.is_empty() and strip.tiles.size() != 3:
		err = "one tile per id, got %d" % strip.tiles.size()
	if err.is_empty():
		var s0 := strip.tiles[0].get_node_or_null(^"Tile/Stack") as Label
		var s1 := strip.tiles[1].get_node_or_null(^"Tile/Stack") as Label
		if s0 == null or s0.text != "×3" or s1 == null or s1.text != "×2":
			err = "stack badges should read ×3 / ×2"
		elif strip.tiles[2].get_node_or_null(^"Tile/Stack") != null:
			err = "single item -> no ×N badge"
	if err.is_empty() and (_pips(strip, 0).total != 3 or _pips(strip, 0).left != 3):
		err = "stacked charges sum: 3/3"
	bulbs[1].use_charge()
	if err.is_empty():
		var n := strip.tiles[0].get_node_or_null(^"Charges/Count") as Label
		if _pips(strip, 0).left != 2 or n == null or n.text != "2/3":
			err = "one bulb spent -> 2/3"
	if err.is_empty():
		var pip := _pips(strip, 0)
		if strip.PIP_R * 2.0 < 11.0 or pip.get_combined_minimum_size().y < 11.0:
			err = "pips should be >= 11 px"
	_cleanup([strip, ps])
	return err


func _strip_right_edge(strip: Control) -> float:
	var r := 0.0
	for row in strip.get_children():
		for t in row.get_children():
			r = maxf(r, (t as Control).get_global_rect().end.x)
	return r


func test_owned_strip_wraps() -> String:
	var ps := _fresh_stats()
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	hud.stats = ps
	_root().add_child(hud)
	var strip: Control = hud.owned_items
	var db := _item_db()
	var ids: Array = []
	for r in db.ITEMS:
		ids.append(str(r.id))
	var err := ""
	for i in 30:   # every ItemDb item once, then 10 duplicates
		ps.grant_item(db.make(ids[i % ids.size()]))
	_settle(hud)
	var rows := strip.get_child_count()
	var uniq := mini(30, ids.size())
	if strip.entries.size() != uniq or strip.overflow != 0:
		err = "30 owned (%d ids) -> %d stacks, no overflow; got %d / +%d" % [ids.size(), uniq, strip.entries.size(), strip.overflow]
	elif rows != ceili(uniq / float(strip.PER_ROW)):
		err = "should wrap to %d rows, got %d" % [ceili(uniq / float(strip.PER_ROW)), rows]
	elif _strip_right_edge(strip) > 1020.0:
		err = "right edge %.0f past 1020" % _strip_right_edge(strip)
	ps.reset()
	for i in 30:   # 30 distinct ids: cap + "+N"
		var it := Item.new()
		it.id = "fake_%02d" % i
		it.display_name = "Fake Thing %d" % i
		it.rarity = "common"
		ps.grant_item(it)
	_settle(hud)
	var cap: int = strip.PER_ROW * strip.MAX_ROWS
	if err.is_empty() and (strip.tiles.size() != cap - 1 or strip.overflow != 30 - (cap - 1)):
		err = "30 distinct -> %d tiles + '+%d', got %d + %d" % [cap - 1, 30 - cap + 1, strip.tiles.size(), strip.overflow]
	if err.is_empty():
		var more := strip.find_child("More", true, false) as Label
		if more == null or more.text != "+%d" % (30 - cap + 1):
			err = "overflow tile should read +%d" % (30 - cap + 1)
	if err.is_empty() and strip.get_child_count() != strip.MAX_ROWS:
		err = "capped at %d rows" % strip.MAX_ROWS
	if err.is_empty() and _strip_right_edge(strip) > 1020.0:
		err = "capped strip right edge %.0f past 1020" % _strip_right_edge(strip)
	ps.grant_item(_item_db().make("minimap"))
	_settle(hud)
	if err.is_empty() and _strip_right_edge(strip) >= (hud.minimap as Control).get_global_rect().position.x:
		err = "strip should stay left of the minimap"
	_cleanup([hud, ps])
	return err


func test_minimap_clamp_and_chase_end() -> String:
	var ps := _fresh_stats()
	var b := _bus()
	var mm := _mount_with_stats("res://scripts/ui/minimap.gd", ps, b)
	ps.grant_item(_item_db().make("minimap"))
	var ch := _Chaser.new(); _root().add_child(ch); ch.global_position = Vector2(600, 300)
	var err := ""
	b.report_chase(ch, true)   # no _process tick: the report itself redraws
	if mm.snapshot.get("chasers", []).size() != 1:
		err = "chase start -> red dot at once"
	b.report_chase(ch, false)
	if err.is_empty() and not mm.snapshot.chasers.is_empty():
		err = "chase end -> red dot gone at once (not on the next 10 Hz tick)"
	var r: Rect2 = mm.map_rect()
	for p in [Vector2(1e6, -1e6), Vector2(-1e6, 1e6), Vector2(-50, 360)]:
		var q: Vector2 = mm.dot_at(p, 4.0)
		if err.is_empty() and not (q.x >= r.position.x + 4.0 and q.x <= r.end.x - 4.0 and q.y >= r.position.y + 4.0 and q.y <= r.end.y - 4.0):
			err = "dot for %s drawn at %s, outside the frame %s" % [p, q, r]
	_cleanup([mm, ch, b, ps])
	return err


func test_hud_hidden_end_screen() -> String:
	var hud: Node = load("res://scripts/ui/hud.gd").new()
	_root().add_child(hud)
	var sc := UiScreen.new()
	_root().add_child(sc)   # added after the HUD (node_added path)
	var err := ""
	if not hud.hud_root.visible:
		err = "HUD visible with no screen open"
	sc.open()
	if err.is_empty() and hud.hud_root.visible:
		err = "end screen open -> whole HUD hidden"
	sc.close()
	if err.is_empty() and not hud.hud_root.visible:
		err = "screen closed -> HUD back"
	var early := UiScreen.new()
	_root().add_child(early)
	var hud2: Node = load("res://scripts/ui/hud.gd").new()
	_root().add_child(hud2)   # screen already in the tree (scan path)
	early.open()
	if err.is_empty() and hud2.hud_root.visible:
		err = "screen present before the HUD should still hide it"
	early.free()   # freed while open
	if err.is_empty() and not hud2.hud_root.visible:
		err = "screen freed -> HUD back"
	_cleanup([sc, hud, hud2])
	_reset_world()
	return err

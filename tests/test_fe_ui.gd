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
		["startle_fills_over_startle_time", test_startle],
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
		["alert_count_scales_past_3", test_alert_scales],
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
	]
	var passed := 0
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


func test_startle() -> String:
	var b := _bus()
	var e := Node2D.new(); _root().add_child(e)
	b.startle_time = 1.0
	b.report_lit(e, true)
	b._process(0.5)
	var err := ""
	if absf(b.get_startle(e) - 0.5) > 0.01:
		err = "0.5 s lit → 0.5, got %f" % b.get_startle(e)
	b._process(0.6)
	if err.is_empty() and b.get_startle(e) < 1.0:
		err = "should be full after 1.0 s"
	b.set_flashlight(false)
	if err.is_empty() and b.get_startle(e) != 0.0:
		err = "light off should reset startle"
	_cleanup([e, b])
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
	b._process(0.4)
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
	if err.is_empty() and shop.offers.size() != 3:
		err = "default offer count should be 3, got %d" % shop.offers.size()
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
	if b.enemy_total() != 12 or b.chasing_count() != 7:
		err = "polled count should be 7 / 12, got %d / %d" % [b.chasing_count(), b.enemy_total()]
	if err.is_empty() and hud.label.text != "Chasing 7 / 12":
		err = "label '%s'" % hud.label.text
	for i in 12:
		b.report_chase(es[i], true)   # BE reports take over from polling
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

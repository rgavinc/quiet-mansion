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

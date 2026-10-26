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

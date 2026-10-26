extends RefCounted
## Items, shop and chests — Back End checks (sync; chest checks use the live tree).

var root: Node


func _stats() -> Node:
	var s: Node = load("res://scripts/autoload/player_stats.gd").new()
	s.reset()
	return s


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["db_has_20_unique_valid_items", test_db_valid],
		["every_item_is_a_tradeoff", test_tradeoffs],
		["apply_changes_stats", test_apply_changes],
		["apply_remove_round_trip", test_round_trip],
		["two_copies_stack_and_remove_separately", test_two_copies],
		["roll_stock_deterministic_no_dupes", test_roll_deterministic],
		["roll_stock_stage_gating", test_stage_gating],
		["buy_without_gold_changes_nothing", test_buy_no_gold],
		["buy_spends_applies_and_owns", test_buy_ok],
		["buy_same_offer_twice_fails", test_buy_twice],
		["reset_clears_items_and_effects", test_reset],
		["owned_items_survive_stage_continue", test_survive_continue],
		["max_health_items_heal_and_clamp", test_max_health],
		["chest_opens_once_grants_one_item", test_chest_once],
		["chest_loot_deterministic", test_chest_deterministic],
		["chest_opens_through_hold_channel", test_chest_channel],
		["fe_shop_adapter_finds_shop", test_fe_adapter],
	]
	var passed := 0
	for item in checks:
		_clean()
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	_clean()
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"it_test"):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()


func _add(n: Node, at: Vector2) -> Node:
	n.set_meta(&"it_test", true)
	root.add_child(n)
	n.global_position = at
	return n


func _snapshot(s: Node) -> Dictionary:
	var d := {}
	for k in s.BASE:
		d[k] = s.get_stat(k)
	d[&"_health"] = s.health
	d[&"_gold"] = s.gold
	return d


func _diff(a: Dictionary, b: Dictionary) -> String:
	for k in a:
		if not is_equal_approx(float(a[k]), float(b[k])):
			return "%s %s -> %s" % [k, a[k], b[k]]
	return ""


func test_db_valid() -> String:
	var ids := ItemDb.ids()
	if ids.size() != 20: return "want 20 items, got %d" % ids.size()
	var seen := {}
	for r in ItemDb.ITEMS:
		var id := str(r.id)
		if seen.has(id): return "duplicate id " + id
		seen[id] = true
		var it := ItemDb.make(id)
		if it == null: return "make(%s) null" % id
		if it.display_name.is_empty() or it.description.is_empty() or it.icon_slot.is_empty():
			return id + ": empty name/description/icon_slot"
		if it.price <= 0: return id + ": price <= 0"
		if not ItemDb.RARITY.has(it.rarity): return id + ": bad rarity " + it.rarity
		if it.mods.is_empty(): return id + ": no modifiers"
		for m in it.mods:
			if not PlayerStats.BASE.has(m.stat): return "%s: unknown stat %s" % [id, m.stat]
	# The icons Designer already drew are used by the matching items.
	for pair in [["extra_heart", "item_icon_extra_heart"], ["minimap", "item_icon_minimap"],
			["bright_bulb", "item_icon_bright_bulb"], ["soft_shoes", "item_icon_soft_shoes"],
			["lucky_coin", "item_icon_lucky_coin"]]:
		if ItemDb.make(pair[0]).icon_slot != pair[1]: return pair[0] + " icon slot"
		if not AnimLibrary.has_slot(pair[1]): return "manifest missing " + pair[1]
	return ""


## Brotato-style: every item makes at least one stat better and at least one worse.
func test_tradeoffs() -> String:
	# Direction in which a stat is "good" for the player.
	var good_up := {&"max_health": true, &"move_speed": true, &"jump_velocity": true, &"climb_speed": true,
		&"pickup_time": false, &"pickup_range": true, &"throw_speed": true, &"light_range": true,
		&"light_angle_deg": true, &"light_startle_time": true, &"light_detect_mult": false,
		&"noise_mult": false, &"invuln_time": true, &"inventory_slots": true, &"gold_find_mult": true,
		&"minimap": true}
	for id in ItemDb.ids():
		var s := _stats()
		var before := _snapshot(s)
		ItemDb.make(id).apply(s)
		var better := false
		var worse := false
		for k in good_up:
			var dv: float = s.get_stat(k) - float(before[k])
			if absf(dv) < 0.0001: continue
			if (dv > 0.0) == good_up[k]: better = true
			else: worse = true
		s.free()
		if not (better and worse): return "%s is not a trade-off (better=%s worse=%s)" % [id, better, worse]
	return ""


func test_apply_changes() -> String:
	var s := _stats()
	ItemDb.make("soft_shoes").apply(s)
	var n: float = s.get_stat(&"noise_mult")
	var sp: float = s.get_stat(&"move_speed")
	ItemDb.make("lucky_coin").apply(s)
	var g: float = s.get_stat(&"gold_find_mult")
	s.free()
	if not is_equal_approx(n, 0.75): return "soft_shoes noise_mult want 0.75 got %s" % n
	if not is_equal_approx(sp, 140.0 * 0.92): return "soft_shoes move_speed got %s" % sp
	return "" if is_equal_approx(g, 1.4) else "lucky_coin gold_find_mult want 1.4 got %s" % g


func test_round_trip() -> String:
	for id in ItemDb.ids():
		var s := _stats()
		var before := _snapshot(s)
		var it := ItemDb.make(id)
		it.apply(s)
		if _diff(before, _snapshot(s)).is_empty():
			s.free(); return id + ": apply changed nothing"
		it.apply(s)   # second apply is a no-op
		it.remove(s)
		var after := _snapshot(s)
		if after[&"_health"] > s.max_health() or after[&"_health"] < 1:
			s.free(); return "%s: health %d out of 1..max" % [id, after[&"_health"]]
		# Hearts lost to a lower max aren't handed back (test_max_health covers health).
		after[&"_health"] = before[&"_health"] if id == "ghost_slippers" else after[&"_health"]
		var d := _diff(before, after)
		s.free()
		if not d.is_empty(): return "%s not restored: %s" % [id, d]
	return ""


func test_two_copies() -> String:
	var s := _stats()
	var a := ItemDb.make("sneakers")
	var b := ItemDb.make("sneakers")
	a.apply(s); b.apply(s)
	var both: float = s.get_stat(&"move_speed")
	a.remove(s)
	var one: float = s.get_stat(&"move_speed")
	s.free()
	if not is_equal_approx(both, 140.0 * 1.15 * 1.15): return "copies don't stack: %s" % both
	return "" if is_equal_approx(one, 140.0 * 1.15) else "removing one copy removed both: %s" % one


func _ids(items: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for it in items:
		out.append(it.id)
	return out


func test_roll_deterministic() -> String:
	var differs := false
	for sd in range(0, 60):
		for st in range(1, 5):
			var a := _ids(Shop.roll_stock(st, sd))
			var b := _ids(Shop.roll_stock(st, sd))
			if a != b: return "stage %d seed %d not deterministic" % [st, sd]
			if a.size() != ItemDb.STOCK_SIZE: return "stock size %d" % a.size()
			var u := {}
			for id in a: u[id] = true
			if u.size() != a.size(): return "duplicate in stock %s" % [a]
		if _ids(Shop.roll_stock(1, sd)) != _ids(Shop.roll_stock(1, 0)):
			differs = true
	return "" if differs else "every seed rolls the same stock"


func test_stage_gating() -> String:
	var seen := {1: {}, 2: {}, 4: {}}
	for st in seen:
		for sd in 300:
			for it in Shop.roll_stock(st, sd):
				seen[st][it.rarity] = true
	if seen[1].has("rare") or seen[1].has("legendary"): return "stage 1 rolled rare/legendary"
	if not seen[1].has("common") or not seen[1].has("uncommon"): return "stage 1 missing common/uncommon"
	if not seen[2].has("rare"): return "stage 2 never rolls rare"
	if seen[2].has("legendary"): return "stage 2 rolled legendary"
	return "" if seen[4].has("legendary") else "stage 4 never rolls legendary"


func test_buy_no_gold() -> String:
	var s := _stats()
	s.add_gold(3)
	var before := _snapshot(s)
	var it := ItemDb.make("extra_heart")   # 10 g
	var ok := Shop.buy(it, s)
	var d := _diff(before, _snapshot(s))
	var n: int = s.owned_items.size()
	s.free()
	if ok: return "buy succeeded with 3 gold"
	if not d.is_empty(): return "state changed: " + d
	if n != 0: return "owned_items grew"
	return "" if not it.sold and not it.is_applied() else "item marked sold/applied"


func test_buy_ok() -> String:
	var s := _stats()
	s.add_gold(20)
	var sig := [0]
	s.items_changed.connect(func(_i): sig[0] += 1)
	var it := ItemDb.make("soft_shoes")   # 7 g
	var ok := Shop.buy(it, s)
	var res := [s.gold, s.get_stat(&"noise_mult"), s.owned_items.size(), s.owned_items.has(it), s.owns("soft_shoes")]
	s.free()
	if not ok: return "buy failed with 20 gold"
	if res[0] != 13: return "gold want 13 got %d" % res[0]
	if not is_equal_approx(res[1], 0.75): return "item not applied (noise_mult %s)" % res[1]
	if res[2] != 1 or not res[3] or not res[4]: return "owned_items not updated"
	return "" if sig[0] == 1 else "items_changed fired %d times" % sig[0]


func test_buy_twice() -> String:
	var s := _stats()
	s.add_gold(30)
	var it := ItemDb.make("soft_shoes")
	Shop.buy(it, s)
	var ok2 := Shop.buy(it, s)
	var res := [s.gold, s.owned_items.size(), s.get_stat(&"noise_mult")]
	s.free()
	if ok2: return "same offer bought twice"
	if res[0] != 23 or res[1] != 1: return "second buy changed gold/items %s" % [res]
	return "" if is_equal_approx(res[2], 0.75) else "applied twice"


func test_reset() -> String:
	var s := _stats()
	var base := _snapshot(s)
	s.add_gold(60)
	Shop.buy(ItemDb.make("extra_heart"), s)
	Shop.buy(ItemDb.make("bright_bulb"), s)
	var bought: Array = s.owned_items.duplicate()
	s.reset()
	var d := _diff(base, _snapshot(s))
	var n: int = s.owned_items.size()
	var still := false
	for it in bought:
		still = still or it.is_applied()
	s.free()
	if n != 0: return "owned_items not cleared"
	if not d.is_empty(): return "effects remain after reset: " + d
	return "" if not still else "items still think they're applied"


## Shop Continue keeps the PlayerStats autoload as is; only restart_run() resets it.
func test_survive_continue() -> String:
	PlayerStats.add_gold(20)
	Shop.buy(ItemDb.make("soft_shoes"))
	FESignals.reset()   # what a stage swap does to FE state
	GameState.reset()
	var kept := PlayerStats.owned_items.size() == 1 and is_equal_approx(PlayerStats.get_stat(&"noise_mult"), 0.75)
	return "" if kept else "owned item lost on stage swap"


func test_max_health() -> String:
	var s := _stats()
	s.take_hit(1, true)   # 2/3
	var heart := ItemDb.make("extra_heart")
	heart.apply(s)
	if s.max_health() != 4 or s.health != 3: var m: String = "extra heart want 3/4 got %d/%d" % [s.health, s.max_health()]; s.free(); return m
	heart.remove(s)
	if s.max_health() != 3 or s.health != 3: var m: String = "remove want 3/3 got %d/%d" % [s.health, s.max_health()]; s.free(); return m
	var gold := ItemDb.make("golden_heart")
	gold.apply(s)
	if s.max_health() != 5 or s.health != 5: var m: String = "golden heart want 5/5 got %d/%d" % [s.health, s.max_health()]; s.free(); return m
	gold.remove(s)
	s.take_hit(1, true); s._invuln_left = 0.0; s.take_hit(1, true)   # 1/3
	var slip := ItemDb.make("ghost_slippers")   # -1 max heart
	slip.apply(s)
	var ok: bool = s.max_health() == 2 and s.health == 1
	slip.remove(s)
	ok = ok and s.max_health() == 3 and s.health == 1
	s.free()
	return "" if ok else "ghost slippers at 1 heart should keep 1 heart alive"


func _chest(at := Vector2(120, 100), sd := 7, st := 1) -> Chest:
	var c := Chest.new()
	c.loot_seed = sd
	c.stage = st
	return _add(c, at)


func test_chest_once() -> String:
	var c := _chest()
	if c.art_slot != Chest.SLOT_CLOSED: return "chest not closed at start"
	var noises := [0]
	var cb := func(_a, _r, _l, src): if src == c: noises[0] += 1
	NoiseBus.noise.connect(cb)
	var first := c.open()
	var second := c.open()
	NoiseBus.noise.disconnect(cb)
	if first == null: return "no item granted"
	if second != null: return "opened twice"
	if PlayerStats.owned_items.size() != 1 or PlayerStats.owned_items[0] != first: return "owned_items want 1"
	if not first.is_applied(): return "chest item not applied"
	if c.art_slot != Chest.SLOT_OPEN: return "art slot not switched to open"
	if c.can_pick_up: return "open chest still interactable"
	return "" if noises[0] == 1 else "chest noise fired %d times" % noises[0]


func test_chest_deterministic() -> String:
	for sd in 30:
		var a := ItemDb.roll_chest(2, sd)
		var b := ItemDb.roll_chest(2, sd)
		if a == null or a.id != b.id: return "seed %d differs" % sd
		if ItemDb.roll_chest(1, sd).rarity in ["rare", "legendary"]: return "stage 1 chest rolled rare+"
	return ""


func test_chest_channel() -> String:
	var p: CharacterBody2D = _add(load("res://scripts/player/player_controller.gd").new(), Vector2(100, 100))
	var c := _chest(Vector2(120, 100))
	for i in 3:   # full hands must not block opening a chest
		p.inventory.add({id = "x%d" % i, name = "x", throwable = true})
	p.interact_pressed()
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < 1.0:   # chest = 1.5 s channel
		p.tick(dt, Vector2.ZERO); t += dt
	if c.is_open: return "opened before its 1.5 s channel"
	while t < 1.7:
		p.tick(dt, Vector2.ZERO); t += dt
	if not c.is_open: return "hold channel didn't open the chest"
	if p.inventory.items.size() != 3: return "chest went into the hands"
	if not is_instance_valid(c) or c.is_queued_for_deletion(): return "chest removed from world"
	return "" if PlayerStats.owned_items.size() == 1 else "no item owned"


func test_fe_adapter() -> String:
	var offers: Array = FESignals.get_shop_offer(3, 2, 42)
	if offers.size() != 3: return "FE got %d offers (Shop not found?)" % offers.size()
	var o: Dictionary = offers[0]
	if not (o.item is Item) or o.id != o.item.id or o.price != o.item.price: return "offer dict doesn't mirror Item"
	PlayerStats.add_gold(100)
	if not FESignals.buy_offer(o): return "buy_offer failed"
	var ok := PlayerStats.gold == 100 - int(o.price) and PlayerStats.owned_items.size() == 1
	if FESignals.buy_offer(o): return "FE bought the same offer twice"
	return "" if ok else "FE buy didn't spend/own (gold %d)" % PlayerStats.gold

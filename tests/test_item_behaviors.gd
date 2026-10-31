extends RefCounted
## Behaviour items (ItemDb rows with `script`) — Back End checks. Each one goes through
## the real game path (PlayerStats.take_hit, NoiseBus, WorldObject.break_apart,
## thrown_object, PlayerController, the enemy FSM tick), never by calling the hook.

const DT := 1.0 / 60.0
var root: Node
var _changed: Array = []


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["rabbits_foot_saves_first_lethal_hit_per_stage", test_rabbits_foot],
		["music_box_pocket_lure_thrown_pulls_chasers", test_music_box],
		["music_box_world_art_slot_or_fallback", test_music_box_art],
		["music_box_tap_throws_facing_not_last_aim", test_music_box_facing],
		["heavy_vases_double_stun_and_carry_slow", test_heavy_vases],
		["flash_bulb_stuns_startle_once_per_stage", test_flash_bulb],
		["music_box_x2_one_throw_spends_one_copy", test_music_box_x2],
		["lure_pocket_no_hand_slot_api_and_signal", test_lure_pocket],
		["lure_charges_survive_shop_refill_on_stage", test_lure_refill_and_shop],
		["tap_throws_lure_true_false_cases", test_tap_throws_lure],
		["rabbits_foot_x2_one_save_per_copy", test_rabbits_foot_x2],
		["flash_bulb_x4_one_stun_per_copy", test_flash_bulb_x4],
		["stacked_behavior_effects_clamp_to_bounds", test_stacked_behavior_bounds],
		["cracked_mirror_offscreen_drain_and_arrow_distance", test_cracked_mirror],
		["greedy_sack_vase_gold_and_louder_break", test_greedy_sack],
		["charges_and_items_changed_on_use_and_stage_start", test_charges_signal],
		["at_most_3_items_pay_with_noise", test_noise_budget],
		["shop_prices_follow_price_scale", test_price_scale],
		["price_affordability_invariants", test_price_affordability],
		["behaviour_rows_load_their_script", test_rows],
		["each_stat_clamps_to_its_own_bounds_x10", test_stat_bounds],
		["item_hooks_clamp_to_stat_bounds_x10", test_hook_bounds],
	]
	var passed := 0
	for item in checks:
		_clean()
		var r: Variant = item[1].call()
		var err: String = r if r is String else "script error (check returned %s)" % [r]
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	_clean()
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"ib_test"):
			root.remove_child(c)
			c.free()
	for g in ["lures", "thrown"]:
		for n in root.get_tree().get_nodes_in_group(g):
			if is_instance_valid(n) and n.get_parent():
				n.get_parent().remove_child(n)
				n.free()
	if PlayerStats.items_changed.is_connected(_on_items_changed):
		PlayerStats.items_changed.disconnect(_on_items_changed)
	_changed.clear()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()


func _on_items_changed(items: Array) -> void:
	_changed.append(items.size())


func _watch() -> void:
	_changed.clear()
	if not PlayerStats.items_changed.is_connected(_on_items_changed):
		PlayerStats.items_changed.connect(_on_items_changed)


func _add(n: Node, at: Vector2) -> Node:
	n.set_meta(&"ib_test", true)
	root.add_child(n)
	n.global_position = at
	return n


func _grant(id: String) -> Item:
	var it := ItemDb.make(id)
	PlayerStats.grant_item(it)
	return it


func _player(at := Vector2(100, 100)) -> CharacterBody2D:
	return _add(load("res://scripts/player/player_controller.gd").new(), at)


func _puppet(at := Vector2(300, 100), sight := 0) -> CharacterBody2D:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e, at)
	e.sight_override = sight
	e.tick(0.0)
	return e


func _run(e: CharacterBody2D, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		e.tick(DT)
		e.global_position += e.velocity * DT
		t += DT
		if until.is_valid() and until.call():
			break
	return t


func _vase(at: Vector2, gold := 0) -> Vase:
	var v := Vase.new()
	_add(v, at)
	v.gold_inside = gold   # after _ready's random roll
	return v


## Flies a thrown object until it lands (frees itself).
func _fly(t: Node) -> void:
	for i in 300:
		if not is_instance_valid(t) or t.is_queued_for_deletion():
			return
		t.step(DT)


# --- Rabbit's Foot ---------------------------------------------------------------
func test_rabbits_foot() -> Variant:
	var it := _grant("rabbits_foot")
	if PlayerStats.max_health() != 2: return "max hearts %d, want 3-1" % PlayerStats.max_health()
	PlayerStats.health = 2
	PlayerStats.take_hit(1, true)
	if PlayerStats.health != 1 or it.charges != 1: return "non-lethal hit used the foot"
	if not PlayerStats.take_hit(1, true): return "lethal hit not landed"
	if PlayerStats.health != 1: return "lethal hit not survived (health %d)" % PlayerStats.health
	if GameState.game_over: return "caught despite the foot"
	if it.charges != 0: return "charge not spent"
	PlayerStats.take_hit(1, true)
	if PlayerStats.health != 0: return "second lethal hit in the stage saved too"
	# Next stage: refilled.
	PlayerStats.reset()
	it = _grant("rabbits_foot")
	it.set_charges(0)
	_player()   # stage start
	if it.charges != 1: return "charge not refilled on stage start"
	PlayerStats.health = 1
	PlayerStats.take_hit(3, true)
	return "" if PlayerStats.health == 1 else "refilled foot didn't save (health %d)" % PlayerStats.health


# --- Music Box ---------------------------------------------------------------------
func test_music_box() -> Variant:
	var it := _grant("music_box")
	var p := _player(Vector2(100, 100))
	if not p.inventory.items.is_empty(): return "stage start put %s in the hands (lures live in the pocket)" % [p.inventory.items]
	if it.charges != 1: return "charges %d, want 1 at stage start" % it.charges
	if PlayerStats.lure_charges() != 1 or PlayerStats.lure_max() != 1: return "pocket %d/%d, want 1/1" % [PlayerStats.lure_charges(), PlayerStats.lure_max()]
	var e := _puppet(Vector2(1100, 100), 0)   # can't see the boy
	if e.state != e.State.CALM: return "not calm at start"
	p.aim_dir = Vector2.RIGHT
	FESignals.selected_enemy = null
	p._tap()   # no ringed enemy, empty hands, nothing to knock: a pocket lure throws
	if it.charges != 0: return "charge not spent on throw"
	if PlayerStats.lure_charges() != 0: return "pocket still %d after the throw" % PlayerStats.lure_charges()
	var thrown: Array = root.get_tree().get_nodes_in_group("thrown")
	if thrown.is_empty(): return "nothing thrown"
	_fly(thrown[0])
	var lures: Array = root.get_tree().get_nodes_in_group("lures")
	if lures.is_empty(): return "lure didn't land as a MusicBoxLure"
	var lure: Node2D = lures[0]
	if lure.global_position.distance_to(p.global_position) < 200.0: return "landed at the boy"
	lure.step(DT)
	if lure.pulses != 1: return "no noise pulse"
	if e.state != e.State.SEARCH: return "enemy didn't go to the lure (state %d)" % e.state
	if e.last_known.distance_to(lure.global_position) > 1.0: return "hunting %s, not the lure %s" % [e.last_known, lure.global_position]
	var d0: float = e.global_position.distance_to(lure.global_position)
	for i in 60:
		lure.step(DT)
		_run(e, DT)
	if e.global_position.distance_to(lure.global_position) >= d0 - 20.0: return "didn't walk toward the lure"
	if e.state != e.State.SEARCH: return "lost the lure while it plays (state %d)" % e.state
	if lure.pulses < 2: return "not repeating (%d pulses)" % lure.pulses
	# A lure is not a weapon: a calm puppet it hits survives.
	var calm := _puppet(Vector2(400, 300), 0)
	var t := Node2D.new()
	t.set_script(load("res://scripts/world/thrown_object.gd"))
	t.set("item", it.lure_dict())
	_add(t, Vector2(100, 300))
	t.setup(Vector2(100, 300), it.lure_dict(), calm, p)
	_fly(t)
	return "" if not calm.is_queued_for_deletion() else "lure killed a calm puppet"


## QA repro: light off, last aim right, boy turns to face left, tap: the lure flies LEFT.
func test_music_box_facing() -> Variant:
	_grant("music_box")
	var p := _player(Vector2(600, 100))
	if p.light_on(): p.toggle_light()
	if p.light_on(): return "light still on"
	p.aim_dir = Vector2.RIGHT
	p.tick(DT, Vector2.LEFT)   # face left
	if p.facing != -1: return "not facing left"
	FESignals.selected_enemy = null
	p._tap()
	var thrown: Array = root.get_tree().get_nodes_in_group("thrown")
	if thrown.is_empty(): return "nothing thrown"
	_fly(thrown[0])
	var lures: Array = root.get_tree().get_nodes_in_group("lures")
	if lures.is_empty(): return "lure didn't land"
	var x: float = (lures[0] as Node2D).global_position.x
	return "" if x < p.global_position.x - 200.0 else "lure landed at x=%.0f, boy at %.0f (not left)" % [x, p.global_position.x]


func test_music_box_art() -> Variant:
	var n := Node2D.new()
	MusicBoxLure.add_visual(n)
	var art := n.get_node_or_null(^"MusicBoxArt")
	var ok := art != null
	if ok and AnimLibrary.has_slot(MusicBoxLure.SLOT):
		ok = art is AnimatedSprite2D
	elif ok:
		ok = art is ColorRect   # slot not in the manifest yet (Designer PR #30)
	n.free()
	return "" if ok else "music_box_world art missing or wrong kind"


# --- Heavy Vases -------------------------------------------------------------------
func _vase_stun(with_item: bool) -> float:
	_clean()
	if with_item:
		_grant("heavy_vases")
	var p := _player(Vector2(100, 100))
	var e := _puppet(Vector2(300, 100), 0)
	e.hear_noise()   # enraged: a hit stuns
	var v := _vase(Vector2(150, 100))
	p.inventory.add(v.to_item())
	var t: Node = p.throw_at(e)
	_fly(t)
	return e._state_left if e.state == e.State.STUNNED else -1.0


func test_heavy_vases() -> Variant:
	var base := _vase_stun(false)
	var heavy := _vase_stun(true)
	if base <= 0.0 or heavy <= 0.0: return "vase hit didn't stun (%s / %s)" % [base, heavy]
	if not is_equal_approx(heavy, base * 2.0): return "stun %.2f vs %.2f, want x2" % [heavy, base]
	# Carry penalty: only while a vase is in hand, through the real tick.
	var p := _player(Vector2(100, 400))
	p.floor_override = 1
	p.tick(DT, Vector2.RIGHT)
	var empty: float = absf(p.velocity.x if p.side_scroll else p.velocity.length())
	p.inventory.add(_vase(Vector2(100, 400)).to_item())
	p.tick(DT, Vector2.RIGHT)
	var carrying: float = absf(p.velocity.x if p.side_scroll else p.velocity.length())
	if not is_equal_approx(carrying, empty * 0.85): return "carry speed %.1f vs %.1f" % [carrying, empty]
	return ""


# --- Flash Bulb --------------------------------------------------------------------
func test_flash_bulb() -> Variant:
	var it := _grant("flash_bulb")
	_player()
	var e := _puppet(Vector2(300, 100), 0)
	e.lit_override = 1
	_run(e, 3.0, func(): return e.state != e.State.CALM and e.state != e.State.STARTLED)
	if e.state != e.State.STUNNED: return "completed startle didn't stun (state %d)" % e.state
	if not is_equal_approx(e._state_left + DT, 2.5) and absf(e._state_left - 2.5) > 0.05: return "stun %.2f, want 2.5" % e._state_left
	if it.charges != 0: return "charge not spent"
	if FESignals.chasing.has(e): return "reported as chasing"
	e.lit_override = 0
	_run(e, 2.6)
	if e.state != e.State.CALM: return "not calm after the flash stun (state %d)" % e.state
	# Second startle this stage: normal chase.
	e.lit_override = 1
	_run(e, 3.0, func(): return e.state == e.State.CHASE or e.state == e.State.STUNNED)
	if e.state != e.State.CHASE: return "second startle in a stage not a chase (state %d)" % e.state
	return ""


# --- Cracked Mirror ----------------------------------------------------------------
func _drain(with_item: bool, at: Vector2) -> float:
	_clean()
	if with_item:
		_grant("cracked_mirror")
	_player(Vector2(100, 100))
	var e := _puppet(at, 0)
	e.hear_noise()
	e._track_left = 0.0
	e.chase_speed = 0.0   # hold distance fixed
	_run(e, 0.5)
	return 1.0 - e.memory


func test_cracked_mirror() -> Variant:
	if PlayerStats.arrow_reveal_distance() != INF: return "reveal distance without mirror %s" % PlayerStats.arrow_reveal_distance()
	var off := Vector2(100 + 900, 100)   # > 640 px: off screen
	var on := Vector2(100 + 400, 100)
	var base_off := _drain(false, off)
	var mir_off := _drain(true, off)
	var base_on := _drain(false, on)
	var mir_on := _drain(true, on)
	if base_off <= 0.0: return "no drain"
	if absf(mir_off / base_off - 1.4) > 0.02: return "off-screen drain x%.2f, want 1.4" % (mir_off / base_off)
	if absf(mir_on / base_on - 1.0) > 0.001: return "on-screen drain changed x%.2f" % (mir_on / base_on)
	if not is_equal_approx(PlayerStats.arrow_reveal_distance(), 1280.0): return "reveal distance %s" % PlayerStats.arrow_reveal_distance()
	PlayerStats.reset()
	return "" if PlayerStats.arrow_reveal_distance() == INF else "reveal distance not reset"


# --- Greedy Sack -------------------------------------------------------------------
var _heard: Array = []

func _on_noise(_at: Vector2, radius: float, loudness: float, _src: Node) -> void:
	_heard.append([radius, loudness])


func _break(with_item: bool) -> Array:
	_clean()
	if with_item:
		_grant("greedy_sack")
	_heard.clear()
	NoiseBus.noise.connect(_on_noise)
	var v := _vase(Vector2(200, 100), 0)
	var g0 := PlayerStats.gold
	v.break_apart()
	NoiseBus.noise.disconnect(_on_noise)
	return [PlayerStats.gold - g0, _heard[0] if not _heard.is_empty() else [0.0, 0.0]]


func test_greedy_sack() -> Variant:
	var plain := _break(false)
	if plain[0] != 0: return "empty vase dropped %d gold without the sack" % plain[0]
	for i in 5:
		var greedy := _break(true)
		if greedy[0] < 1 or greedy[0] > 3: return "empty vase gave %d gold with the sack" % greedy[0]
		if not is_equal_approx(greedy[1][0], plain[1][0] * 1.5): return "break radius %.0f vs %.0f" % [greedy[1][0], plain[1][0]]
	# A full vase keeps its gold; non-vase noise isn't louder.
	_clean()
	_grant("greedy_sack")
	var v := _vase(Vector2(200, 100), 2)
	v.break_apart()
	if PlayerStats.gold != 2: return "full vase changed to %d" % PlayerStats.gold
	_heard.clear()
	NoiseBus.noise.connect(_on_noise)
	NoiseBus.emit_noise(Vector2.ZERO, 100.0, 1.0, null)
	NoiseBus.noise.disconnect(_on_noise)
	return "" if is_equal_approx(_heard[0][0], 100.0) else "non-vase noise scaled"


# --- charges + items_changed (FE) -------------------------------------------------
func test_charges_signal() -> Variant:
	var fb := _grant("flash_bulb")
	var rf := _grant("rabbits_foot")
	if fb.max_charges != 1 or fb.charges != 1 or rf.max_charges != 1: return "max_charges/charges wrong"
	if ItemDb.make("sneakers").max_charges != 0: return "plain item has charges"
	var d := fb.to_dict()
	if not (d.has("charges") and d.has("max_charges")): return "to_dict lacks charges"
	_watch()
	PlayerStats.health = 1
	PlayerStats.take_hit(1, true)   # rabbit's foot fires
	if _changed.size() != 1: return "items_changed on charge use: %d emits" % _changed.size()
	_changed.clear()
	_player()   # stage start resets charges
	if _changed.is_empty(): return "no items_changed on stage start"
	if rf.charges != 1: return "stage start didn't refill"
	return ""


# --- rules -------------------------------------------------------------------------
## Noise budget: at most 3 items may pay with "noise carries farther" (any noise cost
## counts, which is stricter than "noise as the only downside").
func test_noise_budget() -> Variant:
	var louder: PackedStringArray = []
	for r in ItemDb.ITEMS:
		var loud := false
		for m in r.mods:
			if StringName(m.stat) == &"noise_mult" and float(m.get("mul", 1.0)) > 1.0:
				loud = true
		if float((r.get("params", {}) as Dictionary).get("noise_mult", 1.0)) > 1.0:
			loud = true
		if loud:
			louder.append(str(r.id))
	return "" if louder.size() <= 3 else "%d noise-cost items: %s" % [louder.size(), louder]


## Affordability invariants (retune from the measured gold, docs/BACKEND.md "Gold economy").
## Guaranteed side: StageTable's floor-pile gold (generator-enforced for every level) covers the
## cheapest offer of the shop after every stage 1-4, with the shop's own rounding. Typical side
## (from the stage table, no level builds): income = piles x mean amount + half the vase gold
## (vases = props x vase_ratio, 0.45 x mean 2 gold each) must sit at 0.8-1.6 x the rarity-weighted
## mean offer, so a typical run affords about one item per shop, not two; and the gold a
## shop-skipping player has gathered by shop 4 reaches the cheapest legendary (a saving goal).
func test_price_affordability() -> Variant:
	var cum := 0.0
	for st in [1, 2, 3, 4]:
		var P := StageTable.params(st)
		var cheap := StageTable.cheapest_shop_price(st)
		var floor_gold := StageTable.gold_floor_min(P)
		if floor_gold < cheap: return "shop %d: worst-roll gold %d < cheapest offer %d" % [st, floor_gold, cheap]
		var ga: Array = P.gold_amount
		var piles := float(P.gold_piles) * (float(ga[0]) + float(ga[ga.size() - 1])) / 2.0
		var vases := float(P.props) * float(P.vase_ratio)
		var income := piles + 0.5 * vases * 0.45 * 2.0
		cum += income
		var wsum := 0.0
		var psum := 0.0
		for id in ItemDb.pool_for_stage(st):
			var w := float(ItemDb.RARITY[ItemDb.row(id).rarity].weight)
			wsum += w
			psum += w * ItemDb.shop_price(id, st)
		var mean_offer := psum / wsum
		var ratio := income / mean_offer
		if ratio < 0.8 or ratio > 1.6: return "shop %d: typical income %.1f / mean offer %.1f = %.2f, want 0.8-1.6 (one item per shop)" % [st, income, mean_offer, ratio]
	var legendary := 1 << 30
	for r in ItemDb.ITEMS:
		if r.rarity == "legendary":
			legendary = mini(legendary, ItemDb.shop_price(str(r.id), 4))
	if cum < float(legendary): return "a saver's gold by shop 4 (%.0f) can't reach the cheapest legendary (%d)" % [cum, legendary]
	return ""


func test_price_scale() -> Variant:
	if ItemDb.PRICE_SCALE.size() != 4: return "PRICE_SCALE needs one entry per shop (4)"
	for st in [1, 2, 3, 4]:
		for it in Shop.roll_stock(st, 7):
			var want := ItemDb.shop_price(it.id, st)
			if it.price != want: return "%s stage %d price %d, want %d" % [it.id, st, it.price, want]
	if ItemDb.shop_price("sneakers", 4) <= ItemDb.shop_price("sneakers", 1): return "later shops not pricier"
	return ""


func test_rows() -> Variant:
	var n := 0
	for r in ItemDb.ITEMS:
		if r.has("script"):
			n += 1
			var it := ItemDb.make(str(r.id))
			if not it.has_behavior(): return "%s: no behaviour" % r.id
			if it.icon_slot != "item_icon_" + str(r.id): return "%s icon %s" % [r.id, it.icon_slot]
	if n != 6: return "%d behaviour items, want 6" % n
	for id in ["rabbits_foot", "music_box", "heavy_vases", "flash_bulb", "cracked_mirror", "greedy_sack"]:
		if ItemDb.row(id).is_empty(): return "missing " + id
	return ""


# --- stat caps (PlayerStats.STAT_BOUNDS) -----------------------------------------
## Every BASE stat (and every hook key) has [min, max] with min <= base <= max, in the stat's
## own units; PD's numbers are exact; any stack of extreme modifiers lands on the bound.
const PD_BOUNDS := {
	&"max_health": [1.0, 6.0], &"invuln_time": [0.5, 2.0], &"inventory_slots": [1.0, 5.0],
	&"light_startle_time": [0.4, 1.5], &"light_angle_deg": [10.0, 70.0], &"noise_mult": [0.3, 3.0],
}

func test_stat_bounds() -> Variant:
	var B: Dictionary = PlayerStats.STAT_BOUNDS
	for st in PD_BOUNDS:
		if B.get(st, []) != PD_BOUNDS[st]: return "%s bounds %s, want %s" % [st, B.get(st), PD_BOUNDS[st]]
	for st in PlayerStats.BASE:
		if not B.has(st): return "%s has no bounds" % st
		var b: Array = B[st]
		var base := float(PlayerStats.BASE[st])
		if b.size() != 2 or b[0] > base or b[1] < base: return "%s bounds %s don't bracket base %s" % [st, b, base]
		for case in [[1e6, 2.0, b[1]], [-1e6, 0.5, b[0]]]:
			PlayerStats.reset()
			PlayerStats.add_modifier(st, case[0], 1.0, "add")
			for i in 10:
				PlayerStats.add_modifier(st, 0.0, case[1], "stack%d" % i)
			var v := PlayerStats.get_stat(st)
			if absf(v - case[2]) > 1e-4: return "%s stacked to %.3f, want bound %.3f" % [st, v, case[2]]
	for r in ItemDb.ITEMS:
		for m in r.mods:
			if not B.has(StringName(m.stat)): return "%s: %s has no bounds" % [r.id, m.stat]
	# Stacked items hit PD's caps through the real grant path.
	PlayerStats.reset()
	for i in 10:
		for id in ["extra_heart", "thick_sweater", "big_pockets", "grandfathers_watch"]:
			if not ItemDb.row(id).is_empty(): PlayerStats.grant_item(ItemDb.make(id))
	for st in [&"max_health", &"invuln_time", &"inventory_slots", &"light_startle_time"]:
		var v := PlayerStats.get_stat(st)
		var hi: float = PD_BOUNDS[st][1]
		if v > hi + 1e-4: return "10 stacked items push %s to %.3f > %.3f" % [st, v, hi]
	if PlayerStats.max_health() > 6: return "max_health() %d > 6" % PlayerStats.max_health()
	return ""


## Hook multipliers clamp too: 10 Greedy Sacks (vase noise x1.5^10), 10 Cracked Mirrors
## (give-up x1.4^10), 10 Heavy Vases (carry x0.85^10).
func test_hook_bounds() -> Variant:
	var vase := {script_path = "res://scripts/world/vase.gd"}
	for i in 10:
		_grant("greedy_sack"); _grant("cracked_mirror"); _grant("heavy_vases")
		PlayerStats.add_modifier(&"noise_mult", 0.0, 2.0, "stack%d" % i)   # push the stat to its max too
		PlayerStats.add_modifier(&"move_speed", 0.0, 0.5, "stack%d" % i)
	var noise := PlayerStats.get_stat(&"noise_mult") * PlayerStats.noise_hook_mult(Vector2.ZERO, 100.0, 1.0, vase)
	if absf(noise - 3.0) > 1e-4: return "vase noise x%.3f, want capped at x3.0" % noise
	var give_up := PlayerStats.memory_drain_mult(null, true)
	if absf(give_up - PlayerStats.STAT_BOUNDS[&"give_up_speed"][1]) > 1e-4: return "give-up x%.3f not capped" % give_up
	var p := _player()
	p.inventory.items.append(vase)
	var spd: float = p.move_speed()
	if absf(spd - PlayerStats.STAT_BOUNDS[&"move_speed"][0]) > 1e-3: return "carry speed %.3f, want floor %.2f" % [spd, PlayerStats.STAT_BOUNDS[&"move_speed"][0]]
	return ""


# --- Stacked charged items: one event spends exactly one copy -------------------------
## [charges, max_charges] summed over owned copies of `id` (what the FE stacked tile shows).
func _stack(id: String) -> Array:
	var c := 0
	var m := 0
	for it in PlayerStats.owned_items:
		if str(it.id) == id:
			c += it.charges
			m += it.max_charges
	return [c, m]


## QA repro: grant 2 Music Boxes, start a stage, throw once -> 1/2, one more in the pocket.
func test_music_box_x2() -> Variant:
	var a := _grant("music_box")
	var b := _grant("music_box")
	var p := _player(Vector2(600, 100))
	if _stack("music_box") != [2, 2]: return "stage start %s, want 2/2" % [_stack("music_box")]
	if not p.inventory.items.is_empty(): return "lures in the hands: %s" % [p.inventory.items]
	_watch()
	FESignals.selected_enemy = null
	var first := PlayerStats.next_lure()
	p._tap()
	if _stack("music_box") != [1, 2]: return "after one throw %s, want 1/2" % [_stack("music_box")]
	var spent: Item = a if a.owns_lure(first) else b
	var kept: Item = b if spent == a else a
	if spent.charges != 0 or kept.charges != 1: return "wrong copy spent (thrown lure's box %d, other %d)" % [spent.charges, kept.charges]
	if _changed.is_empty(): return "items_changed not fired on the first throw"
	var second := PlayerStats.next_lure()
	if not kept.owns_lure(second): return "next pocket lure isn't the unspent box's"
	var n := _changed.size()
	p._tap()
	if _stack("music_box") != [0, 2]: return "after two throws %s, want 0/2" % [_stack("music_box")]
	if _changed.size() <= n: return "items_changed not fired on the second throw"
	var thrown := root.get_tree().get_nodes_in_group("thrown").size()
	p._tap()
	if root.get_tree().get_nodes_in_group("thrown").size() != thrown: return "empty pocket still threw"
	return ""


## Lure pocket: Music Boxes never take a hand slot, so a full set of boxes doesn't block a
## vase pickup; the pocket API sums copies; lures_changed fires on throw / refill.
func test_lure_pocket() -> Variant:
	for i in 3: _grant("music_box")
	var got: Array = []
	var cb := func(c: int, m: int): got.append([c, m])
	PlayerStats.lures_changed.connect(cb)
	var p := _player(Vector2(100, 100))
	if got.is_empty() or got[-1] != [3, 3]: PlayerStats.lures_changed.disconnect(cb); return "begin_stage lures_changed %s, want [3, 3]" % [got]
	if PlayerStats.lure_charges() != 3 or PlayerStats.lure_max() != 3: PlayerStats.lures_changed.disconnect(cb); return "pocket %d/%d" % [PlayerStats.lure_charges(), PlayerStats.lure_max()]
	# Vase pickup with a full pocket: the hands are free.
	var v := _vase(Vector2(110, 100))
	p.interact_pressed()
	for i in 240:
		p.tick(DT, Vector2.ZERO)
		if not p.inventory.items.is_empty(): break
	p.interact_released()
	if p.inventory.items.size() != 1 or p.inventory.items[0].get("lure", false): PlayerStats.lures_changed.disconnect(cb); return "vase pickup blocked/wrong (%s)" % [p.inventory.items]
	# Holding the vase, nothing ringed: tap throws a lure, the vase stays in hand.
	FESignals.selected_enemy = null
	got.clear()
	p._tap()
	PlayerStats.lures_changed.disconnect(cb)
	if PlayerStats.lure_charges() != 2: return "pocket %d after a throw, want 2" % PlayerStats.lure_charges()
	if got != [[2, 3]]: return "lures_changed on throw %s, want [[2, 3]]" % [got]
	if p.inventory.items.size() != 1: return "the lure throw took the vase from the hands"
	if is_instance_valid(v) and not v.is_queued_for_deletion() and not v.broken: return "vase still in the world"
	return ""


## #38 per-copy charges kept: partial counts survive the shop (buying another copy doesn't
## refill), next stage refills every copy.
func test_lure_refill_and_shop() -> Variant:
	_grant("music_box")
	_grant("music_box")
	var p := _player(Vector2(600, 100))
	FESignals.selected_enemy = null
	p._tap()
	if PlayerStats.lure_charges() != 1: return "after a throw %d, want 1" % PlayerStats.lure_charges()
	PlayerStats.add_gold(500)
	var it := ItemDb.make("music_box")
	if not Shop.buy(it): return "couldn't buy a 3rd box"
	if PlayerStats.lure_max() != 3: return "max %d after buying, want 3" % PlayerStats.lure_max()
	if PlayerStats.lure_charges() != 2: return "shop changed spent counts: %d, want 1 + the new box's 1" % PlayerStats.lure_charges()
	PlayerStats.begin_stage(p)
	return "" if PlayerStats.lure_charges() == 3 else "next stage refilled to %d, want 3" % PlayerStats.lure_charges()


## tap_throws_lure(): true only with lures left and no knock taking the tap.
func test_tap_throws_lure() -> Variant:
	var p := _player(Vector2(100, 100))
	if PlayerStats.tap_throws_lure(): return "true with no Music Box"
	_grant("music_box")
	PlayerStats.begin_stage(p)
	if not PlayerStats.tap_throws_lure(): return "false with a lure and nothing in reach"
	var v := _vase(Vector2(100 + 10 * p.facing, 100))
	if p.knock_target() == null: return "test vase not in knock reach"
	if PlayerStats.tap_throws_lure(): return "true while empty hands would knock the vase"
	FESignals.selected_enemy = null
	p._tap()
	if PlayerStats.lure_charges() != 1: return "the knock tap spent a lure"
	if not v.broken: return "the tap didn't knock the vase"
	if not PlayerStats.tap_throws_lure(): return "false once the vase is gone"
	p._tap()
	if PlayerStats.tap_throws_lure(): return "true with an empty pocket"
	PlayerStats.reset()
	return "" if not PlayerStats.tap_throws_lure() else "true after reset (stale player)"


func test_rabbits_foot_x2() -> Variant:
	_grant("rabbits_foot")
	_grant("rabbits_foot")
	_player()
	if _stack("rabbits_foot") != [2, 2]: return "stage start %s, want 2/2" % [_stack("rabbits_foot")]
	_watch()
	for i in 2:
		PlayerStats.health = 1
		var n := _changed.size()
		PlayerStats.take_hit(1, true)
		if PlayerStats.health != 1: return "lethal hit %d not saved" % (i + 1)
		if _stack("rabbits_foot") != [1 - i, 2]: return "after save %d: %s, want %d/2" % [i + 1, _stack("rabbits_foot"), 1 - i]
		if _changed.size() <= n: return "items_changed not fired on save %d" % (i + 1)
	PlayerStats.take_hit(1, true)
	return "" if PlayerStats.health == 0 else "third lethal hit saved with 2 feet"


func test_flash_bulb_x4() -> Variant:
	for i in 4:
		_grant("flash_bulb")
	_player()
	if _stack("flash_bulb") != [4, 4]: return "stage start %s, want 4/4" % [_stack("flash_bulb")]
	var e := _puppet(Vector2(300, 100), 0)
	_watch()
	for i in 4:
		var n := _changed.size()
		e.lit_override = 1
		_run(e, 3.0, func(): return e.state != e.State.CALM and e.state != e.State.STARTLED)
		if e.state != e.State.STUNNED: return "startle %d not stunned (state %d)" % [i + 1, e.state]
		if _stack("flash_bulb") != [3 - i, 4]: return "after stun %d: %s, want %d/4" % [i + 1, _stack("flash_bulb"), 3 - i]
		if _changed.size() <= n: return "items_changed not fired on stun %d" % (i + 1)
		e.lit_override = 0
		_run(e, 2.6)
		if e.state != e.State.CALM: return "not calm after stun %d (state %d)" % [i + 1, e.state]
	e.lit_override = 1
	_run(e, 3.0, func(): return e.state == e.State.CHASE or e.state == e.State.STUNNED)
	return "" if e.state == e.State.CHASE else "fifth startle with 4 bulbs not a chase (state %d)" % e.state


# --- Stacked multiplicative behaviour effects (PD): product of copies clamps to STAT_BOUNDS ---
## Vase thrown at an enraged puppet: [stun_mult in the dict, stun seconds on the enemy].
func _stacked_vase_stun() -> Array:
	var p := _player(Vector2(100, 100))
	var e := _puppet(Vector2(300, 100), 0)
	e.lit_override = 1
	_run(e, 3.0, func(): return e.state == e.State.CHASE)
	if e.state != e.State.CHASE: return [-1.0, -1.0]
	var d := {id = "v", script_path = "res://scripts/world/vase.gd", throwable = true}
	PlayerStats.dispatch_throw(d, e)   # the real throw path's hook step
	e.on_hit_by_throw(d)
	var r := [float(d.get("stun_mult", 1.0)), e._state_left / e.stun_time]
	_clean()
	return r


func test_stacked_behavior_bounds() -> Variant:
	var B: Dictionary = PlayerStats.STAT_BOUNDS
	for k in [&"stun_mult", &"item_noise_mult", &"item_carry_mult", &"give_up_speed"]:
		if not B.has(k): return "no bounds for %s" % k
	if B[&"stun_mult"][1] != 2.5: return "stun cap x%s, PD says x2.5" % B[&"stun_mult"][1]
	var vase := {script_path = "res://scripts/world/vase.gd"}
	# Heavy Vases stun: 1 copy keeps x2.0; 2 copies exactly x2.5 (not x4); 5 copies still x2.5.
	for case in [[1, 2.0], [2, 2.5], [5, 2.5]]:
		for i in case[0]: _grant("heavy_vases")
		var r := _stacked_vase_stun()
		if r[0] < 0.0: return "puppet never chased"
		if absf(r[0] - case[1]) > 1e-4: return "%d Heavy Vases: stun_mult x%.3f, want x%.2f" % [case[0], r[0], case[1]]
		if absf(r[1] - case[1]) > 1e-3: return "%d Heavy Vases: enemy stunned x%.3f, want x%.2f" % [case[0], r[1], case[1]]
	# An over-tagged dict from anywhere still stuns at most x2.5 on the enemy side.
	_player(Vector2(100, 100))
	var e := _puppet(Vector2(300, 100), 0)
	e.lit_override = 1
	_run(e, 3.0, func(): return e.state == e.State.CHASE)
	if e.state != e.State.CHASE: return "puppet never chased (over-tag case)"
	e.on_hit_by_throw({stun_mult = 8.0})
	if absf(e._state_left / e.stun_time - 2.5) > 1e-3: return "enemy took an uncapped stun x%.2f" % (e._state_left / e.stun_time)
	_clean()
	# Greedy Sack vase-break noise hook: 1 copy x1.5, 2 copies x2.0 (not x2.25).
	for case in [[1, 1.5], [2, 2.0], [4, 2.0]]:
		for i in case[0]: _grant("greedy_sack")
		var m := PlayerStats.noise_hook_mult(Vector2.ZERO, 100.0, 1.0, vase)
		if absf(m - case[1]) > 1e-4: return "%d Greedy Sacks: vase noise x%.3f, want x%.2f" % [case[0], m, case[1]]
		_clean()
	# Heavy Vases carry slow: 1 copy x0.85, 2 copies x0.7225 (inside), 3+ copies floor x0.7.
	for case in [[1, 0.85], [2, 0.7225], [3, 0.7], [4, 0.7]]:
		for i in case[0]: _grant("heavy_vases")
		var m := PlayerStats.carry_speed_mult([vase])
		if absf(m - case[1]) > 1e-4: return "%d Heavy Vases: carry x%.4f, want x%.2f" % [case[0], m, case[1]]
		_clean()
	# Cracked Mirror off-screen give-up: 2 copies x1.96 (inside), 4 copies x3.0 (capped).
	for case in [[1, 1.4], [2, 1.96], [4, 3.0]]:
		for i in case[0]: _grant("cracked_mirror")
		var m := PlayerStats.memory_drain_mult(null, true)
		if absf(m - case[1]) > 1e-4: return "%d Cracked Mirrors: give-up x%.3f, want x%.2f" % [case[0], m, case[1]]
		_clean()
	return ""

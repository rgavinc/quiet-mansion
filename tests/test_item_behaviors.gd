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
		["music_box_lure_in_hand_thrown_pulls_chasers", test_music_box],
		["music_box_world_art_slot_or_fallback", test_music_box_art],
		["music_box_tap_throws_facing_not_last_aim", test_music_box_facing],
		["heavy_vases_double_stun_and_carry_slow", test_heavy_vases],
		["flash_bulb_stuns_startle_once_per_stage", test_flash_bulb],
		["music_box_x2_one_throw_spends_one_copy", test_music_box_x2],
		["rabbits_foot_x2_one_save_per_copy", test_rabbits_foot_x2],
		["flash_bulb_x4_one_stun_per_copy", test_flash_bulb_x4],
		["cracked_mirror_offscreen_drain_and_arrow_distance", test_cracked_mirror],
		["greedy_sack_vase_gold_and_louder_break", test_greedy_sack],
		["charges_and_items_changed_on_use_and_stage_start", test_charges_signal],
		["at_most_3_items_pay_with_noise", test_noise_budget],
		["shop_prices_follow_price_scale", test_price_scale],
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
	var held: Dictionary = p.inventory.current()
	if not held.get("lure", false): return "no lure in hand at stage start (%s)" % [held]
	if it.charges != 1: return "charges %d, want 1 with the lure in hand" % it.charges
	var e := _puppet(Vector2(1100, 100), 0)   # can't see the boy
	if e.state != e.State.CALM: return "not calm at start"
	p.aim_dir = Vector2.RIGHT
	FESignals.selected_enemy = null
	p._tap()   # no ringed enemy: a lure still throws, toward the aim
	if not p.inventory.current().is_empty(): return "lure still in hand after tap"
	if it.charges != 0: return "charge not spent on throw"
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
## Every multiplier stat an item touches has its own [min, max]; noise is PD's x0.3..x3;
## 10 stacked x2 (or x0.5) modifiers land exactly on that stat's max (min).
func test_stat_bounds() -> Variant:
	var nb: Array = PlayerStats.STAT_BOUNDS.get(&"noise_mult", [])
	if nb != [0.3, 3.0]: return "noise bounds %s, want [0.3, 3.0]" % [nb]
	for r in ItemDb.ITEMS:
		for m in r.mods:
			var st := StringName(m.stat)
			var is_mult := float(m.get("mul", 1.0)) != 1.0 or str(st).ends_with("_mult")
			if is_mult and not PlayerStats.STAT_BOUNDS.has(st): return "%s: %s has no bounds" % [r.id, st]
	for st in PlayerStats.STAT_BOUNDS:
		if not PlayerStats.BASE.has(st):
			continue
		var b: Array = PlayerStats.STAT_BOUNDS[st]
		if b.size() != 2 or not (b[0] < 1.0 and b[1] > 1.0): return "%s bounds %s don't bracket x1" % [st, b]
		var base := float(PlayerStats.BASE[st])
		for case in [[2.0, b[1]], [0.5, b[0]]]:
			PlayerStats.reset()
			for i in 10:
				PlayerStats.add_modifier(st, 0.0, case[0], "stack%d" % i)
			var v := PlayerStats.get_stat(st)
			if absf(v - base * case[1]) > 1e-4: return "%s x%s^10 = %.3f, want %.3f" % [st, case[0], v, base * case[1]]
	return ""


## Hook multipliers clamp too: 10 Greedy Sacks (vase noise x1.5^10), 10 Cracked Mirrors
## (give-up x1.4^10), 10 Heavy Vases (carry x0.85^10).
func test_hook_bounds() -> Variant:
	var vase := {script_path = "res://scripts/world/vase.gd"}
	for i in 10:
		_grant("greedy_sack"); _grant("cracked_mirror"); _grant("heavy_vases")
	var noise := PlayerStats.get_stat(&"noise_mult") * PlayerStats.noise_hook_mult(Vector2.ZERO, 100.0, 1.0, vase)
	if absf(noise - 3.0) > 1e-4: return "vase noise x%.3f, want capped at x3.0" % noise
	var give_up := PlayerStats.memory_drain_mult(null, true)
	if absf(give_up - PlayerStats.STAT_BOUNDS[&"give_up_speed"][1]) > 1e-4: return "give-up x%.3f not capped" % give_up
	var p := _player()
	p.inventory.items.append(vase)
	var spd: float = p.move_speed() / float(PlayerStats.BASE[&"move_speed"])
	if absf(spd - PlayerStats.STAT_BOUNDS[&"move_speed"][0]) > 1e-4: return "carry speed x%.3f, want floor x%.2f" % [spd, PlayerStats.STAT_BOUNDS[&"move_speed"][0]]
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


## QA repro: grant 2 Music Boxes, start a stage, throw once -> 1/2 and a lure still in hand.
func test_music_box_x2() -> Variant:
	var a := _grant("music_box")
	var b := _grant("music_box")
	var p := _player(Vector2(600, 100))   # stage start: each copy puts its own lure in hand
	if _stack("music_box") != [2, 2]: return "stage start %s, want 2/2" % [_stack("music_box")]
	var lures := 0
	for d in p.inventory.items:
		if d.get("lure", false): lures += 1
	if lures != 2: return "%d lures in hand at stage start, want 2" % lures
	_watch()
	FESignals.selected_enemy = null
	var first: Dictionary = p.inventory.current()
	p._tap()
	if _stack("music_box") != [1, 2]: return "after one throw %s, want 1/2" % [_stack("music_box")]
	var spent: Item = a if a.owns_lure(first) else b
	var kept: Item = b if spent == a else a
	if spent.charges != 0 or kept.charges != 1: return "wrong copy spent (thrown lure's box %d, other %d)" % [spent.charges, kept.charges]
	if _changed.is_empty(): return "items_changed not fired on the first throw"
	var second: Dictionary = p.inventory.current()
	if not second.get("lure", false): return "no lure in hand after the first throw (%s)" % [second]
	if not kept.owns_lure(second): return "lure in hand isn't the unspent box's"
	var n := _changed.size()
	p._tap()
	if _stack("music_box") != [0, 2]: return "after two throws %s, want 0/2" % [_stack("music_box")]
	if _changed.size() <= n: return "items_changed not fired on the second throw"
	return ""


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

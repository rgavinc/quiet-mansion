class_name ItemDb
extends RefCounted
## The ONE place item numbers live. Adding an item = adding one row to ITEMS.
## Row: {id, name, desc, icon, price, rarity, mods: [{stat, add, mul}]}.
##   add  — added to the base value (default 0)
##   mul  — multiplies the result (default 1)
## Every item is a trade-off (Brotato-style): something better, something worse.
## Stats are PlayerStats.BASE keys; PlayerStats.STAT_BOUNDS (min AND max for every stat) keeps combos sane.
## EVERY number in `desc` is a token filled by describe() from the EFFECTIVE, CAPPED value
## (what the next copy really adds, given what is owned); no digits in `desc` (tests enforce).

## Rarity → shop/chest weight and the first stage whose shop or chests can roll it.
## (The shop after stage N rolls with stage = N; chests in stage N too.)
const RARITY := {
	"common": {weight = 60.0, min_stage = 1},
	"uncommon": {weight = 30.0, min_stage = 1},
	"rare": {weight = 14.0, min_stage = 2},
	"legendary": {weight = 6.0, min_stage = 4},
}

## Exact rarity mix of ITEMS (PD's binding decision).
const MIX := {"common": 6, "uncommon": 7, "rare": 5, "legendary": 2}

## Offers per shop visit.
const STOCK_SIZE := 4

## PROVISIONAL (pending Lead's per-stage gold from the #13 sweep): shop price
## multiplier for the shop after stage N (index N-1). Offer price =
## round(row price * PRICE_SCALE[N-1]); see docs/BACKEND.md "Gold economy" for the math.
## Retune here (one array) once real numbers land; row prices are relative values.
const PRICE_SCALE: Array[float] = [1.1, 1.6, 2.2, 2.9]

## Price of `id` in the shop after `stage` (clamps past the table's ends).
static func shop_price(id: String, stage: int) -> int:
	var r := row(id)
	if r.is_empty():
		return 0
	var i := clampi(stage - 1, 0, PRICE_SCALE.size() - 1)
	return maxi(int(round(float(r.price) * PRICE_SCALE[i])), 1)


## Row: {id, name, desc, icon, price, rarity, mods}, plus for behaviour items
##   script  — res:// path of an Item subclass (scripts/items/behaviors/) with the hooks
##   params  — that script's tunables (ALL behaviour numbers live here, not in scripts)
##   charges — uses per stage (refilled by PlayerStats.begin_stage); FE shows charges/max
##   downside_behavior — true when the cost is part of the behaviour, not a stat mod
##   max_copies — copies worth owning (shops/chests stop offering past it); omitted = derived
##                by max_copies(): the copy at which every upside hits its STAT_BOUNDS cap
## Icon slots are `item_icon_<id>` (Designer; behaviour icons in PR #30). FE falls back
## to its letter tile when a slot isn't in the manifest.
## Noise budget: at most 3 items may use "noise carries farther" as their cost
## (sneakers, grandfather_watch, greedy_sack); tests/test_item_behaviors.gd enforces it.
## Pool mix (PD decision): exactly 6 common / 7 uncommon / 5 rare / 2 legendary = 20
## (ItemDb.MIX; tests/test_items.gd asserts it).
const ITEMS: Array[Dictionary] = [
	# --- common ------------------------------------------------------------
	{id = "bright_bulb", name = "Bright Bulb", icon = "item_icon_bright_bulb", price = 7, rarity = "common",
		desc = "Light reaches {mul:light_range} farther, but puppets notice it {inv:light_detect_mult} sooner.",
		mods = [{stat = &"light_range", mul = 1.3}, {stat = &"light_detect_mult", mul = 1.25}]},
	{id = "soft_shoes", name = "Soft Shoes", icon = "item_icon_soft_shoes", price = 7, rarity = "common",
		desc = "Your noise carries {mul:noise_mult} less far. You move {mul:move_speed} slower.",
		mods = [{stat = &"noise_mult", mul = 0.75}, {stat = &"move_speed", mul = 0.92}]},
	{id = "quick_hands", name = "Quick Hands", icon = "item_icon_quick_hands", price = 6, rarity = "common",
		desc = "Pick things up {mul:pickup_time} faster, but you must stand {mul:pickup_range} closer.",
		mods = [{stat = &"pickup_time", mul = 0.7}, {stat = &"pickup_range", mul = 0.85}]},
	{id = "sneakers", name = "Sneakers", icon = "item_icon_sneakers", price = 6, rarity = "common",
		desc = "Move {mul:move_speed} faster. Squeaky: your noise carries {mul:noise_mult} farther.",
		mods = [{stat = &"move_speed", mul = 1.15}, {stat = &"noise_mult", mul = 1.15}]},
	{id = "banister_gloves", name = "Banister Gloves", icon = "item_icon_banister_gloves", price = 5, rarity = "common",
		desc = "Climb stairs {mul:climb_speed} faster, but your reach is {mul:pickup_range} shorter.",
		mods = [{stat = &"climb_speed", mul = 1.35}, {stat = &"pickup_range", mul = 0.9}]},
	{id = "heavy_vases", name = "Heavy Vases", icon = "item_icon_heavy_vases", price = 6, rarity = "common",
		desc = "Vases you throw or knock over stun puppets {mul:stun} longer. Carrying a vase slows you {mul:carry}.",
		script = "res://scripts/items/behaviors/heavy_vases.gd", downside_behavior = true,
		params = {stun_mult = 2.0, carry_speed_mult = 0.85}, mods = []},
	# --- uncommon ----------------------------------------------------------
	{id = "extra_heart", name = "Extra Heart", icon = "item_icon_extra_heart", price = 10, rarity = "uncommon",
		desc = "+{int:max_health} max heart (and heals it). Heavier: you climb {mul:climb_speed} slower.",
		mods = [{stat = &"max_health", add = 1.0}, {stat = &"climb_speed", mul = 0.85}]},
	{id = "minimap", name = "Minimap", icon = "item_icon_minimap", price = 12, rarity = "uncommon",
		desc = "Shows the floor layout. Fumbling with it: pickups take {sec:pickup_time} s longer.", max_copies = 1,
		mods = [{stat = &"minimap", add = 1.0}, {stat = &"pickup_time", add = 0.15}]},
	{id = "big_pockets", name = "Big Pockets", icon = "item_icon_big_pockets", price = 10, rarity = "uncommon",
		desc = "Hold {int:inventory_slots} more thing in your hands. You move {mul:move_speed} slower.",
		mods = [{stat = &"inventory_slots", add = 1.0}, {stat = &"move_speed", mul = 0.93}]},
	{id = "thick_sweater", name = "Thick Sweater", icon = "item_icon_thick_sweater", price = 9, rarity = "uncommon",
		desc = "+{sec:invuln_time} s of safety after a hit. You move {mul:move_speed} slower.",
		mods = [{stat = &"invuln_time", add = 0.5}, {stat = &"move_speed", mul = 0.95}]},
	{id = "music_box", name = "Music Box", icon = "item_icon_music_box", price = 9, rarity = "uncommon",
		desc = "+{uses} music box lure in your pocket each floor (never in your hands). Tap with nothing ringed to throw it the way you face: it plays loudly where it lands and draws puppets there.",
		script = "res://scripts/items/behaviors/music_box.gd", downside_behavior = true, charges = 1, max_copies = 3,
		params = {world_slot = "music_box_world", lure_time = 4.0, lure_interval = 0.5,
			lure_radius = 900.0, lure_loudness = 1.2}, mods = []},
	{id = "cracked_mirror", name = "Cracked Mirror", icon = "item_icon_cracked_mirror", price = 9, rarity = "uncommon",
		desc = "Puppets searching for you off screen give up {mul:give_up} faster. You only see a chaser's arrow when it is about a screen away.",
		script = "res://scripts/items/behaviors/cracked_mirror.gd", downside_behavior = true,
		params = {offscreen_drain_mult = 1.4, arrow_reveal_distance = 1280.0}, mods = []},
	{id = "gold_magnet", name = "Gold Magnet", icon = "item_icon_gold_magnet", price = 11, rarity = "uncommon",
		desc = "+{add:gold_find_mult} gold found. Heavy: you climb {mul:climb_speed} slower.",
		mods = [{stat = &"gold_find_mult", add = 0.6}, {stat = &"climb_speed", mul = 0.8}]},
	# --- rare (stage 2+) ---------------------------------------------------
	{id = "ghost_slippers", name = "Ghost Slippers", icon = "item_icon_ghost_slippers", price = 16, rarity = "rare",
		desc = "Your noise carries {mul:noise_mult} less far. -{int:max_health} max heart.",
		mods = [{stat = &"noise_mult", mul = 0.55}, {stat = &"max_health", add = -1.0}]},
	{id = "rabbits_foot", name = "Rabbit's Foot", icon = "item_icon_rabbits_foot", price = 14, rarity = "rare",
		desc = "+{uses} save per floor: a hit that would catch you leaves you on {p:save_health} heart instead. -{int:max_health} max heart.",
		script = "res://scripts/items/behaviors/rabbits_foot.gd", charges = 1, max_copies = 2, params = {save_health = 1},
		mods = [{stat = &"max_health", add = -1.0}]},
	{id = "flash_bulb", name = "Flash Bulb", icon = "item_icon_flash_bulb", price = 14, rarity = "rare",
		desc = "+{uses} flash per floor: a puppet you startle with light is stunned for {p:stun_time} s instead of chasing. Light reaches {mul:light_range} less far.",
		script = "res://scripts/items/behaviors/flash_bulb.gd", charges = 1, max_copies = 2, params = {stun_time = 2.5},
		mods = [{stat = &"light_range", mul = 0.9}]},
	{id = "night_eyes", name = "Night Eyes", icon = "item_icon_night_eyes", price = 15, rarity = "rare",
		desc = "Puppets take {inv:light_detect_mult} longer to notice your light. Beam {int:light_angle_deg} degrees narrower.",
		mods = [{stat = &"light_detect_mult", mul = 0.6}, {stat = &"light_angle_deg", add = -10.0}]},
	{id = "grandfather_watch", name = "Grandfather's Watch", icon = "item_icon_grandfather_watch", price = 15, rarity = "rare",
		desc = "Puppets need +{sec:light_startle_time} s of light to startle. Ticks loudly: noise carries {mul:noise_mult} farther.",
		mods = [{stat = &"light_startle_time", add = 0.5}, {stat = &"noise_mult", mul = 1.1}]},
	# --- legendary (stage 4+) ----------------------------------------------
	{id = "shadow_cloak", name = "Shadow Cloak", icon = "item_icon_shadow_cloak", price = 26, rarity = "legendary",
		desc = "Noise carries {mul:noise_mult} less far and puppets take {inv:light_detect_mult} longer to notice your light. Light reaches {mul:light_range} less far.",
		mods = [{stat = &"noise_mult", mul = 0.6}, {stat = &"light_detect_mult", mul = 0.6}, {stat = &"light_range", mul = 0.75}]},
	{id = "greedy_sack", name = "Greedy Sack", icon = "item_icon_greedy_sack", price = 22, rarity = "legendary",
		desc = "Empty vases hold {p:gold_min} to {p:gold_max} gold. Breaking a vase is {mul:vase_noise} louder.",
		script = "res://scripts/items/behaviors/greedy_sack.gd", downside_behavior = true,
		params = {gold_min = 1, gold_max = 3, noise_mult = 1.5}, mods = []},
]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r in ITEMS:
		out.append(str(r.id))
	return out


static func row(id: String) -> Dictionary:
	for r in ITEMS:
		if str(r.id) == id:
			return r
	return {}


## A fresh Item instance for `id` (null if unknown). Its description is what THIS copy
## would add given what `stats` (default: the PlayerStats autoload) already owns.
static func make(id: String, stats: Node = null) -> Item:
	var it := _build(id)
	if it != null:
		it.max_copies = max_copies(id)
		it.description = describe(row(id), stats)
	return it


## make() without the description (describe() builds its what-if copy with this).
static func _build(id: String) -> Item:
	var r := row(id)
	if r.is_empty():
		return null
	var it: Item
	if r.has("script"):
		var scr: Script = load(str(r.script))
		it = scr.new() if scr else Item.new()
	else:
		it = Item.new()
	it.params = (r.get("params", {}) as Dictionary).duplicate(true)
	it.max_charges = int(r.get("charges", 0))
	it.charges = it.max_charges
	it.id = str(r.id)
	it.display_name = str(r.name)
	it.icon_slot = str(r.icon)
	it.price = int(r.price)
	it.rarity = str(r.rarity)
	var ms: Array = []
	for m in r.mods:
		ms.append({stat = StringName(m.stat), add = float(m.get("add", 0.0)), mul = float(m.get("mul", 1.0))})
	it.mods = ms
	return it


## Item text (PRODUCT.md "Item text"): EVERY number is a token, filled from the EFFECTIVE,
## CAPPED value via PlayerStats.effect(): what ONE MORE copy changes, given what `stats`
## owns (default: the PlayerStats autoload; none = a fresh run). Tokens (effect key K = a
## BASE stat or vase_noise / stun / carry / give_up, see PlayerStats.effect):
##   {mul:K}  |after/before - 1| as "N%"    (light_range x1.3 -> "30%"; capped -> less)
##   {inv:K}  |before/after - 1| as "N%"    (time of a rate: light_detect x0.6 -> "67%")
##   {add:K}  |after - before| as "N%"      (gold_find_mult +0.6 -> "60%")
##   {sec:K}  |after - before| seconds      ("0.5")
##   {int:K}  |after - before| whole number (hearts, slots, degrees)
##   {uses}   charges per floor this copy adds
##   {p:key}  the row's params value as is (Flash Bulb stun 2.5 s; does not stack)
## A copy that adds nothing on its upside (GOOD direction) starts with NOTHING_TEXT.
const NOTHING_TEXT := "Another copy adds nothing (at the cap). "
const TOKEN_RE := "\\{(mul|inv|add|sec|int|uses|p)(?::(\\w+))?\\}"
## Which way is better for the player, per effect key (upside detection, max_copies).
const GOOD := {
	"max_health": 1, "move_speed": 1, "climb_speed": 1, "pickup_time": -1, "pickup_range": 1,
	"light_range": 1, "light_angle_deg": 1, "light_startle_time": 1, "light_detect_mult": -1,
	"noise_mult": -1, "invuln_time": 1, "inventory_slots": 1, "gold_find_mult": 1, "minimap": 1,
	"tap_threshold": 0, "throw_speed": 1, "jump_velocity": 0, "gravity": 0,
	"vase_noise": -1, "stun": 1, "carry": 1, "give_up": 1, "uses": 1,
}
## How far max_copies derivation looks (a copy past this is never "useful").
const MAX_COPIES_SCAN := 12


static func describe(r: Dictionary, stats: Node = null) -> String:
	var ps := _ps(stats)
	var toks := _tokens(r, ps)
	var out := str(r.get("desc", ""))
	var dropped := false
	for t in toks:
		if t.get("zero", false):
			out = out.replace(t.raw, ZERO_MARK)
			dropped = true
		else:
			out = out.replace(t.raw, t.text)
	if dropped:
		out = _drop_zero_clauses(out)
	if not _adds_from(r, toks, ps):
		out = NOTHING_TEXT + (out if out != "" else "Nothing else changes.")
	return out


## PRODUCT.md: at a cap the text never shows "0%" / "-0" / "+0 s": a clause whose number is zero
## is dropped (the "adds nothing" line already says when the upside is capped).
const ZERO_MARK := "\u0001"

## Removes every clause of `text` holding ZERO_MARK. Sentences split on ". "; clauses within a
## sentence split on ", but " / ", " / " and " (never inside a "(...)" aside).
static func _drop_zero_clauses(text: String) -> String:
	var sentences: PackedStringArray = text.trim_suffix(".").split(". ")
	var kept: Array = []
	var delim := RegEx.create_from_string(", but |, | and ")
	for sent in sentences:
		if not sent.contains(ZERO_MARK):
			kept.append(sent)
			continue
		var segs: Array = []
		var seps: Array = []
		var at := 0
		for m in delim.search_all(sent):
			segs.append(sent.substr(at, m.get_start() - at))
			seps.append(m.get_string())
			at = m.get_end()
		segs.append(sent.substr(at))
		var out := ""
		var first := true
		for i in segs.size():
			if str(segs[i]).contains(ZERO_MARK):
				continue
			if first:
				out = str(segs[i])
				first = false
			else:
				# Joiner before this clause; a dropped lead clause leaves its successor to open the sentence.
				out += str(seps[i - 1]) + str(segs[i])
		if out == "":
			continue
		if out.begins_with("but ") or out.begins_with("and "):
			out = out.substr(4)
		# After dropping a leading clause, the joiner we kept started the string.
		out = out.lstrip(", ")
		kept.append(out.substr(0, 1).to_upper() + out.substr(1))
	if kept.is_empty():
		return ""
	return ". ".join(kept) + "."


## Each token of `r`'s desc, measured against `ps` + one more copy:
## [{raw, kind, key, before, after, value, text, upside}] in desc order.
static func _tokens(r: Dictionary, ps: Node) -> Array:
	var out: Array = []
	var extra: Array = [_build(str(r.id))]
	var re := RegEx.create_from_string(TOKEN_RE)
	for m in re.search_all(str(r.get("desc", ""))):
		var kind := m.get_string(1)
		var key := m.get_string(2)
		var t := {raw = m.get_string(), kind = kind, key = key, upside = false}
		if kind == "p":
			var prm: Dictionary = r.get("params", {})
			assert(prm.has(key), "%s: no param %s" % [r.id, key])
			t.value = float(prm.get(key, 0.0))
			t.text = fmt_num(t.value)
			out.append(t)
			continue
		var ek := ("uses:" + str(r.id)) if kind == "uses" else key
		var v0: float = ps.effect(ek, [])
		var v1: float = ps.effect(ek, extra)
		var v := 0.0
		match kind:
			"mul": v = absf(v1 / v0 - 1.0) if v0 != 0.0 else 0.0
			"inv": v = absf(v0 / v1 - 1.0) if v1 != 0.0 else 0.0
			"add", "sec", "int", "uses": v = absf(v1 - v0)
		var shown := ""
		match kind:
			"mul", "inv", "add":
				shown = "%d%%" % int(round(v * 100.0))
			"sec":
				shown = fmt_num(v)
			_:
				shown = str(int(round(v)))
		t.before = v0
		t.after = v1
		t.value = v
		t.text = shown
		var good := int(GOOD.get("uses" if kind == "uses" else key, 0))
		var nonzero := shown != "0%" and shown != "0"
		t.zero = not nonzero
		t.upside = nonzero and good != 0 and signf(v1 - v0) == signf(good)
		out.append(t)
	return out


## Seconds / params: up to 2 decimals, no trailing zeros ("2.5", "0.15", "1").
static func fmt_num(v: float) -> String:
	var s := "%.2f" % v
	while s.contains(".") and (s.ends_with("0") or s.ends_with(".")):
		s = s.substr(0, s.length() - 1)
	return s


## True if one more copy of `r` would add something for the player, given `ps`. A row whose
## upside isn't a number (Minimap, Greedy Sack's gold) adds only as the first copy.
static func _adds_from(r: Dictionary, toks: Array, ps: Node) -> bool:
	for t in toks:
		if t.upside:
			return true
	return ps.copies(str(r.id)) == 0 and not _numeric_upside(str(r.id))


static var _numeric_cache := {}
static var _max_cache := {}

## Does the row's FIRST copy (fresh run) show a numeric upside?
static func _numeric_upside(id: String) -> bool:
	if not _numeric_cache.has(id):
		var scratch: Node = load("res://scripts/autoload/player_stats.gd").new()
		var up := false
		for t in _tokens(row(id), scratch):
			up = up or t.upside
		scratch.free()
		_numeric_cache[id] = up
	return _numeric_cache[id]


## Copies of `id` worth owning: the row's `max_copies` if set (Music Box 3), else derived
## on a fresh run: the last copy that still adds something on its upside (caps reached).
static func max_copies(id: String) -> int:
	var r := row(id)
	if r.is_empty():
		return 0
	if r.has("max_copies"):
		return int(r.max_copies)
	if not _max_cache.has(id):
		var scratch: Node = load("res://scripts/autoload/player_stats.gd").new()
		var n := 0
		while n < MAX_COPIES_SCAN and _adds_from(r, _tokens(r, scratch), scratch):
			n += 1
			scratch.grant_item(_build(id))
		scratch.free()
		_max_cache[id] = n
	return _max_cache[id]


## True if a shop / chest may offer `id` now: under max_copies and another copy adds
## something given what `stats` owns (PRODUCT.md: never offer a copy that adds nothing).
static func would_add(id: String, stats: Node = null) -> bool:
	var r := row(id)
	if r.is_empty():
		return false
	var ps := _ps(stats)
	if ps.copies(id) >= max_copies(id):
		return false
	return _adds_from(r, _tokens(r, ps), ps)


## `stats`, else the PlayerStats autoload, else a shared empty scratch PlayerStats.
static var _scratch: Node = null
static func _ps(stats: Node) -> Node:
	var ps := Item._stats(stats)
	if ps != null:
		return ps
	if _scratch == null or not is_instance_valid(_scratch):
		_scratch = load("res://scripts/autoload/player_stats.gd").new()
	return _scratch


## Ids a shop or chest on `stage` may roll.
static func pool_for_stage(stage: int) -> PackedStringArray:
	var out := PackedStringArray()
	for r in ITEMS:
		if stage >= int(RARITY[r.rarity].min_stage):
			out.append(str(r.id))
	return out


## Up to `count` distinct items for `stage`, weighted by rarity, from `rng`. Only items
## would_add() allows (given `stats`, default the autoload). If the stage pool runs short,
## tops up from the rest of the catalogue (any rarity); an empty result means "give gold"
## (Shop.roll_stock -> gold pouch, Chest -> gold).
static func roll(rng: RandomNumberGenerator, stage: int, count: int, exclude: PackedStringArray = PackedStringArray(), stats: Node = null) -> Array[Item]:
	var out: Array[Item] = []
	var staged := pool_for_stage(stage)
	var first: Array[String] = []
	var rest: Array[String] = []
	for id in ids():
		if exclude.has(id) or not would_add(id, stats):
			continue
		if staged.has(id):
			first.append(id)
		else:
			rest.append(id)
	for pool in [first, rest]:
		while out.size() < count and not pool.is_empty():
			var total := 0.0
			for id in pool:
				total += float(RARITY[row(id).rarity].weight)
			var pick := rng.randf() * total
			var idx: int = pool.size() - 1
			for i in pool.size():
				pick -= float(RARITY[row(pool[i]).rarity].weight)
				if pick < 0.0:
					idx = i
					break
			out.append(make(pool[idx], stats))
			pool.remove_at(idx)
	return out


## PROVISIONAL (PD): gold given instead of an item when nothing can be offered.
static func fallback_gold(stage: int) -> int:
	return 4 + 2 * maxi(stage, 1)


## Deterministic RNG for (stage, seed, purpose). Same inputs → same rolls.
static func rng_for(stage: int, seed: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([purpose, stage, seed])
	return rng


## One chest drop for `stage`, deterministic in `seed`.
## null = nothing can be offered: the chest gives fallback_gold(stage) instead.
static func roll_chest(stage: int, seed: int, stats: Node = null) -> Item:
	var got := roll(rng_for(stage, seed, "chest"), stage, 1, PackedStringArray(), stats)
	return got[0] if not got.is_empty() else null

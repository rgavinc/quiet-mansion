class_name ItemDb
extends RefCounted
## The ONE place item numbers live. Adding an item = adding one row to ITEMS.
## Row: {id, name, desc, icon, price, rarity, mods: [{stat, add, mul}]}.
##   add  — added to the base value (default 0)
##   mul  — multiplies the result (default 1)
## Every item is a trade-off (Brotato-style): something better, something worse.
## Stats are PlayerStats.BASE keys; the floors in PlayerStats.MIN keep combos sane.

## Rarity → shop/chest weight and the first stage whose shop or chests can roll it.
## (The shop after stage N rolls with stage = N; chests in stage N too.)
const RARITY := {
	"common": {weight = 60.0, min_stage = 1},
	"uncommon": {weight = 30.0, min_stage = 1},
	"rare": {weight = 14.0, min_stage = 2},
	"legendary": {weight = 6.0, min_stage = 4},
}

## Offers per shop visit.
const STOCK_SIZE := 4

## PROVISIONAL (pending Lead's per-stage gold from the #13 sweep): shop price
## multiplier for the shop after stage N (index N-1). Offer price =
## round(row price * PRICE_SCALE[N-1]); see docs/BACKEND.md "Gold economy" for the math.
## Retune here (one array) once real numbers land; row prices are relative values.
const PRICE_SCALE: Array[float] = [1.2, 1.8, 2.5, 3.3]

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
## Icon slots are `item_icon_<id>` (Designer; behaviour icons in PR #30). FE falls back
## to its letter tile when a slot isn't in the manifest.
## Noise budget: at most 3 items may use "noise carries farther" as their cost
## (lucky_coin, sneakers, greedy_sack); tests/test_item_behaviors.gd enforces it.
const ITEMS: Array[Dictionary] = [
	# --- common ------------------------------------------------------------
	{id = "bright_bulb", name = "Bright Bulb", icon = "item_icon_bright_bulb", price = 7, rarity = "common",
		desc = "Light reaches 30% farther, but puppets notice it 25% faster.",
		mods = [{stat = &"light_range", mul = 1.3}, {stat = &"light_detect_mult", mul = 1.25}]},
	{id = "soft_shoes", name = "Soft Shoes", icon = "item_icon_soft_shoes", price = 7, rarity = "common",
		desc = "Your noise carries 25% less far. You move 8% slower.",
		mods = [{stat = &"noise_mult", mul = 0.75}, {stat = &"move_speed", mul = 0.92}]},
	{id = "lucky_coin", name = "Lucky Coin", icon = "item_icon_lucky_coin", price = 6, rarity = "common",
		desc = "+40% gold found. It jingles: your noise carries 10% farther.",
		mods = [{stat = &"gold_find_mult", add = 0.4}, {stat = &"noise_mult", mul = 1.1}]},
	{id = "quick_hands", name = "Quick Hands", icon = "item_icon_quick_hands", price = 6, rarity = "common",
		desc = "Pick things up 30% faster, but you must stand 15% closer.",
		mods = [{stat = &"pickup_time", mul = 0.7}, {stat = &"pickup_range", mul = 0.85}]},
	{id = "dim_filter", name = "Dim Filter", icon = "item_icon_dim_filter", price = 6, rarity = "common",
		desc = "A softer beam: puppets take 40% longer to notice it. Light reaches 20% less far.",
		mods = [{stat = &"light_detect_mult", mul = 0.7}, {stat = &"light_range", mul = 0.8}]},
	{id = "wide_lens", name = "Wide Lens", icon = "item_icon_wide_lens", price = 5, rarity = "common",
		desc = "Beam is 12 degrees wider but 15% shorter.",
		mods = [{stat = &"light_angle_deg", add = 12.0}, {stat = &"light_range", mul = 0.85}]},
	{id = "sneakers", name = "Sneakers", icon = "item_icon_sneakers", price = 6, rarity = "common",
		desc = "Move 15% faster. Squeaky: your noise carries 15% farther.",
		mods = [{stat = &"move_speed", mul = 1.15}, {stat = &"noise_mult", mul = 1.15}]},
	{id = "banister_gloves", name = "Banister Gloves", icon = "item_icon_banister_gloves", price = 5, rarity = "common",
		desc = "Climb stairs 35% faster, but your reach is 10% shorter.",
		mods = [{stat = &"climb_speed", mul = 1.35}, {stat = &"pickup_range", mul = 0.9}]},
	{id = "heavy_vases", name = "Heavy Vases", icon = "item_icon_heavy_vases", price = 6, rarity = "common",
		desc = "Vases you throw or knock over stun puppets twice as long. Carrying a vase slows you 15%.",
		script = "res://scripts/items/behaviors/heavy_vases.gd", downside_behavior = true,
		params = {stun_mult = 2.0, carry_speed_mult = 0.85}, mods = []},
	# --- uncommon ----------------------------------------------------------
	{id = "extra_heart", name = "Extra Heart", icon = "item_icon_extra_heart", price = 10, rarity = "uncommon",
		desc = "+1 max heart (and heals it). Heavier: you climb 15% slower.",
		mods = [{stat = &"max_health", add = 1.0}, {stat = &"climb_speed", mul = 0.85}]},
	{id = "minimap", name = "Minimap", icon = "item_icon_minimap", price = 12, rarity = "uncommon",
		desc = "Shows the floor layout. Fumbling with it: pickups take 0.15 s longer.",
		mods = [{stat = &"minimap", add = 1.0}, {stat = &"pickup_time", add = 0.15}]},
	{id = "big_pockets", name = "Big Pockets", icon = "item_icon_big_pockets", price = 10, rarity = "uncommon",
		desc = "Hold one more thing. You move 7% slower.",
		mods = [{stat = &"inventory_slots", add = 1.0}, {stat = &"move_speed", mul = 0.93}]},
	{id = "thick_sweater", name = "Thick Sweater", icon = "item_icon_thick_sweater", price = 9, rarity = "uncommon",
		desc = "+0.5 s of safety after a hit. You move 5% slower.",
		mods = [{stat = &"invuln_time", add = 0.5}, {stat = &"move_speed", mul = 0.95}]},
	{id = "music_box", name = "Music Box", icon = "item_icon_music_box", price = 9, rarity = "uncommon",
		desc = "Each floor starts with a music box in hand. Throw it: it plays loudly where it lands and draws puppets there. It takes a hand slot until thrown.",
		script = "res://scripts/items/behaviors/music_box.gd", downside_behavior = true, charges = 1,
		params = {world_slot = "music_box_world", lure_time = 4.0, lure_interval = 0.5,
			lure_radius = 900.0, lure_loudness = 1.2}, mods = []},
	{id = "cracked_mirror", name = "Cracked Mirror", icon = "item_icon_cracked_mirror", price = 9, rarity = "uncommon",
		desc = "Puppets searching for you off screen give up 40% sooner. You only see a chaser's arrow once it is about a screen away.",
		script = "res://scripts/items/behaviors/cracked_mirror.gd", downside_behavior = true,
		params = {offscreen_drain_mult = 1.4, arrow_reveal_distance = 1280.0}, mods = []},
	# --- rare (stage 2+) ---------------------------------------------------
	{id = "ghost_slippers", name = "Ghost Slippers", icon = "item_icon_ghost_slippers", price = 16, rarity = "rare",
		desc = "Your noise carries 45% less far. -1 max heart.",
		mods = [{stat = &"noise_mult", mul = 0.55}, {stat = &"max_health", add = -1.0}]},
	{id = "rabbits_foot", name = "Rabbit's Foot", icon = "item_icon_rabbits_foot", price = 14, rarity = "rare",
		desc = "Once per floor, a hit that would catch you leaves you on 1 heart instead. -1 max heart.",
		script = "res://scripts/items/behaviors/rabbits_foot.gd", charges = 1, params = {},
		mods = [{stat = &"max_health", add = -1.0}]},
	{id = "flash_bulb", name = "Flash Bulb", icon = "item_icon_flash_bulb", price = 14, rarity = "rare",
		desc = "Once per floor, a puppet you startle with light is stunned for 2.5 s instead of chasing. Light reaches 10% less far.",
		script = "res://scripts/items/behaviors/flash_bulb.gd", charges = 1, params = {stun_time = 2.5},
		mods = [{stat = &"light_range", mul = 0.9}]},
	# --- legendary (stage 4+) ----------------------------------------------
	{id = "golden_heart", name = "Golden Heart", icon = "item_icon_golden_heart", price = 24, rarity = "legendary",
		desc = "+2 max hearts (and heals them). -30% gold found.",
		mods = [{stat = &"max_health", add = 2.0}, {stat = &"gold_find_mult", add = -0.3}]},
	{id = "greedy_sack", name = "Greedy Sack", icon = "item_icon_greedy_sack", price = 22, rarity = "legendary",
		desc = "Every vase holds gold. Breaking a vase is 50% louder.",
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


## A fresh Item instance for `id` (null if unknown).
static func make(id: String) -> Item:
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
	it.description = str(r.desc)
	it.icon_slot = str(r.icon)
	it.price = int(r.price)
	it.rarity = str(r.rarity)
	var ms: Array = []
	for m in r.mods:
		ms.append({stat = StringName(m.stat), add = float(m.get("add", 0.0)), mul = float(m.get("mul", 1.0))})
	it.mods = ms
	return it


## Ids a shop or chest on `stage` may roll.
static func pool_for_stage(stage: int) -> PackedStringArray:
	var out := PackedStringArray()
	for r in ITEMS:
		if stage >= int(RARITY[r.rarity].min_stage):
			out.append(str(r.id))
	return out


## Up to `count` distinct items for `stage`, weighted by rarity, from `rng`.
static func roll(rng: RandomNumberGenerator, stage: int, count: int, exclude: PackedStringArray = PackedStringArray()) -> Array[Item]:
	var out: Array[Item] = []
	var pool: Array[String] = []
	for id in pool_for_stage(stage):
		if not exclude.has(id):
			pool.append(id)
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += float(RARITY[row(id).rarity].weight)
		var pick := rng.randf() * total
		var idx := pool.size() - 1
		for i in pool.size():
			pick -= float(RARITY[row(pool[i]).rarity].weight)
			if pick < 0.0:
				idx = i
				break
		out.append(make(pool[idx]))
		pool.remove_at(idx)
	return out


## Deterministic RNG for (stage, seed, purpose). Same inputs → same rolls.
static func rng_for(stage: int, seed: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([purpose, stage, seed])
	return rng


## One chest drop for `stage`, deterministic in `seed`.
static func roll_chest(stage: int, seed: int) -> Item:
	var got := roll(rng_for(stage, seed, "chest"), stage, 1)
	return got[0] if not got.is_empty() else null

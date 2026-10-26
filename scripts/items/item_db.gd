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

## Icon slots that exist in assets/ASSETS_MANIFEST.toml today; other items show FE's
## letter tile until Designer adds `item_icon_<id>`.
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
	{id = "spring_socks", name = "Spring Socks", icon = "item_icon_spring_socks", price = 5, rarity = "common",
		desc = "Jump higher. Landings are louder: noise carries 10% farther.",
		mods = [{stat = &"jump_velocity", add = 40.0}, {stat = &"noise_mult", mul = 1.1}]},
	{id = "banister_gloves", name = "Banister Gloves", icon = "item_icon_banister_gloves", price = 5, rarity = "common",
		desc = "Climb stairs 35% faster, but your reach is 10% shorter.",
		mods = [{stat = &"climb_speed", mul = 1.35}, {stat = &"pickup_range", mul = 0.9}]},
	# --- uncommon ----------------------------------------------------------
	{id = "extra_heart", name = "Extra Heart", icon = "item_icon_extra_heart", price = 10, rarity = "uncommon",
		desc = "+1 max heart (and heals it). Heavier steps: noise carries 15% farther.",
		mods = [{stat = &"max_health", add = 1.0}, {stat = &"noise_mult", mul = 1.15}]},
	{id = "minimap", name = "Minimap", icon = "item_icon_minimap", price = 12, rarity = "uncommon",
		desc = "Shows the floor layout. Fumbling with it: pickups take 0.15 s longer.",
		mods = [{stat = &"minimap", add = 1.0}, {stat = &"pickup_time", add = 0.15}]},
	{id = "big_pockets", name = "Big Pockets", icon = "item_icon_big_pockets", price = 10, rarity = "uncommon",
		desc = "Hold one more thing. You move 7% slower.",
		mods = [{stat = &"inventory_slots", add = 1.0}, {stat = &"move_speed", mul = 0.93}]},
	{id = "strong_arm", name = "Strong Arm", icon = "item_icon_strong_arm", price = 8, rarity = "uncommon",
		desc = "Throws fly 30% faster. Pickups take 0.15 s longer.",
		mods = [{stat = &"throw_speed", mul = 1.3}, {stat = &"pickup_time", add = 0.15}]},
	{id = "thick_sweater", name = "Thick Sweater", icon = "item_icon_thick_sweater", price = 9, rarity = "uncommon",
		desc = "+0.5 s of safety after a hit. You move 5% slower.",
		mods = [{stat = &"invuln_time", add = 0.5}, {stat = &"move_speed", mul = 0.95}]},
	{id = "gold_magnet", name = "Gold Magnet", icon = "item_icon_gold_magnet", price = 11, rarity = "uncommon",
		desc = "+60% gold found. Heavy: you climb 20% slower.",
		mods = [{stat = &"gold_find_mult", add = 0.6}, {stat = &"climb_speed", mul = 0.8}]},
	# --- rare (stage 2+) ---------------------------------------------------
	{id = "night_eyes", name = "Night Eyes", icon = "item_icon_night_eyes", price = 15, rarity = "rare",
		desc = "Puppets take much longer to notice your light (x0.6). Beam 10 degrees narrower.",
		mods = [{stat = &"light_detect_mult", mul = 0.6}, {stat = &"light_angle_deg", add = -10.0}]},
	{id = "ghost_slippers", name = "Ghost Slippers", icon = "item_icon_ghost_slippers", price = 16, rarity = "rare",
		desc = "Your noise carries 45% less far. -1 max heart.",
		mods = [{stat = &"noise_mult", mul = 0.55}, {stat = &"max_health", add = -1.0}]},
	{id = "grandfather_watch", name = "Grandfather's Watch", icon = "item_icon_grandfather_watch", price = 15, rarity = "rare",
		desc = "Puppets need +0.5 s of light to startle. Ticks loudly: noise carries 10% farther.",
		mods = [{stat = &"light_startle_time", add = 0.5}, {stat = &"noise_mult", mul = 1.1}]},
	# --- legendary (stage 4+) ----------------------------------------------
	{id = "golden_heart", name = "Golden Heart", icon = "item_icon_golden_heart", price = 24, rarity = "legendary",
		desc = "+2 max hearts (and heals them). -30% gold found.",
		mods = [{stat = &"max_health", add = 2.0}, {stat = &"gold_find_mult", add = -0.3}]},
	{id = "shadow_cloak", name = "Shadow Cloak", icon = "item_icon_shadow_cloak", price = 26, rarity = "legendary",
		desc = "Noise carries 40% less far and light is noticed 40% slower. Light reaches 25% less far.",
		mods = [{stat = &"noise_mult", mul = 0.6}, {stat = &"light_detect_mult", mul = 0.6}, {stat = &"light_range", mul = 0.75}]},
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
	var it := Item.new()
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

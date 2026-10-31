extends Node
## PlayerStats — the ONE place player numbers live.
## Base values are in BASE. Items add modifiers; nothing else writes stats.
## Read with PlayerStats.get_stat(&"pickup_time"). FE/QA read, never write.

signal health_changed(current: int, max_hp: int)
signal gold_changed(current: int, delta: int)
signal stat_changed(stat: StringName, value: float)
signal died
## Owned (bought / chest) items changed. `items` is PlayerStats.owned_items.
signal items_changed(items: Array)
## Music Box lure pocket changed (a throw, a refill, a box bought). FE: pips from these.
signal lures_changed(charges: int, max: int)

## Base values. Tune here; every class reads through get_stat().
const BASE := {
	&"max_health": 3.0,          # 3 hits = game over
	&"move_speed": 140.0,        # px/s
	&"jump_velocity": 320.0,     # px/s upward (~52px jump with gravity 980)
	&"gravity": 980.0,           # px/s^2
	&"climb_speed": 90.0,        # px/s along stairs
	&"pickup_time": 1.0,         # s holding LMB to pick up
	&"pickup_range": 40.0,       # px; leaving range cancels pickup
	&"tap_threshold": 0.2,       # s; LMB shorter than this = throw
	&"throw_speed": 520.0,       # px/s
	&"light_range": 260.0,       # px, flashlight cone length
	&"light_angle_deg": 40.0,    # cone width
	&"light_startle_time": 1.0,  # s of light on an enemy before it startles
	&"light_detect_mult": 1.0,   # <1 = light is less noticeable (items)
	&"noise_mult": 1.0,          # scales noise the player causes
	&"invuln_time": 1.0,         # s after a hit
	&"inventory_slots": 3.0,
	&"gold_find_mult": 1.0,
	&"minimap": 0.0,             # >= 1 = the minimap item is owned (FE minimap reads has_minimap())
}

## Physics layers (bits). Player and enemies never block each other, so a catch is a
## distance check on overlapping bodies instead of two colliders stalling 26px apart.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

## Stat bounds (PRODUCT.md "Stat caps"): EVERY stat's effective value, all items stacked,
## stays within [min, max], in the stat's OWN units (hearts, px/s, s, slots, degrees; the
## x1-base multipliers read as multipliers). The ONE table: get_stat() clamps every BASE stat
## here, so each BASE key has a row (a test enforces it). Hook-only keys (no BASE row:
## give_up_speed, stun_mult, item_noise_mult, item_carry_mult) are multipliers on 1 and
## clamp in their dispatcher; noise / move speed also clamp the stat x hook product.
## jump_velocity / gravity are pinned to base: no item may change jump height (rails rule).
const STAT_BOUNDS := {
	&"max_health": [1.0, 6.0],          # hearts (PD: max 6)
	&"move_speed": [70.0, 280.0],       # px/s = x0.5 .. x2 (stat x carry hooks)
	&"jump_velocity": [320.0, 320.0],   # pinned: PRODUCT.md rails must stay unclearable
	&"gravity": [980.0, 980.0],         # pinned (jump height)
	&"climb_speed": [36.0, 225.0],      # px/s = x0.4 .. x2.5
	&"pickup_time": [0.3, 3.0],         # s
	&"pickup_range": [20.0, 80.0],      # px = x0.5 .. x2
	&"tap_threshold": [0.1, 0.4],       # s (no item changes it)
	&"throw_speed": [260.0, 1040.0],    # px/s (no item changes it)
	&"light_range": [130.0, 520.0],     # px = x0.5 .. x2
	&"light_angle_deg": [10.0, 70.0],   # degrees (PD: max 70)
	&"light_startle_time": [0.4, 1.5],  # s (PD)
	&"light_detect_mult": [0.3, 3.0],   # startle takes 3.3x .. 0.33x as long
	&"noise_mult": [0.3, 3.0],          # PD: noise x0.3 .. x3 (stat x item noise hooks)
	&"invuln_time": [0.5, 2.0],         # s (PD)
	&"inventory_slots": [1.0, 5.0],     # slots (PD: max 5)
	&"gold_find_mult": [0.25, 3.0],
	&"minimap": [0.0, 1.0],             # flag
	&"give_up_speed": [0.3, 3.0],       # hook only: searching enemy memory drain (Cracked Mirror x1.4 per copy)
	# Behaviour effects that multiply across stacked copies (PD): bound on the product of all
	# copies, applied where the product is formed; the stat bounds above still apply on top.
	&"stun_mult": [0.5, 2.5],           # Heavy Vases thrown/knocked vase stun (x2 per copy): x2.5 total max
	&"item_noise_mult": [0.5, 2.0],     # on_noise hooks: Greedy Sack vase-break noise (x1.5 per copy)
	&"item_carry_mult": [0.7, 1.0],     # carry_speed_mult hooks: Heavy Vases carry slow (x0.85 per copy)
}

## `stat`'s effective value `v` (its own units) clamped to STAT_BOUNDS.
static func clamp_stat(stat: StringName, v: float) -> float:
	var b: Array = STAT_BOUNDS.get(stat, [])
	return clampf(v, b[0], b[1]) if b.size() == 2 else v


## `stat`'s effective multiplier `m` (vs its base; 1 for hook-only keys) clamped to
## STAT_BOUNDS, returned as a multiplier again (unchanged if unbounded).
static func clamp_mult(stat: StringName, m: float) -> float:
	var base := float(BASE.get(stat, 1.0))
	if base == 0.0:
		return m
	return clamp_stat(stat, m * base) / base


## Absolute value of `stat` at its upper / lower cap (in the stat's own units): BASE x bound
## (unbounded stats: BASE). Lead (#13): LevelValidator reads the jump/run caps only through these,
## so a later switch of STAT_BOUNDS to absolute rows only changes these two functions.
static func stat_max(stat: StringName) -> float:
	var b: Array = STAT_BOUNDS.get(stat, [])
	return float(BASE[stat]) * (float(b[1]) if b.size() == 2 else 1.0)


static func stat_min(stat: StringName) -> float:
	var b: Array = STAT_BOUNDS.get(stat, [])
	return float(BASE[stat]) * (float(b[0]) if b.size() == 2 else 1.0)


var health: int = 3
var gold: int = 0
## Bought and chest items (Item resources) this run. Survives stage Continue (this
## autoload is never re-created); cleared, with their modifiers, by reset().
## Held props are NOT here — they live in the level's Inventory and are dropped.
var owned_items: Array = []
## modifiers: Array of {stat, add, mul, source}
var _mods: Array[Dictionary] = []
var _invuln_left: float = 0.0  # counts down in _process, so it freezes while paused (shop)


func _ready() -> void:
	reset()


func get_stat(stat: StringName) -> float:
	return stat_with(stat, [])


## What-if read: `stat` as get_stat() would return it with `extra_mods` (Item.mods rows:
## {stat, add, mul}) added. ItemDb.describe uses it for "what the next copy adds".
func stat_with(stat: StringName, extra_mods: Array) -> float:
	assert(BASE.has(stat), "Unknown stat: %s" % stat)
	var add := 0.0
	var mul := 1.0
	for m in _mods:
		if m.stat == stat:
			add += m.add
			mul *= m.mul
	for m in extra_mods:
		if StringName(m.stat) == stat:
			add += float(m.get("add", 0.0))
			mul *= float(m.get("mul", 1.0))
	return clamp_stat(stat, (float(BASE[stat]) + add) * mul)


func max_health() -> int:
	return int(round(get_stat(&"max_health")))


func add_modifier(stat: StringName, add: float = 0.0, mul: float = 1.0, source: Variant = null) -> void:
	assert(BASE.has(stat), "Unknown stat: %s" % stat)
	_mods.append({stat = stat, add = add, mul = mul, source = source})
	if stat == &"max_health":
		# More max hearts heal by that much; fewer only clamp (never costs an extra heart).
		health = clampi(health + maxi(int(add), 0), 1, max_health())
		health_changed.emit(health, max_health())
	stat_changed.emit(stat, get_stat(stat))


func remove_modifiers_from(source: Variant) -> void:
	var touched := {}
	for i in range(_mods.size() - 1, -1, -1):
		if _mods[i].source == source:
			touched[_mods[i].stat] = true
			_mods.remove_at(i)
	for s in touched:
		stat_changed.emit(s, get_stat(s))
	if touched.has(&"max_health"):
		health = mini(health, max_health())
		health_changed.emit(health, max_health())


## Enforces invuln_time here so no caller can double-hit. Tests may pass ignore_invuln.
func take_hit(amount: int = 1, ignore_invuln: bool = false) -> bool:
	if health <= 0 or amount <= 0:
		return false
	# Run already ended (exit reached / win / death): no more damage or end-of-run events.
	if is_inside_tree() and (GameState.game_over or GameState.run_over):
		return false
	if not ignore_invuln and _invuln_left > 0.0:
		return false
	# Item hooks: on_hit may change or cancel the damage; on_lethal_hit may save the boy.
	for it in _live_items():
		amount = int(it.on_hit(amount))
	if amount <= 0:
		return false
	_invuln_left = get_stat(&"invuln_time")
	if health - amount <= 0:
		for it in _live_items():
			if it.on_lethal_hit():
				health = clampi(int(it.params.get("save_health", 1)), 1, max_health())
				health_changed.emit(health, max_health())
				return true
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health())
	if health == 0:
		died.emit()
		if is_inside_tree():
			var gs := get_node_or_null(^"/root/GameState")
			if gs:
				gs.on_caught()
	return true


func is_invulnerable() -> bool:
	return _invuln_left > 0.0


func _process(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(_invuln_left - delta, 0.0)


func heal(amount: int = 1) -> void:
	if amount <= 0:
		return
	health = mini(health + amount, max_health())
	health_changed.emit(health, max_health())


func add_gold(amount: int) -> void:
	if amount <= 0:
		return  # spending goes through try_spend only
	var delta := int(round(amount * get_stat(&"gold_find_mult"))) if amount > 0 else amount
	gold = maxi(gold + delta, 0)
	gold_changed.emit(gold, delta)


func try_spend(cost: int) -> bool:
	if cost < 0 or cost > gold:
		return false
	gold -= cost
	gold_changed.emit(gold, -cost)
	return true


## Applies `item` (its modifiers, source = item.source_key()) and adds it to
## owned_items. Shop.buy() and Chest.open() both end here. Gold is NOT touched.
func grant_item(item: Object) -> bool:
	if item == null or not item.has_method(&"apply") or owned_items.has(item):
		return false
	item.apply(self)
	owned_items.append(item)
	items_changed.emit(owned_items)
	_emit_lures()
	return true


func owns(item_id: String) -> bool:
	for it in owned_items:
		if is_instance_valid(it) and str(it.get("id")) == item_id:
			return true
	return false


## FE minimap UI: show it when this is true (listen to stat_changed(&"minimap", v)).
func has_minimap() -> bool:
	return get_stat(&"minimap") >= 1.0


# --- item behaviour dispatch (docs/BACKEND.md "Item behaviour hooks") ------------------
## View size: an enemy farther than half of it from the boy (either axis) is off screen.
const SCREEN_SIZE := Vector2(1280, 720)


## Owned items that implement the hook API (live Item instances), plus `extra` (what-if
## copies that are NOT owned: ItemDb.describe / would_add measure "one more copy" this way).
func _live_items(extra: Array = []) -> Array:
	var out: Array = []
	for it in owned_items:
		if is_instance_valid(it) and it is Item:
			out.append(it)
	for it in extra:
		if it is Item:
			out.append(it)
	return out


## Re-emits items_changed (an item's charges changed), and lures_changed if the pocket moved.
func notify_items_changed() -> void:
	items_changed.emit(owned_items)
	_emit_lures()


## Stage start (PlayerController._ready: every stage builds a fresh player). Refills every
## item's charges, runs on_stage_start, then emits items_changed once.
func begin_stage(player: Node = null) -> void:
	_player_ref = weakref(player) if player != null else null
	for it in _live_items():
		it.charges = it.max_charges
		it.on_stage_start(player)
	items_changed.emit(owned_items)
	_emit_lures(true)


# --- Music Box lure pocket (PRODUCT.md: lures never take a hand slot) --------------------
## Each Music Box copy keeps its own charge (#38): one lure per copy per stage. The pocket is
## the sum. Hands (Inventory) never hold a lure.
var _player_ref: WeakRef = null
var _lures_seen := Vector2i(-1, -1)


func _music_boxes() -> Array:
	var out: Array = []
	for it in _live_items():
		if it.has_method(&"lure_dict"):
			out.append(it)
	return out


## Lures left in the pocket this stage.
func lure_charges() -> int:
	var n := 0
	for it in _music_boxes():
		n += maxi(int(it.charges), 0)
	return n


## Pocket size: lures per stage (one per Music Box copy).
func lure_max() -> int:
	var n := 0
	for it in _music_boxes():
		n += maxi(int(it.max_charges), 0)
	return n


## The lure dict of the first copy with a charge left ({} if the pocket is empty). Throwing
## it (dispatch_throw) spends exactly that copy's charge.
func next_lure() -> Dictionary:
	for it in _music_boxes():
		if it.charges > 0:
			return it.lure_dict()
	return {}


## FE hint: true when a tap with NOTHING ringed would throw a lure right now (lures left,
## and the tap isn't a knock: hands full, or no knockable prop in reach). False with no
## live player (menus, shop).
func tap_throws_lure() -> bool:
	if lure_charges() <= 0:
		return false
	var p: Object = _player_ref.get_ref() if _player_ref != null else null
	if p == null or not is_instance_valid(p) or not p.has_method(&"tap_would_throw_lure"):
		return false
	return bool(p.tap_would_throw_lure())


func _emit_lures(force: bool = false) -> void:
	var now := Vector2i(lure_charges(), lure_max())
	if force or now != _lures_seen:
		_lures_seen = now
		lures_changed.emit(now.x, now.y)


## NoiseBus.emit_noise: product of every item's on_noise multiplier.
func noise_hook_mult(at: Vector2, radius: float, loudness: float, source: Variant) -> float:
	return _noise_total(at, radius, loudness, source, []) / get_stat(&"noise_mult")


## Whole noise multiplier for `source` (stat x hooks, both capped), with `extra` copies.
func _noise_total(at: Vector2, radius: float, loudness: float, source: Variant, extra: Array) -> float:
	var m := 1.0
	for it in _live_items(extra):
		m *= float(it.on_noise(at, radius, loudness, source))
	m = clamp_mult(&"item_noise_mult", m)
	# The cap is on the whole noise effect: stat (already in `radius`) x hooks.
	return clamp_mult(&"noise_mult", stat_with(&"noise_mult", _mods_of(extra)) * m)


## PlayerController throw / knock: items may write into `item` (the dict the enemy gets).
func dispatch_throw(item: Dictionary, target: Variant) -> void:
	_dispatch_throw(item, target, [])
	_emit_lures()


func _dispatch_throw(item: Dictionary, target: Variant, extra: Array) -> void:
	for it in _live_items(extra):
		it.on_throw(item, target)
	if item.has("stun_mult"):   # Heavy Vases multiply it once per copy
		item["stun_mult"] = clamp_mult(&"stun_mult", float(item["stun_mult"]))


## Enemy STARTLED -> about to chase. True if an item handled it (first one wins).
func startle_handled(enemy: Node) -> bool:
	for it in _live_items():
		if it.on_startle(enemy):
			return true
	return false


## Gold a breaking vase drops, after item hooks.
func vase_gold(gold: int, vase: Variant = null) -> int:
	for it in _live_items():
		gold = int(it.on_vase_gold(gold, vase))
	return gold


## Move-speed multiplier for what the boy holds (Inventory.items).
func carry_speed_mult(held: Array) -> float:
	return _carry_mult(held, [])


func _carry_mult(held: Array, extra: Array) -> float:
	var m := 1.0
	for it in _live_items(extra):
		m *= float(it.carry_speed_mult(held))
	m = clamp_mult(&"item_carry_mult", m)
	var ms := stat_with(&"move_speed", _mods_of(extra)) / float(BASE[&"move_speed"])
	return clamp_mult(&"move_speed", ms * m) / ms


## Multiplier on a searching enemy's give-up drain.
func memory_drain_mult(enemy: Node, off_screen: bool) -> float:
	return _drain_mult(enemy, off_screen, [])


func _drain_mult(enemy: Node, off_screen: bool, extra: Array) -> float:
	var m := 1.0
	for it in _live_items(extra):
		m *= float(it.memory_drain_mult(enemy, off_screen))
	return clamp_mult(&"give_up_speed", m)


## FE off-screen arrows: show a chaser's arrow only within this many px of the boy.
## INF without Cracked Mirror (always show). Listen to items_changed to re-read it.
func arrow_reveal_distance() -> float:
	var d := INF
	for it in _live_items():
		d = minf(d, float(it.arrow_reveal_distance()))
	return d


static func _mods_of(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if it is Item:
			out.append_array(it.mods)
	return out


## Effective, CAPPED value of one effect, with `extra` (not owned) copies counted as owned.
## The ONE place ItemDb.describe and max-copies read numbers from. Keys:
##   any BASE stat name           get_stat
##   "vase_noise"                 whole vase-break noise multiplier (stat x hooks)
##   "stun"                       thrown/knocked vase stun multiplier (Heavy Vases)
##   "carry"                      move-speed multiplier while holding a vase
##   "give_up"                    off-screen give-up drain multiplier (Cracked Mirror)
##   "uses:<item id>"             charges per stage of all copies of that item
func effect(key: String, extra: Array = []) -> float:
	if BASE.has(StringName(key)):
		return stat_with(StringName(key), _mods_of(extra))
	var vase := {slot = "vase_idle", script_path = "res://scripts/world/vase.gd", throwable = true}
	match key:
		"vase_noise":
			return _noise_total(Vector2.ZERO, 1.0, 1.0, vase, extra)
		"stun":
			var d := vase.duplicate()
			d["stun_mult"] = 1.0
			_dispatch_throw(d, Vector2.ZERO, extra)
			return float(d.get("stun_mult", 1.0))
		"carry":
			return _carry_mult([vase], extra)
		"give_up":
			return _drain_mult(null, true, extra)
	if key.begins_with("uses:"):
		var id := key.substr(5)
		var n := 0
		for it in _live_items(extra):
			if it.id == id:
				n += maxi(int(it.max_charges), 0)
		return float(n)
	push_error("PlayerStats.effect: unknown key %s" % key)
	return 0.0


## Owned copies of `item_id`.
func copies(item_id: String) -> int:
	var n := 0
	for it in _live_items():
		if it.id == item_id:
			n += 1
	return n


## True if world point `p` is outside the view around `center` (the boy).
static func is_off_screen(p: Vector2, center: Vector2) -> bool:
	var d := (p - center).abs()
	return d.x > SCREEN_SIZE.x * 0.5 or d.y > SCREEN_SIZE.y * 0.5


## New run. Keeps nothing: modifiers (all item effects) and owned items go.
func reset() -> void:
	_mods.clear()
	for it in owned_items:
		if is_instance_valid(it) and "_applied_to" in it:
			it.set("_applied_to", null)
	owned_items.clear()
	items_changed.emit(owned_items)
	_player_ref = null
	_emit_lures()
	_invuln_left = 0.0
	health = max_health()
	gold = 0
	health_changed.emit(health, max_health())
	gold_changed.emit(gold, 0)

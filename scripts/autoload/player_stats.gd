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

## Floors so no item combo can produce nonsense (negative time, 0 max hp, ...).
## Physics layers (bits). Player and enemies never block each other, so a catch is a
## distance check on overlapping bodies instead of two colliders stalling 26px apart.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

const MIN := {
	&"max_health": 1.0,
	&"pickup_time": 0.1,
	&"tap_threshold": 0.05,
	&"light_startle_time": 0.2,
	&"inventory_slots": 1.0,
	# Item-stack floors (any item combo stays playable):
	&"move_speed": 60.0,
	&"climb_speed": 30.0,
	&"pickup_range": 16.0,
	&"light_range": 80.0,
	&"light_angle_deg": 10.0,
	&"light_detect_mult": 0.2,
	&"noise_mult": 0.2,
	&"gold_find_mult": 0.1,
}

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
	assert(BASE.has(stat), "Unknown stat: %s" % stat)
	var add := 0.0
	var mul := 1.0
	for m in _mods:
		if m.stat == stat:
			add += m.add
			mul *= m.mul
	return maxf((float(BASE[stat]) + add) * mul, float(MIN.get(stat, 0.0)))


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
				health = 1
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


## Owned items that implement the hook API (live Item instances).
func _live_items() -> Array:
	var out: Array = []
	for it in owned_items:
		if is_instance_valid(it) and it is Item:
			out.append(it)
	return out


## Re-emits items_changed (an item's charges changed).
func notify_items_changed() -> void:
	items_changed.emit(owned_items)


## Stage start (PlayerController._ready: every stage builds a fresh player). Refills every
## item's charges, runs on_stage_start, then emits items_changed once.
func begin_stage(player: Node = null) -> void:
	for it in _live_items():
		it.charges = it.max_charges
		it.on_stage_start(player)
	items_changed.emit(owned_items)


## NoiseBus.emit_noise: product of every item's on_noise multiplier.
func noise_hook_mult(at: Vector2, radius: float, loudness: float, source: Variant) -> float:
	var m := 1.0
	for it in _live_items():
		m *= float(it.on_noise(at, radius, loudness, source))
	return m


## PlayerController throw / knock: items may write into `item` (the dict the enemy gets).
func dispatch_throw(item: Dictionary, target: Variant) -> void:
	for it in _live_items():
		it.on_throw(item, target)


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
	var m := 1.0
	for it in _live_items():
		m *= float(it.carry_speed_mult(held))
	return m


## Multiplier on a searching enemy's give-up drain.
func memory_drain_mult(enemy: Node, off_screen: bool) -> float:
	var m := 1.0
	for it in _live_items():
		m *= float(it.memory_drain_mult(enemy, off_screen))
	return m


## FE off-screen arrows: show a chaser's arrow only within this many px of the boy.
## INF without Cracked Mirror (always show). Listen to items_changed to re-read it.
func arrow_reveal_distance() -> float:
	var d := INF
	for it in _live_items():
		d = minf(d, float(it.arrow_reveal_distance()))
	return d


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
	_invuln_left = 0.0
	health = max_health()
	gold = 0
	health_changed.emit(health, max_health())
	gold_changed.emit(gold, 0)

extends Node
## PlayerStats — the ONE place player numbers live.
## Base values are in BASE. Items add modifiers; nothing else writes stats.
## Read with PlayerStats.get_stat(&"pickup_time"). FE/QA read, never write.

signal health_changed(current: int, max_hp: int)
signal gold_changed(current: int, delta: int)
signal stat_changed(stat: StringName, value: float)
signal died

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
}

var health: int = 3
var gold: int = 0
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
		health = clampi(health + int(add), 1, max_health())
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
	if not ignore_invuln and _invuln_left > 0.0:
		return false
	_invuln_left = get_stat(&"invuln_time")
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


## New run. Keeps nothing.
func reset() -> void:
	_mods.clear()
	_invuln_left = 0.0
	health = max_health()
	gold = 0
	health_changed.emit(health, max_health())
	gold_changed.emit(gold, 0)

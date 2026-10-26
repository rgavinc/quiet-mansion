extends Node
## FESignals — the ONE interface the Front End HUD/overlays listen to.
##
## Autoloaded as `FESignals`. Every FE widget reads only from here, so when
## Back End's foundation lands we rewire THIS file and nothing else.
##
## PLACEHOLDER STATUS (Oct 25): none of PlayerStats / NoiseBus / Enemy state
## machine / Inventory / pickup / shared animation loader exist on
## `development` yet. Everything below is a placeholder and is marked
## `TODO(BE-wire)` where it should be connected to the real signal.
##
## Two ways data gets in:
##   1. Back End (or the demo) calls the `report_*` / `set_*` methods.
##   2. Later: `_wire_backend()` connects BE's real signals to those methods.
## Widgets also call the getters (`health`, `selected_enemy`, ...) on _ready
## so a widget created late still shows the current state.

# --- Player stats ----------------------------------------------------------
## (current, max). TODO(BE-wire): PlayerStats.health_changed / max_health.
signal health_changed(current: int, max_hp: int)
## TODO(BE-wire): PlayerStats.gold_changed.
signal gold_changed(amount: int, delta: int)

# --- Flashlight / selection / startle -------------------------------------
## TODO(BE-wire): flashlight toggle signal from BE player/flashlight.
signal flashlight_toggled(on: bool)
## `enemy` is null when nothing is selected. Only one at a time.
## TODO(BE-wire): BE flashlight hover → selection (or FE owns selection logic).
signal enemy_selected(enemy: Node2D)
## progress 0..1 toward a startle. TODO(BE-wire): Enemy startle timer.
signal startle_progress(enemy: Node2D, progress: float)

# --- Chasing / off-screen --------------------------------------------------
## TODO(BE-wire): Enemy state machine enter/exit CHASE.
signal chase_changed(enemy: Node2D, chasing: bool)
## ratio 1 = full chase memory, 0 = gives up. TODO(BE-wire): Enemy chase memory.
signal chase_memory_changed(enemy: Node2D, ratio: float)

# --- Pickup / inventory ----------------------------------------------------
## TODO(BE-wire): BE pickup state (PlayerStats.pickup_time drives duration).
signal pickup_started(target: Node2D)
signal pickup_progress(progress: float)
signal pickup_cancelled
signal pickup_completed
## items: Array of Dictionary {id, slot, name, throwable}. TODO(BE-wire): Inventory.changed.
signal inventory_changed(items: Array)
## TODO(BE-wire): Inventory.selected_changed.
signal inventory_selected(index: int)

# --- Stat defaults (TODO(BE-wire): read from PlayerStats) -----------------
var max_health: int = 3
var startle_time: float = 1.0
var pickup_time: float = 1.0
## Distance at which an off-screen chaser's gauge reaches 0 when BE does not
## send chase_memory_changed. TODO(BE-wire): EnemyDef.give_up_distance.
var give_up_distance: float = 900.0

# --- Current state (pull-able) --------------------------------------------
var health: int = 3
var gold: int = 0
var flashlight_on: bool = true
var selected_enemy: Node2D = null
var chasing: Array[Node2D] = []
var chase_memory: Dictionary = {}   # enemy instance_id -> ratio
var startle: Dictionary = {}        # enemy instance_id -> progress
var pickup_active: bool = false
var pickup_value: float = 0.0
var items: Array = []
var selected_index: int = -1

## Demo-only: when true, this adapter reads inv_next/inv_prev and
## flashlight_toggle itself. Keep false in the real game (BE owns input).
var placeholder_input_enabled: bool = false

## Placeholder startle integration: enemies currently in the beam.
var _lit: Dictionary = {}           # instance_id -> enemy


func _ready() -> void:
	_wire_backend()


## TODO(BE-wire): connect BE's real signals here when they land, e.g.
##   PlayerStats.health_changed.connect(func(c, m): set_health(c, m))
##   PlayerStats.gold_changed.connect(set_gold)
##   Inventory.changed.connect(set_items); Inventory.selected_changed.connect(select_item)
##   player.pickup_progress.connect(report_pickup_progress) ...
## and set `max_health/startle_time/pickup_time` from PlayerStats.
func _wire_backend() -> void:
	# Deferred: PlayerStats is listed after FESignals in [autoload].
	_wire_player_stats.call_deferred()


## Real once BE PR "PlayerStats autoload" is merged; a no-op until then.
func _wire_player_stats() -> void:
	var ps := get_node_or_null(^"/root/PlayerStats")
	if ps == null:
		return
	ps.health_changed.connect(func(c: int, m: int) -> void: set_health(c, m))
	ps.gold_changed.connect(func(c: int, _d: int) -> void: set_gold(c))
	if ps.has_method(&"get_stat"):
		startle_time = ps.get_stat(&"light_startle_time")
		pickup_time = ps.get_stat(&"pickup_time")
	set_health(ps.health, ps.max_health())
	set_gold(ps.gold)


# --- Stats -----------------------------------------------------------------
func set_health(current: int, max_hp: int = -1) -> void:
	if max_hp > 0:
		max_health = max_hp
	health = clampi(current, 0, max_health)
	health_changed.emit(health, max_health)


func set_gold(amount: int) -> void:
	var delta := amount - gold
	gold = maxi(amount, 0)
	gold_changed.emit(gold, delta)


# --- Flashlight / selection -----------------------------------------------
func set_flashlight(on: bool) -> void:
	if on == flashlight_on:
		return
	flashlight_on = on
	if not on:
		# Light off: nothing is lit any more, so no startle builds.
		for id in _lit.keys():
			_set_startle(_lit[id], 0.0)
		_lit.clear()
	flashlight_toggled.emit(on)


func select_enemy(enemy: Node2D) -> void:
	if enemy != null and not is_instance_valid(enemy):
		enemy = null
	if enemy == selected_enemy:
		return
	selected_enemy = enemy
	enemy_selected.emit(enemy)


## Placeholder: BE reports which enemy the beam is on; we integrate the
## startle gauge over `startle_time`. When BE emits its own startle progress,
## call `report_startle()` instead and stop calling this.
func report_lit(enemy: Node2D, lit: bool) -> void:
	if enemy == null:
		return
	var id := enemy.get_instance_id()
	if lit and flashlight_on:
		_lit[id] = enemy
	elif _lit.has(id):
		_lit.erase(id)
		_set_startle(enemy, 0.0)


func report_startle(enemy: Node2D, progress: float) -> void:
	_set_startle(enemy, progress)


func get_startle(enemy: Node2D) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0
	return float(startle.get(enemy.get_instance_id(), 0.0))


func is_lit(enemy: Node2D) -> bool:
	return enemy != null and is_instance_valid(enemy) and _lit.has(enemy.get_instance_id())


func _set_startle(enemy: Node2D, p: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	p = clampf(p, 0.0, 1.0)
	startle[enemy.get_instance_id()] = p
	startle_progress.emit(enemy, p)


# --- Chase -----------------------------------------------------------------
func report_chase(enemy: Node2D, is_chasing: bool) -> void:
	if enemy == null:
		return
	var idx := chasing.find(enemy)
	if is_chasing and idx == -1:
		chasing.append(enemy)
	elif not is_chasing and idx != -1:
		chasing.remove_at(idx)
		chase_memory.erase(enemy.get_instance_id())
	chase_changed.emit(enemy, is_chasing)


func report_chase_memory(enemy: Node2D, ratio: float) -> void:
	if enemy == null:
		return
	chase_memory[enemy.get_instance_id()] = clampf(ratio, 0.0, 1.0)
	chase_memory_changed.emit(enemy, clampf(ratio, 0.0, 1.0))


## Returns BE's reported ratio if any, else -1 (widget falls back to distance).
func get_chase_memory(enemy: Node2D) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return -1.0
	return float(chase_memory.get(enemy.get_instance_id(), -1.0))


# --- Pickup ------------------------------------------------------------------
func report_pickup_started(target: Node2D = null) -> void:
	pickup_active = true
	pickup_value = 0.0
	pickup_started.emit(target)
	pickup_progress.emit(0.0)


func report_pickup_progress(p: float) -> void:
	if not pickup_active:
		report_pickup_started(null)
	pickup_value = clampf(p, 0.0, 1.0)
	pickup_progress.emit(pickup_value)


func report_pickup_cancelled() -> void:
	if not pickup_active:
		return
	pickup_active = false
	pickup_value = 0.0
	pickup_cancelled.emit()


func report_pickup_completed() -> void:
	pickup_active = false
	pickup_value = 1.0
	pickup_completed.emit()


# --- Inventory ---------------------------------------------------------------
func set_items(new_items: Array) -> void:
	items = new_items.duplicate()
	inventory_changed.emit(items)
	if items.is_empty():
		select_item(-1)
	elif selected_index < 0 or selected_index >= items.size():
		select_item(clampi(selected_index, 0, items.size() - 1))


func select_item(index: int) -> void:
	if items.is_empty():
		index = -1
	else:
		index = clampi(index, 0, items.size() - 1)
	selected_index = index
	inventory_selected.emit(index)


## Wraps around; safe on an empty inventory.
func cycle_item(direction: int) -> void:
	if items.is_empty():
		select_item(-1)
		return
	var i := selected_index if selected_index >= 0 else 0
	select_item(posmod(i + direction, items.size()))


func selected_item() -> Dictionary:
	if selected_index < 0 or selected_index >= items.size():
		return {}
	var it = items[selected_index]
	return it if it is Dictionary else {}


# --- Enemy type lookup -------------------------------------------------------
## Type id used for ring colours. TODO(BE-wire): use EnemyDef.type_id.
func enemy_type_id(enemy: Node) -> String:
	if enemy == null or not is_instance_valid(enemy):
		return ""
	if enemy.has_method("get_type_id"):
		return str(enemy.get_type_id())
	if "type_id" in enemy:
		return str(enemy.get("type_id"))
	if enemy.has_meta("enemy_type"):
		return str(enemy.get_meta("enemy_type"))
	if enemy.is_in_group("puppets"):
		return "puppet_hand"
	return ""


func _process(delta: float) -> void:
	# Placeholder startle integration (remove once BE emits startle progress).
	if _lit.is_empty():
		return
	var step := delta / maxf(startle_time, 0.01)
	for id in _lit.keys():
		var e: Node2D = _lit[id]
		if not is_instance_valid(e):
			_lit.erase(id)
			continue
		_set_startle(e, float(startle.get(id, 0.0)) + step)


func _unhandled_input(event: InputEvent) -> void:
	if not placeholder_input_enabled:
		return
	if event.is_action_pressed("inv_next"):
		cycle_item(1)
	elif event.is_action_pressed("inv_prev"):
		cycle_item(-1)
	elif event.is_action_pressed("flashlight_toggle"):
		set_flashlight(not flashlight_on)


## Clears all state (tests / scene reloads).
func reset() -> void:
	health = max_health
	gold = 0
	flashlight_on = true
	selected_enemy = null
	chasing.clear()
	chase_memory.clear()
	startle.clear()
	_lit.clear()
	pickup_active = false
	pickup_value = 0.0
	items.clear()
	selected_index = -1

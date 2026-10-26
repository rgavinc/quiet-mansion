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
## REAL: emitted by set_flashlight(), which BE's player_controller calls on RMB toggle.
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

# --- Run flow: screens / banner / alerts -----------------------------------
## REAL: PlayerStats.died (hearts hit 0). Game-over screen listens.
signal player_died
## REAL: GameState.reached_exit → stage cleared → shop (Lead: no separate
## stage-complete signal is coming; reached_exit is the hook).
signal stage_cleared(stage: int)
## Level start (scene swap here, or BE/generator calls announce_stage). Banner listens.
signal stage_started(stage: int)
## Shop purchase went through (offer dict, see get_shop_offer).
signal item_purchased(offer: Dictionary)

# --- Stat defaults (TODO(BE-wire): read from PlayerStats) -----------------
## Fresh-run hearts when no PlayerStats is wired (PlayerStats.BASE max_health).
const DEFAULT_MAX_HEALTH := 3
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
## LMB shorter than this = tap (throw / knock). Read from PlayerStats when wired.
var tap_threshold: float = 0.2
var _stats: Node = null
var items: Array = []
var selected_index: int = -1

## Demo-only: when true, this adapter reads inv_next/inv_prev and
## flashlight_toggle itself. Keep false in the real game (BE owns input).
var placeholder_input_enabled: bool = false

## The run's STARTING (stage 1) seed. "Retry seed" replays this, never the
## current stage's seed. -1 = not known yet (captured from the stage-1 level).
var run_seed: int = -1
## Tests: swap scenes synchronously instead of call_deferred.
var swap_deferred := true
## Stage counter when the level scene has no `stage` property (pre PR #13).
var stage: int = 1
## Demo-only shop stock: Callable(count: int, stage: int, seed: int) -> Array[Dictionary].
## Never set in the real game; real stock comes from BE's Shop (see get_shop_offer).
var shop_stub: Callable = Callable()
## True once any report_chase() arrives; until then chase count is polled from enemies.
var _chase_reported: bool = false
var _gs: Node = null
var _shop: Object = null

## Placeholder startle integration: enemies currently in the beam.
var _lit: Dictionary = {}           # instance_id -> enemy


func _ready() -> void:
	_wire_backend()


## Connects BE's real sources. REAL today: PlayerStats (hearts, gold, timings).
## PlayerStats is listed BEFORE FESignals in [autoload], so it already exists.
## TODO(BE-wire) still: Inventory.changed → set_items, Inventory.selected_changed
## → select_item, player.pickup_* → report_pickup_*, Enemy startle/chase signals,
## REAL: BE player_controller calls set_flashlight(on) on RMB toggle (PR #4).
func _wire_backend() -> void:
	if not is_inside_tree() or get_path() != ^"/root/FESignals":
		return   # only the autoload auto-wires; test instances call wire_player_stats()
	var ps := get_node_or_null(^"/root/PlayerStats")
	if ps == null:
		push_warning("FESignals: /root/PlayerStats missing; hearts/gold stay on placeholder values")
		return
	wire_player_stats(ps)
	var gs := get_node_or_null(^"/root/GameState")
	if gs:
		wire_game_state(gs)


## GameState.reached_exit → stage_cleared(stage). Explicit so tests can wire a fake.
func wire_game_state(gs: Node) -> void:
	if _gs != null:
		return
	_gs = gs
	if gs.has_signal(&"reached_exit"):
		gs.reached_exit.connect(func(): stage_cleared.emit(get_stage()))


## Explicit PlayerStats → HUD connection (also used by tests with a fresh instance).
func wire_player_stats(ps: Node) -> void:
	if _stats != null:
		return
	_stats = ps
	if ps.has_signal(&"died"):
		ps.died.connect(func(): player_died.emit())
	ps.health_changed.connect(_on_ps_health)
	ps.gold_changed.connect(_on_ps_gold)
	startle_time = ps.get_stat(&"light_startle_time")
	pickup_time = ps.get_stat(&"pickup_time")
	tap_threshold = ps.get_stat(&"tap_threshold")
	set_health(ps.health, ps.max_health())
	set_gold(ps.gold)


func is_stats_wired() -> bool:
	return _stats != null


func _on_ps_health(current: int, max_hp: int) -> void:
	set_health(current, max_hp)


func _on_ps_gold(current: int, _delta: int) -> void:
	set_gold(current)


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
			var raw = _lit[id]
			if is_instance_valid(raw):
				_set_startle(raw, 0.0)
		_lit.clear()
	flashlight_toggled.emit(on)


## RMB is a toggle (click on, click off), never hold-to-light.
func toggle_flashlight() -> void:
	set_flashlight(not flashlight_on)


## True when the boy has something in hand (the selected inventory item).
## TODO(BE-wire): Inventory.held_item once BE adds hands vs. bag.
func is_holding() -> bool:
	return not selected_item().is_empty()


## Throw line / tap-throw rule: holding something AND an enemy is ringed.
func can_throw() -> bool:
	return is_holding() and get_selected_enemy() != null


func select_enemy(enemy: Node2D) -> void:
	if enemy != null and not is_instance_valid(enemy):
		enemy = null
	if enemy == selected_enemy and (enemy == null or is_instance_valid(selected_enemy)):
		return
	selected_enemy = enemy
	_track(enemy)
	enemy_selected.emit(enemy)


## Valid selected enemy, or null. Widgets should read this (never a freed node).
func get_selected_enemy() -> Node2D:
	var e = selected_enemy   # untyped: may hold a freed instance
	return e if is_instance_valid(e) else null


# --- Enemy lifetime (QA #18) -----------------------------------------------
## Every enemy FE keeps a reference to is tracked: when it leaves the tree
## (killed / freed / level unload) all its selection, startle, lit and chase
## entries are dropped at once. _prune() in _process catches anything else.
func _track(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var cb := _on_enemy_exiting.bind(enemy.get_instance_id())
	if not enemy.tree_exiting.is_connected(cb):
		enemy.tree_exiting.connect(cb, CONNECT_ONE_SHOT)


func _on_enemy_exiting(id: int) -> void:
	forget_enemy(id)


## Drops every FE entry for enemy instance `id` and notifies widgets.
func forget_enemy(id: int) -> void:
	var sel = selected_enemy
	if sel != null and (not is_instance_valid(sel) or sel.get_instance_id() == id):
		selected_enemy = null
		enemy_selected.emit(null)
	for i in range(chasing.size() - 1, -1, -1):
		var c = chasing[i]
		if not is_instance_valid(c) or c.get_instance_id() == id:
			chasing.remove_at(i)
	_lit.erase(id)
	startle.erase(id)
	chase_memory.erase(id)


## Removes entries whose enemy is already freed (no tree_exiting seen).
func _prune() -> void:
	var sel = selected_enemy
	if sel != null and not is_instance_valid(sel):
		selected_enemy = null
		enemy_selected.emit(null)
	for i in range(chasing.size() - 1, -1, -1):
		var c = chasing[i]
		if not is_instance_valid(c):
			chasing.remove_at(i)
	for id in _lit.keys():
		var e = _lit[id]
		if not is_instance_valid(e):
			forget_enemy(id)
	for d in [startle, chase_memory]:
		for id in d.keys():
			if not is_instance_valid(instance_from_id(id)):
				d.erase(id)


## Placeholder: BE reports which enemy the beam is on; we integrate the
## startle gauge over `startle_time`. When BE emits its own startle progress,
## call `report_startle()` instead and stop calling this.
func report_lit(enemy: Node2D, lit: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	if lit and flashlight_on:
		_lit[id] = enemy
		_track(enemy)
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
	_track(enemy)
	startle[enemy.get_instance_id()] = p
	startle_progress.emit(enemy, p)


# --- Chase -----------------------------------------------------------------
func report_chase(enemy: Node2D, is_chasing: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var idx := chasing.find(enemy)
	_chase_reported = true
	if is_chasing and idx == -1:
		chasing.append(enemy)
		_track(enemy)
	elif not is_chasing and idx != -1:
		chasing.remove_at(idx)
		chase_memory.erase(enemy.get_instance_id())
	chase_changed.emit(enemy, is_chasing)


func report_chase_memory(enemy: Node2D, ratio: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_track(enemy)
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
	_prune()
	if _lit.is_empty():
		return
	var step := delta / maxf(startle_time, 0.01)
	for id in _lit.keys():
		var raw = _lit[id]   # untyped first: a freed enemy can't go in a typed var
		if not is_instance_valid(raw):
			forget_enemy(id)
			continue
		_set_startle(raw, float(startle.get(id, 0.0)) + step)


func _unhandled_input(event: InputEvent) -> void:
	if not placeholder_input_enabled:
		return
	if event.is_action_pressed("inv_next"):
		cycle_item(1)
	elif event.is_action_pressed("inv_prev"):
		cycle_item(-1)
	elif event.is_action_pressed("flashlight_toggle"):
		toggle_flashlight()


# --- Enemy registry / alert count ------------------------------------------
## Every live enemy on the stage: groups `enemies` and `puppets` (deduped).
## TODO(BE-wire): BE enemy registry if one lands.
func get_enemies() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for g in [&"enemies", &"puppets"]:
		for e in get_tree().get_nodes_in_group(g):
			if is_instance_valid(e) and not e.is_queued_for_deletion() and not out.has(e):
				out.append(e)
	return out


## Enemies chasing right now. Uses report_chase() once BE sends it; until then polls
## each enemy's `is_chasing()` / `enraged`. TODO(BE-wire): Enemy CHASE state signal.
func chasing_count() -> int:
	if _chase_reported:
		var n := 0
		for raw in chasing:
			if is_instance_valid(raw):
				n += 1
		return n
	var n := 0
	for e in get_enemies():
		if e.has_method(&"is_chasing"):
			n += 1 if e.is_chasing() else 0
		elif "enraged" in e and e.get("enraged"):
			n += 1
	return n


func enemy_total() -> int:
	return get_enemies().size()


# --- Run info (stage / seed) -------------------------------------------------
## Stage from the level scene's `stage` (PR #13 main.gd), else the FE counter.
func get_stage() -> int:
	var s := _scene()
	if s and "stage" in s and int(s.get("stage")) > 0:
		return int(s.get("stage"))
	return stage


## Level seed from the scene's `level_seed` (PR #13), else -1 = no seed (hide it).
func get_seed() -> int:
	var s := _scene()
	if s and "level_seed" in s:
		return int(s.get("level_seed"))
	return -1


func _scene() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().current_scene


## BE / generator can call this at level start; the banner shows "Stage N".
func announce_stage(n: int = -1) -> void:
	if n > 0:
		stage = n
	stage_started.emit(get_stage())


# --- Shop adapter --------------------------------------------------------------
## Offer dicts mirror BE's Item exactly: {id, display_name, description, icon_slot,
## price, rarity, item}. `item` is the real Item (or null for stubs).
## Source order: BE `Shop.roll_stock(stage, seed) -> Array[Item]` if a global class
## `Shop` exists, else `shop_stub` (demo only), else []. TODO(BE-wire): drop the
## class lookup once Shop is an autoload / known class on development.
func get_shop_offer(count: int = 3, for_stage: int = -1, for_seed: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0:
		return out
	var st := for_stage if for_stage > 0 else get_stage()
	var sd := for_seed if for_seed >= 0 else get_seed()
	var raw: Array = []
	var shop := _get_shop()
	if shop and shop.has_method(&"roll_stock"):
		var r = shop.roll_stock(st, sd)
		if r is Array:
			raw = r
	elif shop_stub.is_valid():
		var r = shop_stub.call(count, st, sd)
		if r is Array:
			raw = r
	for it in raw:
		var d := item_to_offer(it)
		if not d.is_empty():
			out.append(d)
		if out.size() >= count:
			break
	return out


## Item (BE resource) or Dictionary → offer dict. Missing fields get safe defaults.
static func item_to_offer(it) -> Dictionary:
	if it == null:
		return {}
	var get_f := func(k: String, def):
		if it is Dictionary:
			return it.get(k, def)
		if it is Object and is_instance_valid(it) and k in it:
			var v = it.get(k)
			return def if v == null else v
		return def
	var d := {
		"id": str(get_f.call("id", "")),
		"display_name": str(get_f.call("display_name", get_f.call("id", "?"))),
		"description": str(get_f.call("description", "")),
		"icon_slot": str(get_f.call("icon_slot", "")),
		"price": maxi(int(get_f.call("price", 0)), 0),
		"rarity": str(get_f.call("rarity", "common")),
		"item": it if it is Object else null,
	}
	return d


## Buy one offer. BE `Shop.buy(item)` when available (it spends via PlayerStats.try_spend
## and applies the item); otherwise spend via try_spend() and call item.apply() if any.
func buy_offer(offer: Dictionary) -> bool:
	if offer.is_empty():
		return false
	var item = offer.get("item", null)
	var shop := _get_shop()
	var ok := false
	if shop and item != null and shop.has_method(&"buy"):
		ok = bool(shop.buy(item))
	else:
		ok = try_spend(int(offer.get("price", 0)))
		if ok and item is Object and is_instance_valid(item) and item.has_method(&"apply"):
			item.apply()
	if ok:
		item_purchased.emit(offer)
	return ok


## Gold spend: PlayerStats.try_spend when wired, else the placeholder gold.
func try_spend(cost: int) -> bool:
	if _stats != null and is_instance_valid(_stats):
		return bool(_stats.try_spend(cost))
	if cost < 0 or cost > gold:
		return false
	set_gold(gold - cost)
	return true


func _get_shop() -> Object:
	if _shop != null and is_instance_valid(_shop):
		return _shop
	var root := get_node_or_null(^"/root/Shop") if is_inside_tree() else null
	if root:
		_shop = root
		return _shop
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "Shop":
			var scr = load(str(c.get("path", "")))
			if scr is Script and scr.can_instantiate():
				_shop = scr.new()
				if _shop is Node:
					add_child(_shop)
			break
	return _shop


# --- Run flow ---------------------------------------------------------------------
## No continues (Product Director): dying ends the run. Both game-over buttons start a
## FRESH run at stage 1 — PlayerStats.reset() (3 hearts, 0 gold, all item modifiers
## cleared), FE inventory cleared, GameState reset.
##   New run    → restart_run(-1)           : level rolls a new seed (Lead: -1 = roll).
##   Retry seed → restart_run(get_run_seed()): the run's stage-1 seed again.
## `at_stage` is ignored on purpose (always 1); kept for call-site compatibility.
func restart_run(new_seed: int = -1, _at_stage: int = 1) -> void:
	if _stats != null and is_instance_valid(_stats) and _stats.has_method(&"reset"):
		_stats.reset()   # BE API: clears modifiers (items), health = base max, gold = 0
	else:
		# No PlayerStats wired (tests / tools): fresh FE numbers.
		set_health(DEFAULT_MAX_HEALTH, DEFAULT_MAX_HEALTH)
		set_gold(0)
	run_seed = new_seed if new_seed >= 0 else -1
	stage = 1
	_request_swap(run_seed, 1, true)


## The RUN seed for "Retry seed" / the game-over screen. In PR #13 the level's
## `level_seed` IS the run seed (each stage = run seed + stage number), so it is
## the same on every stage; captured once and kept through next_stage().
## -1 when the level has no seed (pre PR #13 main.gd).
func get_run_seed() -> int:
	if run_seed >= 0:
		return run_seed
	var s := get_seed()
	if s >= 0:
		run_seed = s
	return s


## Shop Continue: keep hearts/gold/items, load the next stage of the SAME run seed.
func next_stage() -> void:
	stage = get_stage() + 1
	_request_swap(get_run_seed(), stage, false)


func _request_swap(level_seed: int, at_stage: int, fresh: bool) -> void:
	if swap_deferred:
		_swap_scene.call_deferred(level_seed, at_stage, fresh)
	else:
		_swap_scene(level_seed, at_stage, fresh)


func _swap_scene(level_seed: int, at_stage: int, fresh: bool = false) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	tree.paused = false
	var gs := get_node_or_null(^"/root/GameState")
	if gs and gs.has_method(&"reset"):
		gs.reset()
	var cur := tree.current_scene
	if cur == null or cur.scene_file_path.is_empty():
		return
	var packed: PackedScene = load(cur.scene_file_path)
	var inst := packed.instantiate()
	if "level_seed" in inst:
		inst.set("level_seed", level_seed)   # -1 → the level rolls a new one
	if "stage" in inst:
		inst.set("stage", at_stage)
	var keep_h := health
	var keep_max := max_health
	var keep_g := gold
	reset()   # FE state incl. inventory items
	stage = at_stage
	if fresh:
		set_health(health, max_health)   # values already fresh from PlayerStats.reset()
		set_gold(gold)
	else:
		set_health(keep_h, keep_max)
		set_gold(keep_g)
	tree.root.remove_child(cur)
	cur.queue_free()
	tree.root.add_child(inst)
	tree.current_scene = inst
	if fresh and at_stage == 1 and run_seed < 0:
		run_seed = get_seed()   # the new level rolled its seed in _ready


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
	_chase_reported = false

extends RefCounted
## Pickup channel, inventory, throw, NoiseBus — Back End checks driven in a live tree.

var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["tap_does_not_start_pickup", test_tap_no_pickup],
		["hold_picks_up_after_pickup_time", test_hold_pickup],
		["out_of_range_cancels", test_out_of_range_cancels],
		["hit_cancels_pickup", test_hit_cancels],
		["release_early_cancels", test_release_cancels],
		["full_inventory_blocks", test_full_inventory],
		["empty_inventory_scroll_safe", test_empty_scroll],
		["tap_with_item_no_target_noop", test_tap_no_target],
		["throw_blocked_by_prop_makes_noise", test_throw_blocked],
		["miss_still_makes_noise", test_miss_noise],
		["noise_radius_offscreen_reach", test_noise_radius],
		["vase_defaults_vs_generic_override", test_defaults],
		["tap_never_targets_puppet", test_tap_not_puppet],
		["knock_noise_once", test_knock_noise_once],
		["knocked_prop_hits_enemy_where_it_lands", test_knock_lands_on_enemy],
		["player_and_puppet_never_block_each_other", test_layers],
		["puppet_catch_costs_heart_in_scene", test_catch_in_scene],
		["full_pickup_is_pickup_time_from_press", test_pickup_total_time],
	]
	var passed := 0
	for item in checks:
		_clean()
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	_clean()
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"bt_test"):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()
	FESignals.selected_enemy = null


func _add(n: Node, at: Vector2) -> Node:
	n.set_meta(&"bt_test", true)
	root.add_child(n)
	n.global_position = at
	return n


func _player(at := Vector2(100, 100)) -> CharacterBody2D:
	return _add(load("res://scripts/player/player_controller.gd").new(), at)


func _vase(at: Vector2) -> WorldObject:
	var v: WorldObject = load("res://scripts/world/vase.gd").new()
	v.break_on_touch = false
	v.gold_inside = 0
	return _add(v, at)


func _run(p: CharacterBody2D, secs: float, dir := Vector2.ZERO) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < secs:
		p.tick(dt, dir)
		t += dt


func test_tap_no_pickup() -> String:
	var p := _player()
	_vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.1); p.interact_released()
	return "" if p.inventory.items.is_empty() and p.state == p.State.NORMAL else "tap picked up"


func test_hold_pickup() -> String:
	var p := _player()
	_vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.2 + 0.5)
	if p.inventory.items.size() != 0: return "picked up too early"
	if p.state != p.State.PICKUP: return "not in pickup state"
	_run(p, 0.6)
	return "" if p.inventory.items.size() == 1 else "no item after hold"


func test_out_of_range_cancels() -> String:
	var p := _player()
	var v := _vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.5)
	v.global_position = Vector2(400, 100)
	_run(p, 0.05)
	return "" if p.state == p.State.NORMAL and p.pickup_progress == 0.0 else "did not cancel out of range"


func test_hit_cancels() -> String:
	var p := _player()
	_vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.5)
	PlayerStats.take_hit(1, true)
	return "" if p.state == p.State.NORMAL else "hit did not cancel"


func test_release_cancels() -> String:
	var p := _player()
	_vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.6); p.interact_released()
	return "" if p.state == p.State.NORMAL and p.inventory.items.is_empty() else "release kept progress"


func test_full_inventory() -> String:
	var p := _player()
	for i in int(PlayerStats.get_stat(&"inventory_slots")):
		p.inventory.add({id = str(i), throwable = true})
	_vase(Vector2(120, 100))
	p.interact_pressed(); _run(p, 0.4)
	return "" if p.state == p.State.NORMAL else "started pickup with full inventory"


func test_empty_scroll() -> String:
	var p := _player()
	p.inventory.cycle(1); p.inventory.cycle(-1)
	return "" if p.inventory.selected == -1 else "bad selection on empty"


func test_tap_no_target() -> String:
	var p := _player()
	p.inventory.add({id = "v", throwable = true})
	p.interact_pressed(); p.interact_released()
	return "" if p.inventory.items.size() == 1 else "threw with no target"


func test_throw_blocked() -> String:
	var heard := [0]
	var cb := func(_a, _r, _l, _s): heard[0] += 1
	NoiseBus.noise.connect(cb)
	var p := _player()
	var wall := _vase(Vector2(200, 80))   # blocking prop on the line
	var enemy: Node2D = _add(Node2D.new(), Vector2(300, 80))
	enemy.add_to_group("puppets")
	p.inventory.add({id = "v", throwable = true, noise_radius = 500.0})
	var t: Node2D = p.throw_at(enemy)
	for i in 120:
		if not is_instance_valid(t) or t.is_queued_for_deletion(): break
		t.step(1.0 / 60.0)
	NoiseBus.noise.disconnect(cb)
	if not is_instance_valid(enemy): return "enemy hit through prop"
	return "" if heard[0] >= 1 and wall.broken else "blocked throw made no noise"


func test_miss_noise() -> String:
	var heard := [0.0]
	var cb := func(_a, r, _l, _s): heard[0] = r
	NoiseBus.noise.connect(cb)
	var p := _player()
	var ghost: Node2D = _add(Node2D.new(), Vector2(300, 400))  # not an enemy: always a miss
	p.inventory.add({id = "v", throwable = true, noise_radius = 640.0})
	var t: Node2D = p.throw_at(ghost)
	for i in 240:
		if not is_instance_valid(t) or t.is_queued_for_deletion(): break
		t.step(1.0 / 60.0)
	NoiseBus.noise.disconnect(cb)
	return "" if is_equal_approx(heard[0], 640.0) else "miss noise radius %s" % heard[0]


func test_noise_radius() -> String:
	if not NoiseBus.can_hear(Vector2(0, 0), Vector2(700, 0), NoiseBus.DEFAULT_RADIUS):
		return "default radius does not reach just off screen"
	return "" if not NoiseBus.can_hear(Vector2(0, 0), Vector2(900, 0), NoiseBus.DEFAULT_RADIUS) else "radius unbounded"


func test_defaults() -> String:
	var v: WorldObject = load("res://scripts/world/vase.gd").new()
	var g: WorldObject = load("res://scripts/world/obstacle.gd").new()
	var ok: bool = v.can_pick_up and v.throwable and not g.can_pick_up and is_equal_approx(v.noise_radius, NoiseBus.DEFAULT_RADIUS)
	v.free(); g.free()
	return "" if ok else "WorldObject defaults/overrides wrong"


func _puppet(at: Vector2) -> Node2D:
	var e: Node2D = Node2D.new()
	e.add_to_group("puppets")
	e.set_script(null)
	return _add(e, at)


func test_tap_not_puppet() -> String:
	var p := _player()
	var e := _puppet(Vector2(115, 100))
	p.interact_pressed(); p.interact_released()
	return "" if is_instance_valid(e) and not e.is_queued_for_deletion() else "tap hit a puppet directly"


func test_knock_noise_once() -> String:
	var heard := [0]
	var cb := func(_a, _r, _l, _s): heard[0] += 1
	NoiseBus.noise.connect(cb)
	var p := _player()
	var g: WorldObject = load("res://scripts/world/obstacle.gd").new()
	g.break_on_touch = false
	_add(g, Vector2(120, 100))
	p.interact_pressed(); p.interact_released()
	NoiseBus.noise.disconnect(cb)
	return "" if heard[0] == 1 else "knock made %d noises" % heard[0]


func test_knock_lands_on_enemy() -> String:
	var p := _player()
	var g: WorldObject = load("res://scripts/world/obstacle.gd").new()
	g.break_on_touch = false
	_add(g, Vector2(120, 100))
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e, Vector2(148, 100))
	p.interact_pressed(); p.interact_released()
	return "" if e.is_queued_for_deletion() else "falling prop did not hit calm puppet"


func test_layers() -> String:
	var p := _player()
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e, Vector2(400, 400))
	if p.collision_mask & e.collision_layer: return "player collides with puppet"
	if e.collision_mask & p.collision_layer: return "puppet collides with player"
	return ""


## Real colliders (main.gd sizes: player r12, puppet r14), real move_and_slide.
func test_catch_in_scene() -> String:
	var p := _player(Vector2(100, 100))
	var pc := CollisionShape2D.new(); var c1 := CircleShape2D.new(); c1.radius = 12; pc.shape = c1; p.add_child(pc)
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	var ec := CollisionShape2D.new(); var c2 := CircleShape2D.new(); c2.radius = 14; ec.shape = c2; e.add_child(ec)
	_add(e, Vector2(160, 100))
	e._alert()
	for i in 120:
		e._physics_process(1.0 / 60.0)
		if PlayerStats.health < 3: break
	return "" if PlayerStats.health == 2 else "puppet never caught (hp %d, gap %.1f)" % [PlayerStats.health, e.global_position.distance_to(p.global_position)]


func test_pickup_total_time() -> String:
	var p := _player()
	_vase(Vector2(120, 100))
	p.interact_pressed()
	var t := 0.0
	while p.inventory.items.is_empty() and t < 3.0:
		p.tick(1.0 / 60.0, Vector2.ZERO); t += 1.0 / 60.0
	return "" if absf(t - PlayerStats.get_stat(&"pickup_time")) < 0.05 else "full pickup took %.2fs" % t

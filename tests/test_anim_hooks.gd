extends RefCounted
## Animation-state layer: player and enemy transitions + event emission.
## Visual only — does not change gameplay numbers.

const DT := 1.0 / 60.0
var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["map_falls_back_when_clip_missing", test_map_fallback],
		["map_uses_clip_once_present", test_map_prefers_new],
		["player_idle_walk_run", test_player_loco],
		["player_jump_rise_fall_land", test_player_air],
		["player_climb_carry_throw_hide", test_player_actions],
		["player_hurt_hit_caught", test_player_hurt],
		["player_footsteps_every_n_px", test_player_footsteps],
		["enemy_fsm_states_and_events", test_enemy_states],
		["enemy_reach_strike_at_36_frames", test_enemy_reach],
		["enemy_velocity_and_facing_exposed", test_enemy_blend],
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
		if c.has_meta(&"ah_test"):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()
	FESignals.selected_enemy = null


func _add(n: Node, at: Vector2 = Vector2(100, 100)) -> Node:
	n.set_meta(&"ah_test", true)
	root.add_child(n)
	if n is Node2D:
		(n as Node2D).global_position = at
	return n


func _player(at := Vector2(100, 100)) -> CharacterBody2D:
	return _add(load("res://scripts/player/player_controller.gd").new(), at)


func _puppet(at := Vector2(300, 100)) -> CharacterBody2D:
	return _add(load("res://scripts/enemies/puppet_hand.gd").new(), at)


func _watch(node: Node) -> Dictionary:
	var w := {"states": [], "events": []}
	node.anim_state_changed.connect(func(o: StringName, n: StringName) -> void:
		w.states.append([o, n]))
	node.anim_event.connect(func(e: StringName) -> void:
		w.events.append(e))
	return w


func test_map_fallback() -> String:
	var frames := SpriteFrames.new()
	frames.add_animation("boy_idle")
	frames.add_animation("boy_run")
	var m := AnimMap.player_map()
	if m.resolve(&"walk", frames, "boy_run") != "boy_run":
		return "missing boy_walk should fall back to boy_run, got %s" % m.resolve(&"walk", frames, "boy_run")
	if m.resolve(&"idle", frames, "boy_idle") != "boy_idle":
		return "idle should resolve to boy_idle"
	if m.resolve(&"hide", frames, "boy_idle") != "boy_idle":
		return "missing boy_hide should fall back to boy_idle"
	var em := AnimMap.enemy_map()
	var ef := SpriteFrames.new()
	ef.add_animation("puppet_calm")
	ef.add_animation("puppet_chase")
	if em.resolve(&"idle", ef, "puppet_calm") != "puppet_calm":
		return "enemy idle should fall back to puppet_calm"
	if em.resolve(&"search", ef, "puppet_chase") != "puppet_chase":
		return "enemy search should fall back to chase slot"
	return ""


func test_map_prefers_new() -> String:
	var frames := SpriteFrames.new()
	frames.add_animation("boy_run")
	frames.add_animation("boy_walk")
	var m := AnimMap.player_map()
	if m.resolve(&"walk", frames, "boy_run") != "boy_walk":
		return "boy_walk should win once present, got %s" % m.resolve(&"walk", frames, "boy_run")
	var ef := SpriteFrames.new()
	ef.add_animation("puppet_chase")
	ef.add_animation("search")
	var em := AnimMap.enemy_map()
	if em.resolve(&"search", ef, "puppet_chase") != "search":
		return "search clip should win once present"
	return ""


func test_player_loco() -> String:
	var p: CharacterBody2D = _player()
	p.side_scroll = true
	p.floor_override = 1
	p.velocity = Vector2.ZERO
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"idle":
		return "standing should be idle, got %s" % p.anim_hook.anim_state
	# Walk: slower than the run fraction of move_speed, still moving.
	p.velocity.x = p.move_speed() * 0.4
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"walk":
		return "slow move should be walk, got %s" % p.anim_hook.anim_state
	p.velocity.x = p.move_speed()
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"run":
		return "full speed should be run, got %s" % p.anim_hook.anim_state
	if p.anim_hook.normalized_speed < 0.99:
		return "normalized speed at cap should be ~1, got %s" % p.anim_hook.normalized_speed
	if p.anim_hook.velocity.x != p.velocity.x:
		return "hook velocity not exposed"
	p.facing = -1
	p.sync_anim(DT)
	if p.anim_hook.facing != -1:
		return "hook facing should follow the boy"
	# Placeholder walk clip is missing, so the sprite keeps boy_run.
	var spr: AnimatedSprite2D = p.get_node_or_null(^"Anim")
	if spr == null or String(spr.animation) != "boy_run":
		return "walk/run fallback should keep playing boy_run, got %s" % (spr.animation if spr else "none")
	return ""


func test_player_air() -> String:
	var p: CharacterBody2D = _player()
	p.side_scroll = true
	p.floor_override = 1
	p.velocity = Vector2.ZERO
	p.sync_anim(DT)
	var w := _watch(p)
	p.floor_override = 0
	p.velocity.y = -200.0
	p._check_landing()
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"jump":
		return "rising should be jump, got %s" % p.anim_hook.anim_state
	p.velocity.y = 200.0
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"fall":
		return "descending should be fall, got %s" % p.anim_hook.anim_state
	p.floor_override = 1
	p.velocity.y = 0.0
	p._check_landing()
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"land":
		return "touchdown should be land, got %s" % p.anim_hook.anim_state
	if not w.events.has(&"land"):
		return "land event missing: %s" % str(w.events)
	return ""


func test_player_actions() -> String:
	var p: CharacterBody2D = _player()
	p.side_scroll = true
	p.floor_override = 1
	p.state = p.State.CLIMB
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"climb":
		return "climb state missing, got %s" % p.anim_hook.anim_state
	p.state = p.State.NORMAL
	p.inventory.add({id = "v", throwable = true})
	p.velocity = Vector2.ZERO
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"carry_idle":
		return "standing with a vase should be carry_idle, got %s" % p.anim_hook.anim_state
	p.velocity.x = 80.0
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"carry_walk":
		return "moving with a vase should be carry_walk, got %s" % p.anim_hook.anim_state
	var w := _watch(p)
	var thrown: Node2D = p.throw_toward(Vector2(200, 100))
	if thrown:
		thrown.set_meta(&"ah_test", true)
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"throw":
		return "throw window should be throw, got %s" % p.anim_hook.anim_state
	if not w.events.has(&"throw_release"):
		return "throw_release event missing: %s" % str(w.events)
	p._throw_anim_left = 0.0
	p.hiding = true
	p.velocity = Vector2.ZERO
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"hide":
		return "hiding flag should be hide, got %s" % p.anim_hook.anim_state
	return ""


func test_player_hurt() -> String:
	var p: CharacterBody2D = _player()
	p.side_scroll = true
	p.floor_override = 1
	var w := _watch(p)
	if not PlayerStats.take_hit(1, true):
		return "take_hit failed"
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"hurt":
		return "damage should be hurt, got %s" % p.anim_hook.anim_state
	if not w.events.has(&"hit"):
		return "hit event missing: %s" % str(w.events)
	if not PlayerStats.take_hit(PlayerStats.health, true):
		return "lethal hit failed"
	p.sync_anim(DT)
	if p.anim_hook.anim_state != &"caught":
		return "death should be caught, got %s" % p.anim_hook.anim_state
	if not w.events.has(&"caught"):
		return "caught event missing: %s" % str(w.events)
	return ""


func test_player_footsteps() -> String:
	var p: CharacterBody2D = _player()
	p.side_scroll = true
	p.floor_override = 1
	p.velocity.x = p.move_speed()
	var w := _watch(p)
	p.sync_anim(DT)  # enter run
	var need := int(ceil(AnimHook.FOOTSTEP_PX / maxf(p.velocity.x * DT, 0.001)))
	for i in need + 2:
		p.sync_anim(DT)
	var n := 0
	for e in w.events:
		if e == &"footstep":
			n += 1
	if n < 1:
		return "expected at least one footstep after %d px of travel, events=%s" % [AnimHook.FOOTSTEP_PX, str(w.events)]
	return ""


func test_enemy_states() -> String:
	var e: CharacterBody2D = _puppet()
	e.sync_anim(0.0)
	if e.anim_hook.anim_state != &"idle":
		return "calm still should be idle, got %s" % e.anim_hook.anim_state
	e.velocity.x = e.walk_speed
	e.sync_anim(0.0)
	if e.anim_hook.anim_state != &"patrol":
		return "calm moving should be patrol, got %s" % e.anim_hook.anim_state
	var w := _watch(e)
	e._enter_startled()
	if e.anim_hook.anim_state != &"alert":
		return "STARTLED should be alert, got %s" % e.anim_hook.anim_state
	if not w.events.has(&"startle"):
		return "startle event missing: %s" % str(w.events)
	e._set_state(e.State.CHASE)
	if e.anim_hook.anim_state != &"chase":
		return "CHASE should be chase, got %s" % e.anim_hook.anim_state
	e._set_state(e.State.SEARCH)
	if e.anim_hook.anim_state != &"search":
		return "SEARCH should be search, got %s" % e.anim_hook.anim_state
	e._set_state(e.State.STUNNED)
	if e.anim_hook.anim_state != &"stunned":
		return "STUNNED should be stunned, got %s" % e.anim_hook.anim_state
	e._set_state(e.State.RATTLE)
	if e.anim_hook.anim_state != &"rattle":
		return "RATTLE should be rattle, got %s" % e.anim_hook.anim_state
	e._set_state(e.State.RECOVER)
	if e.anim_hook.anim_state != &"recover":
		return "RECOVER should be recover, got %s" % e.anim_hook.anim_state
	e._set_state(e.State.RETURN)
	if e.anim_hook.anim_state != &"patrol":
		return "RETURN should map to patrol, got %s" % e.anim_hook.anim_state
	# Placeholder art: search/recover still play the chase (or startle) slot, never crash.
	return ""


func test_enemy_reach() -> String:
	var e: CharacterBody2D = _puppet()
	# Default catch is hit_frame/fps = 0.6 s = 36 frames at 60 fps (or the 0.6 s fallback).
	if absf(e.reach_delay() - AnimHook.REACH_STRIKE_TIME) > 1e-4:
		return "expected default reach_delay 0.6 s (36 frames), got %s" % e.reach_delay()
	var w := _watch(e)
	e._enter_reach()
	if e.anim_hook.anim_state != &"reach_windup":
		return "REACH start should be reach_windup, got %s" % e.anim_hook.anim_state
	if not w.events.has(&"reach_windup"):
		return "reach_windup event missing: %s" % str(w.events)
	# 35 frames still in the wind-up.
	for i in AnimHook.REACH_STRIKE_FRAMES - 1:
		e._state_left = maxf(e._state_left - DT, 0.0)
		e.sync_anim(DT)
		if e.anim_hook.anim_state != &"reach_windup":
			return "frame %d should still be reach_windup, got %s" % [i + 1, e.anim_hook.anim_state]
	e._state_left = maxf(e._state_left - DT, 0.0)
	e.sync_anim(DT)
	if e.anim_hook.anim_state != &"reach_strike":
		return "frame 36 should be reach_strike, got %s (left=%s)" % [e.anim_hook.anim_state, e._state_left]
	if not w.events.has(&"reach_strike"):
		return "reach_strike event missing: %s" % str(w.events)
	return ""


func test_enemy_blend() -> String:
	var e: CharacterBody2D = _puppet()
	e.velocity.x = e.chase_speed
	e._set_state(e.State.CHASE)
	e.face_dir = -1
	e.sync_anim(0.0)
	if e.anim_hook.facing != -1:
		return "hook facing should follow face_dir (hysteresis lives in update_facing)"
	if absf(e.anim_hook.normalized_speed - 1.0) > 0.05:
		return "chase at cap should normalize near 1, got %s" % e.anim_hook.normalized_speed
	if e.anim_hook.velocity.x != e.velocity.x:
		return "hook velocity not exposed"
	return ""

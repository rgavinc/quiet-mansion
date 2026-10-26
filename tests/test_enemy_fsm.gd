extends RefCounted
## Enemy state machine (enemy_base.gd / puppet_hand.gd) — Back End checks, driven by tick().
## Real-physics movement (gravity, stairs, float, back-off) is in scene_enemy.gd.

const DT := 1.0 / 60.0
var root: Node


func run_all() -> Dictionary:
	root = (Engine.get_main_loop() as SceneTree).root
	var failures: PackedStringArray = []
	var checks := [
		["light_builds_startle_then_chase", test_light_startle],
		["player_lights_uses_cone_and_switch", test_player_lights],
		["light_leaving_resets_startle", test_light_resets],
		["noise_is_instant_chase_and_reports_fe", test_noise_chase],
		["noise_out_of_radius_ignored", test_noise_far],
		["noise_tracks_boy_without_sight", test_noise_tracks],
		["lost_sight_memory_drains_then_returns_home", test_memory_return],
		["sight_regained_refills_memory", test_memory_refill],
		["memory_drains_faster_when_farther", test_memory_distance],
		["several_enemies_chase_at_once", test_multi],
		["landed_hit_backs_off_no_hits_1_5s", test_recover],
		["throw_stuns_enraged_kills_calm", test_stun],
		["freed_chaser_leaves_no_fe_entries", test_freed],
		["enemy_def_plugs_in_float", test_def],
		["topdown_enemy_no_gravity", test_topdown],
		["stair_trigger_covers_both_floors_320px", test_stair_trigger],
		["player_climbs_from_anywhere_in_trigger", test_player_wide_trigger],
		["walker_enters_stair_from_wide_trigger", test_enemy_wide_trigger],
		["walker_paths_with_level_nav_when_set", test_fake_nav],
		["walker_uses_real_level_nav_if_present", test_real_nav],
		["startle_anim_plays_once_and_holds", test_startle_anim],
		["float_uses_chase_float_slot_or_falls_back", test_float_slot],
		["wide_15_tile_stair_player_and_walker_climb", test_wide_stair],
		["chase_count_live_enraged_truthful", test_live_count],
	]
	var passed := 0
	for item in checks:
		_clean()
		var r: Variant = item[1].call()
		# A runtime script error aborts the check and returns null: count it as a failure.
		var err: String = r if r is String else "script error (check returned %s)" % [r]
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	_clean()
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _clean() -> void:
	for c in root.get_children():
		if c.has_meta(&"fsm_test"):
			root.remove_child(c)
			c.free()
	PlayerStats.reset()
	GameState.reset()
	FESignals.reset()


func _add(n: Node, at: Vector2) -> Node:
	n.set_meta(&"fsm_test", true)
	root.add_child(n)
	n.global_position = at
	return n


func _player(at := Vector2(100, 100)) -> CharacterBody2D:
	return _add(load("res://scripts/player/player_controller.gd").new(), at)


func _puppet(at := Vector2(300, 100), sight := 1) -> CharacterBody2D:
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	_add(e, at)
	e.sight_override = sight
	e.tick(0.0)   # records home
	return e


## Moves by velocity by hand (no physics step in sync tests).
func _run(e: CharacterBody2D, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		e.tick(DT)
		e.global_position += e.velocity * DT
		t += DT
		if until.is_valid() and until.call():
			break
	return t


func test_light_startle() -> Variant:
	_player()
	var e := _puppet()
	e.lit_override = 1
	_run(e, 0.5)
	if e.state != e.State.CALM: return "chased before light_startle_time (state %d)" % e.state
	if absf(FESignals.get_startle(e) - 0.5) > 0.05: return "FE startle %.2f at 0.5s" % FESignals.get_startle(e)
	var saw_startled := [false]
	var t := 0.5 + _run(e, 2.0, func():
		if e.state == e.State.STARTLED: saw_startled[0] = true
		return e.state == e.State.CHASE)
	if e.state != e.State.CHASE: return "never chased (state %d)" % e.state
	if not saw_startled[0]: return "skipped STARTLED reaction"
	if t < 1.0 or t > 1.0 + e.startle_reaction_time + 0.1: return "chase after %.2fs" % t
	if not FESignals.chasing.has(e): return "report_chase(true) not sent"
	return ""


func test_player_lights() -> Variant:
	var p := _player(Vector2(100, 100))
	p.aim_dir = Vector2.RIGHT
	if not p.lights(Vector2(250, 110)): return "enemy ahead in range not lit"
	if p.lights(Vector2(-50, 100)): return "enemy behind lit"
	if p.lights(Vector2(100 + PlayerStats.get_stat(&"light_range") + 20, 100)): return "out of range lit"
	p.toggle_light()
	if p.lights(Vector2(250, 100)): return "lit with flashlight off"
	p.toggle_light()
	var e := _puppet(Vector2(250, 100))
	_run(e, 0.3)
	return "" if e.startle > 0.2 else "real cone did not build startle (%.2f)" % e.startle


func test_light_resets() -> Variant:
	_player()
	var e := _puppet()
	e.lit_override = 1
	_run(e, 0.6)
	e.lit_override = 0
	_run(e, DT)
	if e.startle != 0.0 or FESignals.get_startle(e) != 0.0: return "startle stayed %.2f" % e.startle
	e.lit_override = 1
	_run(e, 0.6)
	return "" if e.state == e.State.CALM else "startle carried over"


func test_noise_chase() -> Variant:
	_player()
	var e := _puppet(Vector2(500, 100))
	NoiseBus.emit_noise(Vector2(480, 100), 100.0)
	if e.state != e.State.CHASE: return "noise did not start a chase (state %d)" % e.state
	if not FESignals.chasing.has(e): return "FE chasing missing enemy"
	if FESignals.get_chase_memory(e) != 1.0: return "memory %.2f" % FESignals.get_chase_memory(e)
	if GameState.alerted_puppets != 1: return "alert not registered"
	_run(e, 0.2)
	return "" if e.velocity.x < 0.0 else "not moving to the boy"


func test_noise_far() -> Variant:
	_player()
	var e := _puppet(Vector2(900, 100))
	NoiseBus.emit_noise(Vector2(100, 100), 300.0)
	return "" if e.state == e.State.CALM and not FESignals.chasing.has(e) else "heard noise out of radius"


func test_noise_tracks() -> Variant:
	_player()
	var e := _puppet(Vector2(400, 100), 0)
	e.hear_noise()
	_run(e, e.noise_track_time - 0.2)
	if e.state != e.State.CHASE: return "lost the boy during noise tracking (state %d)" % e.state
	return "" if e.global_position.x < 400.0 - 100.0 else "did not close in (x %.0f)" % e.global_position.x


func test_memory_return() -> Variant:
	_player()
	var e := _puppet(Vector2(400, 100))
	e.hear_noise()
	_run(e, 0.5)
	e.sight_override = 0
	e._track_left = 0.0
	_run(e, 1.0)
	if e.state != e.State.SEARCH: return "not searching after losing sight (state %d)" % e.state
	var m := FESignals.get_chase_memory(e)
	if m <= 0.0 or m >= 1.0: return "FE memory not draining (%.2f)" % m
	if not FESignals.chasing.has(e): return "arrow dropped while still searching"
	_run(e, e.memory_time * 4.0, func(): return e.state == e.State.RETURN)
	if e.state != e.State.RETURN: return "never gave up (memory %.2f)" % e.memory
	if FESignals.chasing.has(e) or FESignals.get_chase_memory(e) != -1.0: return "FE chase entry not cleared on give-up"
	_run(e, 20.0, func(): return e.state == e.State.CALM)
	if e.state != e.State.CALM: return "never got home"
	return "" if e.global_position.distance_to(Vector2(400, 100)) < 8.0 else "calm away from home %s" % e.global_position


func test_memory_refill() -> Variant:
	_player()
	var e := _puppet(Vector2(400, 100))
	e.hear_noise()
	e._track_left = 0.0
	e.sight_override = 0
	_run(e, 2.0)
	e.sight_override = 1
	_run(e, DT)
	return "" if e.state == e.State.CHASE and FESignals.get_chase_memory(e) == 1.0 else "memory not refilled"


func test_multi() -> Variant:
	_player()
	var a := _puppet(Vector2(300, 100))
	var b := _puppet(Vector2(500, 100))
	NoiseBus.emit_noise(Vector2(400, 100), 300.0)
	return "" if FESignals.chasing.has(a) and FESignals.chasing.has(b) and FESignals.chasing.size() == 2 else "chasing %d" % FESignals.chasing.size()


func test_recover() -> Variant:
	var p := _player(Vector2(100, 100))
	var e := _puppet(Vector2(130, 100))
	e.hear_noise()
	e.on_landed_hit(p)
	if e.state != e.State.RECOVER: return "no recover after a hit"
	var t := 0.0
	var away := true
	while e.state == e.State.RECOVER and t < 3.0:
		e.tick(DT); e.global_position += e.velocity * DT; t += DT
		if e.state == e.State.RECOVER and e.velocity.x <= 0.0: away = false
	if not away: return "did not back away from the boy"
	if absf(t - e.recover_time) > 0.05: return "recovered after %.2fs" % t
	return "" if e.state == e.State.CHASE else "did not resume chase (state %d)" % e.state


func test_stun() -> Variant:
	_player()
	var e := _puppet()
	e.hear_noise()
	e.on_hit_by_throw({})
	if e.is_queued_for_deletion(): return "enraged puppet killed by throw"
	if e.state != e.State.STUNNED: return "not stunned"
	_run(e, 0.5)
	if e.velocity != Vector2.ZERO: return "moved while stunned"
	_run(e, 1.1)
	if e.state != e.State.CHASE: return "did not resume after stun (state %d)" % e.state
	var calm := _puppet(Vector2(600, 100))
	calm.on_hit_by_throw({})
	return "" if calm.is_queued_for_deletion() else "calm puppet survived a throw"


func test_freed() -> Variant:
	_player()
	var e := _puppet()
	e.lit_override = 1
	_run(e, 0.3)
	FESignals.report_lit(e, true)
	FESignals.select_enemy(e)
	e.hear_noise()
	var id := e.get_instance_id()
	root.remove_child(e)
	e.free()
	if not FESignals.chasing.is_empty(): return "chasing kept freed enemy"
	if FESignals.chase_memory.has(id) or FESignals.startle.has(id): return "memory/startle entry kept"
	return "" if FESignals.get_selected_enemy() == null else "selection kept"


func test_def() -> Variant:
	var src := GDScript.new()
	src.source_code = "extends Resource\nvar type_id := &\"floating_hand\"\nvar movement := &\"float\"\nvar chase_speed := 50.0\nvar give_up_distance := 900.0\n"
	if src.reload() != OK: return "def script failed"
	var d: Resource = src.new()
	var e: CharacterBody2D = load("res://scripts/enemies/puppet_hand.gd").new()
	e.def = d
	_add(e, Vector2(300, 100))
	if not e.is_floating() or e.chase_speed != 50.0: return "def not applied"
	if e.collision_mask & PlayerStats.LAYER_WORLD: return "float collides with floors"
	if not (e.collision_mask & PlayerStats.LAYER_PLAYER): return "float passes through the boy"
	return "" if FESignals.enemy_type_id(e) == "floating_hand" else "type id %s" % FESignals.enemy_type_id(e)


func test_topdown() -> Variant:
	_player()
	var e := _puppet()
	e.floor_override = 0
	e.hear_noise()
	e.tick(0.5)
	return "" if absf(e.velocity.y) < 0.01 else "top-down enemy fell"


# --- stairs: 320px trigger, LevelNav --------------------------------------------
func _stair_node(b := Vector2(300, 0), t := Vector2(396, -160)) -> Stair:
	var st: Stair = load("res://scripts/world/stair.gd").new()
	st.bottom = Vector2.ZERO
	st.top = t - b
	return _add(st, b)


func test_stair_trigger() -> Variant:
	var st := _stair_node()
	var r := st.global_trigger_rect()
	if absf(r.size.y - 322.0) > 0.5: return "trigger height %s (want 320 + 2px slab tolerance)" % r.size.y
	if not st.is_near(Vector2(340, -12)): return "lower floor, off the line: not detected"
	if not st.is_near(Vector2(390, -172)): return "upper floor at the top: not detected"
	if not st.is_near(Vector2(300, 0)): return "feet on the lower slab: not detected"
	if st.is_near(Vector2(340, -330)): return "detected above the upper band"
	if st.is_near(Vector2(500, -12)): return "detected beside the stair"
	var shape: CollisionShape2D = null
	for c in st.get_children():
		if c is CollisionShape2D: shape = c
	if shape == null or not (shape.shape is RectangleShape2D): return "Area2D shape is not the trigger rectangle"
	return "" if absf((shape.shape as RectangleShape2D).size.y - 322.0) < 0.5 else "shape height %s" % (shape.shape as RectangleShape2D).size.y


func test_player_wide_trigger() -> Variant:
	var st := _stair_node()
	var p := _player(Vector2(350, -12))   # lower floor, 30px+ off the stair line
	p.side_scroll = true
	p.floor_override = 1
	p.tick(DT, Vector2(0, -1))
	if p.state != p.State.CLIMB: return "did not start climbing from the wide trigger"
	for i in 600:
		p.tick(DT, Vector2(0, -1))
		if p.state != p.State.CLIMB: break
	if p.global_position.distance_to(st.global_top()) > 2.0: return "ended at %s" % p.global_position
	# and back down from the upper floor, off the line
	p.global_position = Vector2(392, -172)
	p.tick(DT, Vector2(0, 1))
	return "" if p.state == p.State.CLIMB else "did not start descending from the upper band"


func _walker(at: Vector2) -> CharacterBody2D:
	var e := _puppet(at)
	e.side_scroll = true
	e.floor_override = 1   # grounded (sync test: no physics step)
	return e


func test_enemy_wide_trigger() -> Variant:
	_stair_node()
	var p := _player(Vector2(700, -172))
	p.side_scroll = true
	var e := _walker(Vector2(520, -14))   # comes from the far side of the stair foot
	e.hear_noise()
	var started_x := INF
	var t := 0.0
	while t < 15.0:
		e.tick(DT)
		e.global_position += e.velocity * DT
		t += DT
		if e.climbing and started_x == INF:
			started_x = e.global_position.x
		if e.floor_of(e.global_position) == 1 and not e.climbing:
			break
	if started_x == INF: return "never committed to the stair"
	if started_x < 380.0: return "committed only at x=%.0f (thin line), trigger starts at 396" % started_x
	if e.floor_of(e.global_position) != 1: return "never reached floor 1 (at %s)" % e.global_position
	return "" if (e.global_position + Vector2(0, e._foot())).distance_to(Vector2(396, -160)) < 2.0 else "stepped off at %s" % e.global_position


class FakeNav:
	extends RefCounted
	var calls := 0
	func floor_of(p: Vector2) -> int:
		return 1 if p.y < -80.0 else 0
	func next_waypoint(a: Vector2, b: Vector2) -> Dictionary:
		calls += 1
		if floor_of(a) == floor_of(b):
			return {point = b}
		var bottom := Vector2(600, 0)
		var top := Vector2(696, -160)
		if floor_of(a) == 0:
			return {point = bottom, stair_to = top, stair = {from_floor = 0, to_floor = 1, bottom = bottom, top = top}}
		return {point = top, stair_to = bottom, stair = {from_floor = 0, to_floor = 1, bottom = bottom, top = top}}


func test_fake_nav() -> Variant:
	# A Stair node elsewhere must be ignored: with a nav, the nav's stair is the route.
	_stair_node(Vector2(100, 0), Vector2(196, -160))
	var p := _player(Vector2(900, -172))
	p.side_scroll = true
	var e := _walker(Vector2(300, -14))
	var nav := FakeNav.new()
	e.nav_override = nav
	e.hear_noise()
	var started := Vector2.INF
	var t := 0.0
	while t < 20.0:
		e.tick(DT)
		e.global_position += e.velocity * DT
		t += DT
		if e.climbing and started == Vector2.INF:
			started = e.global_position
		if e.floor_of(e.global_position) == 1 and not e.climbing:
			break
	if nav.calls == 0: return "nav never queried"
	if started == Vector2.INF: return "never climbed"
	if started.x < 560.0: return "climbed at x=%.0f, not the nav stair at 600" % started.x
	if e.floor_of(e.global_position) != 1: return "not on floor 1: %s" % e.global_position
	return "" if absf(e.global_position.y + e._foot() - (-160.0)) < 1.0 else "stood at y=%.1f after the hop" % e.global_position.y


## Only runs once Lead's LevelNav (PR #13) is in the tree; passes as a skip before that.
func test_real_nav() -> Variant:
	const NAV := "res://scripts/levelgen/level_nav.gd"
	const GEN := "res://scripts/levelgen/level_generator.gd"
	if not ResourceLoader.exists(NAV) or not ResourceLoader.exists(GEN):
		return ""
	var S: Script = load(NAV)
	var G: Script = load(GEN)
	var layout: Dictionary = {}
	for sd in range(1, 200):
		var L: Dictionary = G.call(&"generate", sd, 1)
		if int(L.get("floors", 1)) >= 2 and not (L.get("stairs", []) as Array).is_empty():
			layout = L
			break
	if layout.is_empty(): return "no 2-floor layout in seeds 1..199"
	var nav: Object = S.call(&"from_layout", layout)
	S.set(&"current", nav)
	var e := _walker(Vector2.ZERO)
	var got: Object = e.level_nav()
	var err := ""
	if got != nav:
		err = "LevelNav.current not picked up"
	else:
		var st: Dictionary = nav.stairs[0]
		e.global_position = st.bottom - Vector2(0, 14)
		var p := _player(st.top - Vector2(0, 12))
		p.side_scroll = true
		e.hear_noise()
		_run(e, 30.0, func(): return e.floor_of(e.global_position) == int(st.to_floor) and not e.climbing)
		if e.floor_of(e.global_position) != int(st.to_floor):
			err = "walker didn't reach floor %d via LevelNav (at %s)" % [st.to_floor, e.global_position]
	S.set(&"current", null)
	return err


func test_startle_anim() -> Variant:
	_player()
	var e := _puppet()
	var spr: AnimatedSprite2D = e.get_node_or_null("Anim")
	if spr == null or spr.sprite_frames == null: return "no AnimatedSprite2D"
	var slot := String(e.anim_startle)
	if not spr.sprite_frames.has_animation(slot): return "" # art missing: nothing to hold
	var want := int(AnimLibrary.meta(slot).get("frames", 1))
	var n := spr.sprite_frames.get_frame_count(slot)
	if n != want: return "startle has %d frames, manifest says %d" % [n, want]
	if spr.sprite_frames.get_animation_loop(slot): return "startle loops"
	e._enter_startled()
	if spr.animation != slot: return "STARTLED plays %s" % spr.animation
	spr.frame = n - 1                       # as if it played through
	e.on_hit_by_throw({})                   # enraged -> STUNNED
	if e.state != e.State.STUNNED: return "not stunned"
	if spr.animation != slot or spr.frame != n - 1: return "STUNNED restarted the startle (%s f%d)" % [spr.animation, spr.frame]
	e.hear_noise()                          # stays stunned, still holding
	if spr.frame != n - 1: return "noise restarted the hold"
	e.state = e.State.CHASE
	e._set_state(e.State.CHASE)
	return "" if spr.animation == e.chase_slot() else "chase plays %s" % spr.animation


func test_float_slot() -> Variant:
	_player()
	var e := _puppet()
	if e.chase_slot() != "puppet_chase": return "walker chase slot %s" % e.chase_slot()
	e.movement = &"float"
	var want := "puppet_chase_float" if AnimLibrary.has_slot("puppet_chase_float") else "puppet_chase"
	return "" if e.chase_slot() == want else "float chase slot %s, want %s" % [e.chase_slot(), want]


## Any stair width / angle: everything comes from bottom/top (Lead may go to ~15 tiles).
func test_wide_stair() -> Variant:
	var b := Vector2(300, 0)
	var t := Vector2(540, -160)   # 15 tiles of run
	var st := _stair_node(b, t)
	var r := st.global_trigger_rect()
	if r.position.x > 300.0 or r.end.x < 540.0: return "trigger x %s doesn't span the run" % r
	var p := _player(Vector2(500, -12))   # lower floor, near the far end of the run
	p.side_scroll = true
	p.floor_override = 1
	p.tick(DT, Vector2(0, -1))
	if p.state != p.State.CLIMB: return "player can't enter a wide stair from the far end"
	var max_step := 0.0
	for i in 1200:
		var before := p.global_position
		p.tick(DT, Vector2(0, -1))
		max_step = maxf(max_step, before.distance_to(p.global_position))
		if p.state != p.State.CLIMB: break
	if max_step > 20.0: return "player snapped %.0fpx onto the stair" % max_step
	if p.global_position.distance_to(t) > 2.0: return "player ended at %s" % p.global_position
	p.global_position = Vector2(900, -172)
	var e := _walker(Vector2(150, -14))
	e.hear_noise()
	_run(e, 20.0, func(): return e.floor_of(e.global_position) == 1 and not e.climbing)
	if e.floor_of(e.global_position) != 1: return "walker didn't climb the wide stair (at %s)" % e.global_position
	return "" if (e.global_position + Vector2(0, e._foot())).distance_to(t) < 2.0 else "walker stepped off at %s" % e.global_position


func test_live_count() -> Variant:
	_player()
	var es: Array = []
	for i in 5:
		es.append(_puppet(Vector2(300 + 40 * i, 100)))
	var calm_enraged := (es[0] as Node).get("enraged") as bool
	es[0].lit_override = 1
	es[0]._enter_startled()
	var startled_enraged: bool = es[0].enraged
	for e in es:
		e.hear_noise()
	var n := GameState.chasing_count()
	var fe := FESignals.chasing_count()
	es[1]._enter_return()
	var after := GameState.chasing_count()
	if calm_enraged: return "calm puppet reports enraged"
	if startled_enraged: return "startled (not yet chasing) reports enraged"
	if n != 5 or fe != 5: return "5 chasers counted as GameState %d / FE %d (cap?)" % [n, fe]
	if es[1].enraged or after != 4: return "gave-up puppet still enraged/counted (%d)" % after
	return "" if GameState.enemy_count() == 5 else "enemy_count %d" % GameState.enemy_count()


func test_memory_distance() -> Variant:
	_player(Vector2(0, 100))
	var near := _puppet(Vector2(200, 100))
	var far := _puppet(Vector2(1800, 100))
	for e in [near, far]:
		e.hear_noise()
		e.sight_override = 0
		e._track_left = 0.0
		e.chase_speed = 0.0   # keep the distances fixed
	for i in 60:
		near.tick(DT)
		far.tick(DT)
	if not (far.memory < near.memory): return "far %.2f not below near %.2f after 1s" % [far.memory, near.memory]
	return "" if absf(FESignals.get_chase_memory(far) - far.memory) < 0.001 else "FE memory not reported"

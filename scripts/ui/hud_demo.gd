extends Node2D
## FE debug demo — fakes Back End so every FE piece can be seen without the
## foundation. NOT game logic: the fake enemies/pickup here are throwaway.
##
## Controls (input-map actions): A/D move · mouse aims · RMB flashlight_toggle ·
## hold LMB `interact` near the vase = pickup · tap LMB = throw held vase at the
## ringed enemy · scroll inv_next/inv_prev.
## DEBUG-ONLY keys (demo only, not game controls): H hit, J heal, G +gold,
## C make the far enemy chase, R reset.

const WORLD_W := 3200.0
const FLOOR_Y := 560.0
const LIGHT_RANGE := 300.0
const LIGHT_HALF_ANGLE := deg_to_rad(22.0)
const PICKUP_RANGE := 70.0
const CHASE_SPEED := 90.0
const MOVE_SPEED := 220.0

var bus: Node
var player: CharacterBody2D
var light_pivot: Node2D
var enemies: Array[CharacterBody2D] = []
var homes: Dictionary = {}
var vases: Array[Node2D] = []
var _press_time: float = -1.0
var _pickup_target: Node2D = null
var _pickup_t: float = 0.0
var _help: Label


func _ready() -> void:
	bus = get_node_or_null("/root/FESignals")
	bus.reset()
	bus.placeholder_input_enabled = true
	bus.give_up_distance = 1400.0
	bus.flashlight_toggled.connect(_on_flashlight)
	_build_world()
	bus.set_health(3, 3)
	bus.set_gold(12)
	bus.set_items([])   # empty hands: tap knocks, hold picks up
	_on_flashlight(bus.flashlight_on)


func _exit_tree() -> void:
	if bus:
		bus.placeholder_input_enabled = false


func _build_world() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.13, 0.18)
	bg.size = Vector2(WORLD_W, 1400)
	bg.position = Vector2(0, -400)
	bg.z_index = -20
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$World.add_child(bg)
	var dark := CanvasModulate.new()
	dark.color = Color(0.12, 0.11, 0.16)
	$World.add_child(dark)
	_wall(Rect2(0, FLOOR_Y, WORLD_W, 400), Color(0.3, 0.22, 0.18))
	_wall(Rect2(760, FLOOR_Y - 120, 30, 120), Color(0.35, 0.3, 0.3))   # pillar blocks throws
	_wall(Rect2(1500, FLOOR_Y - 60, 50, 60), Color(0.4, 0.3, 0.2))      # crate
	# Boy
	player = CharacterBody2D.new()
	player.name = "Boy"
	player.add_to_group("player")
	player.position = Vector2(300, FLOOR_Y - 26)
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 12; cap.height = 52
	col.shape = cap
	player.add_child(col)
	var body := Polygon2D.new()
	body.color = Color(0.85, 0.75, 0.6)
	body.polygon = PackedVector2Array([Vector2(-12, 26), Vector2(-12, -14), Vector2(0, -26), Vector2(12, -14), Vector2(12, 26)])
	player.add_child(body)
	light_pivot = Node2D.new()
	light_pivot.name = "Flashlight"
	player.add_child(light_pivot)
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.texture = _cone_texture()
	beam.offset = Vector2(150, 0)
	beam.energy = 1.4
	beam.color = Color(1, 0.95, 0.75)
	light_pivot.add_child(beam)
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.limit_left = 0
	cam.limit_right = int(WORLD_W)
	cam.position_smoothing_enabled = true
	player.add_child(cam)
	$World.add_child(player)
	# Enemies: two puppet hands, one unknown type (default ring colour), one far away.
	var specs := [[Vector2(620, FLOOR_Y - 28), "puppet_hand"], [Vector2(1150, FLOOR_Y - 28), "puppet_hand"],
		[Vector2(1800, FLOOR_Y - 28), "crawler"], [Vector2(2900, FLOOR_Y - 28), "puppet_hand"]]
	for sp in specs:
		var e := CharacterBody2D.new()
		e.set_meta("enemy_type", sp[1])
		e.position = sp[0]
		var ec := CollisionShape2D.new()
		var circ := CircleShape2D.new(); circ.radius = 18
		ec.shape = circ
		e.add_child(ec)
		var hand := Polygon2D.new()
		hand.name = "Body"
		hand.color = Color(0.75, 0.6, 0.65) if sp[1] == "puppet_hand" else Color(0.55, 0.7, 0.55)
		hand.polygon = PackedVector2Array([Vector2(-16, 26), Vector2(-18, -6), Vector2(-10, -26), Vector2(-3, -10), Vector2(2, -28), Vector2(8, -10), Vector2(16, -22), Vector2(18, 26)])
		e.add_child(hand)
		$World.add_child(e)
		enemies.append(e)
		homes[e.get_instance_id()] = e.position
	# Vases (props: block throws, can be picked up)
	for x in [480.0, 980.0, 1350.0]:
		var v := StaticBody2D.new()
		v.name = "Vase"
		v.position = Vector2(x, FLOOR_Y - 16)
		var vc := CollisionShape2D.new()
		var vr := RectangleShape2D.new(); vr.size = Vector2(20, 32)
		vc.shape = vr
		v.add_child(vc)
		var vp := Polygon2D.new()
		vp.color = Color(0.4, 0.55, 0.8)
		vp.polygon = PackedVector2Array([Vector2(-6, -16), Vector2(6, -16), Vector2(10, 0), Vector2(6, 16), Vector2(-6, 16), Vector2(-10, 0)])
		v.add_child(vp)
		$World.add_child(v)
		vases.append(v)
	_help = Label.new()
	_help.text = "A/D move · mouse aim · RMB light on/off · hold LMB on vase = pickup · tap LMB = throw (held + ringed) / knock (empty hands) · wheel = items\n[debug] H hit · J heal · G +gold · C far enemy chases · R reset"
	_help.position = Vector2(16, 70)
	_help.add_theme_font_size_override("font_size", 14)
	$HUD.add_child(_help)


func _wall(r: Rect2, c: Color) -> void:
	var b := StaticBody2D.new()
	b.position = r.get_center()
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new(); rs.size = r.size
	cs.shape = rs
	b.add_child(cs)
	var vis := ColorRect.new()
	vis.color = c
	vis.size = r.size
	vis.position = -r.size * 0.5
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vis)
	$World.add_child(b)


func _on_flashlight(on: bool) -> void:
	if light_pivot:
		light_pivot.visible = on


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var dir := Input.get_axis("move_left", "move_right")
	if _pickup_target != null:
		dir = 0.0   # locked into the pickup channel
	player.velocity = Vector2(dir * MOVE_SPEED, 0)
	player.move_and_slide()
	player.position.x = clampf(player.position.x, 20, WORLD_W - 20)
	light_pivot.look_at(get_global_mouse_position())
	_update_light()
	_update_enemies(delta)
	_update_pickup(delta)


func _update_light() -> void:
	var aim := (get_global_mouse_position() - player.global_position).normalized()
	var best: Node2D = null
	var best_ang := INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var to := e.global_position - player.global_position
		var ang := absf(aim.angle_to(to.normalized()))
		var in_beam: bool = bus.flashlight_on and to.length() <= LIGHT_RANGE and ang <= LIGHT_HALF_ANGLE
		bus.report_lit(e, in_beam and not bus.chasing.has(e))
		if in_beam and ang < best_ang:
			best_ang = ang
			best = e
	if best != null:
		bus.select_enemy(best)   # hover moves selection; light-off keeps it


func _update_enemies(delta: float) -> void:
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var p: float = bus.get_startle(e)
		var body := e.get_node("Body") as Polygon2D
		body.scale = Vector2.ONE * (1.0 + 0.12 * p * sin(Time.get_ticks_msec() * 0.05))
		if p >= 1.0 and not bus.chasing.has(e):
			bus.report_lit(e, false)
			bus.report_startle(e, 0.0)
			bus.report_chase(e, true)
		if bus.chasing.has(e):
			var d := e.global_position.distance_to(player.global_position)
			if d > bus.give_up_distance:
				bus.report_chase(e, false)   # gave up → walk home
			else:
				e.velocity = Vector2(signf(player.global_position.x - e.global_position.x) * CHASE_SPEED, 0)
				e.move_and_slide()
				if d < 30.0:
					_hit_player(e)
		else:
			var home: Vector2 = homes[e.get_instance_id()]
			e.position = e.position.move_toward(home, CHASE_SPEED * 0.6 * delta)


func _hit_player(e: Node2D) -> void:
	bus.set_health(bus.health - 1)
	e.position.x += signf(e.global_position.x - player.global_position.x) * 160.0
	if bus.health <= 0:
		bus.set_health(bus.max_health)


func _nearest_vase() -> Node2D:
	var best: Node2D = null
	for v in vases:
		if is_instance_valid(v) and v.global_position.distance_to(player.global_position) <= PICKUP_RANGE:
			if best == null or v.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = v
	return best


func _update_pickup(delta: float) -> void:
	if _press_time < 0.0:
		return
	_press_time += delta
	# Like BE's player_controller: the pickup channel only starts once LMB has
	# been held past tap_threshold, so a tap never starts it (or shows the gauge).
	if _pickup_target == null and _press_time >= bus.tap_threshold and _press_time - delta < bus.tap_threshold:
		var v := _nearest_vase()
		if v:
			_pickup_target = v
			_pickup_t = 0.0
			bus.report_pickup_started(v)
	if _pickup_target != null:
		if not is_instance_valid(_pickup_target) or _pickup_target.global_position.distance_to(player.global_position) > PICKUP_RANGE:
			_cancel_pickup()
			return
		_pickup_t += delta
		bus.report_pickup_progress(_pickup_t / maxf(bus.pickup_time, 0.01))
		if _pickup_t >= bus.pickup_time:
			vases.erase(_pickup_target)
			_pickup_target.queue_free()
			_pickup_target = null
			_press_time = -1.0
			bus.report_pickup_completed()
			var it: Array = bus.items.duplicate()
			it.append({"id": "vase_%d" % Time.get_ticks_msec(), "slot": "vase", "name": "Vase", "throwable": true})
			bus.set_items(it)
			bus.select_item(it.size() - 1)


func _cancel_pickup() -> void:
	_pickup_target = null
	bus.report_pickup_cancelled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_press_time = 0.0
	elif event.is_action_released("interact"):
		var was_tap: bool = _press_time >= 0.0 and _press_time < bus.tap_threshold
		if _pickup_target != null:
			_cancel_pickup()
		if was_tap:
			_on_tap()
		_press_time = -1.0
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:   # DEBUG ONLY
			KEY_H: bus.set_health(bus.health - 1)
			KEY_J: bus.set_health(bus.health + 1)
			KEY_G: bus.set_gold(bus.gold + 5)
			KEY_C:
				var far := enemies[enemies.size() - 1]
				if is_instance_valid(far):
					far.position.x = player.position.x + 900.0
					bus.report_chase(far, true)
			KEY_R: get_tree().reload_current_scene()


## Tap LMB: holding something → throw at the ringed enemy (nothing ringed → do
## nothing); empty hands → knock over a prop in range.
func _on_tap() -> void:
	if bus.is_holding():
		_try_throw()
	else:
		_try_knock()


func _try_knock() -> void:
	var v := _nearest_vase()
	if v == null:
		return
	vases.erase(v)
	v.queue_free()
	# Placeholder NoiseBus: the crash wakes nearby enemies.
	for e in enemies:
		if is_instance_valid(e) and e.global_position.distance_to(v.global_position) < 260.0:
			bus.report_chase(e, true)


func _try_throw() -> void:
	var e: Node2D = bus.selected_enemy
	if not bus.can_throw():
		return   # nothing ringed: never errors, never auto-throws
	var line = $World/WorldOverlay.throw_line
	var items: Array = bus.items.duplicate()
	items.remove_at(bus.selected_index)
	bus.set_items(items)
	if line and not line.blocked:
		bus.report_chase(e, false)
		e.position.x += signf(e.global_position.x - player.global_position.x) * 120.0
	# Blocked or hit, the shatter is loud: wake the target (placeholder for NoiseBus).
	bus.report_chase(e, true)


static func _cone_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 300
	t.height = 220
	return t

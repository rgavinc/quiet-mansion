extends CharacterBody2D
## Player: move, flashlight (RMB toggle), LMB tap = throw held item at the ringed enemy
## (or knock a prop with empty hands), LMB hold = pickup channel, wheel = inventory.
## Every number comes from PlayerStats. Back End owns.

enum State { NORMAL, PICKUP }

@export var knock_range: float = 36.0

var state: State = State.NORMAL
var facing: int = 1  # 1 right, -1 left
var inventory: Inventory
var pickup_target: WorldObject = null
var pickup_progress: float = 0.0

var _interact_down: bool = false
var _interact_held: float = 0.0
var _hp_seen: int = -1


func _ready() -> void:
	add_to_group("player")
	var spr := Sprite2D.new()
	var tex := load("res://assets/art/characters/boy_side_idle.png")
	if tex:
		spr.texture = tex
	add_child(spr)
	var light := Node2D.new()
	light.name = "Flashlight"
	light.set_script(load("res://scripts/player/flashlight.gd"))
	add_child(light)
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	_hp_seen = PlayerStats.health
	PlayerStats.health_changed.connect(_on_health_changed)


func light_on() -> bool:
	var l := get_node_or_null(^"Flashlight")
	return l != null and l.visible


func _physics_process(delta: float) -> void:
	if GameState.game_over:
		velocity = Vector2.ZERO
		return
	tick(delta, Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"))
	move_and_slide()


## All per-frame logic, separate from input polling so tests can drive it.
func tick(delta: float, dir: Vector2) -> void:
	if _interact_down:
		_interact_held += delta
		if state == State.NORMAL and _interact_held >= PlayerStats.get_stat(&"tap_threshold"):
			_try_start_pickup()
	match state:
		State.PICKUP:
			velocity = Vector2.ZERO  # locked in: no moving, no light
			_tick_pickup(delta)
		_:
			if dir.x != 0.0:
				facing = 1 if dir.x > 0.0 else -1
			velocity = dir * PlayerStats.get_stat(&"move_speed")
			_update_hover_select()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	if event.is_action_pressed(&"flashlight_toggle"):
		toggle_light()
	elif event.is_action_pressed(&"interact"):
		interact_pressed()
	elif event.is_action_released(&"interact"):
		interact_released()
	elif event.is_action_pressed(&"inv_next"):
		inventory.cycle(1)
	elif event.is_action_pressed(&"inv_prev"):
		inventory.cycle(-1)


func toggle_light() -> void:
	if state == State.PICKUP:
		return
	var light := get_node_or_null(^"Flashlight")
	if light:
		light.visible = not light.visible
		FESignals.set_flashlight(light.visible)


func interact_pressed() -> void:
	_interact_down = true
	_interact_held = 0.0


func interact_released() -> void:
	if not _interact_down:
		return
	_interact_down = false
	if state == State.PICKUP:
		_cancel_pickup()  # let go early = lose progress
		return
	if _interact_held < PlayerStats.get_stat(&"tap_threshold"):
		_tap()


# --- tap: throw or knock ----------------------------------------------------
func _tap() -> void:
	var held := inventory.current()
	if not held.is_empty():
		var tgt: Node2D = FESignals.selected_enemy
		if held.get("throwable", false) and is_instance_valid(tgt):
			throw_at(tgt)
		return  # holding something with no ringed enemy: tap does nothing
	_try_knock()


func throw_at(tgt: Node2D) -> Node2D:
	var it := inventory.take_current()
	if it.is_empty():
		return null
	var t := Node2D.new()
	t.set_script(load("res://scripts/world/thrown_object.gd"))
	get_parent().add_child(t)
	t.setup(global_position + Vector2(0, -20), it, tgt, self)
	return t


## Empty hands: knock over the ONE nearest prop in range on the side you face.
func _try_knock() -> void:
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("obstacles") + get_tree().get_nodes_in_group("puppets"):
		if not (node is Node2D):
			continue
		var to := (node as Node2D).global_position - global_position
		var d := to.length()
		if d > knock_range or to.x * facing < -4.0:
			continue
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return
	if best.has_method("break_apart"):
		best.break_apart()
	elif best.has_method("try_knock_kill") and not best.try_knock_kill():
		NoiseBus.emit_noise(global_position, 240.0 * PlayerStats.get_stat(&"noise_mult"), 0.6, self)


# --- hold: pickup channel ---------------------------------------------------
func _nearest_pickup() -> WorldObject:
	var best: WorldObject = null
	var best_d := PlayerStats.get_stat(&"pickup_range")
	for o in get_tree().get_nodes_in_group("world_objects"):
		if o is WorldObject and o.can_pick_up and not o.broken:
			var d := global_position.distance_to(o.global_position)
			if d <= best_d:
				best_d = d
				best = o
	return best


func _try_start_pickup() -> void:
	if inventory.is_full():
		return
	var t := _nearest_pickup()
	if t == null:
		return
	state = State.PICKUP
	pickup_target = t
	pickup_progress = 0.0
	FESignals.report_pickup_started(t)


func _tick_pickup(delta: float) -> void:
	if not is_instance_valid(pickup_target) or pickup_target.broken \
			or global_position.distance_to(pickup_target.global_position) > PlayerStats.get_stat(&"pickup_range"):
		_cancel_pickup()
		return
	var dur := maxf(PlayerStats.get_stat(&"pickup_time") * pickup_target.pickup_time_mult, 0.05)
	pickup_progress = minf(pickup_progress + delta / dur, 1.0)
	FESignals.report_pickup_progress(pickup_progress)
	if pickup_progress >= 1.0:
		_complete_pickup()


func _complete_pickup() -> void:
	var t := pickup_target
	state = State.NORMAL
	pickup_target = null
	if inventory.add(t.to_item()):
		t.broken = true  # removed from world silently
		t.queue_free()
	FESignals.report_pickup_completed()


func _cancel_pickup() -> void:
	if state != State.PICKUP:
		return
	state = State.NORMAL
	pickup_target = null
	pickup_progress = 0.0
	FESignals.report_pickup_cancelled()


func _on_health_changed(current: int, _max: int) -> void:
	if current < _hp_seen:
		_cancel_pickup()  # getting hit breaks the channel
	_hp_seen = current


# --- flashlight hover-select ------------------------------------------------
## Mouse over an enemy inside the lit cone selects it (ring). The last selection stays
## when the light goes off; hovering another enemy replaces it.
func _update_hover_select() -> void:
	if not light_on() or not is_inside_tree():
		return
	var mouse := get_global_mouse_position()
	var aim := (mouse - global_position)
	var rng := PlayerStats.get_stat(&"light_range")
	var half := deg_to_rad(PlayerStats.get_stat(&"light_angle_deg") * 0.5)
	for e in get_tree().get_nodes_in_group("puppets"):
		if not (e is Node2D):
			continue
		var to: Vector2 = e.global_position - global_position
		var lit := to.length() <= rng and absf(aim.angle_to(to)) <= half
		FESignals.report_lit(e, lit)
		if lit and e.global_position.distance_to(mouse) <= 28.0:
			FESignals.select_enemy(e)

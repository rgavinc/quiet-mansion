extends Node2D
## Per-stage atmosphere in FE overlay layers: drifting motes in the flashlight beam,
## plus a cheap room layer (dust on 1–2, cobweb drift on 3, faint fog on 4–5).

var skin: HudSkin
var bus: Node
var beam_motes: CPUParticles2D
var room: CPUParticles2D
var _flash: Node2D
var _stage: int = 1


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)
	if bus and bus.has_method(&"get_stage"):
		_stage = int(bus.get_stage())
	_ensure_particles()
	_apply_stage(_stage)
	call_deferred(&"_hook_flashlight")


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	# If motes were reparented onto the flashlight, free them with us if still ours.
	if beam_motes and is_instance_valid(beam_motes) and beam_motes.get_parent() != self:
		beam_motes.queue_free()


func _on_stage(n: int) -> void:
	_stage = n
	_apply_stage(n)
	call_deferred(&"_hook_flashlight")


func _ensure_particles() -> void:
	if beam_motes == null:
		beam_motes = _make_particles("BeamMotes")
		add_child(beam_motes)
	if room == null:
		room = _make_particles("RoomMotes")
		add_child(room)


func _make_particles(nm: String) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = nm
	p.emitting = false
	p.local_coords = true
	p.one_shot = false
	p.explosiveness = 0.0
	p.lifetime = 2.4
	p.preprocess = 1.0
	p.speed_scale = 1.0
	p.direction = Vector2(1, 0)
	p.spread = 18.0
	p.gravity = Vector2(0, 4)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 18.0
	var tex := UiArt.texture(skin.mote_slot) if skin else null
	if tex:
		p.texture = tex
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	return p


func _hook_flashlight() -> void:
	if not is_inside_tree():
		return
	var pl := get_tree().get_first_node_in_group(&"player") as Node
	_flash = pl.get_node_or_null(^"Flashlight") as Node2D if pl else null
	if _flash and beam_motes and beam_motes.get_parent() != _flash:
		beam_motes.reparent(_flash)
		beam_motes.position = Vector2(24, 0)
		beam_motes.rotation = 0
		beam_motes.emitting = true
		beam_motes.amount = maxi(skin.mote_amount, 4)
		beam_motes.lifetime = 1.6
		beam_motes.direction = Vector2(1, 0)
		beam_motes.spread = 16.0
		beam_motes.initial_velocity_min = 18.0
		beam_motes.initial_velocity_max = 46.0
		beam_motes.gravity = Vector2(0, 8)
		beam_motes.color = Color(1.0, 0.95, 0.8, 0.55)


func _apply_stage(stage: int) -> void:
	if room == null or skin == null:
		return
	room.emitting = true
	room.amount = 12
	room.lifetime = 3.5
	room.preprocess = 2.0
	room.local_coords = false   # world space, zoom-agnostic
	room.spread = 180.0
	room.direction = Vector2(1, 0)
	room.gravity = Vector2(0, 2)
	room.initial_velocity_min = 4.0
	room.initial_velocity_max = 12.0
	room.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var bounds := _world_bounds()
	room.global_position = bounds.get_center()
	room.emission_rect_extents = bounds.size * 0.5
	# Dust (1–2), cobweb drift (3), faint fog (4–5).
	if stage <= 2:
		room.color = skin.stage_dust_color
		room.amount = 14
		room.gravity = Vector2(0, 6)
		room.scale_amount_min = 0.4
		room.scale_amount_max = 0.9
	elif stage == 3:
		room.color = skin.stage_cobweb_color
		room.amount = 10
		room.direction = Vector2(1, 0.05)
		room.spread = 8.0
		room.gravity = Vector2(0, 0.5)
		room.initial_velocity_min = 8.0
		room.initial_velocity_max = 16.0
		room.lifetime = 5.0
		room.scale_amount_min = 0.7
		room.scale_amount_max = 1.6
	else:
		room.color = skin.stage_fog_color
		room.amount = 8
		room.spread = 180.0
		room.gravity = Vector2(0, 0)
		room.initial_velocity_min = 3.0
		room.initial_velocity_max = 8.0
		room.lifetime = 6.0
		room.scale_amount_min = 1.6
		room.scale_amount_max = 3.2
	if bus and bus.has_method(&"get_stage"):
		_stage = int(bus.get_stage())


func _world_bounds() -> Rect2:
	if is_inside_tree() and LevelNav.current != null and not LevelNav.current.layout.is_empty():
		return LevelValidator.level_bounds(LevelNav.current.layout)
	return Rect2(0, -480, 1280, 640)


func stage_kind(stage: int = -1) -> StringName:
	var s := _stage if stage < 0 else stage
	if s <= 2:
		return &"dust"
	if s == 3:
		return &"cobweb"
	return &"fog"

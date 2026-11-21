extends Node2D
## Hangs world-space juice on BE animation hooks (#65): footstep/land dust, a
## modest land shake, and a hit-flash cue. Connects to `anim_event` /
## `anim_state_changed` on the boy (and puppets) with has_signal guards so an
## older build without the hooks is harmless.

var skin: HudSkin
var bus: Node
var last_event: StringName = &""
var last_dust: int = 0
var _hooked: Array = []   # nodes we connected to
var _dust: Array = []


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)
	call_deferred(&"rebind")


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	_unhook()
	for n in _dust:
		if is_instance_valid(n):
			n.queue_free()
	_dust.clear()


func _on_stage(_n: int) -> void:
	call_deferred(&"rebind")


func rebind() -> int:
	_unhook()
	if not is_inside_tree():
		return 0
	var hosts: Array = []
	var pl := get_tree().get_first_node_in_group(&"player")
	if pl:
		hosts.append(pl)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		hosts.append(e)
	for n in hosts:
		_hook(n)
	return _hooked.size()


func _hook(n: Object) -> void:
	if n == null or not is_instance_valid(n) or _hooked.has(n):
		return
	var hooked := false
	if n.has_signal(&"anim_event") and not n.anim_event.is_connected(_on_anim_event):
		n.anim_event.connect(_on_anim_event)
		hooked = true
	if n.has_signal(&"anim_state_changed") and not n.anim_state_changed.is_connected(_on_anim_state):
		n.anim_state_changed.connect(_on_anim_state)
		hooked = true
	if hooked:
		_hooked.append(n)


func _unhook() -> void:
	for n in _hooked:
		if n != null and is_instance_valid(n):
			if n.has_signal(&"anim_event") and n.anim_event.is_connected(_on_anim_event):
				n.anim_event.disconnect(_on_anim_event)
			if n.has_signal(&"anim_state_changed") and n.anim_state_changed.is_connected(_on_anim_state):
				n.anim_state_changed.disconnect(_on_anim_state)
	_hooked.clear()


func _on_anim_state(_old_state: StringName, _new_state: StringName) -> void:
	# Reserved for future squash/stretch by state; event cues do the juice today.
	pass


func _on_anim_event(event: StringName) -> void:
	last_event = event
	var src := _event_source()
	match String(event):
		"footstep":
			_puff(src, 0.7)
		"land":
			_puff(src, 1.15)
			_shake(skin.land_shake_amp if "land_shake_amp" in skin else 5.0, 0.12)
		"hit":
			_flash()
			_shake(-1.0, -1.0)   # skin hit amp, already screen-px
		"caught":
			_shake((skin.hit_shake_amp if skin else 11.0) * 1.2, 0.24)
		"throw_release":
			_puff(src, 0.5)
		_:
			pass


func _event_source() -> Node2D:
	# GDScript does not pass the emitter; use the boy first, else the first hooked node.
	if is_inside_tree():
		var pl := get_tree().get_first_node_in_group(&"player")
		if pl is Node2D:
			return pl
	for n in _hooked:
		if n is Node2D and is_instance_valid(n):
			return n
	return null


func _puff(at: Node2D, scale: float) -> void:
	if at == null or not is_instance_valid(at) or not is_inside_tree():
		return
	last_dust += 1
	var p := CPUParticles2D.new()
	p.name = "AnimDust_%d" % last_dust
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.amount = 6
	p.lifetime = 0.28
	p.local_coords = false
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 18.0 * scale
	p.initial_velocity_max = 42.0 * scale
	p.gravity = Vector2(0, 180)
	p.scale_amount_min = 0.4 * scale
	p.scale_amount_max = 0.9 * scale
	p.color = Color(0.82, 0.76, 0.64, 0.7)
	var tex := UiArt.texture(skin.mote_slot if skin else "vfx_dust_mote")
	if tex:
		p.texture = tex
	add_child(p)
	p.global_position = at.global_position
	p.emitting = true
	_dust.append(p)
	var tw := p.create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(_free_dust.bind(p))


func _free_dust(p: Node) -> void:
	_dust.erase(p)
	if is_instance_valid(p):
		p.queue_free()


func _shake(amp: float, dur: float) -> void:
	if not is_inside_tree():
		return
	var rig := CameraRig.active_rig(get_tree())
	if rig and rig.has_method(&"shake"):
		rig.shake(amp, dur)


func _flash() -> void:
	if not is_inside_tree():
		return
	var hit := get_tree().root.find_child("HitFeedback", true, false)
	if hit and hit.has_method(&"play"):
		hit.play()

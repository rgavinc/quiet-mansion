extends Node2D
## Ring under the ONE selected enemy. Listens to FESignals.enemy_selected and
## flashlight_toggled. Persists with the light off; while the light is off the
## selected enemy gets a faint PointLight2D glow so it stays readable in the dark.
## The ring is drawn in WorldOverlay's follow-viewport CanvasLayer so the
## darkness (CanvasModulate) never hides it; it sits on the feet line.
## Colour per enemy type: HudSkin.ring_colors[type_id] (default ring_default).

var skin: HudSkin
var bus: Node
var target: Node2D = null
var color: Color = Color.WHITE

## Where the dark-glow light lives. Must be in the WORLD canvas (lights only
## affect their own canvas). WorldOverlay sets this; default = self.
var glow_parent: Node = null

var _glow: PointLight2D
var _t: float = 0.0


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	top_level = true
	_glow = PointLight2D.new()
	_glow.name = "DarkGlow"
	_glow.texture = _radial_texture()
	_glow.texture_scale = skin.dark_glow_scale
	_glow.energy = 0.0
	_glow.top_level = true
	(glow_parent if glow_parent else self).add_child(_glow)
	if bus == null:
		bus = UiArt.bus()
	if bus:
		bus.enemy_selected.connect(set_target)
		bus.flashlight_toggled.connect(func(_on): _update_glow())
		set_target(bus.get_selected_enemy())
	else:
		set_target(null)


func set_target(enemy: Node2D) -> void:
	target = enemy if (enemy != null and is_instance_valid(enemy)) else null
	visible = target != null
	if target:
		var type_id: String = bus.enemy_type_id(target) if bus else ""
		color = skin.ring_color_for(type_id)
		_glow.color = color.lerp(Color.WHITE, 0.6)
		global_position = target.global_position + Vector2(0, skin.ring_feet_offset)
		_glow.global_position = target.global_position
		_t = 0.0
	_update_glow()
	queue_redraw()


func _update_glow() -> void:
	if _glow == null:
		return
	var light_on: bool = bus.flashlight_on if bus else true
	_glow.energy = 0.0 if (light_on or target == null) else skin.dark_glow_energy
	_glow.enabled = _glow.energy > 0.0


func _process(delta: float) -> void:
	if target != null and not is_instance_valid(target):
		set_target(null)
		if bus and bus.get_selected_enemy() == null and bus.selected_enemy != null:
			bus.select_enemy(null)
		return
	if target == null:
		return
	_t += delta
	global_position = target.global_position + Vector2(0, skin.ring_feet_offset)
	_glow.global_position = target.global_position
	queue_redraw()


func _exit_tree() -> void:
	if _glow and is_instance_valid(_glow) and _glow.get_parent() != self:
		_glow.queue_free()


func _draw() -> void:
	if target == null:
		return
	var rx := skin.ring_radius.x
	var squash := skin.ring_radius.y / maxf(rx, 1.0)
	var grow := 1.0 + 0.25 * exp(-_t * 10.0)   # snap-in on select
	var pulse := 0.85 + 0.15 * sin(_t * 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, squash))
	var c := color
	c.a *= pulse
	draw_arc(Vector2.ZERO, rx * grow, 0.0, TAU, 48, Color(0, 0, 0, 0.5 * c.a), skin.ring_width + 2.0, true)
	draw_arc(Vector2.ZERO, rx * grow, 0.0, TAU, 48, c, skin.ring_width, true)
	draw_arc(Vector2.ZERO, rx * grow * 0.72, 0.0, TAU, 40, Color(c, c.a * 0.35), 1.0, true)


static func _radial_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

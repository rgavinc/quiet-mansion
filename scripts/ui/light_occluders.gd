extends Node
## FE helper: turns on flashlight 2D shadows and attaches LightOccluder2D to the
## built level's furniture / wall / rail / slab collision boxes. Walks the live
## level (group "level") — no generator edits. Caps occluder count for the web export.

const BODY_NAMES := ["Geometry", "LowFurniture", "Rails"]
const MAX_OCCLUDERS := 80
const META := &"fe_occluder"

var skin: HudSkin
var bus: Node
var last_count: int = 0


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)
	call_deferred(&"_install")


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	# Occluders live on the level and free with it; just drop the beam tweak if we still can.
	last_count = 0


func _on_stage(_n: int) -> void:
	call_deferred(&"_install")


func _install() -> void:
	if not is_inside_tree():
		return
	if skin == null:
		skin = HudSkin.load_default()
	_prepare_beam()
	var level := get_tree().get_first_node_in_group(&"level") as Node
	if level == null:
		last_count = 0
		return
	last_count = attach_to(level, skin)


## Enable shadows on the boy's Beam and prefer the cone texture when the slot exists.
func _prepare_beam() -> void:
	if not is_inside_tree():
		return
	var pl := get_tree().get_first_node_in_group(&"player") as Node
	if pl == null:
		return
	var beam := pl.get_node_or_null(^"Flashlight/Beam") as PointLight2D
	if beam == null:
		return
	apply_beam(beam, skin)


static func apply_beam(beam: PointLight2D, skin: HudSkin) -> void:
	if beam == null or skin == null:
		return
	beam.shadow_enabled = skin.light_shadows
	beam.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	beam.shadow_filter_smooth = skin.light_shadow_smooth
	beam.shadow_color = Color(0, 0, 0, 0.72)
	var tex := UiArt.texture(skin.flashlight_cone_slot)
	if tex:
		beam.texture = tex
		beam.texture_scale = skin.cone_texture_scale
		beam.position = Vector2.ZERO
		# Cone art is authored along +X with the pivot at the emitter; the flashlight node aims.


## Attach rect occluders to CollisionShape2D children of the known physics bodies.
static func attach_to(level: Node, skin: HudSkin = null) -> int:
	var cap := MAX_OCCLUDERS
	if skin != null:
		pass
	var n := 0
	for name in BODY_NAMES:
		var body := level.get_node_or_null(NodePath(name))
		if body == null:
			continue
		for c in body.get_children():
			if n >= cap:
				return n
			n += _occlude_shape(c)
	return n


static func _occlude_shape(c: Node) -> int:
	if c is LightOccluder2D or c.get_meta(META, false):
		return 0
	if not (c is CollisionShape2D):
		return 0
	var cs := c as CollisionShape2D
	# Skip existing FE occluder children (re-install on the same level).
	for ch in cs.get_children():
		if ch is LightOccluder2D and ch.get_meta(META, false):
			return 0
	var poly := OccluderPolygon2D.new()
	if cs.shape is RectangleShape2D:
		var hs: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y),
			Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y),
		])
	elif cs.shape is ConvexPolygonShape2D:
		poly.polygon = (cs.shape as ConvexPolygonShape2D).points
	else:
		return 0
	var oc := LightOccluder2D.new()
	oc.name = "FeOccluder"
	oc.occluder = poly
	oc.set_meta(META, true)
	cs.add_child(oc)
	return 1

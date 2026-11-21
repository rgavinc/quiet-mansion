extends Node2D
## Mouse-aim flashlight. Front End owns feel; PlayerController parents this node.

func _ready() -> void:
	# Soft cone (or the blob fallback) ahead of the boy. Shadows are enabled here;
	# FE LightOccluders attaches occluders to the built furniture/walls.
	var skin := HudSkin.load_default()
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.energy = 1.5
	beam.color = Color(1.0, 0.95, 0.75, 1)
	var cone_tex := UiArt.texture(skin.flashlight_cone_slot)
	if cone_tex:
		beam.texture = cone_tex
		beam.texture_scale = skin.cone_texture_scale
		beam.position = Vector2.ZERO
	else:
		beam.position = Vector2(48, 0)
		var tex := UiArt.texture("flashlight_blob")   # manifest slot, never a file path
		if tex:
			beam.texture = tex
			beam.texture_scale = 2.8
	beam.shadow_enabled = skin.light_shadows
	beam.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	beam.shadow_filter_smooth = skin.light_shadow_smooth
	beam.shadow_color = Color(0, 0, 0, 0.72)
	add_child(beam)
	# Fallback cone so the aim direction is readable even without lighting
	if get_node_or_null("Cone") == null:
		var cone := Polygon2D.new()
		cone.name = "Cone"
		cone.color = Color(1, 0.95, 0.6, 0.22)
		cone.polygon = PackedVector2Array([Vector2(8, 0), Vector2(160, -42), Vector2(160, 42)])
		add_child(cone)

func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())

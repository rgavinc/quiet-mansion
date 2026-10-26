extends Node2D
## Mouse-aim flashlight. Front End owns feel; PlayerController parents this node.

func _ready() -> void:
	# Soft light blob ahead of the boy (works with CanvasModulate darkness)
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.position = Vector2(48, 0)
	beam.energy = 1.5
	beam.color = Color(1.0, 0.95, 0.75, 1)
	var tex := UiArt.texture("flashlight_blob")   # manifest slot, never a file path
	if tex:
		beam.texture = tex
		beam.texture_scale = 2.8
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

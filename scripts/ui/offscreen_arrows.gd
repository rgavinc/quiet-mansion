extends Control
## Smash-style edge arrows for CHASING enemies that are off-screen.
## Listens to FESignals.chase_changed (pulls FESignals.chasing each frame) and
## FESignals.chase_memory_changed. Each arrow carries a ring gauge:
##   - BE chase memory ratio when reported (TODO(BE-wire): Enemy chase memory),
##   - else 1 - distance_to_player / FESignals.give_up_distance.
## Lives in a CanvasLayer (screen space).

var skin: HudSkin
var bus: Node
## Last frame's arrows: Array of {enemy, pos, angle, ratio} (read by tests/debug).
var arrows: Array = []


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	arrows.clear()
	if bus == null or get_viewport() == null:
		queue_redraw()
		return
	var vp := get_viewport_rect()
	var xf := get_viewport().get_canvas_transform()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for e in bus.chasing:
		if e == null or not is_instance_valid(e):
			continue
		var sp: Vector2 = xf * e.global_position
		if vp.grow(-4.0).has_point(sp):
			continue
		var ratio: float = bus.get_chase_memory(e)
		if ratio < 0.0:
			var d := player.global_position.distance_to(e.global_position) if player else 0.0
			ratio = clampf(1.0 - d / maxf(bus.give_up_distance, 1.0), 0.0, 1.0)
		var placed := edge_point(vp, sp, skin.arrow_margin)
		arrows.append({"enemy": e, "pos": placed[0], "angle": placed[1], "ratio": ratio,
			"color": skin.ring_color_for(bus.enemy_type_id(e))})
	_spread(vp)
	queue_redraw()


## Side-scroller chasers often share an edge point; stack them along the edge.
func _spread(vp: Rect2) -> void:
	var gap := skin.arrow_size * 2.2
	for i in arrows.size():
		for j in i:
			var pi: Vector2 = arrows[i]["pos"]
			var pj: Vector2 = arrows[j]["pos"]
			if pi.distance_to(pj) < gap:
				var on_side := absf(pi.x - vp.get_center().x) > absf(pi.y - vp.get_center().y) * vp.size.x / vp.size.y
				var shift := Vector2(0, -gap) if on_side else Vector2(gap, 0)
				arrows[i]["pos"] = pj + shift


## Clamp a screen point to the viewport edge (inset by margin) along the ray
## from the screen centre. Returns [position, angle_pointing_outward].
static func edge_point(vp: Rect2, sp: Vector2, margin: float) -> Array:
	var c := vp.get_center()
	var dir := sp - c
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	var half := vp.size * 0.5 - Vector2(margin, margin)
	var sx: float = INF if absf(dir.x) < 0.0001 else half.x / absf(dir.x)
	var sy: float = INF if absf(dir.y) < 0.0001 else half.y / absf(dir.y)
	var s := minf(sx, sy)
	return [c + dir * s, dir.angle()]


func _draw() -> void:
	var sz := skin.arrow_size
	for a in arrows:
		var pos: Vector2 = a["pos"] - global_position
		var ang: float = a["angle"]
		var col: Color = a["color"]
		var ratio: float = a["ratio"]
		draw_set_transform(pos, ang, Vector2.ONE)
		# Gauge ring behind the arrow head (drains clockwise).
		draw_circle(Vector2.ZERO, sz * 0.75, skin.gauge_back)
		if ratio > 0.0:
			draw_arc(Vector2.ZERO, sz * 0.75, -PI * 0.5 - ang, -PI * 0.5 - ang + TAU * ratio, 32, skin.arrow_gauge.lerp(col, 1.0 - ratio), 3.0, true)
		var tip := PackedVector2Array([Vector2(sz * 1.6, 0), Vector2(sz * 0.55, -sz * 0.72), Vector2(sz * 0.55, sz * 0.72)])
		draw_colored_polygon(tip, Color(0, 0, 0, 0.6))
		var inner := PackedVector2Array([Vector2(sz * 1.42, 0), Vector2(sz * 0.68, -sz * 0.55), Vector2(sz * 0.68, sz * 0.55)])
		draw_colored_polygon(inner, col)
		draw_circle(Vector2.ZERO, sz * 0.32, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

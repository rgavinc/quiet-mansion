extends Node
## Eases a Camera2D's `offset` slightly toward the selected enemy and back to 0
## when nothing is selected. Listens to FESignals.selected_enemy (pulled each frame).
## Strength / max / speed: HudSkin (nudge_*).

## Camera to nudge. Empty = the viewport's current Camera2D.
@export var camera_path: NodePath

var skin: HudSkin
var bus: Node


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()


func get_camera() -> Camera2D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera2D
	return get_viewport().get_camera_2d() if get_viewport() else null


static func target_offset(cam_anchor: Vector2, enemy_pos: Vector2, strength: float, max_len: float) -> Vector2:
	return ((enemy_pos - cam_anchor) * strength).limit_length(max_len)


func _process(delta: float) -> void:
	var cam := get_camera()
	if cam == null:
		return
	var goal := Vector2.ZERO
	var e: Node2D = bus.selected_enemy if bus else null
	if e != null and is_instance_valid(e):
		goal = target_offset(cam.global_position, e.global_position, skin.nudge_strength, skin.nudge_max)
	cam.offset = cam.offset.lerp(goal, 1.0 - exp(-skin.nudge_speed * delta))

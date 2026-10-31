extends Node
## Eases a Camera2D's `offset` slightly toward the selected enemy and back to 0
## when nothing is selected. Listens to FESignals.selected_enemy (pulled each frame). The offset is kept inside the
## camera's limits (CameraRig.clamp_offset), so a nudge at a wall never shows void.
## Strength / max / speed: HudSkin (nudge_*).

## Camera to nudge. Empty = the viewport's current Camera2D.
@export var camera_path: NodePath

var skin: HudSkin
var bus: Node


func _init() -> void:
	process_priority = -200   # eases the offset before CameraRig (-100) moves + clamps


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
	var e: Node2D = bus.get_selected_enemy() if bus else null   # never a freed node
	if e != null:
		goal = target_offset(cam.global_position, e.global_position, skin.nudge_strength, skin.nudge_max)
	# Camera2D applies `offset` AFTER its limit clamp, so keep centre + offset inside the limits
	# (goal and the eased value both: the centre moves while the offset lags) or the view shows
	# void past a wall. CameraRig does the same clamp after it moves the camera.
	var lim := CameraRig.camera_limits(cam)
	var view := CameraRig.view_size(cam)
	var base := cam.get_screen_center_position() - cam.offset
	goal = CameraRig.clamp_offset(base, goal, lim, view)
	cam.offset = CameraRig.clamp_offset(base, cam.offset.lerp(goal, 1.0 - exp(-skin.nudge_speed * delta)), lim, view)

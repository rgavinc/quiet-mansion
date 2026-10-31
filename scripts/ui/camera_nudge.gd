extends Node
## Leans the view slightly toward the selected enemy and back to 0 when nothing is selected.
## Listens to FESignals.selected_enemy (pulled each frame). Strength / max / speed: HudSkin (nudge_*).
##
## The eased lean lives in `current` (never clamped here). CameraRig reads it every frame and folds
## it into its smoothed follow target BEFORE clamping to the limits, so with the nudge held into a
## wall the combined view eases into the wall like any follow instead of being cut dead by a
## clamp applied after the move. The rig also keeps `Camera2D.offset` at 0.
## Without a CameraRig in the tree (a bare camera) it falls back to easing `Camera2D.offset`
## itself, clamped to the limits (CameraRig.clamp_offset), so a nudge at a wall never shows void.

## Camera to nudge. Empty = the viewport's current Camera2D.
@export var camera_path: NodePath

var skin: HudSkin
var bus: Node
## The eased, unclamped lean (world px) CameraRig adds to its follow target.
var current := Vector2.ZERO


func _init() -> void:
	process_priority = -200   # eases the offset before CameraRig (-100) moves + clamps


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	add_to_group(CameraRig.NUDGE_GROUP)


func get_camera() -> Camera2D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera2D
	return get_viewport().get_camera_2d() if get_viewport() else null


static func target_offset(cam_anchor: Vector2, enemy_pos: Vector2, strength: float, max_len: float) -> Vector2:
	return ((enemy_pos - cam_anchor) * strength).limit_length(max_len)


## Drop the lean (stage start / new run: the camera snaps, the nudge starts again from 0).
func reset() -> void:
	current = Vector2.ZERO


func _process(delta: float) -> void:
	var cam := get_camera()
	if cam == null:
		return
	var rig := CameraRig.active_rig(get_tree())
	var goal := Vector2.ZERO
	var e: Node2D = bus.get_selected_enemy() if bus else null   # never a freed node
	if e != null:
		# Lean from where the view would sit on the boy (the rig's un-nudged goal), not from the
		# leaning view itself, so the lean does not feed back on itself.
		var anchor := rig.follow_goal() if rig != null else cam.global_position
		goal = target_offset(anchor, e.global_position, skin.nudge_strength, skin.nudge_max)
	var k := 1.0 - exp(-skin.nudge_speed * delta)
	if rig != null:
		current = current.lerp(goal, k)
		return
	# No rig: Camera2D applies `offset` AFTER its limit clamp, so keep centre + offset inside the
	# limits (goal and the eased value both: the centre moves while the offset lags).
	current = cam.offset
	var lim := CameraRig.camera_limits(cam)
	var view := CameraRig.view_size(cam)
	var base := cam.get_screen_center_position() - cam.offset
	goal = CameraRig.clamp_offset(base, goal, lim, view)
	cam.offset = CameraRig.clamp_offset(base, cam.offset.lerp(goal, k), lim, view)
	current = cam.offset

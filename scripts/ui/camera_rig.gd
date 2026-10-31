class_name CameraRig
extends Node
## FE owns the player camera's bounds and follow (Camera2D itself is built by main.gd).
## Lives in `world_overlay.tscn`, so it needs no hook in main.gd: it adopts the viewport's
## current Camera2D the first frame it sees it (a new camera = a new stage or a new run), and then
##   1. clamps the camera LIMITS to the level: `LevelNav.current.layout` →
##      `LevelValidator.level_bounds` (PR #13), else a TileMap/TileMapLayer used rect, else the
##      1280x720 dev room. A level smaller than the screen on an axis is centred on that axis
##      (same rule main.gd used), so the view never leaves `limits`.
##   2. follows the boy itself (built-in smoothing is switched off): critically damped per axis,
##      X quick, Y slower and speed capped, so a stair climb glides and never lurches. The target
##      is clamped to the limits BEFORE smoothing, so the view never winds up against a wall.
##   3. snaps (no easing) when it adopts a camera, and on `snap()`. Nothing else snaps.
##   4. keeps `Camera2D.offset` (CameraNudge) inside the limits: Godot applies `offset` AFTER
##      the limit clamp, so an unchecked nudge at a wall shows void past it.
## Camera2D's own limits stay set to the same rect as the safety net.

const DEV_ROOM := Rect2(0, 0, 1280, 720)
## Longest frame (s) the follow integrates, so a hitch can't throw the view.
const MAX_DT := 0.1

var skin: HudSkin
## Camera to drive. Empty = the viewport's current Camera2D.
@export var camera_path: NodePath

## Level bounds the limits came from, and the camera-centre limits (>= one screen per axis).
var bounds: Rect2 = DEV_ROOM
var limits: Rect2 = DEV_ROOM
## Where the (un-nudged) view is centred, and the follow velocity.
var center := Vector2.ZERO
var velocity := Vector2.ZERO
## Where `bounds` came from: &"level_nav", &"tilemap" or &"room".
var bounds_source: StringName = &"room"

var _cam: Camera2D
var _target: Node2D
var _nav: Object


func _init() -> void:
	# Nudge eases the offset first, then this moves + clamps, then the Camera2D reads both.
	process_priority = -100


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()


func get_camera() -> Camera2D:
	if not camera_path.is_empty():
		return get_node_or_null(camera_path) as Camera2D
	return get_viewport().get_camera_2d() if is_inside_tree() and get_viewport() else null


# --- pure helpers (tested) -----------------------------------------------------

## Camera limits for a level: the level bounds, widened per axis (centred on the level) up to
## one screen. `view` = world px the viewport shows (viewport size / zoom).
static func limits_for(b: Rect2, view: Vector2) -> Rect2:
	var c := b.get_center()
	var lo := Vector2(minf(b.position.x, c.x - view.x / 2.0), minf(b.position.y, c.y - view.y / 2.0))
	var hi := Vector2(maxf(b.end.x, c.x + view.x / 2.0), maxf(b.end.y, c.y + view.y / 2.0))
	return Rect2(Vector2(floorf(lo.x), floorf(lo.y)), Vector2(ceilf(hi.x), ceilf(hi.y)) - Vector2(floorf(lo.x), floorf(lo.y)))


## Clamp a view centre so a `view`-sized screen stays inside `lim`.
static func clamp_center(c: Vector2, lim: Rect2, view: Vector2) -> Vector2:
	return Vector2(_clamp_axis(c.x, lim.position.x + view.x / 2.0, lim.end.x - view.x / 2.0),
			_clamp_axis(c.y, lim.position.y + view.y / 2.0, lim.end.y - view.y / 2.0))


## Clamp a nudge `offset` so (centre + offset) still has the screen inside `lim`.
static func clamp_offset(c: Vector2, offset: Vector2, lim: Rect2, view: Vector2) -> Vector2:
	return clamp_center(c + offset, lim, view) - c


static func _clamp_axis(v: float, lo: float, hi: float) -> float:
	return (lo + hi) * 0.5 if lo > hi else clampf(v, lo, hi)


## Camera2D limits as a rect (the limits the engine really applies).
static func camera_limits(cam: Camera2D) -> Rect2:
	return Rect2(Vector2(cam.limit_left, cam.limit_top),
			Vector2(cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top))


## World px the camera's viewport shows.
static func view_size(cam: Camera2D) -> Vector2:
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size if vp else Vector2(1280, 720)
	return size / cam.zoom


## One axis of Unity-style SmoothDamp (critically damped spring, no overshoot): returns
## [new_position, new_velocity]. Starts from the current velocity, so a stepped target eases in.
static func smooth_damp(cur: float, target: float, vel: float, smooth_time: float, max_speed: float, dt: float) -> Array:
	smooth_time = maxf(smooth_time, 0.0001)
	var omega := 2.0 / smooth_time
	var x := omega * dt
	var k := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var max_change := max_speed * smooth_time
	change = clampf(change, -max_change, max_change)
	var goal := cur - change
	var tmp := (vel + omega * change) * dt
	vel = (vel - omega * tmp) * k
	var out := goal + (change + tmp) * k
	if (target - cur > 0.0) == (out > target):   # never overshoot
		out = target
		vel = 0.0
	return [out, vel]


## Level bounds for the camera: [Rect2, source].
static func level_bounds_for(tree: SceneTree) -> Array:
	var nav: LevelNav = LevelNav.current
	if nav != null and not nav.layout.is_empty():
		return [LevelValidator.level_bounds(nav.layout), &"level_nav"]
	if tree != null:
		var scene := tree.current_scene if tree.current_scene else tree.root
		var tm := _find_tilemap(scene)
		if tm:
			var used: Rect2i = tm.get_used_rect()
			var ts := Vector2(tm.tile_set.tile_size) if tm.tile_set else Vector2(16, 16)
			var r: Rect2 = (tm as Node2D).get_global_transform() * Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts)
			if r.has_area():
				return [r, &"tilemap"]
	return [DEV_ROOM, &"room"]


static func _find_tilemap(n: Node) -> Node:
	if n.is_class("TileMapLayer") or n.is_class("TileMap"):
		return n
	for c in n.get_children():
		var f := _find_tilemap(c)
		if f:
			return f
	return null


# --- the rig ---------------------------------------------------------------------

## Take over `cam` (and follow `target`, default: the camera's parent if it is the boy, else
## group `player`): clamp its limits to the level, turn built-in smoothing off, snap.
func adopt(cam: Camera2D, target: Node2D = null) -> void:
	_cam = cam
	_target = target
	cam.position_smoothing_enabled = false
	refresh_limits()
	snap()


## Recompute bounds + camera limits from the level (also when the level's nav changes).
func refresh_limits() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	_nav = LevelNav.current
	var r := level_bounds_for(get_tree())
	bounds = r[0]
	bounds_source = r[1]
	limits = limits_for(bounds, view_size(_cam))
	_cam.limit_left = int(limits.position.x)
	_cam.limit_top = int(limits.position.y)
	_cam.limit_right = int(limits.end.x)
	_cam.limit_bottom = int(limits.end.y)
	_cam.limit_smoothed = false


## Jump straight to the target: stage start / new run. No other path snaps.
func snap() -> void:
	velocity = Vector2.ZERO
	var t := follow_target()
	if _cam != null and is_instance_valid(_cam):
		center = clamp_center(t.global_position if t else _cam.global_position, limits, view_size(_cam))
		_cam.offset = Vector2.ZERO
		_apply()


func follow_target() -> Node2D:
	if _target != null and is_instance_valid(_target):
		return _target
	if _cam != null and is_instance_valid(_cam):
		var par := _cam.get_parent()
		if par is Node2D and (par as Node).is_in_group(&"player"):
			return par
	if is_inside_tree():
		var g := get_tree().get_first_node_in_group(&"player")
		if g is Node2D:
			return g
	return null


func _process(delta: float) -> void:
	var cam := get_camera()
	if cam == null:
		return
	if cam != _cam:
		adopt(cam, _target)
		return
	if LevelNav.current != _nav:
		refresh_limits()
	var t := follow_target()
	if t == null:
		return
	if skin == null:
		skin = HudSkin.load_default()
	var dt := minf(delta, MAX_DT)
	var goal := clamp_center(t.global_position, limits, view_size(cam))
	var sx := smooth_damp(center.x, goal.x, velocity.x, skin.camera_smooth_x, INF, dt)
	var sy := smooth_damp(center.y, goal.y, velocity.y, skin.camera_smooth_y, skin.camera_max_speed_y, dt)
	center = Vector2(sx[0], sy[0])
	velocity = Vector2(sx[1], sy[1])
	_apply()


## Put the camera at `center` and keep its nudge offset inside the limits.
func _apply() -> void:
	_cam.global_position = center
	_cam.offset = clamp_offset(center, _cam.offset, camera_limits(_cam), view_size(_cam))
	_cam.force_update_scroll()

class_name AnimHook
extends RefCounted
## Shared animation-state layer. Player and enemies derive an anim_state from
## their existing physics / FSM each frame and publish it here, plus one-shot
## events FE can hang dust, shake, hit-flash and squash-stretch on.
## Gameplay numbers are not tuned here.

signal anim_state_changed(old_state: StringName, new_state: StringName)
signal anim_event(event: StringName)

const MOVE_EPS := 5.0
## Horizontal speed at or above this fraction of the current move cap is "run".
const RUN_FRAC := 0.75
const LAND_TIME := 0.15
const FOOTSTEP_PX := 32.0
## Catch lands this many physics frames after a default reach starts (0.6 s at 60 fps).
const REACH_STRIKE_FRAMES := 36
const REACH_STRIKE_TIME := 36.0 / 60.0

var anim_state: StringName = &""
var facing: int = 1
var velocity: Vector2 = Vector2.ZERO
## 0..n, velocity length over the current move cap (blend input).
var normalized_speed: float = 0.0
var map: AnimMap
var footstep_px: float = FOOTSTEP_PX
var _foot_accum: float = 0.0


func set_state(s: StringName) -> void:
	if s == anim_state:
		return
	var old := anim_state
	anim_state = s
	anim_state_changed.emit(old, s)


func emit_event(event: StringName) -> void:
	anim_event.emit(event)


func set_motion(vel: Vector2, cap: float, face: int) -> void:
	velocity = vel
	facing = face
	normalized_speed = vel.length() / maxf(cap, 1.0)


func track_footsteps(moving: bool, delta: float) -> void:
	if not moving:
		_foot_accum = 0.0
		return
	_foot_accum += velocity.length() * delta
	while _foot_accum >= footstep_px:
		_foot_accum -= footstep_px
		emit_event(&"footstep")


func resolved_animation(frames: SpriteFrames, fallback: String) -> String:
	if map == null:
		return fallback
	return map.resolve(anim_state, frames, fallback)

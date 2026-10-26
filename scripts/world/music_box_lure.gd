class_name MusicBoxLure
extends Node2D
## A landed Music Box: plays a loud tune for `lure_time` s, a NoiseBus pulse every
## `interval` s at its own position. Enemies treat a noise from a lure (is_lure()) as a
## lure: they hunt toward it instead of toward the boy (Enemy.hear_lure). Back End owns.
## Art: the ONE manifest slot `music_box_world` (Designer PR #30), in flight and landed;
## an amber placeholder box when the slot isn't in the manifest yet.

const SLOT := "music_box_world"

var radius: float = 900.0
var loudness: float = 1.2
var lure_time: float = 4.0
var interval: float = 0.5
var pulses: int = 0
var _left: float = 0.0
var _next: float = 0.0


func setup(it: Dictionary) -> void:
	radius = float(it.get("noise_radius", radius))
	loudness = float(it.get("noise_loudness", loudness))
	lure_time = float(it.get("lure_time", lure_time))
	interval = maxf(float(it.get("lure_interval", interval)), 0.05)


func is_lure() -> bool:
	return true


func _ready() -> void:
	add_to_group("lures")
	add_visual(self)
	_left = lure_time
	_next = 0.0


## Sprite from the manifest slot, or a placeholder when the slot is missing.
static func add_visual(parent: Node) -> void:
	if AnimLibrary.has_slot(SLOT):
		var spr := AnimatedSprite2D.new()
		spr.name = "MusicBoxArt"
		spr.sprite_frames = AnimLibrary.frames_for([SLOT])
		spr.animation = SLOT
		spr.offset = AnimLibrary.offset_for(SLOT)
		spr.play()
		parent.add_child(spr)
	else:
		var r := ColorRect.new()
		r.name = "MusicBoxArt"
		r.size = Vector2(12, 10)
		r.position = Vector2(-6, -10)
		r.color = Color(0.85, 0.6, 0.25)
		parent.add_child(r)


## Side-scroll: drop onto the slab below (it rests where it fell, not mid-air).
func settle() -> void:
	if not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	if space == null:
		return
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 400), PlayerStats.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit:
		global_position = hit.position


func _physics_process(delta: float) -> void:
	step(delta)


## Separate from _physics_process so tests can drive it.
func step(delta: float) -> void:
	if _left <= 0.0:
		return
	_next -= delta
	if _next <= 0.0:
		_next += interval
		pulses += 1
		NoiseBus.emit_noise(global_position, radius, loudness, self)
	_left -= delta
	if _left <= 0.0:
		queue_free()

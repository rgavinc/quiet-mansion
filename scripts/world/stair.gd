class_name Stair
extends Area2D
## A staircase between two floors. The player climbs it with up/down while overlapping.
## `bottom` and `top` are local points; the generator sets them. Back End owns.

@export var bottom: Vector2 = Vector2(-48, 0)
@export var top: Vector2 = Vector2(48, -160)
@export var width: float = 20.0
@export var from_floor: int = 0   # LEVELGEN.md: lower floor index
@export var to_floor: int = 1     # upper floor index


func _ready() -> void:
	add_to_group("stairs")
	var shape := CollisionShape2D.new()
	var seg := SegmentShape2D.new()
	seg.a = bottom
	seg.b = top
	shape.shape = seg
	add_child(shape)


func global_bottom() -> Vector2:
	return to_global(bottom)


func global_top() -> Vector2:
	return to_global(top)


## 0 at bottom, 1 at top, for a world point (projected onto the stair line).
func t_at(p: Vector2) -> float:
	var a := global_bottom()
	var b := global_top()
	return clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1.0), 0.0, 1.0)


func point_at(t: float) -> Vector2:
	return global_bottom().lerp(global_top(), clampf(t, 0.0, 1.0))


func is_near(p: Vector2) -> bool:
	return p.distance_to(point_at(t_at(p))) <= width

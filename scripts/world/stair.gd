class_name Stair
extends Area2D
## A staircase between two floors. The player climbs it with up/down while overlapping.
## `bottom` and `top` are local points; the generator sets them. Back End owns.

@export var bottom: Vector2 = Vector2(-48, 0)
@export var top: Vector2 = Vector2(48, -160)
@export var width: float = 20.0          # "on the stair line" tolerance (mid-climb re-grab)
@export var from_floor: int = 0   # LEVELGEN.md: lower floor index
@export var to_floor: int = 1     # upper floor index


func _ready() -> void:
	add_to_group("stairs")
	# LEVELGEN.md: the trigger covers both bands (320px tall) so it can be entered from either floor.
	var r := trigger_rect(bottom, top)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	shape.position = r.get_center()
	add_child(shape)


## Trigger area for a stair from `b` (lower floor feet point) to `t` (upper floor feet point),
## derived only from those two points so any stair width / angle works (LEVELGEN: 4 tiles now,
## Lead may widen to ~15): x = the stair's run (+1px so the ends count), y = from one rise above
## the upper end (the upper band) down to the lower slab (+2px so feet on the slab count).
## For a one-floor rise of 160px that's the documented 320px. Works on LevelNav stair dicts too.
static func trigger_rect(b: Vector2, t: Vector2) -> Rect2:
	var x0 := minf(b.x, t.x) - 1.0
	var x1 := maxf(b.x, t.x) + 1.0
	var rise := absf(b.y - t.y)
	var y0 := minf(b.y, t.y) - rise
	var y1 := maxf(b.y, t.y) + 2.0
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func global_trigger_rect() -> Rect2:
	return trigger_rect(global_bottom(), global_top())


## Inside the 320px trigger (either floor).
func contains(p: Vector2) -> bool:
	return global_trigger_rect().has_point(p)


## Within `width` of the stair line itself (already on the stairs).
func on_line(p: Vector2) -> bool:
	return p.distance_to(point_at(t_at(p))) <= width


## Where a climb starts for a point inside the trigger: its spot on the line if it's on the
## stairs, else the stair end on its floor (0 = bottom / lower floor, 1 = top / upper floor).
func entry_t(p: Vector2) -> float:
	if on_line(p):
		return t_at(p)
	var mid := (global_bottom().y + global_top().y) * 0.5
	return 1.0 if p.y <= mid else 0.0   # above the stair's half-height = upper floor


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


## Player / enemy detection: the whole trigger area, not just the stair line.
func is_near(p: Vector2) -> bool:
	return contains(p)

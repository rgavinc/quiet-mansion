extends Node2D
## A thrown held object. Flies straight at the target; walls (physics bodies) and
## blocking props stop it. Wherever it stops, it shatters with its own noise radius.

const MAX_OVERSHOOT := 80.0

var item: Dictionary = {}
var target: Node2D = null
var velocity: Vector2 = Vector2.ZERO
var _travel_left: float = 600.0
var shooter: Node2D = null


func setup(from: Vector2, it: Dictionary, tgt: Node2D, who: Node2D) -> void:
	global_position = from
	item = it
	target = tgt
	shooter = who
	var aim := tgt.global_position if is_instance_valid(tgt) else from + Vector2(300, 0)
	velocity = (aim - from).normalized() * PlayerStats.get_stat(&"throw_speed")
	_travel_left = from.distance_to(aim) + MAX_OVERSHOOT


func _ready() -> void:
	add_to_group("thrown")
	var r := ColorRect.new()
	r.size = Vector2(10, 12)
	r.position = Vector2(-5, -6)
	r.color = Color(0.7, 0.6, 0.5)
	add_child(r)


func _physics_process(delta: float) -> void:
	step(delta)


## Separate from _physics_process so tests can drive it.
func step(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	# 1) walls / any physics body
	var space := get_world_2d().direct_space_state if is_inside_tree() else null
	if space:
		var q := PhysicsRayQueryParameters2D.create(from, to)
		if shooter is CollisionObject2D:
			q.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(q)
		if hit and not (hit.collider is Node and (hit.collider as Node).is_in_group("puppets")):
			_shatter(hit.position, null)
			return
	# 2) enemies and blocking props along the segment
	for e in get_tree().get_nodes_in_group("puppets"):
		if e is Node2D and _seg_dist(from, to, e.global_position) <= 16.0:
			_shatter(e.global_position, e)
			return
	for o in get_tree().get_nodes_in_group("world_objects"):
		if o is WorldObject and o.blocks_throws and not o.broken and _seg_dist(from, to, o.global_position) <= 10.0:
			o.break_apart()
			_shatter(o.global_position, null)
			return
	global_position = to
	_travel_left -= (to - from).length()
	if _travel_left <= 0.0:
		_shatter(global_position, null)  # miss: still loud where it lands


static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _shatter(at: Vector2, enemy: Node) -> void:
	if enemy and enemy.has_method("on_hit_by_throw"):
		enemy.on_hit_by_throw(item)
	NoiseBus.emit_noise(at, float(item.get("noise_radius", NoiseBus.DEFAULT_RADIUS)) * PlayerStats.get_stat(&"noise_mult"), 1.0, self)
	WorldObject._drop_gold(at, int(item.get("gold_inside", 0)))
	queue_free()

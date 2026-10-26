extends Node2D
## Dashed aim line from the boy to the selected (ringed) enemy. Shown exactly
## when the boy is holding something AND an enemy is ringed (FESignals.can_throw). Turns red when a physics ray hits a
## wall/prop (anything but the boy and the target) first, and marks the hit.
## Listens to FESignals.enemy_selected / inventory_selected / inventory_changed.

## Physics layers that can block a throw. TODO(BE-wire): match BE's layer names.
@export_flags_2d_physics var block_mask: int = 0xFFFFFFFF

var skin: HudSkin
var bus: Node
var blocked: bool = false
var hit_point: Vector2 = Vector2.ZERO

var _from: Vector2
var _to: Vector2
var _active: bool = false


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	top_level = true
	z_as_relative = false
	z_index = 40
	if bus == null:
		bus = UiArt.bus()
	visible = false


func should_show() -> bool:
	if bus == null:
		return false
	return bus.can_throw()


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_active = player != null and should_show()
	visible = _active
	if not _active:
		blocked = false
		return
	var enemy: Node2D = bus.selected_enemy
	_from = player.global_position
	_to = enemy.global_position
	var exclude: Array[RID] = []
	for n in [player, enemy]:
		if n is CollisionObject2D:
			exclude.append((n as CollisionObject2D).get_rid())
	var res := ray_block(get_world_2d().direct_space_state, _from, _to, exclude, block_mask)
	blocked = not res.is_empty()
	hit_point = res.get("position", _to)
	queue_redraw()


## Pure helper (also used by tests): first blocking hit between from→to, or {}.
static func ray_block(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array[RID], mask: int) -> Dictionary:
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return space.intersect_ray(q)


func _draw() -> void:
	if not _active:
		return
	var a := to_local(_from)
	var b := to_local(_to)
	var stop := to_local(hit_point) if blocked else b
	var c := skin.throw_blocked if blocked else skin.throw_clear
	draw_dashed_line(a, stop, c, 2.0, skin.throw_dash, true, true)
	if blocked:
		draw_dashed_line(stop, b, Color(c, c.a * 0.25), 1.0, skin.throw_dash, true, true)
		var s := 6.0
		draw_line(stop + Vector2(-s, -s), stop + Vector2(s, s), c, 2.5)
		draw_line(stop + Vector2(-s, s), stop + Vector2(s, -s), c, 2.5)
	else:
		draw_circle(b, 3.5, c)

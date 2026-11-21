class_name PropVisual
extends RefCounted
## Shared sprite / placeholder helpers for gold piles, generic obstacles and thrown props.
## Collision, sizes and positions stay with the caller. Back End owns.

const GOLD_SLOT := "gold_coin"
## Planned floor-junk slots. None are in the manifest yet; ColorRect stays until Designer adds one.
const OBSTACLE_SLOTS: PackedStringArray = [
	"prop_obstacle",
	"obstacle_idle",
]
const THROWN_VASE_SLOT := "vase_thrown"
## How many coin sprites to stack for a pile (the collected amount is unchanged).
const GOLD_PILE_MAX := 5
## Local Y of the floor under a gold node (generator places the node 4 px above the slab).
const GOLD_FLOOR_Y := 4.0
## Tight, deterministic offsets around the first coin so a pile stays inside the 14 px pickup radius.
const GOLD_PILE_OFFSETS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(4, -2),
	Vector2(-4, -1),
	Vector2(3, -4),
	Vector2(-3, -3),
]


static func has_art(slot: String) -> bool:
	if slot.is_empty() or not AnimLibrary.has_slot(slot):
		return false
	var sf := AnimLibrary.frames_for([slot])
	return sf.has_animation(slot) and sf.get_frame_count(slot) > 0


static func first_slot(candidates: PackedStringArray) -> String:
	for s in candidates:
		if has_art(s):
			return s
	return ""


static func frame_size(slot: String) -> Vector2:
	var fs: Array = AnimLibrary.meta(slot).get("frame_size", [0, 0])
	if fs.size() >= 2:
		return Vector2(float(fs[0]), float(fs[1]))
	return Vector2.ZERO


static func add_sprite(parent: Node2D, slot: String, pos := Vector2.ZERO, extra_offset := Vector2.ZERO, sc := Vector2.ONE) -> AnimatedSprite2D:
	var spr := AnimatedSprite2D.new()
	spr.name = slot
	spr.sprite_frames = AnimLibrary.frames_for([slot])
	spr.animation = slot
	spr.position = pos
	spr.offset = AnimLibrary.offset_for(slot) + extra_offset
	spr.scale = sc
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if spr.sprite_frames.has_animation(slot):
		spr.play(slot)
	parent.add_child(spr)
	return spr


static func add_placeholder(parent: Node2D, size: Vector2, color: Color, centered := true) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Placeholder"
	r.size = size
	r.position = -size * 0.5 if centered else Vector2.ZERO
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Scale that fits `frame` inside `box` (never changes the box / hitbox).
static func fit_scale(frame: Vector2, box: Vector2) -> float:
	if frame.x <= 0.0 or frame.y <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return 1.0
	return minf(box.x / frame.x, box.y / frame.y)


## Offset so the sprite's feet (or the frame bottom, if the pivot is centred) sit on the node origin.
static func feet_offset(slot: String) -> Vector2:
	var fs := frame_size(slot)
	if fs == Vector2.ZERO:
		return Vector2.ZERO
	var pv := AnimLibrary.pivot(slot)
	if pv.y >= fs.y * 0.75:
		return AnimLibrary.offset_for(slot)
	# Centre / top pivots: pin the bottom-centre of the frame to the origin, keep the x pivot.
	return Vector2(fs.x * 0.5 - pv.x, -fs.y * 0.5)


## Sprite scaled to `box`, bottom-centre of the box = the floor. `parent` origin is the box centre.
static func add_fitted_floor_sprite(parent: Node2D, slot: String, box: Vector2) -> AnimatedSprite2D:
	var fs := frame_size(slot)
	var fit := fit_scale(fs, box)
	var spr := add_sprite(parent, slot, Vector2(0, box.y * 0.5), Vector2.ZERO, Vector2(fit, fit))
	spr.offset = feet_offset(slot)
	return spr


static func add_gold_pile(parent: Node2D, amount: int) -> void:
	if not has_art(GOLD_SLOT):
		add_placeholder(parent, Vector2(6, 6), Color(1.0, 0.82, 0.2))
		return
	# Node is 4 px above the slab; shift each coin so its bottom sits on that floor, plus pile lift.
	var floor_shift := Vector2(0, GOLD_FLOOR_Y - frame_size(GOLD_SLOT).y * 0.5)
	var n := clampi(amount, 1, GOLD_PILE_MAX)
	for i in n:
		var off: Vector2 = GOLD_PILE_OFFSETS[i]
		var spr := add_sprite(parent, GOLD_SLOT, off + floor_shift)
		spr.name = "Coin%d" % i
		spr.z_index = i


static func add_obstacle_visual(parent: Node2D, box: Vector2) -> String:
	var slot := first_slot(OBSTACLE_SLOTS)
	if slot.is_empty():
		add_placeholder(parent, box, Color(0.45, 0.35, 0.25))
		return ""
	add_fitted_floor_sprite(parent, slot, box)
	return slot


static func add_thrown_visual(parent: Node2D, item: Dictionary) -> void:
	var slot := THROWN_VASE_SLOT if Item.is_vase(item) and has_art(THROWN_VASE_SLOT) else str(item.get("slot", ""))
	if has_art(slot):
		add_sprite(parent, slot)
		return
	add_placeholder(parent, Vector2(10, 12), Color(0.7, 0.6, 0.5))


static func is_rect_placeholder(n: Node) -> bool:
	if n is ColorRect:
		return true
	if n is Polygon2D:
		return true
	return false


static func has_rect_placeholder(root: Node) -> bool:
	for c in root.get_children():
		if is_rect_placeholder(c):
			return true
	return false

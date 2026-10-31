class_name FurnitureSkin
extends RefCounted
## Furniture art for LevelGenerator.build: one sprite per furniture piece, picked by height class
## (1-4 tiles) from the manifest slots `furniture_h{h}_{a,b,...}` (bottom-centre pivot, top edge at
## the collision height; prefers the width matching the piece). Data-driven: any new slot with that name is used.
## The pick comes from its own RNG stream (seeded from the layout's build_seed), so layouts,
## collision and validator hashes never change. A piece with no usable slot keeps the flat
## placeholder ColorRect. Collision is untouched. Lead owns.

const ROOT := "FurnitureSprites"
const PREFIX := "furniture_h"
const TILE := 16

## Tests only: {height -> [slot names]} replaces the manifest lookup (empty dict = no slots).
static var slots_override: Variant = null


static func slots_for_height(h: int) -> Array:
	var names: Array
	if slots_override is Dictionary:
		names = (slots_override as Dictionary).get(h, [])
	else:
		names = AnimLibrary.slots_with_prefix("%s%d_" % [PREFIX, h])
	var out: Array = []
	for s in names:
		if UiArt.texture(str(s)) != null:
			out.append(str(s))
	return out


## Slots to pick from for a piece h tiles tall and `w_tiles` wide: those whose width is exactly
## the piece's (the art is drawn to the collision box); with none, every slot of the height class
## (a mismatched width is still fine, centred on the box).
static func candidates(h: int, w_tiles: int) -> Array:
	var all := slots_for_height(h)
	var exact := all.filter(func(s): return int(frame_size(s).x) == w_tiles * TILE)
	return exact if not exact.is_empty() else all


static func frame_size(slot: String) -> Vector2:
	var fs: Array = AnimLibrary.meta(slot).get("frame_size", [])
	if fs.size() == 2:
		return Vector2(int(fs[0]), int(fs[1]))
	var tex := UiArt.texture(slot)
	return tex.get_size() if tex else Vector2.ZERO


static func rng_for(L: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("qm:furniture:%d:%d" % [int(L.get("build_seed", 0)), int(L.get("stage", 1))]).hash()
	return rng


## Per furniture piece (layout order): the chosen slot and flip, or "" for the placeholder.
static func choose(L: Dictionary) -> Array:
	var rng := rng_for(L)
	var out: Array = []
	for fu in L.get("furniture", []):
		var c := candidates(int(fu.h), int(fu.w))
		var pick := rng.randi()   # always consumed: a missing slot never shifts later picks
		var flip := rng.randf() < 0.5
		out.append({slot = str(c[pick % c.size()]) if not c.is_empty() else "", flip = flip})
	return out


## Adds the sprites under `level` and returns how many pieces got one. `rects` are the
## placeholder ColorRects in furniture order (hidden when their piece got a sprite).
static func paint(level: Node2D, L: Dictionary, rects: Array) -> int:
	var root := Node2D.new()
	root.name = ROOT
	level.add_child(root)
	var picks := choose(L)
	var n := 0
	for i in picks.size():
		var slot: String = picks[i].slot
		if slot.is_empty():
			continue
		var fu: Dictionary = L.furniture[i]
		var fs := frame_size(slot)
		var tex := UiArt.texture(slot)
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(Vector2.ZERO, fs)
		var sp := Sprite2D.new()
		sp.name = "Furniture_%d" % i
		sp.texture = at
		sp.centered = false
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.flip_h = bool(picks[i].flip)
		# Designer's rule: the frame's bottom edge stands on the floor surface (its top row is the
		# collision top), centred on the box. flip_h mirrors inside the same rect.
		sp.offset = -Vector2(fs.x * 0.5, fs.y)
		sp.position = Vector2((float(fu.x) + float(fu.w) * 0.5) * TILE, LevelValidator.surface_y(int(fu.floor)))
		sp.z_index = -5
		sp.set_meta(&"slot", slot)
		root.add_child(sp)
		if i < rects.size() and rects[i] != null:
			(rects[i] as CanvasItem).visible = false
		n += 1
	return n

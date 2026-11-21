class_name StageRim
extends RefCounted
## Navigation rim for the dark stages (PD): a faint 1px line along the top edge of every floor, over
## every stair opening at the gallery handrail, and along the top of every piece of furniture, so the
## boy can read the level where the flashlight does not reach. Stage 5 is near-black outside the cone.
##
## It lives in its own CanvasLayer (layer 4, below the HUD at 20 and WorldOverlay at 5) that follows
## the camera: a separate canvas is neither multiplied by the stage CanvasModulate nor lit by the
## flashlight, so the line has the same strength everywhere. Strength = StageTable.look(stage).rim_alpha
## (0 on stage 1: no nodes at all). Lines only, one Line2D per segment; it never touches the enemies'
## sprites or visibility (Front End owns those). Node names are stable and data-driven from the layout:
##   Floor_<floor>_<n>   top edge of floor <floor>, split at the stair cutouts
##   Rail_<n>            stair opening <n> (L.stairs order), at the handrail top
##   Furn_<n>            furniture piece <n> (L.furniture order), its top
## Lead owns.

const NODE := "StageRim"
const LAYER := 4
const COLOR := Color(0.72, 0.86, 1.0)   # cold, like the dark stages' tint; alpha comes from the table
const RAIL_TOP_PX := 28.0                # visible gallery handrail height above the upper surface


## Builds (or rebuilds) the rim under `level` for layout `L` at `alpha`. Returns the layer, or null
## when alpha <= 0 (nothing drawn, no node kept).
static func build(level: Node, L: Dictionary, alpha: float) -> CanvasLayer:
	var old := level.get_node_or_null(NODE)
	if old:
		level.remove_child(old)
		old.free()
	if alpha <= 0.0 or L.is_empty():
		return null
	var layer := CanvasLayer.new()
	layer.name = NODE
	layer.layer = LAYER
	layer.follow_viewport_enabled = true
	level.add_child(layer)
	var col := Color(COLOR, clampf(alpha, 0.0, 1.0))
	var right := float((int(L.width_tiles) + 1) * LevelGenerator.TILE)
	for f in int(L.floors):
		var holes: Array = []
		for s in L.stairs:
			if int(s.to_floor) == f:
				holes.append(LevelValidator.stair_hole(s))
		holes.sort_custom(func(a, b): return a.x < b.x)
		var y := float(LevelValidator.surface_y(f))
		var x0 := 0.0
		var n := 0
		for h in holes:
			if h.x > x0:
				_line(layer, "Floor_%d_%d" % [f, n], x0, h.x, y, col)
				n += 1
			x0 = maxf(x0, h.y)
		if x0 < right:
			_line(layer, "Floor_%d_%d" % [f, n], x0, right, y, col)
	var i := 0
	for s in L.stairs:
		var hole := LevelValidator.stair_hole(s)
		_line(layer, "Rail_%d" % i, hole.x, hole.y, float(LevelValidator.surface_y(int(s.to_floor))) - RAIL_TOP_PX, col)
		i += 1
	i = 0
	for fu in L.furniture:
		var sp := LevelValidator.furniture_span(fu)
		_line(layer, "Furn_%d" % i, sp.x, sp.y, float(LevelValidator.surface_y(int(fu.floor))) - float(int(fu.h) * LevelGenerator.TILE), col)
		i += 1
	return layer


## One horizontal 1px line covering pixel row `y` (the row of the edge itself) from x0 to x1.
static func _line(parent: Node, name: String, x0: float, x1: float, y: float, col: Color) -> void:
	var ln := Line2D.new()
	ln.name = name
	ln.width = 1.0
	ln.default_color = col
	ln.antialiased = false
	ln.points = PackedVector2Array([Vector2(x0, y + 0.5), Vector2(x1, y + 0.5)])
	parent.add_child(ln)

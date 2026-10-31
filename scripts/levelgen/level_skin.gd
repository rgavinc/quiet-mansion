class_name LevelSkin
extends RefCounted
## Paints a built level from the `tiles_stage1` atlas (docs/DESIGN.md): band dressing behind,
## stair pieces, then slabs / slab ends / wall columns / doorway trim in front. Purely visual:
## collision stays LevelGenerator's boxes. Returns false (and paints nothing) when the atlas
## PNG isn't there, so the generator keeps its flat placeholder colours. Lead owns.

const SLOT := "tiles_stage1"
const T := 16
const COLS := 21
# single tiles (index = row * 21 + col)
const FLOOR_TOP := 0
const FLOOR_FILL := 2
const CEILING_TRIM := 4
const SLAB_END_LEFT := 6
const SLAB_END_RIGHT := 7
const WALLPAPER := [8, 9, 10, 11, 12]
const WAINSCOT := [13, 14, 15]          # band rows 6, 7, 8
const WALL_COLUMN := 16
const WALL_COLUMN_TOP := 17
const DOOR_LINTEL := 18
const DOOR_POST_LEFT := 19
const DOOR_POST_RIGHT := 20
# stair pieces [col, row, w, h] in atlas tiles (ASSETS_MANIFEST.toml); atlas row 5 = upper slab row,
# atlas column c = stair column c (stair rising right; mirrored to x + 20 - c rising left)
const STAIR_PIECES := {
	stair_stamp = [3, 5, 15, 10],
	landing_bottom = [0, 12, 3, 3],
	landing_top = [18, 2, 3, 3],
	stair_rail_cap = [15, 3, 3, 2],
}
# gallery rail over the upper-slab opening (PRODUCT.md "Stair opening"): Designer PR #33 adds
# `stair_gallery_rail` = [9, 2, 6, 3] (tiles x+9..x+14, band rows 6-8; `stair_rail_cap` carries it
# over x+15..x+17). Read from ASSETS_MANIFEST.toml; without it, `stair_rail_cap` is repeated over
# x+9..x+14 as a stand-in.
const GALLERY_RAIL := "stair_gallery_rail"
const GALLERY_RAIL_FALLBACK := "stair_rail_cap"
const MANIFEST := "res://assets/ASSETS_MANIFEST.toml"
const SLAB_ATLAS_ROW := 5
const STAIR_WIDTH := 21
const BAND_ROWS := 9                     # rows 0..8 above the slab


static func paint(level: Node2D, L: Dictionary) -> bool:
	var tex := UiArt.texture(SLOT)
	if tex == null:
		return false
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)
	var back := _layer(level, "TilesBack", ts, -15)
	var stairs := _layer(level, "TilesStairs", ts, -6)
	var front := _layer(level, "TilesFront", ts, -5)
	var F := int(L.floors)
	var W := int(L.width_tiles)

	# hole columns per slab floor, and which room each column is in (wallpaper per room)
	var holes := {}
	for s in L.stairs:
		var h := LevelValidator.stair_hole(s)
		for c in range(int(h.x) / T, int(h.y) / T):
			holes[Vector2i(c, int(s.to_floor))] = true
	for f in F:
		var top := _row(f) - BAND_ROWS
		var room := 0
		for c in W + 1:
			if L.walls.any(func(w): return int(w.floor) == f and int(w.x) == c):
				room += 1
			var paper: int = WALLPAPER[(room + f) % WALLPAPER.size()]
			for r in BAND_ROWS:
				var idx: int = paper
				if r == 0:
					idx = paper if holes.has(Vector2i(c, f + 1)) else CEILING_TRIM
				elif r >= 6:
					idx = WAINSCOT[r - 6]
				_put(src, back, Vector2i(c, top + r), idx)
			if holes.has(Vector2i(c, f)):
				_put(src, back, Vector2i(c, _row(f)), paper)   # opened slab shows wallpaper

	for f in F + 1:
		for c in W + 1:
			if not holes.has(Vector2i(c, f)):
				_put(src, front, Vector2i(c, _row(f)), FLOOR_FILL if f == F else FLOOR_TOP)

	for s in L.stairs:
		var x := LevelValidator.stair_x(s)
		var rising_right: bool = s.top.x > s.bottom.x
		var ty := _row(int(s.to_floor))
		for key in STAIR_PIECES:
			var pc: Array = STAIR_PIECES[key]
			for i in int(pc[2]):
				for j in int(pc[3]):
					var ac := Vector2i(int(pc[0]) + i, int(pc[1]) + j)
					var col := x + ac.x if rising_right else x + STAIR_WIDTH - 1 - ac.x
					_put(src, stairs, Vector2i(col, ty + ac.y - SLAB_ATLAS_ROW), ac.y * COLS + ac.x, not rising_right)
		# gallery rail across the opening (x+9..x+14 + the rail cap's x+15..x+17, mirrored rising
		# left); its collision is the generator's Rails body
		var rail := rail_piece()
		var pc: Array = rail.piece
		var cells := []   # [atlas cell, stair column]
		if rail.name == GALLERY_RAIL:
			for i in int(pc[2]):
				for j in int(pc[3]):
					cells.append([Vector2i(int(pc[0]) + i, int(pc[1]) + j), int(pc[0]) + i])
		else:
			for c in range(9, 15):
				for j in int(pc[3]):
					cells.append([Vector2i(int(pc[0]) + (c - 9) % int(pc[2]), int(pc[1]) + j), c])
		for cell in cells:
			var ac: Vector2i = cell[0]
			var col: int = x + int(cell[1]) if rising_right else x + STAIR_WIDTH - 1 - int(cell[1])
			_put(src, stairs, Vector2i(col, ty + ac.y - SLAB_ATLAS_ROW), ac.y * COLS + ac.x, not rising_right)
		# slab ends where the cutout begins (x+8 rising right, x+12 rising left)
		if rising_right:
			_put(src, front, Vector2i(x + 8, ty), SLAB_END_RIGHT)
		else:
			_put(src, front, Vector2i(x + 12, ty), SLAB_END_LEFT)

	for w in L.walls:
		var top := _row(int(w.floor)) - BAND_ROWS
		var c := int(w.x)
		_put(src, front, Vector2i(c, top), WALL_COLUMN_TOP)
		var solid_rows := 9 if not bool(w.doorway) else 5
		for r in range(1, solid_rows):
			_put(src, front, Vector2i(c, top + r), WALL_COLUMN)
		if bool(w.doorway):
			_put(src, front, Vector2i(c, top + 5), DOOR_LINTEL)
			for r in range(6, 9):
				_put(src, front, Vector2i(c - 1, top + r), DOOR_POST_LEFT)
				_put(src, front, Vector2i(c + 1, top + r), DOOR_POST_RIGHT)
	return true


## Tile row of floor f's slab (its top edge is the floor surface).
## {name, piece [col,row,w,h]}: Designer's `stair_gallery_rail` from the manifest's tiles_stage1
## entry when present, else the `stair_rail_cap` fallback.
static func rail_piece() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f != null:
		var in_slot := false
		var rx := RegEx.create_from_string("^\\s*%s\\s*=\\s*\\[\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)" % GALLERY_RAIL)
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("[[asset]]"):
				in_slot = false
			elif line.strip_edges() == 'slot = "%s"' % SLOT:
				in_slot = true
			elif in_slot:
				var m := rx.search(line)
				if m:
					return {name = GALLERY_RAIL, piece = [int(m.strings[1]), int(m.strings[2]), int(m.strings[3]), int(m.strings[4])]}
	return {name = GALLERY_RAIL_FALLBACK, piece = STAIR_PIECES[GALLERY_RAIL_FALLBACK]}


static func _row(f: int) -> int:
	return int(LevelValidator.surface_y(f)) / T


static func _layer(level: Node2D, n: String, ts: TileSet, z: int) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = n
	l.tile_set = ts
	l.z_index = z
	l.collision_enabled = false
	level.add_child(l)
	return l


static func _put(src: TileSetAtlasSource, layer: TileMapLayer, cell: Vector2i, idx: int, flip := false) -> void:
	var ac := Vector2i(idx % COLS, idx / COLS)
	if not src.has_tile(ac):
		src.create_tile(ac)
	layer.set_cell(cell, 0, ac, TileSetAtlasSource.TRANSFORM_FLIP_H if flip else 0)

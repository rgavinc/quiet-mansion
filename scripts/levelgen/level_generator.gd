class_name LevelGenerator
extends RefCounted
## Seeded procedural side-scroll level (docs/LEVELGEN.md). Lead owns.
##
##   var L := LevelGenerator.generate(seed, stage)    # pure data, deterministic from (seed, stage)
##   var built := LevelGenerator.build(L, $World)     # nodes; also sets LevelNav.current
##
## generate() rolls a layout with a derived seed, runs LevelValidator (which also demands the
## full content budget), rerolls up to MAX_ATTEMPTS times, then falls back to a hand-made
## known-good layout for the stage. Never returns an invalid layout, never crashes on bad input.
##
## Layout (all positions are FEET points in World space; floor f surface y = -f*160):
##   seed, stage, attempt, rerolls, fallback, reject_reasons, build_seed
##   floors, width_tiles, safe_radius, budget {enemies, props, gold, chests}
##   rooms     [{floor, x0, x1}]               tiles, x1 = next wall column
##   walls     [{floor, x, doorway}]           tile column; doorway = 3-tile gap at floor level
##   furniture [{floor, x, w, h}]              tiles; h > 2 can't be jumped (blocks walking)
##   stairs    [{from_floor, to_floor, bottom, top}]   to_floor = from_floor + 1
##   props     [{type: "vase"|"obstacle", pos}]
##   gold      [{pos, amount}]
##   chests    [{pos}]
##   enemies   [{type, movement, pos, home, floor}]
##   start, exit

const TILE := 16
const FLOOR_PX := 160
const FLOOR_TILES := 10
const DOOR_ROWS := 3
const STAIR_TILES := 15          # diagonal run (240px) for a one-floor rise (160px), ~34 deg
const LANDING_TILES := 3         # flat landing beyond each end; footprint 21 tiles
const MAX_ATTEMPTS := 20
const PLAYER_RADIUS := 12.0
const PUPPET_RADIUS := 14.0
const ENEMY_SPACING := 64.0
const CHEST_SCRIPT := "res://scripts/world/chest.gd"

const C_SLAB := Color(0.42, 0.33, 0.27)
const C_WALL := Color(0.36, 0.28, 0.24)
const C_FURN := Color(0.52, 0.38, 0.26)
const C_STAIR := Color(0.62, 0.5, 0.36)


static func derive_seed(seed_value: int, stage: int, attempt: int) -> int:
	return ("qm:%d:%d:%d" % [seed_value, stage, attempt]).hash()


## opts: params (Dictionary overriding StageTable keys), max_attempts (int).
static func generate(seed_value: int, stage: int, opts: Dictionary = {}) -> Dictionary:
	var P := StageTable.params(stage)
	var over: Variant = opts.get("params", {})
	if over is Dictionary:
		P.merge(over, true)
	var max_a := maxi(int(opts.get("max_attempts", MAX_ATTEMPTS)), 0)
	var reasons: Array = []
	for attempt in max_a:
		var rng := RandomNumberGenerator.new()
		rng.seed = derive_seed(seed_value, stage, attempt)
		var L := generate_layout(rng, stage, P)
		if over is Dictionary and not (over as Dictionary).is_empty():
			L.custom_params = true   # tests only: table-match rules relaxed (see LevelValidator)
		var errs := LevelValidator.validate(L)
		if errs.is_empty():
			L.merge({seed = seed_value, attempt = attempt, rerolls = attempt, fallback = false,
					reject_reasons = reasons, build_seed = derive_seed(seed_value, stage, attempt)}, true)
			return L
		reasons.append(errs[0])
	push_warning("LevelGenerator: seed %d stage %d failed all %d attempts (last: %s); using the stage %d known-good layout" % [
			seed_value, stage, max_a, reasons[-1] if not reasons.is_empty() else "max_attempts 0", clampi(stage, 1, StageTable.STAGE_COUNT)])
	var fb := fallback_layout(stage)
	fb.merge({seed = seed_value, attempt = -1, rerolls = max_a, fallback = true,
			reject_reasons = reasons, build_seed = derive_seed(seed_value, stage, -1)}, true)
	return fb


static func _empty_layout(stage: int, floors: int, width_tiles: int, P: Dictionary) -> Dictionary:
	return {stage = stage, floors = floors, width_tiles = width_tiles,
			safe_radius = maxf(float(P.get("safe_radius", 0.0)), LevelValidator.MIN_ENEMY_DIST),
			budget = StageTable.budget_of(P), gold_floor = StageTable.gold_floor_min(P),
			rooms = [], walls = [], furniture = [], stairs = [], props = [], gold = [],
			chests = [], enemies = [], start = Vector2.ZERO, exit = Vector2.ZERO}


static func generate_layout(rng: RandomNumberGenerator, stage: int, P: Dictionary) -> Dictionary:
	var F := clampi(int(P.get("floors", 3)), LevelValidator.MIN_FLOORS, LevelValidator.MAX_FLOORS)
	var wt: Array = P.get("width_tiles", [240, 240])
	var U := rng.randi_range(ceili(float(wt[0]) / 4.0), maxi(floori(float(wt[wt.size() - 1]) / 4.0), ceili(float(wt[0]) / 4.0)))
	U = maxi(U, 5)
	var W := U * 4
	var L := _empty_layout(stage, F, W, P)
	# room walls stack floor to floor (one partition), so any room (24-40 tiles) can hold a
	# 21-tile stair footprint on both floors it joins; doorways are rolled per floor
	var parts: Array = _partition(rng, U)
	for f in F:
		var x := 0
		for i in parts.size():
			var w: int = parts[i] * 4
			L.rooms.append({floor = f, x0 = x, x1 = x + w})
			if i == 0:
				L.walls.append({floor = f, x = 0, doorway = false})
			var last := i == parts.size() - 1
			L.walls.append({floor = f, x = x + w,
					doorway = (not last) and rng.randf() >= float(P.get("solid_wall_chance", 0.0))})
			x += w

	# start (ground floor, one end) and exit (top floor, other end): always different floors
	var left := rng.randf() < 0.5
	var near_x := float(TILE + 40)
	var far_x := float(W * TILE - 40)
	L.start = Vector2(near_x if left else far_x, LevelValidator.surface_y(0))
	L.exit = Vector2(far_x if left else near_x, LevelValidator.surface_y(F - 1))
	var used := _used_from(L)

	# stairs between each adjacent pair
	var spl: Array = P.get("stairs_per_link", [1, 2])
	var smin := int(spl[0]) if spl.size() > 0 else 1
	var smax := int(spl[1]) if spl.size() > 1 else smin
	# Each stair is pushed flush against a solid end of the upper floor's walkable segment, on
	# the side its slab cutout faces, so the floor the cutout cuts off is a reserved dead pocket
	# (docs/DESIGN.md: hole over x+9..x+17 rising right). Random placement is the fallback.
	for f in F - 1:
		for k in rng.randi_range(smin, maxi(smax, smin)):
			var cands := _flush_candidates(L, f, LevelValidator.segments(L).get(f + 1, []))
			_shuffle(rng, cands)
			var placed := false
			for c in cands:
				if _try_stair(L, used, f, c[0], c[1]):
					placed = true
					break
			for _try in 40:
				if placed:
					break
				placed = _try_stair(L, used, f, rng.randi_range(1, W - 21), 1 if rng.randf() < 0.5 else -1)

	# furniture: one block per room at most
	for r in L.rooms:
		if rng.randf() >= float(P.get("furniture_chance", 0.0)):
			continue
		var w := rng.randi_range(2, 3)
		var h := rng.randi_range(3, 4) if rng.randf() < float(P.get("tall_furniture_chance", 0.0)) else rng.randi_range(1, 2)
		for _try in 12:
			var fx := rng.randi_range(int(r.x0) + 3, maxi(int(r.x1) - 3 - w, int(r.x0) + 3))
			var a := float((fx - 1) * TILE)
			var b := float((fx + w + 1) * TILE)
			if _free(used[r.floor], a, b) and LevelValidator.furniture_rail_ok(L, r.floor, fx * TILE, (fx + w) * TILE, h):
				L.furniture.append({floor = r.floor, x = fx, w = w, h = h})
				used[r.floor].append(Vector2(a, b))
				break

	_connect(rng, L, used)
	_populate(rng, L, P, used, stage)
	return L


## Px spans per floor that new things must keep clear of: walls (+ margin), start, exit,
## stairs, furniture.
static func _used_from(L: Dictionary) -> Dictionary:
	var used := {}
	for f in int(L.floors):
		used[f] = []
	for wl in L.walls:
		used[int(wl.floor)].append(Vector2((wl.x - 2) * TILE, (wl.x + 3) * TILE))
	used[LevelValidator.floor_of(L.start.y)].append(Vector2(L.start.x - 24, L.start.x + 24))
	used[LevelValidator.floor_of(L.exit.y)].append(Vector2(L.exit.x - 32, L.exit.x + 32))
	for st in L.stairs:
		var sp := LevelValidator.stair_span(st)
		used[int(st.from_floor)].append(sp)
		used[int(st.to_floor)].append(sp)
	for fu in L.furniture:
		used[int(fu.floor)].append(Vector2((fu.x - 1) * TILE, (fu.x + fu.w + 1) * TILE))
	return used


## Content: props (each with a clear jump lane), gold, chests, enemies (out of sight, a screen
## away). Fills L's lists; the validator rejects the layout if any budget is short.
static func _populate(rng: RandomNumberGenerator, L: Dictionary, P: Dictionary, used: Dictionary, stage: int) -> void:
	var F := int(L.floors)
	var lanes := {}
	for f in F:
		lanes[f] = []
	var lane := LevelValidator.PROP_LANE
	var rooms: Array = L.rooms
	if rooms.is_empty():
		return
	# breakable props: lane [x - lane, x + lane] clear of walls, stairs, furniture, start, exit, props
	for i in int(P.get("props", 0)):
		for _try in 120:
			var r: Dictionary = rooms[rng.randi() % rooms.size()]
			var lo := float(r.x0 * TILE) + TILE + lane + 1.0
			var hi := float(r.x1 * TILE) - lane - 1.0
			if hi <= lo:
				continue
			var x := roundf(rng.randf_range(lo, hi))
			var f: int = r.floor
			if not _free(used[f], x - lane - 1.0, x + lane + 1.0):
				continue
			var kind := "vase" if rng.randf() < float(P.get("vase_ratio", 0.5)) else "obstacle"
			L.props.append({type = kind, pos = Vector2(x, LevelValidator.surface_y(f))})
			used[f].append(Vector2(x - 12, x + 12))
			lanes[f].append(Vector2(x - lane - 1.0, x + lane + 1.0))
			break

	# gold piles (may sit in a prop lane: picking gold up is fine) and chests (never in a lane),
	# only on floor reachable from the start (not beyond a stair's slab cutout)
	var g := LevelValidator.floor_graph(L)
	var reach := LevelValidator.reachable_from(g, LevelValidator.node_at(g.segments, 0, L.start.x))
	var ga: Array = P.get("gold_amount", [1, 1])
	for key in ["gold", "chests"]:
		var half := 10.0 if key == "gold" else 14.0
		for i in int(P.get("gold_piles" if key == "gold" else "chests", 0)):
			for _try in 40:
				var r: Dictionary = rooms[rng.randi() % rooms.size()]
				var f: int = r.floor
				var lo := float((r.x0 + 2) * TILE)
				var hi := float((r.x1 - 1) * TILE)
				var x := roundf(rng.randf_range(lo, hi))
				if not _free(used[f], x - half, x + half):
					continue
				if key == "chests" and not _free(lanes[f], x - half, x + half):
					continue
				if not reach.has(LevelValidator.node_at(g.segments, f, x)):
					continue
				var y := LevelValidator.surface_y(f)
				if key == "gold":
					L.gold.append({pos = Vector2(x, y - 4), amount = rng.randi_range(int(ga[0]), int(ga[ga.size() - 1]))})
				else:
					L.chests.append({pos = Vector2(x, y)})
				used[f].append(Vector2(x - half, x + half))
				break

	# PD gold floor: raise the smallest piles (no RNG) until the floor-pile total reaches the table's minimum
	var gsum := 0
	for gp in L.gold:
		gsum += int(gp.amount)
	var gmax := int(ga[ga.size() - 1])
	while gsum < int(L.gold_floor):
		var lo_i := -1
		for gi in L.gold.size():
			if int(L.gold[gi].amount) < gmax and (lo_i < 0 or int(L.gold[gi].amount) < int(L.gold[lo_i].amount)):
				lo_i = gi
		if lo_i < 0:
			break
		L.gold[lo_i].amount = int(L.gold[lo_i].amount) + 1
		gsum += 1

	# enemies: a screen away from the start on any floor, off the start view, out of its sight
	var weights := {}
	var raw: Dictionary = P.get("enemy_weights", {"puppet_hand": 1.0})
	for id in raw:
		if int(StageTable.enemy_type(id).get("min_stage", 1)) <= stage:
			weights[id] = float(raw[id])
	if weights.is_empty():
		weights = {"puppet_hand": 1.0}
	var view := LevelValidator.start_view(L)
	var W := int(L.width_tiles)
	for i in int(P.get("enemies", 0)):
		var etype := _weighted(rng, weights)
		for _try in 80:
			var f := rng.randi_range(0, F - 1)
			var x := roundf(rng.randf_range(2.0 * TILE, (W - 1) * TILE))
			var p := Vector2(x, LevelValidator.surface_y(f))
			if not _free(used[f], x - PUPPET_RADIUS - 2.0, x + PUPPET_RADIUS + 2.0):
				continue
			if p.distance_to(L.start) < float(L.safe_radius) + 8.0:
				continue
			var hw := LevelValidator.ENEMY_HALF_W
			if view.intersects(Rect2(x - hw, p.y - 64.0, hw * 2.0, 64.0)):
				continue
			if LevelValidator.in_line_of_sight(L, L.start, p):
				continue
			# walkers only where the boy can walk to (never a gallery sealed between two stair
			# openings: they'd never move, QA); floaters drift through walls and may be anywhere
			if StringName(StageTable.movement_for(etype)) != &"float" and not reach.has(LevelValidator.node_at(g.segments, f, x)):
				continue
			var crowded := false
			for e in L.enemies:
				if (e.pos as Vector2).distance_to(p) < ENEMY_SPACING:
					crowded = true
					break
			if crowded:
				continue
			L.enemies.append({type = etype, movement = StageTable.movement_for(etype), pos = p, home = p, floor = f})
			used[f].append(Vector2(x - PUPPET_RADIUS - 2.0, x + PUPPET_RADIUS + 2.0))
			break


## Repair pass: while some walkable segment (walls/tall furniture split floors) can't be
## reached from the start, add a stair from a reached segment to an unreached one on an
## adjacent floor. Keeps rerolls rare without making every wall a doorway.
static func _connect(rng: RandomNumberGenerator, L: Dictionary, used: Dictionary) -> void:
	for _pass in 128:
		var g := LevelValidator.floor_graph(L)
		var reach := LevelValidator.reachable_from(g, LevelValidator.node_at(g.segments, 0, L.start.x))
		var missing := []
		for f in g.segments:
			for i in (g.segments[f] as Array).size():
				if not reach.has("%d:%d" % [f, i]) and not _is_pocket(L, f, g.segments[f][i]):
					missing.append([f, i])
		if missing.is_empty() or reach.is_empty():
			return
		var score := _reach_score(L)
		var placed := false
		for m in missing:
			for df in [-1, 1]:
				var f2: int = m[0] + df
				if placed or not g.segments.has(f2):
					continue
				var segs2: Array = g.segments[f2]
				for j in segs2.size():
					if placed or not reach.has("%d:%d" % [f2, j]):
						continue
					var a: Vector2 = g.segments[m[0]][m[1]]
					var b: Vector2 = segs2[j]
					var lo := ceili(maxf(a.x, b.x) / TILE) + LANDING_TILES
					var hi := floori(minf(a.y, b.y) / TILE) - LANDING_TILES
					if hi - lo < STAIR_TILES:
						continue
					var lower := mini(m[0], f2)
					var up_seg: Vector2 = a if m[0] > f2 else b
					var cands := _flush_candidates(L, lower, [up_seg])
					_shuffle(rng, cands)
					for _try in 24:
						cands.append([rng.randi_range(lo - LANDING_TILES, hi + LANDING_TILES - STAIR_TILES - 2 * LANDING_TILES),
								1 if rng.randf() < 0.5 else -1])
					for c in cands:
						if placed:
							break
						if not _try_stair(L, used, lower, c[0], c[1], false):
							continue
						if _reach_score(L) > score:   # keeps the exit, reaches more floor
							placed = true
						else:
							L.stairs.pop_back()
							used[lower].pop_back()
							used[lower + 1].pop_back()
		if not placed:
			placed = _open_blocker(L, g, reach, missing)
		if not placed:
			return


## Stair f->f+1 with leftmost tile x rising right (dir 1) or left (-1), if its 21-tile footprint
## is in bounds and free. bottom/top per docs/DESIGN.md: x+3 / x+18 rising right, mirrored left.
static func _try_stair(L: Dictionary, used: Dictionary, f: int, x: int, dir: int, guard := true) -> bool:
	var span := STAIR_TILES + 2 * LANDING_TILES
	if x < 1 or x + span > int(L.width_tiles):
		return false
	var bx := x + LANDING_TILES if dir > 0 else x + LANDING_TILES + STAIR_TILES
	var tx := bx + STAIR_TILES * dir
	var a := float(x * TILE)
	var b := float((x + span) * TILE)
	if not _stair_free(L, used, f, a, b) or (guard and _cutout_strands(L, f + 1, tx * TILE, dir)):
		return false
	var st := {from_floor = f, to_floor = f + 1,
			bottom = Vector2(bx * TILE, LevelValidator.surface_y(f)),
			top = Vector2(tx * TILE, LevelValidator.surface_y(f + 1))}
	# rails keep clear of running jumps off furniture already on the upper floor (QA #13 b2)
	for fu in L.furniture:
		if int(fu.floor) == f + 1:
			var ko := LevelValidator.rail_keepout(int(fu.h) * TILE)
			for rw in LevelValidator.stair_rail_walls(st):
				if ko > 0.0 and LevelValidator.span_gap(LevelValidator.furniture_span(fu), rw) <= ko:
					return false
	L.stairs.append(st)
	used[f].append(Vector2(a, b))
	used[f + 1].append(Vector2(a, b))
	return true


## True if a stair arriving on floor f with its top at px `top`, rising `dir`, would cut off the
## exit or another stair's end on f: the cutout faces away from the top, and everything from it
## to the next blocker that way is only reachable through the hole.
static func _cutout_strands(L: Dictionary, f: int, top: float, dir: int) -> bool:
	var hole := Vector2(minf(top, top - dir * LevelValidator.STAIR_HOLE_PX), maxf(top, top - dir * LevelValidator.STAIR_HOLE_PX))
	var lo := 0.0
	var hi := INF
	for bl in LevelValidator.blockers(L, f):
		if dir > 0 and bl.y <= hole.x:
			lo = maxf(lo, bl.y)
		elif dir < 0 and bl.x >= hole.y:
			hi = minf(hi, bl.x)
	var region := Vector2(lo, hole.x) if dir > 0 else Vector2(hole.y, hi)
	var pts := []
	if LevelValidator.floor_of(L.exit.y) == f:
		pts.append(L.exit.x)
	for st in L.stairs:
		if int(st.to_floor) == f:
			pts.append(st.top.x + signf(st.top.x - st.bottom.x))
		if int(st.from_floor) == f:
			pts.append(st.bottom.x)
	for x in pts:
		if x > region.x and x < region.y:
			return true
	return false


## [x, dir] for stairs flush against each end of the upper-floor segments and against the
## footprints of stairs already on floors f / f+1: rising right against a left anchor, rising
## left against a right anchor, so the cutout always faces the anchor.
static func _flush_candidates(L: Dictionary, f: int, segs: Array) -> Array:
	var span := STAIR_TILES + 2 * LANDING_TILES
	var out := []
	for sg in segs:
		out.append([ceili(sg.x / TILE) + 1, 1])
		out.append([floori(sg.y / TILE) - 1 - span, -1])
	for st in L.stairs:
		if int(st.from_floor) in [f, f + 1] or int(st.to_floor) in [f, f + 1]:
			var sp := LevelValidator.stair_span(st)
			out.append([roundi(sp.y / TILE), 1])
			out.append([roundi(sp.x / TILE) - span, -1])
	return out


## A walkable piece cut off by slab cutouts that nothing could use anyway: it lies inside the
## merged footprints (+1 tile) of the stairs on floor f. Nothing is ever placed there.
static func _is_pocket(L: Dictionary, f: int, sg: Vector2) -> bool:
	var spans := []
	for st in L.stairs:
		if int(st.to_floor) == f or int(st.from_floor) == f:
			var sp := LevelValidator.stair_span(st)
			spans.append(Vector2(sp.x - TILE - 0.5, sp.y + TILE + 0.5))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var cur := Vector2(INF, -INF)
	for sp in spans:
		if sp.x <= cur.y:
			cur.y = maxf(cur.y, sp.y)
		else:
			if sg.x >= cur.x and sg.y <= cur.y:
				return true
			cur = sp
	return sg.x >= cur.x and sg.y <= cur.y


static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## Walkable px reachable from the start (pockets excluded), +1e9 if the exit is reachable.
static func _reach_score(L: Dictionary) -> float:
	var g := LevelValidator.floor_graph(L)
	var reach := LevelValidator.reachable_from(g, LevelValidator.node_at(g.segments, 0, L.start.x))
	var out := 0.0
	for f in g.segments:
		for i in (g.segments[f] as Array).size():
			if reach.has("%d:%d" % [f, i]):
				out += g.segments[f][i].y - g.segments[f][i].x
	if reach.has(LevelValidator.node_at(g.segments, LevelValidator.floor_of(L.exit.y), L.exit.x)):
		out += 1e9
	return out


## Repair fallback: open the wall (-> doorway) or lower the tall furniture (-> 2 tiles) between
## an unreached segment and a reached neighbour on the same floor.
static func _open_blocker(L: Dictionary, g: Dictionary, reach: Dictionary, missing: Array) -> bool:
	# first next to a reached neighbour; failing that, next to any neighbour (exit's segment first)
	var ef := LevelValidator.floor_of(L.exit.y)
	var en := LevelValidator.node_at(g.segments, ef, L.exit.x)
	var order := missing.duplicate()
	order.sort_custom(func(a, b): return "%d:%d" % a == en and "%d:%d" % b != en)
	for any in [false, true]:
		if _open_next_to(L, g, reach, order, any):
			return true
	return false


static func _open_next_to(L: Dictionary, g: Dictionary, reach: Dictionary, missing: Array, any: bool) -> bool:
	for m in missing:
		var f: int = m[0]
		var i: int = m[1]
		var segs: Array = g.segments[f]
		for j in [i - 1, i + 1]:
			if j < 0 or j >= segs.size() or not (any or reach.has("%d:%d" % [f, j])):
				continue
			var a: float = minf(segs[i].y, segs[j].y)
			var b: float = maxf(segs[i].x, segs[j].x)
			var opened := false
			for wl in L.walls:
				var wx: float = wl.x * TILE
				if int(wl.floor) == f and not wl.doorway and wx >= a - 0.5 and wx + TILE <= b + 0.5 \
						and int(wl.x) > 0 and int(wl.x) < int(L.width_tiles):
					wl.doorway = true
					opened = true
			for fu in L.furniture:
				if int(fu.floor) == f and int(fu.h) > LevelValidator.MAX_JUMP_TILES \
						and fu.x * TILE >= a - 0.5 and (fu.x + fu.w) * TILE <= b + 0.5:
					fu.h = LevelValidator.MAX_JUMP_TILES
					opened = true
			if opened:
				return true
	return false


## Split U units into rooms of 5-10 units.
static func _partition(rng: RandomNumberGenerator, U: int) -> Array:
	# rooms of 6-10 units (24-40 tiles); never leave a remainder that can't be split (1-5, 11)
	var out := []
	var rem := U
	while rem > 10:
		var ks := []
		for k in range(6, 11):
			var r := rem - k
			if r == 0 or (r >= 6 and r != 11):
				ks.append(k)
		if ks.is_empty():
			break
		var k: int = ks[rng.randi_range(0, ks.size() - 1)]
		out.append(k)
		rem -= k
	if rem > 0:
		out.append(rem)
	return out


## A stair footprint [a, b] is clear on both its floors: no wall column (doorways included),
## furniture, or anything already placed (start, exit, other stairs). Walls only need their own
## tile clear here, not the generator's wider wall margin.
static func _stair_free(L: Dictionary, used: Dictionary, f: int, a: float, b: float) -> bool:
	for ff in [f, f + 1]:
		if LevelValidator._span_hits_solid(L, ff, a - 1.0, b + 1.0, true):
			return false
		for sp in used[ff]:
			if b > sp.x and a < sp.y and not _is_wall_margin(L, ff, sp):
				return false
	return true


static func _is_wall_margin(L: Dictionary, f: int, sp: Vector2) -> bool:
	for wl in L.walls:
		if int(wl.floor) == f and is_equal_approx(sp.x, (wl.x - 2) * TILE) and is_equal_approx(sp.y, (wl.x + 3) * TILE):
			return true
	return false


static func _free(spans: Array, a: float, b: float) -> bool:
	for s in spans:
		if b > s.x and a < s.y:
			return false
	return true


## Random x in [lo, hi] with `half` px clear either side, or NAN.
static func _free_x(rng: RandomNumberGenerator, spans: Array, lo: float, hi: float, half: float) -> float:
	if hi <= lo:
		return NAN
	for _try in 12:
		var x := roundf(rng.randf_range(lo, hi))
		if _free(spans, x - half, x + half):
			return x
	return NAN


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += maxf(float(weights[k]), 0.0)
	var r := rng.randf() * total
	for k in weights:
		r -= maxf(float(weights[k]), 0.0)
		if r <= 0.0:
			return k
	return weights.keys()[0]


## Hand-made, known-good layout for a stage (validated for every stage in tests). Used after
## MAX_ATTEMPTS rerolls. Stage-table floors and width (rounded to 40-tile rooms), every
## interior wall a doorway, no furniture, stairs zig-zag (ground floor right end -> next floor
## left end -> ...), start bottom-left, exit top-right. Content is placed with a fixed seed so
## the fallback is identical every time and still meets the full budget and every rule.
static func fallback_layout(stage: int) -> Dictionary:
	var st := clampi(stage, 1, StageTable.stage_count())
	var P := StageTable.params(st)
	var F := clampi(int(P.floors), LevelValidator.MIN_FLOORS, LevelValidator.MAX_FLOORS)
	var wt: Array = P.width_tiles
	var rooms_n := maxi(roundi((float(wt[0]) + float(wt[wt.size() - 1])) / 2.0 / 40.0), 2)
	var W := rooms_n * 40
	var L := _empty_layout(st, F, W, P)
	for f in F:
		for i in rooms_n:
			L.rooms.append({floor = f, x0 = i * 40, x1 = i * 40 + 40})
		for i in rooms_n + 1:
			L.walls.append({floor = f, x = i * 40, doorway = i != 0 and i != rooms_n})
	L.start = Vector2(56, 0)
	# exit at the end of the top floor away from the last stair's footprint
	L.exit = Vector2(W * TILE - 40 if F % 2 == 1 else 56.0, LevelValidator.surface_y(F - 1))
	for f in F - 1:
		# zig-zag: even floors climb leftwards at the right end, odd floors rightwards at the left end
		var bx := W - LANDING_TILES - 1 if f % 2 == 0 else LANDING_TILES + 2   # flush to the end wall (cutout faces it)
		var tx := bx - STAIR_TILES if f % 2 == 0 else bx + STAIR_TILES
		L.stairs.append({from_floor = f, to_floor = f + 1,
				bottom = Vector2(bx * TILE, LevelValidator.surface_y(f)),
				top = Vector2(tx * TILE, LevelValidator.surface_y(f + 1))})
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(0, st, -99)
	_populate(rng, L, P, _used_from(L), st)
	return L


## Build nodes under `world` (main.tscn's World: uses Player/Exit/Puppets/Obstacles if present).
## Invalid layouts are replaced by the fallback. Returns {level, player, exit, enemies, stairs,
## bounds, nav, layout} or {} if world is null.
## Art: LevelSkin.paint() dresses the level from the docs/DESIGN.md `tiles_stage1` atlas
## (band dressing, stair_stamp / landing_bottom / landing_top / stair_rail_cap, slabs with the
## stair cutout and slab ends, wall columns, doorway trim) and hides the placeholder colours.
## `skin`, if set, replaces it: called as skin.call(level, layout) after geometry + stairs.
## Collision is always the generator's plain boxes, so painting is purely visual.
static var skin: Callable = Callable()


static func build(layout: Variant, world: Node) -> Dictionary:
	if world == null or not is_instance_valid(world):
		return {}
	var L: Dictionary = layout if layout is Dictionary else {}
	if not LevelValidator.validate(L).is_empty():
		push_warning("LevelGenerator.build: invalid layout (seed %s stage %s): %s; using the stage known-good layout" % [
				L.get("seed", "?"), L.get("stage", "?"), LevelValidator.validate(L).slice(0, 1)])
		L = fallback_layout(int(L.get("stage", 1)))
	seed(int(L.get("build_seed", 0)))   # Vase._ready rolls hidden gold with the global RNG
	var F := int(L.floors)
	var W := int(L.width_tiles)
	var right := float((W + 1) * TILE)

	var level := Node2D.new()
	level.name = "Level"
	world.add_child(level)
	world.move_child(level, 0)
	var geo := StaticBody2D.new()
	geo.name = "Geometry"
	geo.collision_layer = PlayerStats.LAYER_WORLD
	geo.collision_mask = 0
	level.add_child(geo)
	var placeholder: Array[ColorRect] = []
	for f in F + 1:   # slab under every floor + ceiling, cut open over each stair arriving here
		var y := float(LevelValidator.surface_y(f))
		var holes: Array = []
		for s in L.stairs:
			if int(s.to_floor) == f:
				holes.append(LevelValidator.stair_hole(s))
		holes.sort_custom(func(a, b): return a.x < b.x)
		var x0 := 0.0
		for h in holes:
			if h.x > x0:
				placeholder.append(_box(geo, Rect2(x0, y, h.x - x0, TILE), C_SLAB))
			x0 = maxf(x0, h.y)
		if x0 < right:
			placeholder.append(_box(geo, Rect2(x0, y, right - x0, TILE), C_SLAB))
	# gallery rail wall at the far edge of every stair opening (PRODUCT.md, QA-revised): world
	# collision, so the boy and walkers can't walk or jump into the opening; floaters don't mask
	# WORLD and drift through; climbers pass 96px under its foot. Plus a near-edge guard inside the
	# opening 16px back from the top landing (LevelValidator.stair_rail_near).
	var rails_body := StaticBody2D.new()
	rails_body.name = "Rails"
	rails_body.collision_layer = PlayerStats.LAYER_WORLD
	rails_body.collision_mask = 0
	level.add_child(rails_body)
	var rails := []
	for s in L.stairs:
		var ty := float(LevelValidator.surface_y(int(s.to_floor)))
		for r in LevelValidator.stair_rail_walls(s):
			var rect := Rect2(r.x, ty - LevelValidator.RAIL_H_PX, r.y - r.x, LevelValidator.RAIL_H_PX)
			placeholder.append(_box(rails_body, rect, C_STAIR))
			rails.append(rect)
	for wl in L.walls:
		var surf := float(LevelValidator.surface_y(wl.floor))
		var top := surf - (FLOOR_TILES - 1) * TILE
		var h := (FLOOR_TILES - 1 - (DOOR_ROWS if wl.doorway else 0)) * TILE
		placeholder.append(_box(geo, Rect2(wl.x * TILE, top, TILE, h), C_WALL))
	# Furniture <= 2 tiles is a jump-up for the boy and walkable in the nav graph (segments only
	# split at walls and tall furniture), but walkers can't jump: they parked against it (QA route
	# gap). It gets its own WORLD body that every built enemy has a collision exception with, so
	# walkers pass in front of it; the boy, light, sight rays and throws see it exactly as before.
	var low_furn := StaticBody2D.new()
	low_furn.name = "LowFurniture"
	low_furn.collision_layer = PlayerStats.LAYER_WORLD
	low_furn.collision_mask = 0
	level.add_child(low_furn)
	for fu in L.furniture:
		var surf := float(LevelValidator.surface_y(fu.floor))
		var low := int(fu.h) <= LevelValidator.MAX_JUMP_TILES
		_box(low_furn if low else geo, Rect2(fu.x * TILE, surf - fu.h * TILE, fu.w * TILE, fu.h * TILE), C_FURN)

	var stairs := []
	var lines: Array = []
	var stair_root := Node2D.new()
	stair_root.name = "Stairs"
	level.add_child(stair_root)
	for s in L.stairs:
		var st: Area2D = load("res://scripts/levelgen/level_stair.gd").new()   # BE Stair + landing-side upper entry (QA B2)
		st.position = s.bottom
		st.bottom = Vector2.ZERO
		st.top = s.top - s.bottom
		st.from_floor = s.from_floor
		st.to_floor = s.to_floor
		var line := Line2D.new()
		line.points = PackedVector2Array([st.bottom, st.top])
		line.width = 6.0
		line.default_color = C_STAIR
		line.z_index = -4
		st.add_child(line)
		lines.append(line)
		stair_root.add_child(st)
		stairs.append(st)

	var painted := false
	if skin.is_valid():
		skin.call(level, L)
	else:
		painted = LevelSkin.paint(level, L)
	if painted:   # atlas drew slabs, walls and stairs: drop their placeholder colours
		for r in placeholder:
			r.visible = false
		for ln in lines:
			ln.visible = false

	var props_root := _child(world, "Obstacles", level)
	for p in L.props:
		var ob: Node2D = load("res://scripts/world/vase.gd" if p.type == "vase" else "res://scripts/world/obstacle.gd").new()
		ob.position = p.pos + Vector2(0, -10)   # WorldObject draws centred
		props_root.add_child(ob)
	for g in L.gold:
		var gp := Node2D.new()
		gp.set_script(load("res://scripts/world/gold_pickup.gd"))
		gp.set("amount", int(g.amount))
		gp.position = g.pos
		level.add_child(gp)
	for c in L.chests:
		var ch: Node2D
		if ResourceLoader.exists(CHEST_SCRIPT):
			ch = load(CHEST_SCRIPT).new()
		else:
			ch = Marker2D.new()   # spot only until BE ships chest.gd
			ch.add_to_group("chest_spots")
		ch.position = c.pos
		level.add_child(ch)

	var enemies := []
	var en_root := _child(world, "Puppets", level)
	for e in L.enemies:
		var def := StageTable.enemy_def(str(e.type))
		var en: CharacterBody2D = load(def.script_path).new()
		if "def" in en:   # BE Enemy (#26): _ready applies type_id / movement from the def
			en.set("def", def)
		en.set_meta("enemy_def", def)
		# BE's enemy shape exactly as BE's own scenes/tests make it: a centred circle, origin at
		# the body centre (enemy_base _feet() = origin + _foot()). Never offset it (QA B1: a
		# feet-origin offset broke the ledge ray and stair feet checks); spawn the centre so the
		# feet (layout point) land on the floor.
		_circle_centred(en, PUPPET_RADIUS)
		var foot: float = en.call("_foot") if en.has_method("_foot") else PUPPET_RADIUS
		en.position = (e.pos as Vector2) - Vector2(0, foot)
		en.set_meta("enemy_type", str(e.type))
		en.set_meta("movement", e.movement)
		en.set_meta("home", e.home)
		if "movement" in en:   # EnemyDef.movement once BE's state machine lands
			en.set("movement", e.movement)
		en_root.add_child(en)
		en.add_collision_exception_with(low_furn)   # walkers can't jump: they pass low furniture
		enemies.append(en)

	var player := CharacterBody2D.new()
	player.set_script(load("res://scripts/player/player_controller.gd"))
	_circle(player, PLAYER_RADIUS)
	player.set("side_scroll", true)
	player.position = L.start
	_child(world, "Player", level).add_child(player)
	var fl := player.get_node_or_null("Flashlight") as Node2D
	if fl:
		fl.position = Vector2(0, -30)

	var ex := Area2D.new()
	ex.set_script(load("res://scripts/world/exit_zone.gd"))
	ex.position = L.exit + Vector2(0, -32)
	_child(world, "Exit", level).add_child(ex)

	_stable_names(level)
	for n in [player, ex] + enemies:
		_stable_names(n.get_parent())

	var nav := LevelNav.from_layout(L)
	LevelNav.current = nav
	level.set_meta("nav", nav)
	level.set_meta("layout", L)
	level.add_to_group("level")
	level.tree_exiting.connect(func(): if LevelNav.current == nav: LevelNav.current = null)
	return {level = level, player = player, exit = ex, enemies = enemies, stairs = stairs,
			rails = rails, bounds = LevelValidator.level_bounds(L), nav = nav, layout = L}


## Give auto-named ("@Class@123") children deterministic names so a rebuild of the same seed
## yields an identical node tree (names included).
static func _stable_names(n: Node) -> void:
	var i := 0
	for c in n.get_children():
		if str(c.name).begins_with("@"):
			c.name = "%s_%d" % [c.get_class(), i]
		i += 1
		if c.get_child_count() > 0 and c.owner == null:
			_stable_names(c)


static func _child(world: Node, name: String, fallback: Node) -> Node:
	var n := world.get_node_or_null(name)
	return n if n else fallback


static func _box(body: StaticBody2D, r: Rect2, color: Color) -> ColorRect:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	body.add_child(cs)
	var vis := ColorRect.new()
	vis.position = r.position
	vis.size = r.size
	vis.color = color
	vis.z_index = -5
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(vis)
	return vis


## BE enemy body shape: circle centred on the node origin (BE convention).
static func _circle_centred(body: CollisionObject2D, radius: float) -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	body.add_child(cs)


## Collision circle with its bottom at the node origin (feet), matching bottom-centre art (boy:
## his controller climbs with global_position = the stair's feet point).
static func _circle(body: CollisionObject2D, radius: float) -> void:
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	cs.position = Vector2(0, -radius)
	body.add_child(cs)

class_name LevelValidator
extends RefCounted
## Checks a LevelGenerator layout against docs/LEVELGEN.md. Pure data, no nodes, never crashes:
## validate() returns a list of human-readable problems; empty = good. Lead owns.
##
## Rules:
##  - geometry sane: 3-4 floors, rooms 24-40 tiles (a 21-tile stair footprint fits), everything
##    inside the level bounds
##  - start and exit on DIFFERENT floors
##  - every stair joins two existing, adjacent floors (to_floor = from_floor + 1), its ends
##    sit on both floor surfaces, it is a diagonal of exactly STAIR_RUN_PX (240px = 15 tiles)
##    horizontal x 160px rise (~34 deg), and its footprint = bottom landing + run + top landing
##    (48 + 240 + 48 = 336px = 21 tiles) is inside the level and clear of walls (doorways too)
##    and furniture on BOTH floors. Nothing else (props, gold, chests, enemies, start, exit,
##    other stairs) may sit in a footprint, so landings are always clear (overlap rule).
##    `bottom` = start of the diagonal at the end of the bottom landing; `top` = end of the
##    diagonal at the start of the top landing. Placement per docs/DESIGN.md (wide-stair art):
##    leftmost tile x, bottom = left edge of tile x+3 (lower floor), top = left edge of tile
##    x+18 (upper floor) for a stair rising right; columns mirrored (c -> x+20-c) rising left.
##    Both ends sit on tile edges.
##  - the upper floor slab is cut open over the 9 diagonal tiles next to `top` (x+9..x+17
##    rising right, x+3..x+11 rising left). The hole is a blocker in the floor graph (too wide
##    to jump), so the route never relies on floor the cutout removes, and nothing (start,
##    exit, props, gold, chests, enemies) may stand over it.
##  - exit reachable from start by walking + stairs only. Walls without a doorway and furniture
##    taller than 2 tiles block; furniture <= 2 tiles can be jumped onto (jump apex ~52px).
##  - no prop ever has to be broken: every prop has a clear jump lane (PROP_LANE px each side,
##    no walls/doorway lintels, furniture, stairs, other props, chests, start or exit), and a
##    plain jump over it never comes within its touch radius (prop_jump_clears). No pickup/throw.
##  - every gold pile, chest and walking enemy is reachable
##  - no enemy within max(safe_radius, 1280px) of the start on ANY floor (straight-line
##    distance), none inside the start camera view, none in line of sight of the start
##  - nothing overlaps: start, exit, stairs, props, gold, chests, enemies each own a footprint
##    on their floor; none of them sits inside a wall column or furniture
##  - full content budget: layout.budget {enemies, props, gold, chests} all met exactly

const TILE := 16.0
const FLOOR_PX := 160.0
const MIN_FLOORS := 3
const MAX_FLOORS := 4
const MAX_JUMP_TILES := 2
const MOUNT_TILES := 3             # the climb-over piece: 48px, above one capped jump from the floor (apex 52.2px, margin 4.2px) - never climbed directly
const MOUNT_STEP_MAX_TILES := 2   # steps touching it are 1-2 tiles, so every single climb is <= 2 tiles (32px)
const MOUNT_MARGIN_PX := 16.0     # apex clearance over the tallest single climb required (actual margin: 52.2 - 32 = 20.2px)
const MOUNT_RUN_TILES := 2        # open floor wanted beyond the steps on both sides
const BLOCKER_MARGIN_PX := 8.0    # a blocker's top must stay this far above the best capped jump from any surface next to it
const EXIT_STAIR_PX := 600.0       # a cluster side's exit: stairs (a stair foot or a slab cutout edge) within this run ...
const EXIT_OPEN_PX := 1500.0       # ... or this much open floor (no wall, blocker or cutout) to run along
const MIN_ROOM_TILES := 24
const MAX_ROOM_TILES := 40
const STAIR_RUN_PX := 240.0         # 15 tiles horizontal for a 160px rise (~34 deg, boy_climb_stairs art)
const STAIR_LANDING_PX := 48.0      # 3-tile flat landing beyond each end of the diagonal
const STAIR_HOLE_PX := 144.0        # upper slab cut open over 9 tiles (x+9..x+17 rising right)
const RAIL_H_PX := 96.0             # gallery rail collider height above the upper surface (QA: the boy's
                                   # jump apex is ~52-55px; 96 leaves >= 40px for future jump boosts;
                                   # test_levelgen checks apex at the stat cap + 16px <= this). The
                                   # visible handrail is 28px, finial 40px; the rest is invisible.
const NEAR_GUARD_PX := 16.0         # near-edge guard set-back from the top landing edge (> 14px radius)
const RAIL_W_PX := 6.0              # rail wall thickness, on the slab at the opening's far edge
const STAIR_FOOTPRINT_PX := STAIR_RUN_PX + 2.0 * STAIR_LANDING_PX   # 336px = 21 tiles
const SCREEN := Vector2(1280, 720)  # project viewport; the camera is zoom 1
const MIN_ENEMY_DIST := 1280.0      # one screen, any floor
const ENEMY_HALF_W := 32.0          # puppet art half-width, for the on-screen check
const SIGHT_PX := 1280.0            # a full screen: the start sits at a level edge, where the camera is clamped
const PROP_LANE := 64.0             # clear px either side of a prop to jump it (see prop_jump_clears)
const PROP_LIFT := 10.0             # props are built 10px above the floor (WorldObject draws centred)
const PROP_TOUCH := 12.0            # WorldObject.touch_radius
## Footprint half-widths on a floor (px).
const HALF := {start = 16.0, exit = 24.0, props = 10.0, gold = 8.0, chests = 12.0, enemies = 14.0}
const REQUIRED := ["floors", "width_tiles", "rooms", "walls", "furniture", "stairs",
		"props", "gold", "chests", "enemies", "start", "exit", "budget"]


static func surface_y(f: int) -> float:
	return -f * FLOOR_PX


## Floor index for a point standing on (or above, within the band) a floor surface.
static func floor_of(y: float) -> int:
	return int(floor(-(y - 0.5) / FLOOR_PX)) if y <= 0.5 else 0


static func validate(layout: Variant) -> PackedStringArray:
	var errs: PackedStringArray = []
	if not (layout is Dictionary) or (layout as Dictionary).is_empty():
		errs.append("layout is empty or not a Dictionary")
		return errs
	var L: Dictionary = layout
	for k in REQUIRED:
		if not L.has(k) or L[k] == null:
			errs.append("missing key: %s" % k)
	if not errs.is_empty():
		return errs
	var F := int(L.floors)
	var W := int(L.width_tiles)
	if F < MIN_FLOORS or F > MAX_FLOORS:
		errs.append("floors %d outside %d-%d" % [F, MIN_FLOORS, MAX_FLOORS])
		return errs
	if W < 20:
		errs.append("level only %d tiles wide" % W)
		return errs
	var bounds := level_bounds(L)
	var stage := int(L.get("stage", 0))
	var table := {}
	if stage >= 1 and stage <= StageTable.STAGE_COUNT and not L.get("custom_params", false):
		table = StageTable.params(stage)
	var table_errs := _table_errors(L, F, W, stage, table)

	for r in L.rooms:
		var w := int(r.x1) - int(r.x0)
		if w < MIN_ROOM_TILES or w > MAX_ROOM_TILES:
			errs.append("room on floor %d is %d tiles wide (%d-%d)" % [r.floor, w, MIN_ROOM_TILES, MAX_ROOM_TILES])
		if int(r.floor) < 0 or int(r.floor) >= F:
			errs.append("room on missing floor %d" % r.floor)

	for key in ["start", "exit"]:
		var p: Variant = L[key]
		if not (p is Vector2):
			errs.append("%s is not a position" % key)
			return errs
		if not bounds.has_point(p):
			errs.append("%s %s out of bounds" % [key, p])
	if floor_of(L.start.y) == floor_of(L.exit.y):
		errs.append("exit is on the start floor (%d)" % floor_of(L.start.y))

	# stairs
	var stairs_seen: Array = []
	for s in L.stairs:
		var ff := int(s.get("from_floor", -1))
		var tf := int(s.get("to_floor", -1))
		if ff < 0 or tf < 0 or ff >= F or tf >= F:
			errs.append("stair %d->%d joins a floor that doesn't exist" % [ff, tf])
			continue
		if tf != ff + 1:
			errs.append("stair %d->%d doesn't join adjacent floors" % [ff, tf])
			continue
		if not (s.get("bottom") is Vector2) or not (s.get("top") is Vector2):
			errs.append("stair %d->%d has no end points" % [ff, tf])
			continue
		var b: Vector2 = s.bottom
		var t: Vector2 = s.top
		if not bounds.has_point(b) or not bounds.has_point(t):
			errs.append("stair %d->%d out of bounds" % [ff, tf])
			continue
		if not is_equal_approx(b.y, surface_y(ff)) or not is_equal_approx(t.y, surface_y(tf)):
			errs.append("stair %d->%d ends are not on the floor surfaces" % [ff, tf])
		if not is_equal_approx(absf(t.x - b.x), STAIR_RUN_PX):
			errs.append("stair %d->%d at x=%d runs %dpx, must be %dpx (15 tiles)" % [ff, tf, int(b.x), int(absf(t.x - b.x)), int(STAIR_RUN_PX)])
		if fmod(b.x, TILE) != 0.0 or fmod(t.x, TILE) != 0.0:
			errs.append("stair %d->%d at x=%d: ends must sit on tile left edges (x+3 / x+18)" % [ff, tf, int(b.x)])
		var sp := stair_span(s)
		if sp.x < bounds.position.x or sp.y > bounds.end.x:
			errs.append("stair %d->%d at x=%d: landing out of bounds" % [ff, tf, int(b.x)])
		if _span_hits_solid(L, ff, sp.x, sp.y, false) or _span_hits_solid(L, tf, sp.x, sp.y, false):
			errs.append("stair %d->%d at x=%d (footprint incl. landings) is blocked by a wall, doorway or furniture" % [ff, tf, int(b.x)])
		stairs_seen.append(s)
		# gallery rail wall: at the opening's far edge, on solid slab, inside the stair footprint
		var rw := stair_rail(s)
		var ho := stair_hole(s)
		var far_edge: float = ho.x if t.x > b.x else ho.y   # where the upper floor drops off
		var touches := is_equal_approx(rw.y, far_edge) if t.x > b.x else is_equal_approx(rw.x, far_edge)
		if not touches or (rw.y > ho.x + 0.01 and rw.x < ho.y - 0.01) or rw.x < sp.x or rw.y > sp.y:
			errs.append("stair %d->%d at x=%d: gallery rail wall %s not on the slab at the opening's far edge" % [ff, tf, int(b.x), rw])
		var rn := stair_rail_near(s)
		var near_edge: float = ho.y if t.x > b.x else ho.x
		if rn.x < ho.x or rn.y > ho.y or minf(absf(rn.x - near_edge), absf(rn.y - near_edge)) < NEAR_GUARD_PX - 0.01:
			errs.append("stair %d->%d at x=%d: near-edge guard %s not inside the opening %dpx back from the top landing" % [ff, tf, int(b.x), rn, int(NEAR_GUARD_PX)])
		# upper slab cutout (x+9..x+17): nothing may stand over the hole
		var hole := stair_hole(s)
		for o in occupants(L):
			if o.what != "stair" and int(o.floor) == tf and o.b > hole.x and o.a < hole.y:
				errs.append("%s at %s over the stair %d->%d slab cutout" % [o.what, o.pos, ff, tf])
	# no standable spot (floor or furniture top) lets a capped running jump clear a rail (QA #13 b2/b3)
	errs.append_array(rail_jump_errors(L))
	# a piece the floor graph treats as a blocker is never climbable, from the floor or from furniture next to it
	errs.append_array(blocker_climb_errors(L))
	errs.append_array(shake_off_errors(L))
	errs.append_array(cluster_exit_errors(L))
	if not errs.is_empty():
		errs.append_array(table_errs)
		return errs

	# reachability over the floor graph (same graph LevelNav routes enemies on)
	var g := floor_graph(L)
	var reach := reachable_from(g, node_at(g.segments, floor_of(L.start.y), L.start.x))
	var exit_node := node_at(g.segments, floor_of(L.exit.y), L.exit.x)
	if exit_node == "" or not reach.has(exit_node):
		errs.append("exit not reachable from start by walking + stairs")
	for key in ["gold", "chests"]:
		for o in L[key]:
			if not (o.get("pos") is Vector2):
				continue
			var n := node_at(g.segments, floor_of(o.pos.y), o.pos.x)
			if n == "" or not reach.has(n):
				errs.append("%s at %s not reachable" % [key, o.pos])
	for e in L.get("enemies", []):   # walkers must be able to walk to the boy (floaters fly)
		if e.get("pos") is Vector2 and StringName(e.get("movement", &"walk")) != &"float":
			var n := node_at(g.segments, floor_of(e.pos.y), e.pos.x)
			if n == "" or not reach.has(n):
				errs.append("walker %s at %s not reachable from the start" % [e.get("type", "?"), e.pos])

	# enemies: distance (any floor), start camera view, line of sight
	var safe := maxf(maxf(float(L.get("safe_radius", 0.0)), float(table.get("safe_radius", 0.0))), MIN_ENEMY_DIST)
	var view := start_view(L)
	for e in L.enemies:
		var p: Vector2 = e.get("pos", Vector2.INF)
		if not bounds.has_point(p):
			continue   # reported by the footprint pass
		if p.distance_to(L.start) < safe:
			errs.append("enemy %s too close to start (%dpx < %dpx)" % [p, int(p.distance_to(L.start)), int(safe)])
		elif view.intersects(Rect2(p.x - ENEMY_HALF_W, p.y - 64.0, ENEMY_HALF_W * 2.0, 64.0)):
			errs.append("enemy %s on screen at the start" % p)
		elif in_line_of_sight(L, L.start, p):
			errs.append("enemy %s in line of sight of start" % p)

	# footprints: bounds, inside geometry, overlaps
	var occ := occupants(L)
	var by_floor := {}
	for o in occ:
		if not bounds.has_point(o.pos):
			errs.append("%s %s out of bounds" % [o.what, o.pos])
			continue
		if o.what != "stair" and _span_hits_solid(L, o.floor, o.a, o.b, false):
			errs.append("%s %s inside a wall or furniture" % [o.what, o.pos])
		by_floor.get_or_add(o.floor, []).append(o)
	for f in by_floor:
		var list: Array = by_floor[f]
		list.sort_custom(func(a, b): return a.a < b.a)
		var reach_end := -INF
		var last: Dictionary = {}
		for o in list:
			if o.a < reach_end:
				errs.append("%s %s overlaps %s %s on floor %d" % [o.what, o.pos, last.what, last.pos, f])
			if o.b > reach_end:
				reach_end = o.b
				last = o

	# props: a clear jump lane, so none ever has to be broken
	for o in occ:
		if o.what != "props":
			continue
		var a: float = o.pos.x - PROP_LANE
		var z: float = o.pos.x + PROP_LANE
		if a < TILE or z > W * TILE:
			errs.append("prop %s has no jump lane (level edge)" % o.pos)
			continue
		if _span_hits_solid(L, o.floor, a, z, true):
			errs.append("prop %s has no jump lane (wall, doorway, furniture or stair)" % o.pos)
			continue
		for q in by_floor.get(o.floor, []):
			if q == o or q.what in ["gold", "enemies", "stair"]:
				continue   # gold is picked up, enemies move; stairs checked above
			if q.b > a and q.a < z:
				errs.append("prop %s has no jump lane (%s %s)" % [o.pos, q.what, q.pos])
				break

	# content budget
	var bud: Variant = L.budget
	if bud is Dictionary:
		for k in ["enemies", "props", "gold", "chests"]:
			if (L[k] as Array).size() != int(bud.get(k, 0)):
				errs.append("budget: %d/%d %s" % [(L[k] as Array).size(), int(bud.get(k, 0)), k])
	else:
		errs.append("budget is not a Dictionary")
	# PD gold floor: floor piles alone reach the stage's guaranteed minimum
	var gsum := StageTable.worst_roll_gold(L)
	if gsum < int(L.get("gold_floor", 0)):
		errs.append("gold floor: floor piles total %d < the stage minimum %d" % [gsum, int(L.get("gold_floor", 0))])
	errs.append_array(table_errs)
	return errs


## Stage-table rules (QA): floors, width, budget and enemy types must match StageTable for
## the layout's stage unless it was built with custom params.
static func _table_errors(L: Dictionary, F: int, W: int, stage: int, table: Dictionary) -> PackedStringArray:
	var te: PackedStringArray = []
	# the stage table is the source of truth (QA): floors, width, budget, safe radius, enemy types
	if not table.is_empty():
		var wt: Array = table.width_tiles
		if F != int(table.floors):
			te.append("stage %d needs %d floors, has %d" % [stage, table.floors, F])
		if W < int(wt[0]) or W > int(wt[wt.size() - 1]):
			te.append("stage %d width %d tiles outside the table's %d-%d" % [stage, W, wt[0], wt[wt.size() - 1]])
		if int(L.get("gold_floor", 0)) < StageTable.gold_floor_min(table):
			te.append("gold floor %d below the stage table's %d" % [int(L.get("gold_floor", 0)), StageTable.gold_floor_min(table)])
		var tb := StageTable.budget(stage)
		if L.budget is Dictionary:
			for k in tb:
				if int((L.budget as Dictionary).get(k, -1)) != int(tb[k]):
					te.append("budget %s %d != stage table %d" % [k, int((L.budget as Dictionary).get(k, -1)), tb[k]])
	for e in L.enemies:
		var id := str(e.get("type", ""))
		if not StageTable.ENEMY_TYPES.has(id):
			te.append("enemy type '%s' not in StageTable.ENEMY_TYPES" % id)
			continue
		var t: Dictionary = StageTable.ENEMY_TYPES[id]
		if stage >= 1 and int(t.min_stage) > stage:
			te.append("enemy type %s before its min_stage %d" % [id, t.min_stage])
		if StringName(e.get("movement", &"")) != StringName(t.movement):
			te.append("enemy %s movement %s != table %s" % [id, e.get("movement"), t.movement])
	return te


## Everything that takes floor space: [{what, floor, a, b, pos}] (stairs on both their floors).
static func occupants(L: Dictionary) -> Array:
	var out := []
	for key in ["start", "exit"]:
		var p: Variant = L.get(key)
		if p is Vector2:
			out.append({what = key, floor = floor_of(p.y), a = p.x - HALF[key], b = p.x + HALF[key], pos = p})
	for key in ["props", "gold", "chests", "enemies"]:
		for o in L.get(key, []):
			var p: Variant = o.get("pos") if o is Dictionary else null
			if not (p is Vector2):
				out.append({what = key, floor = -99, a = 0.0, b = 0.0, pos = Vector2.INF})
				continue
			out.append({what = key, floor = floor_of(p.y), a = p.x - HALF[key], b = p.x + HALF[key], pos = p})
	for s in L.get("stairs", []):
		if not (s.get("bottom") is Vector2) or not (s.get("top") is Vector2):
			continue
		var sp := stair_span(s)
		out.append({what = "stair", floor = int(s.from_floor), a = sp.x, b = sp.y, pos = s.bottom})
		out.append({what = "stair", floor = int(s.to_floor), a = sp.x, b = sp.y, pos = s.top})
	return out


## What the camera shows when the level starts: centred on the start, clamped to the level
## (main.gd's camera limits; levels smaller than the screen are centred).
static func start_view(L: Dictionary) -> Rect2:
	var b := level_bounds(L)
	var c := b.get_center()
	var lo := Vector2(minf(b.position.x, c.x - SCREEN.x / 2), minf(b.position.y, c.y - SCREEN.y / 2))
	var hi := Vector2(maxf(b.end.x, c.x + SCREEN.x / 2), maxf(b.end.y, c.y + SCREEN.y / 2))
	var p: Vector2 = L.get("start", Vector2.ZERO)
	var x := clampf(p.x - SCREEN.x / 2, lo.x, hi.x - SCREEN.x)
	var y := clampf(p.y - SCREEN.y / 2, lo.y, hi.y - SCREEN.y)
	return Rect2(Vector2(x, y), SCREEN)


## True if a player running at `speed` can jump (jump_velocity, gravity) over a prop with
## touch radius `touch` sitting `lift` px above the floor without ever touching it, taking off
## and landing within `lane` px of it. Simulated at 60 Hz like the game.
static func prop_jump_clears(speed: float, jump_velocity: float, gravity: float,
		touch: float = PROP_TOUCH, lift: float = PROP_LIFT, lane: float = PROP_LANE) -> bool:
	var dt := 1.0 / 60.0
	var takeoff := -lane
	while takeoff < 0.0:
		var x := takeoff
		var y := 0.0
		var vy := -jump_velocity
		var ok := true
		while true:
			if Vector2(x, y).distance_to(Vector2(0, -lift)) <= touch:
				ok = false
				break
			vy += gravity * dt
			y += vy * dt
			x += speed * dt
			if y >= 0.0:
				break
		if ok and x > touch and x <= lane:
			return true
		takeoff += 1.0
	return false


## Pixel rect the whole level occupies (walls included, one ceiling slab on top).
static func level_bounds(L: Dictionary) -> Rect2:
	var F := int(L.get("floors", 1))
	var W := int(L.get("width_tiles", 0))
	return Rect2(0, -F * FLOOR_PX, (W + 1) * TILE, F * FLOOR_PX + TILE)


## Horizontal [a, b] px spans on floor f that a walker cannot pass.
static func blockers(L: Dictionary, f: int) -> Array:
	var out := []
	for w in L.get("walls", []):
		if int(w.floor) == f and not bool(w.doorway):
			out.append(Vector2(w.x * TILE, w.x * TILE + TILE))
	for fu in L.get("furniture", []):
		if int(fu.floor) == f and int(fu.h) > MAX_JUMP_TILES and not mount_passable(L, fu):
			out.append(Vector2(fu.x * TILE, (fu.x + fu.w) * TILE))
	for s in L.get("stairs", []):   # slab cutout: a 144px hole you can't walk or jump across
		if int(s.get("to_floor", -1)) == f and s.get("bottom") is Vector2 and s.get("top") is Vector2:
			out.append(stair_hole(s))
	out.sort_custom(func(a, b): return a.x < b.x)
	return out


## Spans on floor f that stop a walker for certain: walls, stair holes and furniture taller
## than MOUNT_TILES (a MOUNT_TILES piece is climbed over, see mount_passable).
static func hard_blockers(L: Dictionary, f: int) -> Array:
	var out := []
	for w in L.get("walls", []):
		if int(w.floor) == f and not bool(w.doorway):
			out.append(Vector2(w.x * TILE, w.x * TILE + TILE))
	for fu in L.get("furniture", []):
		if int(fu.floor) == f and int(fu.h) > MAX_JUMP_TILES and int(fu.h) != MOUNT_TILES:
			out.append(Vector2(fu.x * TILE, (fu.x + fu.w) * TILE))
	for s in L.get("stairs", []):
		if int(s.get("to_floor", -1)) == f and s.get("bottom") is Vector2 and s.get("top") is Vector2:
			out.append(stair_hole(s))
	return out


## The two steps of a climb-over piece: furniture of 1..MOUNT_STEP_MAX_TILES tiles touching it
## on each side. {left, right} or {} if either is missing.
static func step_pieces(L: Dictionary, fu: Dictionary) -> Dictionary:
	var out := {}
	var f := int(fu.floor)
	for o in L.get("furniture", []):
		if o == fu or int(o.floor) != f or int(o.h) < 1 or int(o.h) > MOUNT_STEP_MAX_TILES:
			continue
		if int(o.x) + int(o.w) == int(fu.x):
			out["left"] = o
		elif int(fu.x) + int(fu.w) == int(o.x):
			out["right"] = o
	return out if out.has("left") and out.has("right") else {}


## Tallest single climb (px) on the way over a climb-over piece: floor -> step -> top, either side.
static func max_single_climb_px(fu: Dictionary, steps: Dictionary) -> float:
	var m := 0.0
	for k in ["left", "right"]:
		var sh := float(int(steps[k].h) * TILE)
		m = maxf(m, maxf(sh, float(int(fu.h) * TILE) - sh))
	return m


## px of capped-jump apex left over the tallest single climb (20.2px with 2-tile steps).
static func climb_margin_px(fu: Dictionary, steps: Dictionary) -> float:
	return min_jump_apex() - max_single_climb_px(fu, steps)


## A MOUNT_TILES-tall piece with a step on each side does not split its segment: the boy climbs
## step -> top -> step (no single climb over 2 tiles = 32px, so item combos that slow him cannot
## strand him) and walks off the far side. Needs MOUNT_RUN_TILES of open floor beyond both steps
## and no other MOUNT_TILES piece closer than that.
static func mount_passable(L: Dictionary, fu: Dictionary) -> bool:
	if int(fu.h) != MOUNT_TILES:
		return false
	var st := step_pieces(L, fu)
	if st.is_empty() or climb_margin_px(fu, st) < MOUNT_MARGIN_PX:
		return false
	var f := int(fu.floor)
	var run := MOUNT_RUN_TILES * TILE
	var a := float(int(st.left.x) * TILE)
	var b := float((int(st.right.x) + int(st.right.w)) * TILE)
	for bl in hard_blockers(L, f):
		if bl.y > a - run and bl.x < b + run:
			return false
	for o in L.get("furniture", []):
		if o != fu and o != st.left and o != st.right and int(o.floor) == f and int(o.h) == MOUNT_TILES:
			if (o.x + o.w) * TILE > a - run and o.x * TILE < b + run:
				return false
	return true


## Furniture the floor graph treats as a wall: taller than a jump and not a passable climb-over
## cluster (a bare or one-step 3-tile piece, any 4-tile piece).
static func blocker_pieces(L: Dictionary) -> Array:
	var out := []
	for fu in L.get("furniture", []):
		if int(fu.h) > MAX_JUMP_TILES and not mount_passable(L, fu):
			out.append(fu)
	return out


## Furthest take-off gap (px, from the edge of a surface to the foot of the piece) at which a capped
## running jump still gets the feet within BLOCKER_MARGIN_PX of a top `rise_px` above the take-off
## surface; -1 if the capped apex never gets that close (see rail_jump_reach for the arc maths).
static func blocker_reach(rise_px: float) -> float:
	var j := capped_jump()
	var need := maxf(rise_px - BLOCKER_MARGIN_PX, 0.0)
	var disc := j.x * j.x - 2.0 * j.y * need
	if min_jump_apex() <= need or disc <= 0.0:
		return -1.0
	return max_run_speed() * (j.x + sqrt(disc)) / j.y + BODY_R


## One error per (blocker piece, surface) pair where the blocker can be climbed: from the floor, or
## from the top of any other non-blocker piece on that floor whose gap to it is within a jump.
## Touching pieces are gap 0. Blockers never serve as a surface (nothing reaches them).
static func blocker_climb_errors(L: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for b in blocker_pieces(L):
		out.append_array(blocker_climbs(L, b))
	return out


## The climb errors of one blocker piece (see blocker_climb_errors); empty if nothing reaches its top.
static func blocker_climbs(L: Dictionary, b: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var blk := blocker_pieces(L)
	var bh := float(int(b.h) * TILE)
	var sp := furniture_span(b)
	if blocker_reach(bh) >= 0.0:
		out.append("blocker h%d at x=%d on floor %d can be climbed from the floor (top %dpx, capped apex %.1fpx, needs %dpx clear)" % [
				int(b.h), int(sp.x), int(b.floor), int(bh), min_jump_apex(), int(BLOCKER_MARGIN_PX)])
	for o in L.get("furniture", []):
		if int(o.floor) != int(b.floor) or blk.has(o):
			continue
		var gap := span_gap(sp, furniture_span(o))
		var reach := blocker_reach(bh - float(int(o.h) * TILE))
		if reach >= 0.0 and gap <= reach:
			out.append("blocker h%d at x=%d on floor %d can be climbed from the h%d piece at x=%d (gap %dpx <= jump reach %dpx)" % [
					int(b.h), int(sp.x), int(b.floor), int(o.h), int(o.x) * int(TILE), int(gap), int(reach)])
	return out


## Shake-off rule. A piece taller than a walker can jump (h > MAX_JUMP_TILES) whose top the boy CAN
## stand on (a passable climb-over piece, or a blocker something reaches) must have a free side to
## come down on, so an enemy rattle / shake-off can never drop him back on the top in a loop. A side
## is free when, past the piece (past its touching step, if it has one), MOUNT_RUN_TILES of floor
## are clear of walls, stair holes and other tall pieces. Without one: no way down but the top.
static func shake_off_errors(L: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var right := float((int(L.get("width_tiles", 0)) + 1) * TILE)
	var run := float(MOUNT_RUN_TILES * TILE)
	for fu in L.get("furniture", []):
		if int(fu.h) <= MAX_JUMP_TILES:
			continue
		if not mount_passable(L, fu) and blocker_climbs(L, fu).is_empty():
			continue
		var f := int(fu.floor)
		var sp := furniture_span(fu)
		var free_side := false
		for dir in [-1, 1]:
			var edge: float = sp.x if dir < 0 else sp.y
			var step_o := {}
			for o in L.get("furniture", []):   # a touching low piece is a step down, not a wall
				if o != fu and int(o.floor) == f and int(o.h) <= MAX_JUMP_TILES and int(o.h) >= 1:
					var os := furniture_span(o)
					if (dir < 0 and os.y == sp.x) or (dir > 0 and os.x == sp.y):
						step_o = o
			if not step_o.is_empty():
				var ss := furniture_span(step_o)
				edge = ss.x if dir < 0 else ss.y
			var lo: float = edge - run if dir < 0 else edge
			var hi: float = edge if dir < 0 else edge + run
			if lo < 0.0 or hi > right:
				continue
			var clear := true
			for bl in hard_blockers(L, f):
				if bl.y > lo and bl.x < hi and not (is_equal_approx(bl.x, sp.x) and is_equal_approx(bl.y, sp.y)):
					clear = false
			for o in L.get("furniture", []):
				if o != fu and int(o.floor) == f and int(o.h) > MAX_JUMP_TILES:
					var os := furniture_span(o)
					if os.y > lo and os.x < hi:
						clear = false
			if clear:
				free_side = true
		if not free_side:
			out.append("h%d piece at x=%d on floor %d has a climbable top but no free shake-off side (%d tiles of clear floor past a step or the piece)" % [
					int(fu.h), int(sp.x), f, MOUNT_RUN_TILES])
	return out


## Can the boy, standing at `edge` px on floor f, run away in direction `dir` (+1 right, -1 left)?
## Yes if a stair is within EXIT_STAIR_PX before the first wall / blocker (the foot of a stair that
## starts on this floor, or the near edge of a slab cutout he can drop down), or if EXIT_OPEN_PX of
## floor lies ahead before a wall, a blocker, a cutout or the end of the level.
static func run_exit(L: Dictionary, f: int, edge: float, dir: int) -> bool:
	var bound := float((int(L.get("width_tiles", 0)) + 1) * TILE) if dir > 0 else 0.0
	var solid := absf(bound - edge)   # distance to the first thing that stops him
	var holes := []
	for s in L.get("stairs", []):
		if int(s.get("to_floor", -1)) == f and s.get("bottom") is Vector2 and s.get("top") is Vector2:
			holes.append(stair_hole(s))
	var nearest_stair := INF   # distance to the nearest stair access ahead
	for s in L.get("stairs", []):
		if int(s.get("from_floor", -1)) == f and s.get("bottom") is Vector2:
			var d := (float(s.bottom.x) - edge) * dir
			if d >= 0.0:
				nearest_stair = minf(nearest_stair, d)
	for h in holes:
		var d: float = (h.x - edge) if dir > 0 else (edge - h.y)
		if d >= 0.0:
			nearest_stair = minf(nearest_stair, d)
	var first_open := solid   # to the first wall, blocker, cutout or the level end
	for bl in blockers(L, f):
		var d: float = (bl.x - edge) if dir > 0 else (edge - bl.y)
		if d < 0.0:
			continue
		first_open = minf(first_open, d)
		var is_hole := false
		for h in holes:
			if h == bl:
				is_hole = true
		if not is_hole:
			solid = minf(solid, d)
	return (nearest_stair <= EXIT_STAIR_PX and nearest_stair <= solid) or first_open >= EXIT_OPEN_PX


## "Dead-end clusters": a climb-over cluster that has no way to run from a walker on at least one
## side. The walker can come from either side and the boy is shaken off to the other, so BOTH sides
## need `run_exit` (stairs within EXIT_STAIR_PX, or EXIT_OPEN_PX of open floor), measured from the far
## edge of the step on that side.
static func cluster_exit_errors(L: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for fu in L.get("furniture", []):
		if int(fu.h) != MOUNT_TILES or not mount_passable(L, fu):
			continue
		var st := step_pieces(L, fu)
		var f := int(fu.floor)
		for dir in [-1, 1]:
			var step: Dictionary = st.left if dir < 0 else st.right
			var sp := furniture_span(step)
			var edge: float = sp.x if dir < 0 else sp.y
			if not run_exit(L, f, edge, dir):
				out.append("dead-end cluster: the %d-tile piece at x=%d on floor %d has no exit on its %s side (no stair within %dpx and under %dpx of open floor)" % [
						MOUNT_TILES, int(furniture_span(fu).x), f, "left" if dir < 0 else "right", int(EXIT_STAIR_PX), int(EXIT_OPEN_PX)])
	return out


## Walkable segments per floor: {f: [Vector2(a, b), ...]} between blockers.
static func segments(L: Dictionary) -> Dictionary:
	var out := {}
	var right := (int(L.get("width_tiles", 0)) + 1) * TILE
	for f in int(L.get("floors", 0)):
		var segs := []
		var cur := 0.0
		for bl in blockers(L, f):
			if bl.x > cur:
				segs.append(Vector2(cur, bl.x))
			cur = maxf(cur, bl.y)
		if cur < right:
			segs.append(Vector2(cur, right))
		out[f] = segs
	return out


## Floor graph: nodes "floor:segment", edges = stairs.
## {segments, adj: {node: [{to, stair}]}} where stair is the index into L.stairs.
static func floor_graph(L: Dictionary) -> Dictionary:
	var segs := segments(L)
	var adj := {}
	var F := int(L.get("floors", 0))
	var stairs: Array = L.get("stairs", [])
	for i in stairs.size():
		var s: Dictionary = stairs[i]
		if not (s.get("bottom") is Vector2) or not (s.get("top") is Vector2):
			continue
		var ff := int(s.get("from_floor", -1))
		var tf := int(s.get("to_floor", -1))
		if ff < 0 or tf < 0 or ff >= F or tf >= F:
			continue
		var na := node_at(segs, ff, s.bottom.x)
		var nb := node_at(segs, tf, s.top.x + signf(s.top.x - s.bottom.x))   # landing side of the cutout
		if na == "" or nb == "":
			continue
		adj.get_or_add(na, []).append({to = nb, stair = i})
		adj.get_or_add(nb, []).append({to = na, stair = i})
	return {segments = segs, adj = adj}


static func reachable_from(g: Dictionary, start: String) -> Dictionary:
	var reach := {}
	if start == "":
		return reach
	var q := [start]
	reach[start] = true
	while not q.is_empty():
		var n: String = q.pop_front()
		for e in g.adj.get(n, []):
			if not reach.has(e.to):
				reach[e.to] = true
				q.append(e.to)
	return reach


static func node_at(segs: Dictionary, f: int, x: float) -> String:
	var list: Array = segs.get(f, [])
	for i in list.size():
		var s: Vector2 = list[i]
		if x > s.x and x < s.y:
			return "%d:%d" % [f, i]
	return ""


## True if x on floor f is inside any wall column (doorway or not) or furniture.
static func is_solid(L: Dictionary, f: int, x: float) -> bool:
	return _span_hits_solid(L, f, x, x, false)


## Walls (doorway or not) and furniture; plus stair footprints when include_stairs.
static func _span_hits_solid(L: Dictionary, f: int, a: float, b: float, include_stairs: bool) -> bool:
	for w in L.get("walls", []):
		if int(w.floor) == f and b >= w.x * TILE and a <= w.x * TILE + TILE:
			return true
	for fu in L.get("furniture", []):
		if int(fu.floor) == f and b >= fu.x * TILE and a <= (fu.x + fu.w) * TILE:
			return true
	return include_stairs and _on_stair(L, f, a, b)


static func _on_stair(L: Dictionary, f: int, a: float, b: float) -> bool:
	for s in L.get("stairs", []):
		if not (s.get("bottom") is Vector2) or not (s.get("top") is Vector2):
			continue
		if int(s.get("from_floor", -1)) != f and int(s.get("to_floor", -1)) != f:
			continue
		var sp := stair_span(s)
		if b >= sp.x and a <= sp.y:
			return true
	return false


## Stair footprint [x0, x1] px: bottom landing + diagonal + top landing (both floors).
static func stair_span(s: Dictionary) -> Vector2:
	return Vector2(minf(s.bottom.x, s.top.x) - STAIR_LANDING_PX, maxf(s.bottom.x, s.top.x) + STAIR_LANDING_PX)


## Leftmost tile x of the 21-tile stair (docs/DESIGN.md placement).
static func stair_x(s: Dictionary) -> int:
	return int(round(stair_span(s).x / TILE))


## Upper-slab cutout [a, b] px on to_floor (docs/DESIGN.md): the 9 diagonal tiles next to `top`,
## i.e. tiles x+9..x+17 for a stair rising right, x+3..x+11 (mirrored) rising left.
static func stair_hole(s: Dictionary) -> Vector2:
	var d := signf(s.top.x - s.bottom.x)
	var tx: float = s.top.x
	return Vector2(minf(tx, tx - d * STAIR_HOLE_PX), maxf(tx, tx - d * STAIR_HOLE_PX))


## Gallery rail collider [a, b] px on to_floor (PRODUCT.md "Stair opening", QA-revised): a thin
## vertical wall at the FAR edge of the opening, where the upper floor drops off, standing on the
## solid slab: rising right just left of px 144 from the stair's leftmost tile edge (left edge of
## x+9), rising left just right of px 192 (mirrored). From the upper surface up RAIL_H_PX (96px,
## above the boy's ~52px jump). Layer WORLD: blocks the boy and walkers; floaters don't mask WORLD.
## A climber at that x is ~64px above the lower floor (96px under the wall's foot), so climbing
## never touches it. The visible `stair_gallery_rail` still spans the whole opening.
static func stair_rail(s: Dictionary) -> Vector2:
	var x0 := stair_x(s) * TILE
	if s.top.x > s.bottom.x:
		return Vector2(x0 + 144.0 - RAIL_W_PX, x0 + 144.0)
	return Vector2(x0 + 192.0, x0 + 192.0 + RAIL_W_PX)


## Near-edge guard [a, b] px on to_floor: the same RAIL_H_PX wall inside the opening, NEAR_GUARD_PX back
## from the stair-top landing edge, so a body walking off the top landing toward the opening is
## stopped on the slab corner instead of dropping a floor. NEAR_GUARD_PX (16) > the widest body
## radius (14), so a body standing on the stair's top point never touches it; climbers pass it
## kinematically (they never collide while climbing). Not in the QA spec (far edge only); added
## because scene_rail proved the near edge was open.
static func stair_rail_near(s: Dictionary) -> Vector2:
	var h := stair_hole(s)
	if s.top.x > s.bottom.x:
		return Vector2(h.y - NEAR_GUARD_PX - RAIL_W_PX, h.y - NEAR_GUARD_PX)
	return Vector2(h.x + NEAR_GUARD_PX, h.x + NEAR_GUARD_PX + RAIL_W_PX)


## Every rail collider x span over a stair opening (far-edge wall, near-edge guard).
static func stair_rail_walls(s: Dictionary) -> Array[Vector2]:
	return [stair_rail(s), stair_rail_near(s)]


## Rail clearance (PRODUCT.md "Stair opening", QA #13 b2/b3). Standable spots are the floor and
## furniture tops (props have no collision). From a surface `h_px` above the floor, a jump at the
## stat caps (jump_velocity max, gravity min, move_speed max, no carry penalty) keeps the boy's
## feet above RAIL_H_PX - RAIL_CLEAR_MARGIN for a horizontal run of rail_jump_reach(h_px) px.
## Any such surface must keep rail_keepout(h_px) px from every rail wall on its floor: the reach,
## plus BODY_R overhang at take-off (he stays grounded until his centre is ~r past the edge) and
## BODY_R for his leading edge, plus JUMP_SLACK_PX for 60Hz integration.
const RAIL_CLEAR_MARGIN := 16.0
const BODY_R := 14.0
const JUMP_SLACK_PX := 8.0


## (jump_velocity, gravity) at the stat caps that maximise height (PlayerStats.stat_max / stat_min).
static func capped_jump() -> Vector2:
	return Vector2(PlayerStats.stat_max(&"jump_velocity"), PlayerStats.stat_min(&"gravity"))


static func max_jump_apex() -> float:
	var j := capped_jump()
	return j.x * j.x / (2.0 * j.y)


## Apex at the stat caps that MINIMISE height (jump_velocity at stat_min, gravity at stat_max):
## what a climb must survive. (Today both are pinned to BASE, so it equals max_jump_apex().)
static func min_jump_apex() -> float:
	var v := PlayerStats.stat_min(&"jump_velocity")
	return v * v / (2.0 * PlayerStats.stat_max(&"gravity"))


## Fastest horizontal speed in the air (move_speed at its cap; carry penalties only slow him).
static func max_run_speed() -> float:
	return PlayerStats.stat_max(&"move_speed")


static func rail_jump_reach(h_px: float) -> float:
	var j := capped_jump()
	var need := RAIL_H_PX - RAIL_CLEAR_MARGIN - h_px   # height to gain above the take-off surface
	if need <= 0.0:
		return INF
	var disc := j.x * j.x - 2.0 * j.y * need
	if disc < 0.0:
		return 0.0
	return max_run_speed() * (j.x + sqrt(disc)) / j.y   # time the feet are above `need`, at full speed


static func rail_keepout(h_px: float) -> float:
	var r := rail_jump_reach(h_px)
	return 0.0 if r <= 0.0 else r + 2.0 * BODY_R + JUMP_SLACK_PX


## Furniture block {floor, x, w, h} as [a, b] px and its top height px.
static func furniture_span(fu: Dictionary) -> Vector2:
	return Vector2(float(fu.x) * TILE, float(int(fu.x) + int(fu.w)) * TILE)


## px between two spans (negative when they overlap).
static func span_gap(a: Vector2, b: Vector2) -> float:
	return maxf(b.x - a.y, a.x - b.y)


## True if furniture [a, b] px of height h tiles on floor f keeps clear of every rail there.
static func furniture_rail_ok(L: Dictionary, f: int, a: float, b: float, h: int) -> bool:
	var ko := rail_keepout(h * TILE)
	if ko <= 0.0:
		return true
	for s in L.stairs:
		if int(s.to_floor) != f:
			continue
		for rw in stair_rail_walls(s):
			if span_gap(Vector2(a, b), rw) <= ko:
				return false
	return true


static func rail_jump_errors(L: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if rail_keepout(0.0) > 0.0:
		out.append("a capped running jump from the floor clears the %dpx rail (apex %.1fpx)" % [int(RAIL_H_PX), max_jump_apex()])
	for fu in L.furniture:
		var sp := furniture_span(fu)
		if not furniture_rail_ok(L, int(fu.floor), sp.x, sp.y, int(fu.h)):
			out.append("furniture h%d at x=%d on floor %d is within %dpx of a stair rail: a capped running jump from it clears the rail" % [
					int(fu.h), int(sp.x), int(fu.floor), int(rail_keepout(int(fu.h) * TILE))])
	return out


## The two landings [{floor, a, b}]: bottom one beyond `bottom` on from_floor, top one beyond `top` on to_floor.
static func stair_landings(s: Dictionary) -> Array:
	var d := signf(s.top.x - s.bottom.x)
	var bx: float = s.bottom.x
	var tx: float = s.top.x
	return [{floor = int(s.from_floor), a = minf(bx, bx - d * STAIR_LANDING_PX), b = maxf(bx, bx - d * STAIR_LANDING_PX)},
			{floor = int(s.to_floor), a = minf(tx, tx + d * STAIR_LANDING_PX), b = maxf(tx, tx + d * STAIR_LANDING_PX)}]


## Same floor, within one screen width, nothing solid-and-blocking between.
static func in_line_of_sight(L: Dictionary, a: Vector2, b: Vector2) -> bool:
	if floor_of(a.y) != floor_of(b.y):
		return false
	if absf(a.x - b.x) > SIGHT_PX:
		return false
	var lo := minf(a.x, b.x)
	var hi := maxf(a.x, b.x)
	for bl in blockers(L, floor_of(a.y)):
		if bl.y > lo and bl.x < hi:
			return false
	return true


## True if a jump at the stat caps lifts the feet at least MOUNT_MARGIN_PX over a top h_px high
## (kinematic bound; the real climb is simulated in tests/climb_sim.gd).
static func can_mount(h_px: float) -> bool:
	return min_jump_apex() - h_px >= MOUNT_MARGIN_PX


## Furniture the boy can climb onto: climb-over pieces (mount_passable) standing in a
## segment the start can reach.
static func mountable_pieces(L: Dictionary) -> Array:
	var out := []
	var g := floor_graph(L)
	var reach := reachable_from(g, node_at(g.segments, floor_of(L.start.y), float(L.start.x)))
	for fu in L.get("furniture", []):
		if not mount_passable(L, fu):
			continue
		var sp := furniture_span(fu)
		var n := node_at(g.segments, int(fu.floor), (sp.x + sp.y) * 0.5)
		if n != "" and reach.has(n):
			out.append(fu)
	return out


## One error per floor with no reachable piece the boy can climb onto (generator guarantee;
## not part of validate(): hand-built layouts and the fallback need not have furniture).
static func mountable_floor_errors(L: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var have := {}
	for fu in mountable_pieces(L):
		have[int(fu.floor)] = true
	for f in int(L.get("floors", 0)):
		if not have.has(f):
			out.append("floor %d has no reachable %d-tile piece to climb onto" % [f, MOUNT_TILES])
	return out

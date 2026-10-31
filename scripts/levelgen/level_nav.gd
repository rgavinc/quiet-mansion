class_name LevelNav
extends RefCounted
## Floor graph + stair positions for the current level, as plain data. Enemies query it
## whether or not they're on screen (off-screen enemies skip rendering, never this).
## Built by LevelGenerator.build(); `LevelNav.current` is the live level's nav (null when
## no generated level is loaded, e.g. unit tests and the old top-down map).
## World coordinates: the level is built with its origin at the World node's origin.
##
##   var nav := LevelNav.current
##   var wp := nav.next_waypoint(my_pos, target_pos)
##   # wp = {} unreachable | {point} walk to it | {point, stair_to, stair} walk to point, then climb to stair_to
## A target standing ON a stair (between its landings, e.g. the boy mid-climb) is reached by
## taking that stair from whichever landing is nearer by route; it is never mapped to the floor
## under / over it (that parked walkers directly below or above the boy, QA route gap).
## next_waypoint is pure and re-planned every call, so a target changing floor re-routes at once.

## How close (px, perpendicular) to a stair's line a point counts as on that stair.
const ON_STAIR_PX := 20.0

static var current: LevelNav = null

var layout: Dictionary
var graph: Dictionary          # LevelValidator.floor_graph(layout)
var stairs: Array = []         # [{from_floor, to_floor, bottom, top}] (copies of layout.stairs)


static func from_layout(L: Dictionary) -> LevelNav:
	var n := LevelNav.new()
	n.layout = L
	n.graph = LevelValidator.floor_graph(n.layout)
	for s in n.layout.get("stairs", []):
		n.stairs.append((s as Dictionary).duplicate())
	return n


func floor_of(p: Vector2) -> int:
	return clampi(LevelValidator.floor_of(p.y), 0, maxi(int(layout.get("floors", 1)) - 1, 0))


## Graph node for a point; if it's inside a blocker, the nearest segment on that floor.
func node_for(p: Vector2) -> String:
	var f := floor_of(p)
	var n := LevelValidator.node_at(graph.get("segments", {}), f, p.x)
	if n != "":
		return n
	var list: Array = graph.get("segments", {}).get(f, [])
	var best := -1
	var best_d := INF
	for i in list.size():
		var s: Vector2 = list[i]
		var d := minf(absf(p.x - s.x), absf(p.x - s.y))
		if d < best_d:
			best_d = d
			best = i
	return "" if best < 0 else "%d:%d" % [f, best]


## Shortest list of stair hops from a to b by walked distance (|dx| on floors + stair length),
## not by stair count (QA #13 b4: a 1-stair route twice the length beat a 2-stair short one):
## [{stair, enter, exit}] (enter/exit are feet points). [] when already in the same segment;
## null when unreachable. Dijkstra over stair-exit states; ties keep the earlier stair index.
func route(a: Vector2, b: Vector2) -> Variant:
	var na := node_for(a)
	var nb := node_for(b)
	if na == "" or nb == "":
		return null
	if na == nb:
		return []
	var adj: Dictionary = graph.get("adj", {})
	# state: {node, pos, cost, prev (state index or -1), stair, up}; -1 = the start
	var states := [{node = na, pos = a, cost = 0.0, prev = -1, stair = -1, up = true}]
	var best_at := {}   # "stair:up" -> state index (each stair exit is reached at most once)
	var done := {}
	var goal := -1
	var goal_cost := INF
	while true:
		var cur := -1
		for i in states.size():
			if not done.has(i) and (cur < 0 or float(states[i].cost) < float(states[cur].cost)):
				cur = i
		if cur < 0 or float(states[cur].cost) >= goal_cost:
			break
		done[cur] = true
		var st: Dictionary = states[cur]
		if st.node == nb:
			var c := float(st.cost) + absf((st.pos as Vector2).x - b.x)
			if c < goal_cost:
				goal_cost = c
				goal = cur
		var f := int(str(st.node).split(":")[0])
		for e in adj.get(st.node, []):
			var s: Dictionary = stairs[e.stair]
			var up := int(s.from_floor) == f
			var enter: Vector2 = s.bottom if up else s.top
			var exit: Vector2 = s.top if up else s.bottom
			var c2 := float(st.cost) + absf((st.pos as Vector2).x - enter.x) + enter.distance_to(exit)
			var key := "%d:%s" % [e.stair, up]
			if best_at.has(key):
				var j: int = best_at[key]
				if done.has(j) or c2 >= float(states[j].cost):
					continue
				states[j] = {node = e.to, pos = exit, cost = c2, prev = cur, stair = int(e.stair), up = up}
			else:
				best_at[key] = states.size()
				states.append({node = e.to, pos = exit, cost = c2, prev = cur, stair = int(e.stair), up = up})
	if goal < 0:
		return null
	var hops := []
	var k := goal
	while int(states[k].prev) >= 0:
		var s: Dictionary = stairs[states[k].stair]
		var up: bool = states[k].up
		hops.push_front({stair = s, enter = s.bottom if up else s.top, exit = s.top if up else s.bottom})
		k = int(states[k].prev)
	return hops


## Walked length of the best route from a to b (INF when unreachable).
func route_distance(a: Vector2, b: Vector2) -> float:
	var r: Variant = route(a, b)
	return INF if r == null else _route_len(a, r as Array, b)


## Index of the stair whose line p is on, strictly between its two landings; -1 if none.
func stair_at(p: Vector2) -> int:
	for i in stairs.size():
		var s: Dictionary = stairs[i]
		var b: Vector2 = s.bottom
		var t: Vector2 = s.top
		if p.y >= b.y - 2.0 or p.y <= t.y + 2.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, b, t)
		if q.distance_to(p) <= ON_STAIR_PX:
			return i
	return -1


## Where to walk next to get from a toward b. See class doc.
func next_waypoint(a: Vector2, b: Vector2) -> Dictionary:
	var si := stair_at(b)
	if si >= 0 and stair_at(a) != si:
		return _toward_stair(a, si)
	return _next_on_floors(a, b)


## Target on stair si: walk (and climb other stairs if needed) to its nearer landing, then climb it.
func _toward_stair(a: Vector2, si: int) -> Dictionary:
	var s: Dictionary = stairs[si]
	var best := {}
	var best_d := INF
	for up in [true, false]:
		var enter: Vector2 = s.bottom if up else s.top
		var exit: Vector2 = s.top if up else s.bottom
		var r: Variant = route(a, enter)
		if r == null:
			continue
		var d := _route_len(a, r as Array, enter)
		if d < best_d:
			best_d = d
			best = {point = enter, stair_to = exit, stair = s} if (r as Array).is_empty() else _next_on_floors(a, enter)
	return best


func _route_len(a: Vector2, hops: Array, b: Vector2) -> float:
	var d := 0.0
	var cur := a
	for h in hops:
		d += absf(cur.x - (h.enter as Vector2).x) + (h.enter as Vector2).distance_to(h.exit)
		cur = h.exit
	return d + absf(cur.x - b.x)


func _next_on_floors(a: Vector2, b: Vector2) -> Dictionary:
	var r: Variant = route(a, b)
	if r == null:
		return {}
	if (r as Array).is_empty():
		return {point = b}
	var hop: Dictionary = r[0]
	return {point = hop.enter, stair_to = hop.exit, stair = hop.stair}

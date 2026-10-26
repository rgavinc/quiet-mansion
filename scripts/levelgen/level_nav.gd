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


## Shortest list of stair hops from a to b: [{stair, enter, exit}] (enter/exit are feet points).
## [] when already in the same segment; null when unreachable.
func route(a: Vector2, b: Vector2) -> Variant:
	var na := node_for(a)
	var nb := node_for(b)
	if na == "" or nb == "":
		return null
	if na == nb:
		return []
	var prev := {na: null}
	var q := [na]
	while not q.is_empty():
		var n: String = q.pop_front()
		if n == nb:
			break
		for e in graph.get("adj", {}).get(n, []):
			if not prev.has(e.to):
				prev[e.to] = {from = n, stair = e.stair}
				q.append(e.to)
	if not prev.has(nb):
		return null
	var hops := []
	var cur := nb
	while prev[cur] != null:
		var link: Dictionary = prev[cur]
		var s: Dictionary = stairs[link.stair]
		var going_up := int(s.from_floor) == int(str(link.from).split(":")[0])
		hops.push_front({stair = s, enter = s.bottom if going_up else s.top, exit = s.top if going_up else s.bottom})
		cur = link.from
	return hops


## Where to walk next to get from a toward b. See class doc.
func next_waypoint(a: Vector2, b: Vector2) -> Dictionary:
	var r: Variant = route(a, b)
	if r == null:
		return {}
	if (r as Array).is_empty():
		return {point = b}
	var hop: Dictionary = r[0]
	return {point = hop.enter, stair_to = hop.exit, stair = hop.stair}

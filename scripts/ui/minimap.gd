extends Control
## Corner minimap, shown only while PlayerStats.has_minimap() (the Minimap item).
## Floors as bands, player dot, exit marker, and chasers BE reported (FESignals.chasing) in red.
## Cheap: the picture is rebuilt at REFRESH_HZ (not every frame) and nothing runs while hidden.
##
## Level bounds are read generically, in this order:
##   1. Lead's generated level (PR #13): `LevelNav.current.layout` (floors, width_tiles,
##      stairs), with LevelValidator.level_bounds() when present. Looked up through the
##      global class list, so this file parses without #13.
##   2. A TileMapLayer / TileMap under the current scene: its used rect -> one band.
##   3. Otherwise the 1280x720 screen room (development's top-down map) merged with the
##      player / exit / enemies, one band.

const REFRESH_HZ := 10.0
const MAX_SIZE := Vector2(240, 120)
const PAD := 6.0
const MIN_H := 48.0                  # long, flat levels get stretched vertically to stay readable
const FLOOR_PX := 160.0              # #13 LevelValidator.FLOOR_PX (fallback if not readable)
const C_BACK := Color(0.05, 0.04, 0.07, 0.78)
const C_RIM := Color(0.45, 0.38, 0.3, 1)
const C_BAND := Color(0.36, 0.3, 0.26, 0.85)
const C_BAND_ALT := Color(0.3, 0.25, 0.22, 0.85)
const C_STAIR := Color(0.62, 0.5, 0.36)
const C_PLAYER := Color(1, 1, 1)
const C_EXIT := Color(1.0, 0.82, 0.3)
const C_CHASER := Color(1.0, 0.22, 0.2)

var skin: HudSkin
var bus: Node
## PlayerStats (default: the autoload).
var stats: Node
## Snapshot drawn last (tests/debug): {bounds: Rect2, bands: Array[Rect2], stairs: Array,
## player: Vector2|null, exit: Vector2|null, chasers: Array[Vector2], source: String}.
var snapshot: Dictionary = {}
var _acc := 0.0
## instance_id -> [enemy, bound tree_exiting callable] for reported chasers.
var _watched := {}
var _exiting: Node = null
var _map_rect := Rect2()


func _enter_tree() -> void:
	if bus == null:
		bus = UiArt.bus()
	if stats == null:
		stats = get_node_or_null(^"/root/PlayerStats")
	_wire(true)
	if is_node_ready():
		refresh()


## Signals go to methods and only while in the tree (no lambdas): a HUD that left the tree on
## a stage change (QA B1) is disconnected and never reads a null tree.
func _exit_tree() -> void:
	_wire(false)
	_unwatch_all()


func _wire(on: bool) -> void:
	var pairs := []
	if stats and is_instance_valid(stats):
		pairs.append([stats, &"items_changed", _on_items_changed])
		pairs.append([stats, &"stat_changed", _on_stat_changed])
	if bus and is_instance_valid(bus):
		pairs.append([bus, &"chase_changed", _on_chase_changed])
	for p in pairs:
		var o: Object = p[0]
		if not o.has_signal(p[1]):
			continue
		var connected := o.is_connected(p[1], p[2])
		if on and not connected:
			o.connect(p[1], p[2])
		elif not on and connected:
			o.disconnect(p[1], p[2])


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = MAX_SIZE
	refresh()


func _on_items_changed(_items: Array) -> void:
	refresh()


func _on_stat_changed(stat: StringName, _value: float) -> void:
	if stat == &"minimap":
		refresh()


## Chase start/end: redraw now so a red dot appears/vanishes at once, not on the next tick.
## While chasing, the enemy's tree_exiting is watched, so a chaser freed (or removed) without
## a chase-end report loses its dot at once too.
func _on_chase_changed(enemy: Node2D, chasing: bool) -> void:
	if enemy != null and is_instance_valid(enemy):
		if chasing:
			_watch(enemy)
		else:
			_unwatch(enemy)
	refresh()


func _watch(e: Node) -> void:
	var id := e.get_instance_id()
	if _watched.has(id):
		return
	var cb := _on_chaser_exiting.bind(e)
	e.tree_exiting.connect(cb)
	_watched[id] = [e, cb]


func _unwatch(e: Node) -> void:
	var id := e.get_instance_id()
	var w: Array = _watched.get(id, [])
	_watched.erase(id)
	if not w.is_empty() and is_instance_valid(w[0]) and (w[0] as Node).tree_exiting.is_connected(w[1]):
		(w[0] as Node).tree_exiting.disconnect(w[1])


func _unwatch_all() -> void:
	for id in _watched.keys():
		var w: Array = _watched[id]
		if is_instance_valid(w[0]):
			_unwatch(w[0])
	_watched.clear()


## Enemies whose tree_exiting this minimap listens to (tests).
func watched_count() -> int:
	return _watched.size()


func _on_chaser_exiting(e: Node) -> void:
	_unwatch(e)    # re-watched if it is reported chasing again
	_exiting = e   # still inside the tree during tree_exiting: skip it explicitly
	refresh()
	_exiting = null


func enabled() -> bool:
	return stats != null and is_instance_valid(stats) and stats.has_method(&"has_minimap") and bool(stats.has_minimap())


func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / REFRESH_HZ:
		return
	_acc = 0.0
	refresh()


## Re-reads visibility and the level, then redraws (called at REFRESH_HZ).
func refresh() -> void:
	if not is_inside_tree():
		return
	visible = enabled()
	if not visible:
		snapshot = {}
		return
	snapshot = read_level()
	_layout()
	queue_redraw()


func _scene() -> Node:
	var t := get_tree()
	return t.current_scene if t else null


static func _global_script(cls: String) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == cls:
			return load(str(c.get("path", ""))) as Script
	return null


func read_level() -> Dictionary:
	var snap := {bounds = Rect2(), bands = [], stairs = [], player = null, exit = null, chasers = [], source = ""}
	var t := get_tree()
	if t == null:
		return snap
	var points: Array[Vector2] = []
	for p in t.get_nodes_in_group(&"player"):
		if p is Node2D:
			snap.player = (p as Node2D).global_position
			points.append(snap.player)
			break
	for x in t.get_nodes_in_group(&"exit"):
		if x is Node2D:
			snap.exit = (x as Node2D).global_position
			points.append(snap.exit)
			break
	if bus and "chasing" in bus:
		for raw in bus.chasing:
			if raw != null and is_instance_valid(raw) and raw is Node2D and raw != _exiting \
					and (raw as Node).is_inside_tree() and not (raw as Node).is_queued_for_deletion():
				_watch(raw)   # reported before this minimap existed
				snap.chasers.append((raw as Node2D).global_position)
	# 1. #13 generated level
	var nav_script := _global_script("LevelNav")
	var nav = nav_script.get("current") if nav_script else null
	if nav != null and nav is Object and "layout" in nav and nav.layout is Dictionary and not (nav.layout as Dictionary).is_empty():
		var L: Dictionary = nav.layout
		var floors := maxi(int(L.get("floors", 1)), 1)
		var fpx := FLOOR_PX
		var val := _global_script("LevelValidator")
		if val and val.get("FLOOR_PX") != null:
			fpx = float(val.get("FLOOR_PX"))
		var b := Rect2()
		if val and val.has_method(&"level_bounds"):
			b = val.level_bounds(L)
		else:
			b = Rect2(0, -floors * fpx, (int(L.get("width_tiles", 80)) + 1) * 16.0, floors * fpx + 16.0)
		snap.bounds = b
		for f in floors:   # floor f's band: from its surface (y = -f * fpx) up one floor
			snap.bands.append(Rect2(b.position.x, -(f + 1) * fpx, b.size.x, fpx))
		for s in L.get("stairs", []):
			if s is Dictionary and s.get("bottom") is Vector2 and s.get("top") is Vector2:
				snap.stairs.append([s.bottom, s.top])
		snap.source = "level_nav"
		return snap
	# 2. tilemap under the scene
	var scene := _scene()
	if scene:
		var tm := _find_tilemap(scene)
		if tm:
			var used: Rect2i = tm.get_used_rect()
			var ts := Vector2(tm.tile_set.tile_size) if tm.tile_set else Vector2(16, 16)
			var r := Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts)
			r = (tm as Node2D).get_global_transform() * r
			if r.has_area():
				snap.bounds = r
				snap.bands = [r]
				snap.source = "tilemap"
				return snap
	# 3. screen room + actors
	var r := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for p in points + (snap.chasers as Array):
		r = r.expand(p)
	for e in t.get_nodes_in_group(&"enemies"):
		if e is Node2D:
			r = r.expand((e as Node2D).global_position)
	snap.bounds = r
	snap.bands = [r]
	snap.source = "screen"
	return snap


static func _find_tilemap(n: Node) -> Node:
	if n.is_class("TileMapLayer") or n.is_class("TileMap"):
		return n
	for c in n.get_children():
		var f := _find_tilemap(c)
		if f:
			return f
	return null


## World point -> minimap-local point, clamped inside the map frame (so a dot past the level
## bounds sits on the edge instead of drawing outside the frame).
func to_map(p: Vector2) -> Vector2:
	var b: Rect2 = snapshot.get("bounds", Rect2())
	if not b.has_area():
		return _map_rect.position
	var q := _map_rect.position + (p - b.position) / b.size * _map_rect.size
	return q.clamp(_map_rect.position, _map_rect.end)


## Centre for a dot of radius r: kept r px inside the frame.
func dot_at(p: Vector2, r: float) -> Vector2:
	var q := to_map(p)
	var inner := _map_rect.grow(-r)
	if not inner.has_area():
		return _map_rect.get_center()
	return q.clamp(inner.position, inner.end)


## Map rect used by the last draw (minimap-local), for tests.
func map_rect() -> Rect2:
	return _map_rect


## Fits the level bounds into the control: sets _map_rect. False if there is nothing to fit.
func _layout() -> bool:
	var b: Rect2 = snapshot.get("bounds", Rect2())
	if not b.has_area():
		return false
	var sz0 := size.max(MAX_SIZE)
	var avail := sz0 - Vector2(PAD, PAD) * 2.0
	var k := minf(avail.x / b.size.x, avail.y / b.size.y)
	var sz := b.size * k
	sz.y = clampf(sz.y, minf(MIN_H, avail.y), avail.y)   # non-uniform for wide side-scroller levels
	_map_rect = Rect2(Vector2(sz0.x - PAD - sz.x, PAD), sz)   # hug the right edge
	return true


func _draw() -> void:
	if snapshot.is_empty():
		return
	if not _layout():
		return
	draw_rect(_map_rect.grow(PAD), C_BACK)
	draw_rect(_map_rect.grow(PAD), C_RIM, false, 2.0)
	var i := 0
	for band in snapshot.bands:
		var r := Rect2(to_map(band.position), Vector2.ZERO).expand(to_map((band as Rect2).end)).intersection(_map_rect)
		draw_rect(r.grow_individual(0, -1, 0, -1), C_BAND if i % 2 == 0 else C_BAND_ALT)
		draw_line(Vector2(r.position.x, r.end.y), r.end, C_STAIR, 1.0)   # floor line
		i += 1
	for s in snapshot.stairs:
		draw_line(to_map(s[0]), to_map(s[1]), C_STAIR, 2.0)
	if snapshot.exit != null:
		var e := dot_at(snapshot.exit, 6.0)
		draw_rect(Rect2(e - Vector2(4, 6), Vector2(8, 11)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(e - Vector2(3, 5), Vector2(6, 9)), C_EXIT)
	for c in snapshot.chasers:
		var q := dot_at(c, 4.0)
		draw_circle(q, 4.0, Color(0, 0, 0, 0.8))
		draw_circle(q, 3.0, C_CHASER)
	if snapshot.player != null:
		var p := dot_at(snapshot.player, 4.5)
		draw_circle(p, 4.5, Color(0, 0, 0, 0.85))
		draw_circle(p, 3.5, C_PLAYER)

extends Node2D
## World-space FE overlays in one node: dark-stage puppet glints + silhouettes, selection ring, per-enemy startle
## meters, pickup gauge, throw line, camera nudge and the camera rig (level limits + follow). Drop
## `scenes/ui/world_overlay.tscn` under the level's world root.
## The drawn pieces live in a child CanvasLayer that follows the camera
## (follow_viewport) so the level's CanvasModulate darkness never dims the UI;
## only the selected-enemy glow light stays in the world canvas.

const SelectionRing := preload("res://scripts/ui/selection_ring.gd")
const StartleMeter := preload("res://scripts/ui/startle_meter.gd")
const PickupGauge := preload("res://scripts/ui/pickup_gauge.gd")
const ThrowLine := preload("res://scripts/ui/throw_line.gd")
const CameraNudge := preload("res://scripts/ui/camera_nudge.gd")
const DarkGlints := preload("res://scripts/ui/dark_glints.gd")

var skin: HudSkin
var bus: Node
var dark_glints: Node2D
var ring: Node2D
var pickup_gauge: Node2D
var throw_line: Node2D
var camera_nudge: Node
var camera_rig: CameraRig
var layer: CanvasLayer
var _meters: Dictionary = {}   # enemy instance_id -> meter


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	layer = CanvasLayer.new()
	layer.name = "OverlayLayer"
	layer.layer = 5
	layer.follow_viewport_enabled = true
	add_child(layer)
	dark_glints = _add(DarkGlints.new(), "DarkGlints")   # first: under the ring and meters
	var r := SelectionRing.new()
	r.glow_parent = self
	ring = _add(r, "SelectionRing")
	pickup_gauge = _add(PickupGauge.new(), "PickupGauge")
	throw_line = _add(ThrowLine.new(), "ThrowLine")
	camera_nudge = CameraNudge.new()
	camera_nudge.name = "CameraNudge"
	camera_nudge.skin = skin
	camera_nudge.bus = bus
	add_child(camera_nudge)
	camera_rig = CameraRig.new()   # limits to the level, smooth follow, snap on a new camera
	camera_rig.name = "CameraRig"
	camera_rig.skin = skin
	add_child(camera_rig)
	if bus:
		bus.startle_progress.connect(_on_startle)


func _add(n: Node2D, nm: String) -> Node2D:
	n.name = nm
	n.set("skin", skin)
	n.set("bus", bus)
	layer.add_child(n)
	return n


func meter_for(enemy: Node2D) -> Node2D:
	if enemy == null or not is_instance_valid(enemy):
		return null
	var raw = _meters.get(enemy.get_instance_id(), null)
	return raw if is_instance_valid(raw) else null


func _on_startle(enemy: Node2D, p: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var raw = _meters.get(id, null)   # untyped: the meter frees itself with its enemy
	var m: Node2D = raw if is_instance_valid(raw) else null
	if m == null:
		if p <= 0.0:
			return
		m = StartleMeter.new()
		m.name = "Startle_%d" % id
		m.skin = skin
		m.bus = bus
		m.target = enemy
		layer.add_child(m)
		_meters[id] = m
		m.tree_exiting.connect(func(): _meters.erase(id))
	m.set_progress(p)

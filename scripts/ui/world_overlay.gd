extends Node2D
## World-space FE overlays in one node: selection ring, per-enemy startle
## meters, pickup gauge, throw line and camera nudge. Drop
## `scenes/ui/world_overlay.tscn` under the level's world root.
## The drawn pieces live in a child CanvasLayer that follows the camera
## (follow_viewport) so the level's CanvasModulate darkness never dims the UI;
## only the selected-enemy glow light stays in the world canvas.

const SelectionRing := preload("res://scripts/ui/selection_ring.gd")
const StartleMeter := preload("res://scripts/ui/startle_meter.gd")
const PickupGauge := preload("res://scripts/ui/pickup_gauge.gd")
const ThrowLine := preload("res://scripts/ui/throw_line.gd")
const CameraNudge := preload("res://scripts/ui/camera_nudge.gd")

var skin: HudSkin
var bus: Node
var ring: Node2D
var pickup_gauge: Node2D
var throw_line: Node2D
var camera_nudge: Node
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
	if bus:
		bus.startle_progress.connect(_on_startle)


func _add(n: Node2D, nm: String) -> Node2D:
	n.name = nm
	n.set("skin", skin)
	n.set("bus", bus)
	layer.add_child(n)
	return n


func meter_for(enemy: Node2D) -> Node2D:
	if enemy == null:
		return null
	return _meters.get(enemy.get_instance_id(), null)


func _on_startle(enemy: Node2D, p: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	var m: Node2D = _meters.get(id, null)
	if m == null or not is_instance_valid(m):
		if p <= 0.0:
			return
		m = StartleMeter.new()
		m.name = "Startle_%d" % id
		m.skin = skin
		m.bus = bus
		m.target = enemy
		layer.add_child(m)
		_meters[id] = m
	m.set_progress(p)

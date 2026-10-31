extends Label
## "tap: throw lure", just above the inventory strip, exactly while BE says a tap with nothing
## ringed would throw a Music Box lure: PlayerStats.tap_throws_lure() (PR #41: lures live in
## their own pocket, never in the hands, so the old "Music Box is the selected hand item" test
## can no longer be true). Without #41 (no such method) it falls back to the legacy held lure
## dict ({lure = true, ...}) being selected.
## Updated on PlayerStats.lures_changed and FESignals.inventory_changed / inventory_selected
## (ring changes come through inventory_selected + the knock reach, so it also re-checks each
## frame while lures are left: tap_throws_lure() flips as the boy walks up to a prop).

const TEXT := "tap: throw lure"

var skin: HudSkin
var bus: Node
## PlayerStats (default: the autoload; tests inject one).
var stats: Node


func _enter_tree() -> void:
	if bus == null:
		bus = UiArt.bus()
	_wire(true)
	var ps := _stats()
	if ps and ps.has_signal(&"lures_changed") and not ps.is_connected(&"lures_changed", _on_lures):
		ps.connect(&"lures_changed", _on_lures)
	if is_node_ready():
		refresh()


## Methods (no lambdas), connected only while in the tree.
func _exit_tree() -> void:
	_wire(false)
	var ps := _stats()
	if ps and ps.has_signal(&"lures_changed") and ps.is_connected(&"lures_changed", _on_lures):
		ps.disconnect(&"lures_changed", _on_lures)


func _stats() -> Node:
	if stats != null and is_instance_valid(stats):
		return stats
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"PlayerStats") if tree else null


func _on_lures(_c: int, _m: int) -> void:
	refresh()


## True while BE says a tap with nothing ringed throws a pocket lure.
func pocket_lure() -> bool:
	var ps := _stats()
	return ps != null and ps.has_method(&"tap_throws_lure") and bool(ps.tap_throws_lure())


## Cheap per-frame check: only while a lure is left (or the hint is up and needs to drop).
func _process(_delta: float) -> void:
	var ps := _stats()
	if ps != null and ps.has_method(&"lure_charges"):
		if visible or int(ps.lure_charges()) > 0:
			refresh()
	elif visible != wants_visible():   # legacy: the held dict changes through the bus signals
		refresh()


func _wire(on: bool) -> void:
	if bus == null or not is_instance_valid(bus):
		return
	for sig in [&"inventory_changed", &"inventory_selected"]:
		if not bus.has_signal(sig):
			continue
		var connected: bool = bus.is_connected(sig, _on_inventory)
		if on and not connected:
			bus.connect(sig, _on_inventory)
		elif not on and connected:
			bus.disconnect(sig, _on_inventory)


func _ready() -> void:
	text = TEXT
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	add_theme_constant_override("outline_size", 4)
	refresh()


func _on_inventory(_arg: Variant) -> void:
	refresh()


## True while the held (selected) item is a lure.
static func holds_lure(b: Node) -> bool:
	if b == null or not b.has_method(&"selected_item"):
		return false
	var d: Dictionary = b.selected_item()
	return bool(d.get("lure", false))


## With #41's API the answer is exactly tap_throws_lure(); without it, the legacy held lure.
func wants_visible() -> bool:
	var ps := _stats()
	if ps != null and ps.has_method(&"tap_throws_lure"):
		return pocket_lure()
	return holds_lure(bus)


func refresh() -> void:
	if not is_inside_tree():
		return
	visible = wants_visible()

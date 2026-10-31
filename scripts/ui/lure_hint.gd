extends Label
## "tap: throw lure", just above the inventory strip, while a tap with nothing ringed would
## throw a Music Box lure: BE PlayerStats.tap_throws_lure() (lures live in their own pocket,
## never in the hands), or a legacy held lure dict ({lure = true, ...}) selected.
## Updated on FESignals.inventory_changed / inventory_selected / PlayerStats.lures_changed,
## and re-checked each frame while lures are left (the knock-reach part moves with the boy).

const TEXT := "tap: throw lure"

var skin: HudSkin
var bus: Node


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


static func _stats() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"PlayerStats") if tree else null


func _on_lures(_c: int, _m: int) -> void:
	refresh()


## True while BE says a tap with nothing ringed throws a pocket lure.
static func pocket_lure() -> bool:
	var ps := _stats()
	return ps != null and ps.has_method(&"tap_throws_lure") and bool(ps.tap_throws_lure())


func _process(_delta: float) -> void:
	var ps := _stats()
	if ps and ps.has_method(&"lure_charges") and int(ps.lure_charges()) > 0:
		refresh()
	elif visible and not holds_lure(bus):
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


func refresh() -> void:
	if not is_inside_tree():
		return
	visible = holds_lure(bus) or pocket_lure()

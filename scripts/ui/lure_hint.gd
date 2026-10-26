extends Label
## "tap: throw lure", just above the inventory strip, only while the selected held item is a
## lure (the Music Box's lure dict from BE: {lure = true, throwable = true, ...}).
## Updated on FESignals.inventory_changed / inventory_selected; no polling.

const TEXT := "tap: throw lure"

var skin: HudSkin
var bus: Node


func _enter_tree() -> void:
	if bus == null:
		bus = UiArt.bus()
	_wire(true)
	if is_node_ready():
		refresh()


## Methods (no lambdas), connected only while in the tree.
func _exit_tree() -> void:
	_wire(false)


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
	visible = holds_lure(bus)

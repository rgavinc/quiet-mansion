extends Label
## "tap: throw lure", just above the inventory strip, only while the selected held item is a
## lure (the Music Box's lure dict from BE: {lure = true, throwable = true, ...}).
## Updated on FESignals.inventory_changed / inventory_selected; no polling.

const TEXT := "tap: throw lure"

var skin: HudSkin
var bus: Node


func _ready() -> void:
	if bus == null:
		bus = UiArt.bus()
	text = TEXT
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	add_theme_constant_override("outline_size", 4)
	if bus:
		if bus.has_signal(&"inventory_changed"):
			bus.inventory_changed.connect(func(_i): refresh())
		if bus.has_signal(&"inventory_selected"):
			bus.inventory_selected.connect(func(_i): refresh())
	refresh()


## True while the held (selected) item is a lure.
static func holds_lure(b: Node) -> bool:
	if b == null or not b.has_method(&"selected_item"):
		return false
	var d: Dictionary = b.selected_item()
	return bool(d.get("lure", false))


func refresh() -> void:
	visible = holds_lure(bus)

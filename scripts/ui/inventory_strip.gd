extends MarginContainer
## Held-item strip. Listens to FESignals.inventory_changed / inventory_selected.
## Items are Dictionaries {id, slot, name, throwable}; the icon is looked up
## BY SLOT NAME ("icon_" + slot, then slot) via the manifest. Empty-safe.
## Scroll wheel (inv_next / inv_prev) selection is owned by Back End's Inventory;
## this widget only highlights.

var skin: HudSkin
var bus: Node

var _row: HBoxContainer
var _name_label: Label
var _slots: Array[PanelContainer] = []
var _items: Array = []
var _selected: int = -1


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if theme == null and ResourceLoader.exists("res://assets/ui/hud_theme.tres"):
		theme = load("res://assets/ui/hud_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_bottom", 14)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	add_child(col)
	_name_label = Label.new()
	_name_label.name = "ItemName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	col.add_child(_name_label)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 6)
	col.add_child(_row)
	if bus == null:
		bus = UiArt.bus()
	if bus:
		bus.inventory_changed.connect(_on_items)
		bus.inventory_selected.connect(_on_selected)
		_on_items(bus.items)
		_on_selected(bus.selected_index)
	else:
		_on_items([])


func slot_count() -> int:
	return _slots.size()


func selected_index() -> int:
	return _selected


func _on_items(items: Array) -> void:
	_items = items.duplicate()
	for s in _slots:
		s.queue_free()
	_slots.clear()
	if _items.is_empty():
		# One dim empty slot so the strip never vanishes / never indexes empty.
		var empty := _make_slot({})
		empty.modulate = Color(1, 1, 1, 0.45)
		_row.add_child(empty)
		_slots.append(empty)
		_name_label.text = "Hold LMB to pick up"
		_selected = -1
		return
	for it in _items:
		var d: Dictionary = it if it is Dictionary else {}
		var s := _make_slot(d)
		_row.add_child(s)
		_slots.append(s)
	_on_selected(_selected)


func _on_selected(index: int) -> void:
	_selected = index if (index >= 0 and index < _items.size()) else -1
	for i in _slots.size():
		var sel := i == _selected
		_slots[i].theme_type_variation = &"HudSlotSelected" if sel else &"HudSlot"
		var icon := _slots[i].get_child(0) as HudIcon
		if icon and sel and is_inside_tree():
			icon.do_pop()
	if _selected >= 0:
		var d: Dictionary = _items[_selected] if _items[_selected] is Dictionary else {}
		_name_label.text = str(d.get("name", d.get("slot", "")))
	elif not _items.is_empty():
		_name_label.text = ""


func _make_slot(d: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"HudSlot"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(skin.slot_size, skin.slot_size)
	var icon := HudIcon.new()
	icon.kind = HudIcon.Kind.ITEM
	icon.skin = skin
	var slot := str(d.get("slot", ""))
	if not slot.is_empty():
		icon.slot = "icon_" + slot if UiArt.texture("icon_" + slot) != null else slot
	icon.label_text = str(d.get("name", slot))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(icon)
	return p

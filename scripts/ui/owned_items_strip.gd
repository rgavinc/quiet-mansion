extends HBoxContainer
## Owned-items strip (top-left, under hearts + gold). Driven by PlayerStats.items_changed,
## which BE fires on every buy / chest grant, every charge change (Item.use_charge /
## set_charges) and once per stage start (begin_stage refills charges).
## One tile per owned Item: icon by `icon_slot` (manifest), else a letter tile with the
## shop's initials (Shop.initials / unique_initials) on the rarity rim (HudSkin.rarity_colors,
## Designer's palette). Items with max_charges > 0 (Flash Bulb, Rabbit's Foot, Music Box)
## get one pip per charge under the tile, filled = left this stage, plus "n/max".
## Reads only Item fields (id, display_name, icon_slot, rarity, charges, max_charges).

const ShopUi := preload("res://scripts/ui/shop.gd")
const TILE := 40.0
const PIP_R := 3.5
const PIP_FULL := Color(1.0, 0.86, 0.35)
const PIP_EMPTY := Color(0.25, 0.22, 0.28, 0.9)

var skin: HudSkin
## PlayerStats (default: the autoload).
var stats: Node
## Last drawn entries: [{id, name, icon_slot, rarity, charges, max_charges, tile}] (tests/debug).
var entries: Array = []


func _ready() -> void:
	name = "OwnedItems" if name.begins_with("@") else name
	if skin == null:
		skin = HudSkin.load_default()
	if stats == null:
		stats = get_node_or_null(^"/root/PlayerStats")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	if stats and stats.has_signal(&"items_changed"):
		stats.items_changed.connect(_on_items_changed)
	refresh()


func _on_items_changed(_items: Array) -> void:
	refresh()


func refresh() -> void:
	var list: Array = stats.get("owned_items") if stats and "owned_items" in stats else []
	for c in get_children():
		remove_child(c)
		c.queue_free()
	entries.clear()
	var live: Array = []
	for it in list:
		if it is Object and is_instance_valid(it):
			live.append(it)
	var names: PackedStringArray = []
	for it in live:
		names.append(str(it.get("display_name")))
	var tiles: Dictionary = ShopUi.unique_initials(names)
	for it in live:
		var e := {
			id = str(it.get("id")), name = str(it.get("display_name")),
			icon_slot = str(it.get("icon_slot")), rarity = str(it.get("rarity")),
			charges = int(it.get("charges")) if "charges" in it else 0,
			max_charges = int(it.get("max_charges")) if "max_charges" in it else 0,
		}
		e.tile = tiles.get(e.name, ShopUi.initials(e.name))
		entries.append(e)
		add_child(_make_entry(e))
	visible = not entries.is_empty()


func _rim(rarity: String) -> Color:
	return skin.rarity_colors.get(rarity, skin.rarity_colors.get("common", Color.WHITE))


func _make_entry(e: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "Item_%s" % e.id
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.tooltip_text = e.name
	var box := PanelContainer.new()
	box.name = "Tile"
	box.custom_minimum_size = Vector2(TILE, TILE)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.09, 0.85)
	sb.border_color = _rim(e.rarity)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	box.add_theme_stylebox_override(&"panel", sb)
	col.add_child(box)
	var tex: Texture2D = UiArt.first_frame(e.icon_slot) if not e.icon_slot.is_empty() else null
	if tex:
		var tr := TextureRect.new()
		tr.name = "Icon"
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	else:
		var l := Label.new()
		l.name = "Initials"
		l.text = e.tile
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", _rim(e.rarity))
		box.add_child(l)
	if e.max_charges > 0:
		var row := HBoxContainer.new()
		row.name = "Charges"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pips := _Pips.new()
		pips.name = "Pips"
		pips.left = e.charges
		pips.total = e.max_charges
		row.add_child(pips)
		if e.max_charges > 1:
			var n := Label.new()
			n.name = "Count"
			n.text = "%d/%d" % [e.charges, e.max_charges]
			n.add_theme_font_size_override("font_size", 11)
			row.add_child(n)
		col.add_child(row)
		if e.charges <= 0:
			box.modulate = Color(1, 1, 1, 0.45)   # spent this stage
	return col


## One dot per charge: filled = left this stage.
class _Pips extends Control:
	var left := 0
	var total := 0

	func _get_minimum_size() -> Vector2:
		return Vector2(total * (PIP_R * 2.0 + 3.0), PIP_R * 2.0 + 2.0)

	func _draw() -> void:
		for i in total:
			var c := Vector2(PIP_R + 1.0 + i * (PIP_R * 2.0 + 3.0), PIP_R + 1.0)
			draw_circle(c, PIP_R + 1.0, Color(0, 0, 0, 0.7))
			draw_circle(c, PIP_R, PIP_FULL if i < left else PIP_EMPTY)

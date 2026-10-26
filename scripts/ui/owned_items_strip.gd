extends VBoxContainer
## Owned-items strip (top-left, under hearts + gold). Driven by PlayerStats.items_changed,
## which BE fires on every buy / chest grant, every charge change (Item.use_charge /
## set_charges) and once per stage start (begin_stage refills charges).
## One tile per owned item id: duplicates stack into one tile with a "×N" badge. Icon by
## `icon_slot` (manifest), else a letter tile with the shop's initials (Shop.initials /
## unique_initials) on the rarity rim (HudSkin.rarity_colors, Designer's palette).
## Items with max_charges > 0 (Flash Bulb, Rabbit's Foot, Music Box) get charge pips under
## the tile (filled = left this stage; summed over a stack). The pips are the count; a
## numeric "n/max" only appears past MAX_PIPS (then a single pip + the number).
## `make_compact()` gives the shop's smaller one-row variant (same stacking / tiles).
## Wraps: PER_ROW tiles a row, MAX_ROWS rows; past that the last tile is "+N" (hidden ids),
## so the strip never reaches the minimap (right edge <= 14 + PER_ROW * 46 px).
## Signals are connected to methods while in the tree only (no lambdas): a HUD that left
## the tree on a stage change never reacts.

const ShopUi := preload("res://scripts/ui/shop.gd")
const TILE := 40.0
const SEP := 6
const PER_ROW := 12
const MAX_ROWS := 2
## Pip display cap: up to this many charges are drawn as pips (no number); above it, one
## pip + "n/max".
const MAX_PIPS := 5
const PIP_R := 5.5            # 11 px pips
const PIP_GAP := 3.0
const PIP_FULL := Color(1.0, 0.86, 0.35)
## Spent pip: near-black fill inside a light ring, inside a black edge, so it reads on both
## the dark mansion walls (ring) and light backdrops (fill + edge).
const PIP_EMPTY := Color(0.07, 0.06, 0.09)
const PIP_RING := Color(0.9, 0.86, 0.78)
const PIP_EDGE := Color(0, 0, 0, 0.9)
## ×N stack badge: white text on a dark rounded pill (bottom-right of the tile).
const BADGE_BG := Color(0.04, 0.03, 0.06, 0.82)
const BADGE_TEXT := Color.WHITE

var skin: HudSkin
## PlayerStats (default: the autoload).
var stats: Node
## Last drawn stacks, in first-owned order: [{id, name, icon_slot, rarity, count, charges,
## max_charges, tile}] (tests/debug). Includes stacks hidden by the cap.
var entries: Array = []
## Tile Controls actually shown (entries[0 .. tiles.size()-1]), and the "+N" overflow count.
var tiles: Array[Control] = []
var overflow := 0
## Layout (make_compact() shrinks these).
var tile_size := TILE
var per_row := PER_ROW
var max_rows := MAX_ROWS
var pip_r := PIP_R
var sep := SEP
var compact := false


## Shop variant: 28 px tiles, 8 px pips, one row of 14 (+N past that).
func make_compact(row_tiles: int = 14) -> void:
	compact = true
	tile_size = 28.0
	pip_r = 4.0
	sep = 4
	per_row = row_tiles
	max_rows = 1
	if is_node_ready():
		refresh()


func _enter_tree() -> void:
	if stats == null:
		stats = get_node_or_null(^"/root/PlayerStats")
	if stats and stats.has_signal(&"items_changed") and not stats.items_changed.is_connected(_on_items_changed):
		stats.items_changed.connect(_on_items_changed)
	if is_node_ready():
		refresh()   # re-entering: catch up on anything missed while out of the tree


func _exit_tree() -> void:
	if stats and is_instance_valid(stats) and stats.has_signal(&"items_changed") and stats.items_changed.is_connected(_on_items_changed):
		stats.items_changed.disconnect(_on_items_changed)


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	refresh()


func _on_items_changed(_items: Array) -> void:
	refresh()


func _stacks() -> Array:
	var list: Array = stats.get("owned_items") if stats and is_instance_valid(stats) and "owned_items" in stats else []
	var order: Array = []
	var by_id := {}
	for it in list:
		if not (it is Object and is_instance_valid(it)):
			continue
		var id := str(it.get("id"))
		if not by_id.has(id):
			by_id[id] = {
				id = id, name = str(it.get("display_name")), icon_slot = str(it.get("icon_slot")),
				rarity = str(it.get("rarity")), count = 0, charges = 0, max_charges = 0,
			}
			order.append(by_id[id])
		var e: Dictionary = by_id[id]
		e.count += 1
		e.charges += int(it.get("charges")) if "charges" in it else 0
		e.max_charges += int(it.get("max_charges")) if "max_charges" in it else 0
	return order


func refresh() -> void:
	if not is_inside_tree() or skin == null:
		return
	for c in get_children():
		remove_child(c)
		c.queue_free()
	tiles.clear()
	entries = _stacks()
	var names: PackedStringArray = []
	for e in entries:
		names.append(e.name)
	var initials: Dictionary = ShopUi.unique_initials(names)
	for e in entries:
		e.tile = initials.get(e.name, ShopUi.initials(e.name))
	var cap := per_row * max_rows
	var shown := entries.size() if entries.size() <= cap else cap - 1
	overflow = entries.size() - shown
	var row: HBoxContainer = null
	for i in shown + (1 if overflow > 0 else 0):
		if i % per_row == 0:
			row = HBoxContainer.new()
			row.name = "Row%d" % (i / per_row)
			row.add_theme_constant_override("separation", sep)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(row)
		var t := _make_entry(entries[i]) if i < shown else _make_overflow(overflow)
		row.add_child(t)
		if i < shown:
			tiles.append(t)
	visible = not entries.is_empty()


## Widest the strip can get (px): PER_ROW tiles + gaps.
static func max_width() -> float:
	return PER_ROW * TILE + (PER_ROW - 1) * SEP + 8.0   # + room for 3 pips under a tile


func _rim(rarity: String) -> Color:
	return skin.rarity_colors.get(rarity, skin.rarity_colors.get("common", Color.WHITE))


func _tile_box(rim: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "Tile"
	box.custom_minimum_size = Vector2(tile_size, tile_size)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.09, 0.85)
	sb.border_color = rim
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	box.add_theme_stylebox_override(&"panel", sb)
	return box


func _small_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.04))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_overflow(n: int) -> Control:
	var col := VBoxContainer.new()
	col.name = "Overflow"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := _tile_box(Color(0.6, 0.55, 0.65))
	var l := _small_label("+%d" % n, 11 if compact else 15)
	l.name = "More"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	col.add_child(box)
	return col


func _make_entry(e: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.name = "Item_%s" % e.id
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.tooltip_text = e.name if e.count == 1 else "%s ×%d" % [e.name, e.count]
	var box := _tile_box(_rim(e.rarity))
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
		var l := _small_label(e.tile, 11 if compact else 16)
		l.name = "Initials"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", _rim(e.rarity))
		box.add_child(l)
	if e.count > 1:
		box.add_child(_badge(e.count))
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
		pips.r = pip_r
		row.add_child(pips)
		if e.max_charges > MAX_PIPS:
			var n := _small_label("%d/%d" % [e.charges, e.max_charges], 10 if compact else 12)
			n.name = "Count"
			row.add_child(n)
		col.add_child(row)
		if e.charges <= 0:
			box.modulate = Color(1, 1, 1, 0.45)   # spent this stage
	return col


## "×N" pill: a full-tile overlay (PanelContainer children fill it) with the pill
## anchored bottom-right, so it sits in the corner instead of across the icon.
func _badge(count: int) -> Control:
	var overlay := Control.new()
	overlay.name = "BadgeLayer"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	pill.name = "Badge"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BADGE_BG
	sb.set_corner_radius_all(6 if not compact else 4)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	pill.add_theme_stylebox_override(&"panel", sb)
	var l := Label.new()
	l.name = "Stack"
	l.text = "×%d" % count
	l.add_theme_font_size_override("font_size", 9 if compact else 11)
	l.add_theme_color_override("font_color", BADGE_TEXT)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	overlay.add_child(pill)
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_right = -1
	pill.offset_bottom = -1
	return overlay


## One 11 px dot per charge (filled = left this stage). Over MAX_PIPS: one dot (lit while any
## is left) and the "n/max" label carries the number.
class _Pips extends Control:
	var left := 0
	var total := 0
	var r := PIP_R

	func dots() -> int:
		return total if total <= MAX_PIPS else 1

	func lit(i: int) -> bool:
		return i < left if total <= MAX_PIPS else left > 0

	func _get_minimum_size() -> Vector2:
		var n := dots()
		var gap := PIP_GAP if r >= PIP_R else 2.0
		return Vector2(n * (r * 2.0 + 2.0) + (n - 1) * gap, r * 2.0 + 2.0)

	func _draw() -> void:
		var gap := PIP_GAP if r >= PIP_R else 2.0
		for i in dots():
			var c := Vector2(r + 1.0 + i * (r * 2.0 + 2.0 + gap), r + 1.0)
			draw_circle(c, r + 1.0, PIP_EDGE)
			if lit(i):
				draw_circle(c, r, PIP_FULL)
			else:
				draw_circle(c, r, PIP_RING)
				draw_circle(c, r - 1.5, PIP_EMPTY)

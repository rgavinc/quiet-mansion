extends VBoxContainer
## Owned-items strip (top-left, under hearts + gold). Driven by PlayerStats.items_changed,
## which BE fires on every buy / chest grant, every charge change (Item.use_charge /
## set_charges) and once per stage start (begin_stage refills charges).
## One tile per owned item id: duplicates stack into one tile with a "×N" badge.
## Order (stable): items with charges first, then stacks (count > 1), then the rest, each
## group in acquisition order, so what matters stays visible ahead of the "+N" tile. Icon by
## `icon_slot` (manifest), else a letter tile with the shop's initials (Shop.initials /
## unique_initials) on the rarity rim (HudSkin.rarity_colors, Designer's palette).
## Items with max_charges > 0 (Flash Bulb, Rabbit's Foot, Music Box) get charge pips under
## the tile (filled = left this stage; summed over a stack). The pips are the count; a
## numeric "n/max" only appears past MAX_PIPS (then a single pip + the number).
## `make_compact()` gives the shop's smaller one-row variant (same stacking / tiles).
## Wraps: PER_ROW tiles a row, MAX_ROWS rows; past that the last tile is "+N" (hidden ids),
## so the strip never reaches the minimap (right edge <= 14 + PER_ROW * 46 px).
## No-widen guarantee: every column is exactly one tile wide (custom_minimum_size +
## clip_contents). Pips wrap onto up to 2 lines inside the tile width (shrinking the dot if
## needed); past what fits, one pip + a small "n/max" sized to fit the tile. So the strip
## is always per_row * tile + gaps wide, whatever is owned (max_width()).
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
## "+N" reveals the hidden items: tooltip (mouse_filter STOP) + click toggles a popover list.
## Off in the HUD (it never takes the mouse); make_compact() (shop) turns it on.
var overflow_interactive := false
## Popover stays inside this Control's rect (e.g. the shop's OffersPanel), else the screen.
var popover_bounds: Control
var overflow_tile: Control
var popover: PanelContainer
var _eat_release := MOUSE_BUTTON_NONE


## Shop variant: 28 px tiles, smaller pips, `row_tiles` a row, `rows` rows (+N past that).
func make_compact(row_tiles: int = 11, rows: int = 1) -> void:
	compact = true
	tile_size = 28.0
	pip_r = 3.5
	sep = 4
	per_row = row_tiles
	max_rows = rows
	overflow_interactive = true
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
		if _in_pocket(it):
			e.pocket = true   # its lure charges show in the lure pocket, not on this tile
			continue
		e.charges += int(it.get("charges")) if "charges" in it else 0
		e.max_charges += int(it.get("max_charges")) if "max_charges" in it else 0
	# stable: group key, then first-owned index
	for i in order.size():
		order[i].order = i
	order.sort_custom(func(a, b):
		var ka := _group(a)
		var kb := _group(b)
		return ka < kb or (ka == kb and a.order < b.order))
	return order


## 0 = has charges, 1 = stacked, 2 = the rest.
static func _group(e: Dictionary) -> int:
	if e.max_charges > 0:
		return 0
	if e.count > 1:
		return 1
	return 2


func refresh() -> void:
	if not is_inside_tree() or skin == null:
		return
	for c in get_children():
		if c == popover:
			continue
		remove_child(c)
		c.queue_free()
	tiles.clear()
	overflow_tile = null
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
		var t := _make_entry(entries[i]) if i < shown else _make_overflow(overflow, hidden_entries())
		row.add_child(t)
		if i < shown:
			tiles.append(t)
		else:
			overflow_tile = t
	visible = not entries.is_empty()
	if popover and popover.visible:
		if overflow > 0:
			_fill_popover()
		else:
			close_overflow()


## Widest the strip can get (px): per_row tiles + gaps (columns never widen).
func max_width() -> float:
	return per_row * tile_size + (per_row - 1) * sep


## Music Box copies keep a tile here, but with PR #41's lure pocket (PlayerStats.lure_max())
## their charges live in the pocket pips next to the hand strip, so the tile shows none: no
## pips, no "spent" fade, no charged-first ordering. Without #41 they stay ordinary charged items.
func _in_pocket(it: Object) -> bool:
	return it.has_method(&"lure_dict") and stats != null and stats.has_method(&"lure_max")


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


## Stacks hidden behind "+N" (in display order).
func hidden_entries() -> Array:
	return entries.slice(tiles.size()) if overflow > 0 else []


## One line per stack: "Name", "Name ×N", plus " (c/max charges)" for charged items.
static func entry_line(e: Dictionary) -> String:
	var t: String = e.name if e.count == 1 else "%s ×%d" % [e.name, e.count]
	if e.max_charges > 0:
		t += " (%d/%d charges)" % [e.charges, e.max_charges]
	return t


func overflow_tooltip() -> String:
	var lines: PackedStringArray = []
	for e in hidden_entries():
		lines.append(entry_line(e))
	return "\n".join(lines)


func _make_overflow(n: int, hidden: Array = []) -> Control:
	var col := VBoxContainer.new()
	col.name = "Overflow"
	col.mouse_filter = Control.MOUSE_FILTER_STOP if overflow_interactive else Control.MOUSE_FILTER_IGNORE
	if overflow_interactive:
		col.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		col.gui_input.connect(_on_overflow_input)
	var lines: PackedStringArray = []
	for e in hidden:
		lines.append(entry_line(e))
	col.tooltip_text = "\n".join(lines)
	_fix_column(col)
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
	_fix_column(col)
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
	var art: Control = box.get_child(box.get_child_count() - 1)
	if e.count > 1:
		box.add_child(_badge(e.count))
	if e.max_charges > 0:
		var row := HBoxContainer.new()
		row.name = "Charges"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 1)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size.x = tile_size
		row.clip_contents = true
		var pips := _Pips.new()
		pips.name = "Pips"
		pips.left = e.charges
		pips.total = e.max_charges
		pips.lines = 1 if compact else 2   # shop: keep its 2 tile rows short
		pips.fit(pip_r, tile_size)
		row.add_child(pips)
		if pips.numeric():
			var txt := "%d/%d" % [e.charges, e.max_charges]
			var room := tile_size - pips.get_combined_minimum_size().x - 1.0
			var n := _small_label(txt, _fit_font(txt, room, 10 if compact else 12))
			n.name = "Count"
			n.add_theme_constant_override("outline_size", 2)
			n.clip_text = true   # min width 0: can never widen the column
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
		col.add_child(row)
		if e.charges <= 0:
			# spent this stage: fade the icon and tile, not the ×N badge
			box.self_modulate = Color(1, 1, 1, 0.45)
			art.modulate = Color(1, 1, 1, 0.45)
	return col


## Column = exactly one tile wide; children can never push it wider.
func _fix_column(col: Control) -> void:
	col.custom_minimum_size.x = tile_size
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.clip_contents = true


## Largest font size <= `want` (min 7) whose text fits `room` px.
func _fit_font(txt: String, room: float, want: int) -> int:
	var font := ThemeDB.fallback_font
	var fs := want
	while fs > 7 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0 > room:
		fs -= 1
	return fs


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


func _on_overflow_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		toggle_overflow()
		accept_event()


func is_overflow_open() -> bool:
	return popover != null and popover.visible


func toggle_overflow() -> void:
	if is_overflow_open():
		close_overflow()
	else:
		open_overflow()


func open_overflow() -> void:
	if overflow <= 0 or not is_inside_tree():
		return
	if popover == null:
		popover = PanelContainer.new()
		popover.name = "OverflowList"
		popover.top_level = true   # an overlay: containers don't lay it out or size by it
		popover.z_index = 10
		popover.mouse_filter = Control.MOUSE_FILTER_STOP   # clicks on the list stay on it
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.045, 0.08, 0.96)
		sb.border_color = Color(0.85, 0.78, 0.6)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		popover.add_theme_stylebox_override(&"panel", sb)
		add_child(popover)
	popover.visible = true
	_fill_popover()


func close_overflow() -> void:
	if popover:
		popover.visible = false


func _fill_popover() -> void:
	for c in popover.get_children():
		popover.remove_child(c)
		c.queue_free()
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var title := _small_label("Also owned", 12)
	title.add_theme_color_override("font_color", Color(0.85, 0.8, 0.72))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Items"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for e in hidden_entries():
		var cell := HBoxContainer.new()
		cell.name = "Hidden_%s" % e.id
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_make_entry(e))
		var l := _small_label(entry_line(e), 11)
		l.name = "Name"
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		grid.add_child(cell)
	box.add_child(grid)
	popover.add_child(box)
	_place_popover.call_deferred()
	_place_popover()


## Above the "+N" tile, right-aligned to it, clamped inside popover_bounds (or the screen).
func _place_popover() -> void:
	if not is_overflow_open() or not is_inside_tree():
		return
	popover.reset_size()
	var sz := popover.get_combined_minimum_size()
	var b := popover_bounds.get_global_rect() if popover_bounds and is_instance_valid(popover_bounds) and popover_bounds.is_inside_tree() \
			else get_viewport().get_visible_rect()
	b = b.grow(-4.0)
	var anchor := overflow_tile.get_global_rect() if overflow_tile and is_instance_valid(overflow_tile) else get_global_rect()
	var pos := Vector2(anchor.end.x - sz.x, anchor.position.y - sz.y - 6.0)
	pos.x = clampf(pos.x, b.position.x, maxf(b.end.x - sz.x, b.position.x))
	pos.y = clampf(pos.y, b.position.y, maxf(b.end.y - sz.y, b.position.y))
	popover.global_position = pos
	popover.size = sz


## A click outside the list (and outside "+N", which toggles itself) only closes it: the click is
## consumed, so nothing underneath (a card's Buy, Continue) gets it; a second click acts.
func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and not ev.pressed and ev.button_index == _eat_release:
		_eat_release = MOUSE_BUTTON_NONE   # the matching release of the closing click
		get_viewport().set_input_as_handled()
		return
	if not is_overflow_open():
		return
	if ev is InputEventMouseButton and ev.pressed:
		var p: Vector2 = ev.position
		var on_tile := overflow_tile != null and is_instance_valid(overflow_tile) and overflow_tile.get_global_rect().has_point(p)
		if not on_tile and not popover.get_global_rect().has_point(p):
			close_overflow()
			_eat_release = ev.button_index
			get_viewport().set_input_as_handled()


## One dot per charge (filled = left this stage), wrapped onto up to `lines` (HUD 2, shop 1) lines inside the
## tile width; the dot shrinks (to 60 % of its radius) before giving up. Past MAX_PIPS, or
## if they still don't fit: one dot (lit while any is left) and the "n/max" label.
class _Pips extends Control:
	const GAP := 1.0
	var lines := 2
	var left := 0
	var total := 0
	var r := PIP_R
	var max_w := INF
	var per_line := 0

	func cell() -> float:
		return r * 2.0 + 1.5   # fill diameter + the dark edge

	func _per_line(rr: float) -> int:
		return maxi(int(floor((max_w + GAP) / (rr * 2.0 + 1.5 + GAP))), 1)

	## Pick the radius / dots-per-line for a `width` px tile.
	func fit(want_r: float, width: float) -> void:
		max_w = width
		r = want_r
		var need := mini(total, MAX_PIPS)
		while _per_line(r) * lines < need and r - 0.5 >= want_r * 0.6:
			r -= 0.5
		per_line = _per_line(r)
		update_minimum_size()

	## Pips while they fit, else 1 pip + "n/max". HUD (40 px tile, 2 lines): pips up to MAX_PIPS (5).
	## Shop compact row (28 px tile, 1 line, dot shrinks to 60 %): 3 fit, so "n/max" above 3 charges.
	func numeric() -> bool:
		return total > MAX_PIPS or total > per_line * lines

	func dots() -> int:
		return 1 if numeric() else total

	func lit(i: int) -> bool:
		return left > 0 if numeric() else i < left

	func _get_minimum_size() -> Vector2:
		var n := dots()
		var pl := maxi(per_line, 1) if per_line > 0 else n
		var cols := mini(n, pl)
		var ln := int(ceil(float(n) / pl))
		return Vector2(cols * cell() + (cols - 1) * GAP, ln * cell() + (ln - 1) * GAP)

	func _draw() -> void:
		var n := dots()
		var pl := maxi(per_line, 1) if per_line > 0 else n
		var w := size.x
		for i in n:
			var line := i / pl
			var in_line := mini(n - line * pl, pl)
			var lw := in_line * cell() + (in_line - 1) * GAP
			var x0 := (w - lw) * 0.5 if not numeric() else 0.0
			var c := Vector2(x0 + cell() * 0.5 + (i % pl) * (cell() + GAP), cell() * 0.5 + line * (cell() + GAP))
			draw_circle(c, r + 0.75, PIP_EDGE)
			if lit(i):
				draw_circle(c, r, PIP_FULL)
			else:
				draw_circle(c, r, PIP_RING)
				draw_circle(c, maxf(r - 1.5, 1.0), PIP_EMPTY)

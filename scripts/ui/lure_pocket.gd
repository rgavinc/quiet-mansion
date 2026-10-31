extends HBoxContainer
## Music Box lure pocket (PR #41): lure_max() pips, filled = lure_charges(), right of the
## held-item (hand) strip, with a small Music Box tile so it never reads as a hand slot.
## Hidden while lure_max() == 0 (no Music Box owned), or when PlayerStats has no pocket API
## (without #41). Redrawn on PlayerStats.lures_changed(charges, max), which BE fires on a
## throw, a stage refill, a buy and a reset. Signals are connected to methods only while in
## the tree (no lambdas), like the other item widgets.
## `anchor_strip` (the HUD's InventoryStrip, via slots_rect()) is what it sits beside: it
## follows the hand row's right edge each frame while shown, so it never overlaps a slot.

const ICON_SLOT := "item_icon_music_box"
const TILE := 32.0
const PIP_R := 5.5            # 11 px pips, like the owned strip
const PIP_GAP := 3.0
const MAX_PIPS := 5           # above this: one pip + "n/max"
const GAP := 12.0             # px between the last hand slot and the pocket
const PIP_FULL := Color(1.0, 0.86, 0.35)
const PIP_EMPTY := Color(0.07, 0.06, 0.09)
const PIP_RING := Color(0.9, 0.86, 0.78)
const PIP_EDGE := Color(0, 0, 0, 0.9)

var skin: HudSkin
## PlayerStats (default: the autoload; tests inject one).
var stats: Node
## The hand strip to sit beside (needs slots_rect() -> Rect2, global). Null = place nothing.
var anchor_strip: Control
## Last drawn state (tests/debug).
var charges := 0
var max_charges := 0

var _pips: _Pips
var _count: Label


func _enter_tree() -> void:
	if stats == null:
		stats = get_node_or_null(^"/root/PlayerStats")
	if stats and stats.has_signal(&"lures_changed") and not stats.is_connected(&"lures_changed", _on_lures):
		stats.connect(&"lures_changed", _on_lures)
	if is_node_ready():
		refresh()   # re-entering: catch up on anything missed while out of the tree


func _exit_tree() -> void:
	if stats and is_instance_valid(stats) and stats.has_signal(&"lures_changed") and stats.is_connected(&"lures_changed", _on_lures):
		stats.disconnect(&"lures_changed", _on_lures)


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var box := PanelContainer.new()
	box.name = "Tile"
	box.custom_minimum_size = Vector2(TILE, TILE)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.09, 0.85)
	sb.border_color = skin.rarity_colors.get("uncommon", Color.WHITE)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	box.add_theme_stylebox_override(&"panel", sb)
	var tex: Texture2D = UiArt.first_frame(ICON_SLOT)
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
		l.text = "MB"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	add_child(box)
	_pips = _Pips.new()
	_pips.name = "Pips"
	add_child(_pips)
	_count = Label.new()
	_count.name = "Count"
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.04))
	_count.add_theme_constant_override("outline_size", 4)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	tooltip_text = "Music Box lures"
	refresh()


func _on_lures(_c: int, _m: int) -> void:
	refresh()


func refresh() -> void:
	if not is_inside_tree() or _pips == null:
		return
	var has_api := stats != null and is_instance_valid(stats) and stats.has_method(&"lure_max") \
			and stats.has_method(&"lure_charges")
	max_charges = maxi(int(stats.lure_max()), 0) if has_api else 0
	charges = clampi(int(stats.lure_charges()), 0, max_charges) if has_api else 0
	visible = max_charges > 0
	_pips.left = charges
	_pips.total = max_charges
	_pips.update_minimum_size()
	_pips.queue_redraw()
	_count.visible = max_charges > MAX_PIPS
	_count.text = "%d/%d" % [charges, max_charges]
	modulate = Color(1, 1, 1, 1.0 if charges > 0 else 0.6)   # spent: dim, like a spent item


## Sit just right of the hand slots, bottom-aligned with them.
func _process(_delta: float) -> void:
	if not visible or anchor_strip == null or not is_instance_valid(anchor_strip) \
			or not anchor_strip.has_method(&"slots_rect"):
		return
	var r: Rect2 = anchor_strip.slots_rect()
	var parent := get_parent() as Control
	var origin := parent.global_position if parent else Vector2.ZERO
	position = Vector2(r.end.x + GAP, r.end.y - size.y - maxf(0.0, (r.size.y - size.y) * 0.5)) - origin


## One dot per lure (filled = left this stage); over MAX_PIPS a single dot, lit while any is left.
class _Pips extends Control:
	var left := 0
	var total := 0

	func dots() -> int:
		return total if total <= MAX_PIPS else 1

	func lit(i: int) -> bool:
		return i < left if total <= MAX_PIPS else left > 0

	func _get_minimum_size() -> Vector2:
		var n := dots()
		return Vector2(n * PIP_R * 2.0 + maxi(n - 1, 0) * PIP_GAP + 2.0, PIP_R * 2.0 + 2.0)

	func _draw() -> void:
		for i in dots():
			var c := Vector2(PIP_R + 1.0 + i * (PIP_R * 2.0 + PIP_GAP), size.y * 0.5)
			draw_circle(c, PIP_R + 1.0, PIP_EDGE)
			if lit(i):
				draw_circle(c, PIP_R, PIP_FULL)
			else:
				draw_circle(c, PIP_R, PIP_RING)
				draw_circle(c, PIP_R - 1.5, PIP_EMPTY)

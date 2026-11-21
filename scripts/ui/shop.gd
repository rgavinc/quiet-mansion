extends UiScreen
## Stage-clear + merchant shop. Opens on FESignals.stage_cleared (REAL:
## GameState.reached_exit on stages 1..MAX_STAGES-1; the last stage shows the win
## screen instead — docs/PRODUCT.md), pauses the
## tree, shows N offers from FESignals.get_shop_offer (BE Shop.roll_stock when the
## class exists, else demo stub, else empty), buys via FESignals.buy_offer
## (Shop.buy / PlayerStats.try_spend). Continue → FESignals.next_stage().
##
## Layout: `shop_backdrop` (320x180) covers the screen; the merchant
## (`merchant_idle`, beckoning loop) stands at backdrop x≈172 behind the counter
## (y≈110). Offer cards sit in the LEFT column and the title/gold/Continue in the
## RIGHT column, so nothing covers the merchant band. Missing art → dim + panels
## + a drawn silhouette in the same spot.
##
## Under the offer cards: a compact owned-items row (the HUD's OwnedItemsStrip in
## make_compact() mode: same stacking / tiles), live on PlayerStats.items_changed; hearts
## sit next to the gold. Bus / stats signals are connected to methods while in the tree
## only, and disconnected in _exit_tree (a shop left behind by a stage change never reacts).

## Loaded at build time, not preloaded: the strip preloads this script (initials), and a
## preload cycle leaks both scripts at exit.
const OWNED_STRIP_PATH := "res://scripts/ui/owned_items_strip.gd"

const BACKDROP_SIZE := Vector2(320, 180)
## Most offer cards the left column holds (4 cards with 2-line descriptions + the
## message line, tested). The stock BE's Shop.roll_stock returns is shown in full up
## to this (BE ItemDb.STOCK_SIZE = 4).
const MAX_CARDS := 4
## Description lines per card; the full text is in the card's tooltip.
const DESC_LINES := 2

var title: Label
var gold_label: Label
var message: Label
var offers_box: VBoxContainer
var continue_button: Button
var merchant: Node2D
var merchant_anchor: Control
var has_backdrop := false
## PlayerStats for the owned row (tests); null = /root/PlayerStats.
var stats: Node
var owned_row: HBoxContainer
var owned_label: Label
var owned_strip: Control
var hearts_box: HBoxContainer
var hearts: Array[HudIcon] = []

var offers: Array[Dictionary] = []
var cards: Array[Control] = []
var sold: Array[bool] = []


func _build() -> void:
	var bd := UiScreen.backdrop(skin.shop_backdrop_slot)
	has_backdrop = bd != null
	if has_backdrop:
		root.add_child(bd)
	else:
		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.color = skin.screen_dim
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(dim)

	# Merchant: positioned in backdrop space in _layout_merchant().
	merchant_anchor = Control.new()
	merchant_anchor.name = "MerchantAnchor"
	merchant_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	merchant_anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(merchant_anchor)
	var sf := UiArt.frames(skin.merchant_slot)
	if sf:
		var spr := AnimatedSprite2D.new()
		spr.name = "Merchant"
		spr.sprite_frames = sf
		spr.animation = skin.merchant_slot
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.offset = AnimLibrary.offset_for(skin.merchant_slot)   # pivot = feet
		merchant = spr
	else:
		merchant = _MerchantStandIn.new()
		merchant.name = "Merchant"
	merchant_anchor.add_child(merchant)
	merchant_anchor.resized.connect(_layout_merchant)

	# LEFT column: offers.
	var left := PanelContainer.new()
	left.name = "OffersPanel"
	left.anchor_left = 0.0
	left.anchor_right = 0.0
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_left = 32
	left.offset_right = 32 + 460
	left.offset_top = 72
	left.offset_bottom = -72
	left.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override(&"separation", 10)
	left.add_child(lcol)
	var lt := UiScreen.label("The merchant's wares", 22)
	lcol.add_child(lt)
	offers_box = VBoxContainer.new()
	offers_box.name = "Offers"
	offers_box.add_theme_constant_override(&"separation", 10)
	offers_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(offers_box)
	message = UiScreen.label("", 18, Color(1.0, 0.55, 0.45))
	message.name = "Message"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lcol.add_child(message)
	if stats == null:
		stats = get_node_or_null(^"/root/PlayerStats")
	owned_row = HBoxContainer.new()
	owned_row.name = "OwnedRow"
	owned_row.add_theme_constant_override(&"separation", 8)
	owned_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owned_label = UiScreen.label("Owned", 16, Color(0.85, 0.8, 0.72))
	owned_label.name = "OwnedLabel"
	owned_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	owned_row.add_child(owned_label)
	owned_strip = load(OWNED_STRIP_PATH).new()
	owned_strip.name = "OwnedItems"
	owned_strip.skin = skin
	owned_strip.stats = stats
	owned_strip.make_compact(11, 1)
	owned_strip.popover_bounds = left   # the overflow list stays inside OffersPanel   # one row of 11 (+N): fits OffersPanel's 460 px under 4 cards
	owned_strip.overflow_focus_lost.connect(_on_overflow_focus_lost)   # own child's signal: nothing to disconnect
	owned_row.add_child(owned_strip)
	lcol.add_child(owned_row)

	# RIGHT column: stage clear title, gold, Continue.
	var right := PanelContainer.new()
	right.name = "InfoPanel"
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 0.0
	right.offset_left = -32 - 380
	right.offset_right = -32
	right.offset_top = 72
	right.offset_bottom = 72 + 260
	right.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(right)
	var rcol := VBoxContainer.new()
	rcol.alignment = BoxContainer.ALIGNMENT_CENTER
	rcol.add_theme_constant_override(&"separation", 14)
	right.add_child(rcol)
	title = UiScreen.label("Stage clear!", 40, skin.slot_selected)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rcol.add_child(title)
	var gold_row := HBoxContainer.new()
	gold_row.name = "StatsRow"
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override(&"separation", 6)
	hearts_box = HBoxContainer.new()
	hearts_box.name = "Hearts"
	hearts_box.add_theme_constant_override(&"separation", 2)
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_row.add_child(hearts_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gold_row.add_child(gap)
	gold_row.add_child(UiScreen.coin_icon(skin.coin_slot, 28))
	gold_label = UiScreen.label("", 26, skin.gold_color)
	gold_label.name = "Gold"
	gold_row.add_child(gold_label)
	rcol.add_child(gold_row)
	continue_button = UiScreen.button("Continue")
	continue_button.name = "Continue"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.pressed.connect(_on_continue)
	rcol.add_child(continue_button)


func _connect_bus(_b: Node) -> void:
	_wire(true)
	_refresh()


func _enter_tree() -> void:
	if is_node_ready():
		_wire(true)   # re-entering: reconnect + catch up
		_refresh()


func _exit_tree() -> void:
	super._exit_tree()
	_wire(false)


## Methods only (no lambdas); connected while in the tree.
func _wire(on: bool) -> void:
	var pairs := []
	if bus and is_instance_valid(bus):
		pairs.append([bus, &"stage_cleared", _on_stage_cleared])
		pairs.append([bus, &"gold_changed", _on_gold_changed])
		pairs.append([bus, &"health_changed", _on_health_changed])
	if stats and is_instance_valid(stats):
		pairs.append([stats, &"items_changed", _on_items_changed])
	for p in pairs:
		var o: Object = p[0]
		if not o.has_signal(p[1]):
			continue
		var connected := o.is_connected(p[1], p[2])
		if on and not connected:
			o.connect(p[1], p[2])
		elif not on and connected:
			o.disconnect(p[1], p[2])


func _on_stage_cleared(_stage: int) -> void:
	open_shop()


func _on_gold_changed(_amount: int, _delta: int) -> void:
	_refresh()


func _on_health_changed(_current: int, _max_hp: int) -> void:
	_refresh()


func _on_items_changed(_items: Array) -> void:
	_refresh()


## Merchant feet at backdrop (merchant_x, counter_y), scaled like the cover backdrop.
func _layout_merchant() -> void:
	var sz := merchant_anchor.size
	if sz.x <= 0 or sz.y <= 0:
		return
	var s := maxf(sz.x / BACKDROP_SIZE.x, sz.y / BACKDROP_SIZE.y)   # KEEP_ASPECT_COVERED
	var origin := (sz - BACKDROP_SIZE * s) * 0.5
	merchant.position = origin + Vector2(skin.merchant_x, skin.counter_y) * s
	merchant.scale = Vector2.ONE * s


## Screen-space x band the merchant occupies (for layout tests / tuning).
func merchant_band() -> Vector2:
	var s := merchant.scale.x
	return Vector2(merchant.position.x - 32 * s, merchant.position.x + 32 * s)


## Shows the stock BE's Shop returns (all of it, clamped to 1..MAX_CARDS);
## `count` > 0 asks for at most that many. The demo stub gets the same cap.
func open_shop(count: int = -1) -> void:
	var n := clampi(count if count > 0 else skin.shop_offer_count, 1, MAX_CARDS)
	if owned_strip:
		owned_strip.close_overflow()
		owned_strip.reset_input_state()
	offers = bus.get_shop_offer(n) if bus and bus.has_method(&"get_shop_offer") else ([] as Array[Dictionary])
	_tile_text = unique_initials(_catalogue_names(offers))
	sold.clear()
	for c in offers_box.get_children():
		offers_box.remove_child(c)
		c.queue_free()
	cards.clear()
	for i in offers.size():
		sold.append(false)
		var card := _make_card(i, offers[i])
		offers_box.add_child(card)
		cards.append(card)
	var st: int = bus.get_stage() if bus and bus.has_method(&"get_stage") else 1
	title.text = "Stage %d clear!" % st
	message.text = "The merchant has nothing for you tonight." if offers.is_empty() else ""
	if not is_open():
		open()
	_layout_merchant.call_deferred()
	if merchant is AnimatedSprite2D:
		(merchant as AnimatedSprite2D).play(skin.merchant_slot)
	_refresh()
	continue_button.grab_focus.call_deferred()


func _make_card(i: int, o: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Offer%d" % i
	card.custom_minimum_size = Vector2(0, 84)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	card.add_child(row)
	row.add_child(_icon_for(o))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rarity := str(o.get("rarity", "common"))
	var nm := UiScreen.label(str(o.get("display_name", "?")), 20, skin.rarity_colors.get(rarity, Color.WHITE))
	nm.name = "Name"
	info.add_child(nm)
	var full := str(o.get("description", ""))
	var desc := UiScreen.label(full, 15, Color(0.78, 0.75, 0.7))
	desc.name = "Desc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 0)
	desc.max_lines_visible = DESC_LINES   # long text ends in "…"; full text in the tooltip
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.tooltip_text = "%s\n%s" % [str(o.get("display_name", "")), full] if not full.is_empty() else ""
	info.add_child(desc)
	row.add_child(info)
	var buy := UiScreen.button("%d g" % int(o.get("price", 0)), 18)
	buy.name = "Buy"
	buy.custom_minimum_size = Vector2(96, 40)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(buy_index.bind(i))
	row.add_child(buy)
	return card


## 32x32 icon by icon_slot via the manifest (×2), else a letter tile.
func _icon_for(o: Dictionary) -> Control:
	var tex := UiArt.first_frame(str(o.get("icon_slot", "")))
	if tex:
		var tr := TextureRect.new()
		tr.name = "Icon"
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(64, 64)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	# Fallback letter tile: square, two-letter initials, rim in the rarity colour.
	var p := Panel.new()
	p.name = "Icon"
	p.theme_type_variation = &"HudSlot"
	p.custom_minimum_size = Vector2(64, 64)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim := skin.rarity_colors.get(str(o.get("rarity", "common")), skin.rarity_colors.get("common", Color.WHITE)) as Color
	p.add_theme_stylebox_override(&"panel", _tile_style(rim))
	var nm := str(o.get("display_name", "?"))
	var l := UiScreen.label(str(_tile_text.get(nm, initials(nm))), 26, rim)
	l.name = "Initials"
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Letter-tile text per display name (set in open_shop).
var _tile_text: Dictionary = {}


## Two-letter initials: first letters of the first two words ("Big Pockets" → "BP",
## "Grandfather's Watch" → "GW"); one word → its first two letters ("Minimap" → "MI").
static func initials(display_name: String) -> String:
	var words: PackedStringArray = []
	for w in display_name.strip_edges().split(" ", false):
		var letters := ""
		for ch in w:
			if ch.to_upper() != ch.to_lower() or ch.is_valid_int():
				letters += ch
		if not letters.is_empty():
			words.append(letters)
	if words.is_empty():
		return "?"
	if words.size() == 1:
		return words[0].left(2).to_upper()
	return (words[0].left(1) + words[1].left(1)).to_upper()


## initials() for each name, made unique within `names`: names are taken in sorted
## order (so a tile never depends on which items rolled) and a clash keeps the first
## letter and tries the following letters of the last word, then of the whole name
## ("Soft Shoes" → "SS", "Spring Socks" → "SO").
static func unique_initials(names: PackedStringArray) -> Dictionary:
	var sorted := names.duplicate()
	sorted.sort()
	var out := {}
	var used := {}
	for nm in sorted:
		if out.has(nm):
			continue
		var t := initials(nm)
		if used.has(t):
			var words := nm.strip_edges().split(" ", false)
			var pool := (words[-1].substr(1) + nm.replace(" ", "").substr(1)).to_upper()
			for ch in pool:
				var cand := t.left(1) + ch
				if ch.to_upper() != ch.to_lower() and not used.has(cand):
					t = cand
					break
		used[t] = true
		out[nm] = t
	return out


## All item names BE's ItemDb knows (so tiles are stable across visits), plus the
## offers' own names; just the offers when ItemDb isn't there.
func _catalogue_names(list: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "ItemDb":
			var db = load(str(c.get("path", "")))
			if db is Script and "ITEMS" in db:
				for r in db.ITEMS:
					out.append(str(r.get("name", "")))
			break
	for o in list:
		var nm := str(o.get("display_name", ""))
		if not out.has(nm):
			out.append(nm)
	return out


func _tile_style(rim: Color) -> StyleBox:
	var theme := load("res://assets/ui/hud_theme.tres") as Theme
	var base: StyleBox = theme.get_stylebox(&"panel", &"HudSlot") if theme and theme.has_stylebox(&"panel", &"HudSlot") else null
	var sb := (base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()) as StyleBoxFlat
	sb.border_color = rim
	if not base is StyleBoxFlat:
		sb.bg_color = Color(0.07, 0.05, 0.09, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
	return sb


## Returns true when bought. Sold-out / unaffordable → false + feedback, no gold change.
func buy_index(i: int) -> bool:
	if i < 0 or i >= offers.size():
		return false
	if sold[i]:
		message.text = "Sold out."
		return false
	var o := offers[i]
	var ok: bool = bus.buy_offer(o) if bus and bus.has_method(&"buy_offer") else false
	if ok:
		sold[i] = true
		message.text = "Bought %s." % str(o.get("display_name", ""))
		_sparkle(cards[i])
	else:
		message.text = "Not enough gold for %s." % str(o.get("display_name", ""))
		var t := create_tween()
		t.tween_property(cards[i], "modulate", Color(1, 0.4, 0.4), 0.08)
		t.tween_property(cards[i], "modulate", Color.WHITE, 0.2)
	_refresh()
	return ok


func is_sold(i: int) -> bool:
	return i >= 0 and i < sold.size() and sold[i]


func _refresh() -> void:
	if gold_label == null or not is_inside_tree():
		return
	_refresh_hearts()
	if owned_label:
		var owned: Array = stats.get("owned_items") if stats and is_instance_valid(stats) and "owned_items" in stats else []
		owned_label.text = "Owned" if not owned.is_empty() else "Owned: nothing yet"
	var g: int = int(bus.gold) if bus and "gold" in bus else 0
	gold_label.text = " %d gold" % g
	for i in cards.size():
		var card := cards[i]
		if not is_instance_valid(card):
			continue
		var buy := card.find_child("Buy", true, false) as Button
		if buy == null:
			continue
		if sold[i]:
			buy.text = "SOLD"
			buy.disabled = true
			card.modulate = Color(1, 1, 1, 0.5)
		else:
			buy.disabled = false
			var price := int(offers[i].get("price", 0))
			buy.add_theme_color_override(&"font_color", Color.WHITE if price <= g else Color(1, 0.45, 0.4))


## Hearts next to the gold: one per max heart, filled = current (bus.health / max_health).
func _refresh_hearts() -> void:
	if hearts_box == null:
		return
	var cur: int = int(bus.health) if bus and "health" in bus else 0
	var mx: int = int(bus.max_health) if bus and "max_health" in bus else cur
	mx = clampi(mx, 0, 12)
	while hearts.size() < mx:
		var h := HudIcon.new()
		h.kind = HudIcon.Kind.HEART
		h.slot = "ui_heart_full"
		h.skin = skin
		hearts_box.add_child(h)
		hearts.append(h)
	while hearts.size() > mx:
		var h: HudIcon = hearts.pop_back()
		hearts_box.remove_child(h)
		h.queue_free()
	for i in hearts.size():
		hearts[i].filled = i < cur


func filled_hearts() -> int:
	return hearts.filter(func(h): return h.filled).size()


func _sparkle(card: Control) -> void:
	var sf := UiArt.frames(skin.sparkle_slot)
	if sf == null:
		return
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(2, 2)
	spr.position = Vector2(40, card.size.y * 0.5)
	card.add_child(spr)
	spr.animation_finished.connect(spr.queue_free)
	spr.play(skin.sparkle_slot)


## The "+N" tile that had focus is gone (nothing is hidden any more): Continue takes it.
func _on_overflow_focus_lost() -> void:
	if continue_button and continue_button.is_visible_in_tree():
		continue_button.grab_focus()


func _on_continue() -> void:
	if owned_strip:
		owned_strip.close_overflow()
		owned_strip.reset_input_state()
	close()
	if bus and bus.has_method(&"next_stage"):
		bus.next_stage()


## Drawn silhouette (top hat + coat + lantern) when merchant_idle isn't in the manifest.
class _MerchantStandIn extends Node2D:
	func _draw() -> void:
		var c := Color(0.12, 0.09, 0.14)
		draw_rect(Rect2(-14, -44, 28, 44), c)              # coat
		draw_circle(Vector2(0, -50), 8, Color(0.85, 0.82, 0.76))  # porcelain mask
		draw_rect(Rect2(-9, -68, 18, 12), c)               # top hat
		draw_rect(Rect2(-13, -57, 26, 3), c)
		draw_circle(Vector2(18, -26), 4, Color(1.0, 0.75, 0.3))   # lantern

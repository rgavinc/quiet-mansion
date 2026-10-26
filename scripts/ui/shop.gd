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

const BACKDROP_SIZE := Vector2(320, 180)

var title: Label
var gold_label: Label
var message: Label
var offers_box: VBoxContainer
var continue_button: Button
var merchant: Node2D
var merchant_anchor: Control
var has_backdrop := false

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
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
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


func _connect_bus(b: Node) -> void:
	if b.has_signal(&"stage_cleared"):
		b.stage_cleared.connect(func(_s): open_shop())
	if b.has_signal(&"gold_changed"):
		b.gold_changed.connect(func(_g, _d): _refresh())


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


func open_shop(count: int = -1) -> void:
	var n := count if count > 0 else skin.shop_offer_count
	offers = bus.get_shop_offer(n) if bus and bus.has_method(&"get_shop_offer") else ([] as Array[Dictionary])
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
	var desc := UiScreen.label(str(o.get("description", "")), 15, Color(0.78, 0.75, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 0)
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
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var p := Panel.new()
	p.name = "Icon"
	p.theme_type_variation = &"HudSlot"
	p.custom_minimum_size = Vector2(64, 64)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiScreen.label(str(o.get("display_name", "?")).left(1).to_upper(), 30)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


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
	if gold_label == null:
		return
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


func _on_continue() -> void:
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

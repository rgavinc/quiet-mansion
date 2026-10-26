class_name UiScreen
extends CanvasLayer
## Base for full-screen FE screens (game over, win, shop). While open it pauses the
## tree, runs with PROCESS_MODE_ALWAYS, and its root Control STOPs the mouse so
## clicks never reach the game. (The HUD stays mouse-ignore; screens are NOT
## under HudRoot, so hud.gd's ignore rules never touch them.)

signal opened
signal closed

const THEME_PATH := "res://assets/ui/hud_theme.tres"

## Injected in tests; defaults to /root/FESignals.
var bus: Node
var skin: HudSkin
var root: Control
var _open := false


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if bus == null:
		bus = UiArt.bus()
	if skin == null:
		skin = HudSkin.load_default()
	root = Control.new()
	root.name = "ScreenRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(THEME_PATH):
		root.theme = load(THEME_PATH)
	add_child(root)
	_build()
	root.visible = false
	visible = false
	if bus:
		_connect_bus(bus)


## Override: build widgets under `root`.
func _build() -> void:
	pass


## Override: hook bus signals.
func _connect_bus(_b: Node) -> void:
	pass


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	root.visible = true
	get_tree().paused = true
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	root.visible = false
	get_tree().paused = false
	closed.emit()


func _exit_tree() -> void:
	# Never leave the game frozen if a screen is freed while open.
	if _open and is_inside_tree():
		get_tree().paused = false


# --- small builders --------------------------------------------------------
static func label(text: String, size: int = 20, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override(&"font_color", color)
	return l


static func button(text: String, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override(&"font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


## Full-screen still by slot (cover, nearest), or null when the slot is missing.
static func backdrop(slot: String) -> TextureRect:
	var tex := UiArt.texture(slot)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.name = "Backdrop"
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Spinning coin icon (gold_coin slot) or a drawn gold disc fallback.
## Coin next to a gold number. Static face frame by default: `gold_coin` is a spin
## loop (face → edge-on → face) and at UI size the edge-on frames read as a thin
## sliver. `spin = true` plays the loop instead.
static func coin_icon(slot: String, px: float = 28.0, spin: bool = false) -> Control:
	var sf := UiArt.frames(slot)
	var holder := Control.new()
	holder.name = "Coin"
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sf and not spin:
		var tr := TextureRect.new()
		tr.name = "Face"
		tr.texture = sf.get_frame_texture(slot, 0)   # frame 0 = full face
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(tr)
	elif sf:
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.animation = slot
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var fs: Vector2 = sf.get_frame_texture(slot, 0).get_size()
		spr.scale = Vector2.ONE * (px / maxf(fs.y, 1.0))
		spr.position = Vector2(px, px) * 0.5
		holder.add_child(spr)
		spr.play(slot)
	else:
		holder.draw.connect(func():
			holder.draw_circle(Vector2(px, px) * 0.5, px * 0.42, Color(1.0, 0.8, 0.25))
			holder.draw_arc(Vector2(px, px) * 0.5, px * 0.42, 0, TAU, 24, Color(0.55, 0.38, 0.08), 2.0))
	return holder


## Shared game-over / win layout: first existing art slot in `slots` as the
## backdrop (+ a shade on its dark right half), else a dim screen + a themed
## PanelContainer. Either way the text column ("TextPanel" → "Column") sits on
## the RIGHT half. Returns {has_art, slot, column}.
static func right_half_layout(host: Control, slots: Array, dim: Color) -> Dictionary:
	var art: TextureRect = null
	var used := ""
	for sl in slots:
		art = backdrop(str(sl))
		if art:
			used = str(sl)
			break
	if art:
		host.add_child(art)
		var shade := ColorRect.new()
		shade.name = "Shade"
		shade.color = Color(0, 0, 0, 0.35)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.anchor_left = 0.5
		shade.anchor_right = 1.0
		shade.anchor_bottom = 1.0
		host.add_child(shade)
	else:
		var d := ColorRect.new()
		d.name = "Dim"
		d.color = dim
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(d)
	var panel: Control = MarginContainer.new() if art else PanelContainer.new()
	panel.name = "TextPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 48
	panel.offset_right = -48
	panel.offset_top = 96
	panel.offset_bottom = -96
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	return {has_art = art != null, slot = used, column = col}


## Centered "<coin> N gold" row. Returns [row, label].
static func gold_row(coin_slot: String, color: Color, size: int = 26) -> Array:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin_icon(coin_slot, 28))
	var l := label("", size, color)
	l.name = "Gold"
	row.add_child(l)
	return [row, l]

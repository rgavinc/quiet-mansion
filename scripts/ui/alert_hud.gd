extends MarginContainer
## Alert counter (top-right): "chasing N / M" for the stage, no cap. One pip per
## enemy up to skin.alert_max_pips (wraps to a second row past 8), numbers beyond.
## Data: FESignals.chasing_count() / enemy_total() (report_chase once BE sends it,
## else polls enemies' is_chasing()/enraged; registry = groups enemies ∪ puppets).
## TODO(BE-wire): event-driven once BE emits chase state; polled at 10 Hz for now.

var skin: HudSkin
var bus: Node

var label: Label
var pips: Control
var chasing := 0
var total := 0
var _accum := 0.0

const PIPS_PER_ROW := 8


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 40)   # below the AI watermark line
	var panel := PanelContainer.new()
	panel.name = "AlertPanel"
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	label = Label.new()
	label.name = "AlertLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(label)
	pips = Control.new()
	pips.name = "Pips"
	pips.custom_minimum_size = Vector2(PIPS_PER_ROW * 14, 12)
	pips.draw.connect(_draw_pips)
	col.add_child(pips)
	if bus and bus.has_signal(&"chase_changed"):
		bus.chase_changed.connect(func(_e, _c): refresh())
	refresh()


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= 0.1:
		_accum = 0.0
		refresh()


func refresh() -> void:
	if bus == null:
		return
	var c: int = bus.chasing_count() if bus.has_method(&"chasing_count") else 0
	var t: int = bus.enemy_total() if bus.has_method(&"enemy_total") else 0
	t = maxi(t, c)
	if c == chasing and t == total and label.text != "":
		return
	chasing = c
	total = t
	visible = total > 0
	label.text = "Chasing %d / %d" % [chasing, total]
	var heat := 0.0 if total == 0 else float(chasing) / float(total)
	label.add_theme_color_override(&"font_color", skin.alert_calm.lerp(skin.alert_hot, clampf(heat * 1.5, 0.0, 1.0)) if chasing > 0 else skin.alert_calm)
	var shown := mini(total, skin.alert_max_pips)
	var rows := maxi(1, ceili(float(shown) / PIPS_PER_ROW))
	pips.custom_minimum_size = Vector2(PIPS_PER_ROW * 14, rows * 14)
	pips.visible = total <= skin.alert_max_pips
	pips.queue_redraw()


func _draw_pips() -> void:
	var shown := mini(total, skin.alert_max_pips)
	var w := pips.size.x
	for i in shown:
		var row := i / PIPS_PER_ROW
		var colm := i % PIPS_PER_ROW
		var ctr := Vector2(w - 7 - colm * 14, 7 + row * 14)
		var hot := i < chasing
		pips.draw_circle(ctr, 5.0, skin.alert_hot if hot else Color(skin.alert_calm, 0.35))

extends MarginContainer
## Styled hearts + gold counter. Listens to FESignals.health_changed / gold_changed.
## Styling: assets/ui/hud_theme.tres (panel/label) + assets/ui/hud_skin.tres (colours/sizes).
## Art slots (optional, placeholder drawn if absent): ui_heart_full, ui_heart_empty, ui_gold.

var skin: HudSkin
var bus: Node

var _hearts_box: HBoxContainer
var _hearts: Array[HudIcon] = []
var _coin: HudIcon
var _gold_label: Label
var _last_health: int = -1


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if theme == null and ResourceLoader.exists("res://assets/ui/hud_theme.tres"):
		theme = load("res://assets/ui/hud_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_top", 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(row)
	var hp_panel := PanelContainer.new()
	hp_panel.name = "HealthPanel"
	row.add_child(hp_panel)
	_hearts_box = HBoxContainer.new()
	_hearts_box.add_theme_constant_override("separation", 4)
	hp_panel.add_child(_hearts_box)
	var gold_panel := PanelContainer.new()
	gold_panel.name = "GoldPanel"
	row.add_child(gold_panel)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	gold_panel.add_child(gold_row)
	_coin = HudIcon.new()
	_coin.kind = HudIcon.Kind.COIN
	_coin.slot = "ui_gold"
	_coin.skin = skin
	gold_row.add_child(_coin)
	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.text = "0"
	_gold_label.custom_minimum_size = Vector2(36, 0)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_row.add_child(_gold_label)

	if bus == null:
		bus = UiArt.bus()
	if bus:
		bus.health_changed.connect(_on_health)
		bus.gold_changed.connect(_on_gold)
		_on_health(bus.health, bus.max_health)
		_gold_label.text = str(bus.gold)
	else:
		_on_health(3, 3)


func heart_count() -> int:
	return _hearts.size()


func filled_hearts() -> int:
	var n := 0
	for h in _hearts:
		if h.filled:
			n += 1
	return n


func gold_text() -> String:
	return _gold_label.text if _gold_label else ""


func _on_health(current: int, max_hp: int) -> void:
	max_hp = maxi(max_hp, 0)
	while _hearts.size() < max_hp:
		var h := HudIcon.new()
		h.kind = HudIcon.Kind.HEART
		h.slot = "ui_heart_full"
		h.skin = skin
		_hearts_box.add_child(h)
		_hearts.append(h)
	while _hearts.size() > max_hp:
		var h: HudIcon = _hearts.pop_back()
		h.queue_free()
	for i in _hearts.size():
		var was := _hearts[i].filled
		_hearts[i].filled = i < current
		if _last_health >= 0 and was != _hearts[i].filled and is_inside_tree():
			_hearts[i].do_pop()
	_last_health = current


func _on_gold(amount: int, delta: int) -> void:
	_gold_label.text = str(amount)
	if delta != 0 and is_inside_tree():
		_coin.do_pop()
		var flash := skin.gold_color if delta > 0 else skin.heart_full
		_gold_label.modulate = flash.lightened(0.3)
		var tw := create_tween()
		tw.tween_property(_gold_label, "modulate", Color.WHITE, skin.pop_time * 2.0)

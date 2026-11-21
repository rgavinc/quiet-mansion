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
var _gold_target: int = 0
var _gold_shown: float = 0.0
var _gold_rate: float = 0.0
var _pulse_t: float = 0.0
var _shatter_bits: Array = []


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
		_gold_target = int(bus.gold)
		_gold_shown = float(_gold_target)
		_gold_label.text = str(_gold_target)
	else:
		_on_health(3, 3)
		_gold_target = 0
		_gold_shown = 0.0


func heart_count() -> int:
	return _hearts.size()


func filled_hearts() -> int:
	var n := 0
	for h in _hearts:
		if h.filled:
			n += 1
	return n


func gold_text() -> String:
	# Committed total (tests / readback). The visible label may still be counting up.
	return str(_gold_target)


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
		if _last_health >= 0 and was and not _hearts[i].filled and is_inside_tree():
			_shatter_heart(_hearts[i])
			_hearts[i].do_pop()
		elif _last_health >= 0 and was != _hearts[i].filled and is_inside_tree():
			_hearts[i].do_pop()
	_last_health = current


func _on_gold(amount: int, delta: int) -> void:
	_gold_target = amount
	if delta > 0 and is_inside_tree() and skin.gold_count_time > 0.0:
		# Visible label counts up at a constant rate; gold_text() is the committed total.
		_gold_rate = absf(float(amount) - _gold_shown) / maxf(skin.gold_count_time, 0.05)
		if _coin:
			_coin.do_pop()
		_gold_label.modulate = skin.gold_color.lightened(0.3)
		var tw := create_tween()
		tw.tween_property(_gold_label, "modulate", Color.WHITE, skin.pop_time * 2.0)
	else:
		_gold_shown = float(amount)
		_gold_rate = 0.0
		if _gold_label:
			_gold_label.text = str(amount)
		if delta != 0 and is_inside_tree():
			if _coin:
				_coin.do_pop()
			var flash := skin.gold_color if delta > 0 else skin.heart_full
			_gold_label.modulate = flash.lightened(0.3)
			var tw := create_tween()
			tw.tween_property(_gold_label, "modulate", Color.WHITE, skin.pop_time * 2.0)


func _process(delta: float) -> void:
	if _gold_label and absf(_gold_shown - float(_gold_target)) > 0.001:
		var rate := _gold_rate if _gold_rate > 0.0 else absf(float(_gold_target) - _gold_shown) / maxf(skin.gold_count_time, 0.05)
		_gold_shown = move_toward(_gold_shown, float(_gold_target), rate * delta)
		if absf(_gold_shown - float(_gold_target)) <= 0.51:
			_gold_shown = float(_gold_target)
			_gold_rate = 0.0
		_gold_label.text = str(int(round(_gold_shown)))
	# Pulse the last remaining heart.
	var filled := filled_hearts()
	if filled == 1:
		_pulse_t += delta
		var h: HudIcon = null
		for ic in _hearts:
			if ic.filled:
				h = ic
				break
		if h:
			var w := 0.5 + 0.5 * sin(_pulse_t * TAU / maxf(skin.last_heart_period, 0.2))
			h.pop = 1.0 + skin.last_heart_pulse * w
	else:
		_pulse_t = 0.0
		for ic in _hearts:
			if is_equal_approx(ic.pop, 1.0) == false and ic.get("pop") != null:
				# Don't fight an in-flight do_pop tween hard; only reset idle extras.
				if ic.pop < 1.02:
					ic.pop = 1.0
	# Reap shatter bits.
	for i in range(_shatter_bits.size() - 1, -1, -1):
		var b = _shatter_bits[i]
		if not is_instance_valid(b):
			_shatter_bits.remove_at(i)


func _shatter_heart(h: HudIcon) -> void:
	if h == null or not is_inside_tree():
		return
	var origin := h.global_position + h.size * 0.5
	for i in 6:
		var bit := ColorRect.new()
		bit.size = Vector2(5, 5)
		bit.color = skin.heart_full
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bit.z_index = 8
		var host := get_parent() if get_parent() is Control else self
		host.add_child(bit)
		bit.global_position = origin + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		_shatter_bits.append(bit)
		var tw := bit.create_tween()
		var dest := bit.position + Vector2(randf_range(-22, 22), randf_range(-28, 8))
		tw.tween_property(bit, "position", dest, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(bit, "modulate:a", 0.0, 0.28)
		tw.tween_callback(bit.queue_free)

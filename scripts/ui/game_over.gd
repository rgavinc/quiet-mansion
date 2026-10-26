extends UiScreen
## Game-over screen. Opens on FESignals.player_died (REAL: PlayerStats.died),
## pauses the tree, shows stage reached, gold and the run seed (hidden when the
## level has no seed), with Retry (same seed) and New run.
## Art: `game_over_art` slot (PR #14: boy caught, right half kept dark for text);
## missing → dim + themed panel. Text/buttons always sit on the RIGHT half.

var title: Label
var stage_label: Label
var gold_label: Label
var seed_label: Label
var retry_button: Button
var new_run_button: Button
var has_art := false

var _stage := 1
var _gold := 0
var _seed := -1


func _build() -> void:
	var art := UiScreen.backdrop(skin.game_over_slot)
	has_art = art != null
	if has_art:
		root.add_child(art)
		# Keep the dark right half readable even if the art is brighter than expected.
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.35)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.anchor_left = 0.5
		shade.anchor_right = 1.0
		shade.anchor_bottom = 1.0
		root.add_child(shade)
	else:
		var dim := ColorRect.new()
		dim.name = "Dim"
		dim.color = skin.screen_dim
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(dim)

	# Right half column.
	var col_host: Control
	if has_art:
		col_host = MarginContainer.new()
	else:
		col_host = PanelContainer.new()   # themed panel fallback
	col_host.name = "TextPanel"
	col_host.anchor_left = 0.5
	col_host.anchor_right = 1.0
	col_host.anchor_top = 0.0
	col_host.anchor_bottom = 1.0
	col_host.offset_left = 48
	col_host.offset_right = -48
	col_host.offset_top = 96
	col_host.offset_bottom = -96
	col_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col_host)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_host.add_child(col)

	title = UiScreen.label("GAME OVER", 56, skin.title_color)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	stage_label = UiScreen.label("", 26)
	stage_label.name = "Stage"
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stage_label)

	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_row.add_child(UiScreen.coin_icon(skin.coin_slot, 28))
	gold_label = UiScreen.label("", 26, skin.gold_color)
	gold_label.name = "Gold"
	gold_row.add_child(gold_label)
	col.add_child(gold_row)

	seed_label = UiScreen.label("", 18, Color(0.7, 0.68, 0.64))
	seed_label.name = "Seed"
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(seed_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 18)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retry_button = UiScreen.button("Retry")
	retry_button.name = "Retry"
	retry_button.pressed.connect(_on_retry)
	new_run_button = UiScreen.button("New run")
	new_run_button.name = "NewRun"
	new_run_button.pressed.connect(_on_new_run)
	buttons.add_child(retry_button)
	buttons.add_child(new_run_button)
	col.add_child(buttons)


func _connect_bus(b: Node) -> void:
	if b.has_signal(&"player_died"):
		b.player_died.connect(show_for_run)


## Snapshot the run and open. Safe to call more than once.
func show_for_run() -> void:
	_stage = int(bus.get_stage()) if bus and bus.has_method(&"get_stage") else 1
	_seed = int(bus.get_seed()) if bus and bus.has_method(&"get_seed") else -1
	_gold = int(bus.gold) if bus and "gold" in bus else 0
	stage_label.text = "Reached stage %d" % _stage
	gold_label.text = " %d gold" % _gold
	seed_label.visible = _seed >= 0
	seed_label.text = "Seed %d" % _seed
	retry_button.tooltip_text = "Same seed" if _seed >= 0 else "Same level"
	if not is_open():
		open()
	retry_button.grab_focus.call_deferred()


func _on_retry() -> void:
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(_seed, 1)


func _on_new_run() -> void:
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(-1, 1)

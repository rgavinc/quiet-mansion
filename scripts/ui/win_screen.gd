extends UiScreen
## Win screen (docs/PRODUCT.md "Run end"): clearing stage FESignals.MAX_STAGES' exit
## shows this INSTEAD of the shop. Opens on FESignals.run_won (REAL:
## GameState.reached_exit on the last stage), pauses the tree, captures the mouse.
## Shows the run seed, gold, stages cleared and run time, with one primary New run
## (same as game over: PlayerStats.reset(), stage 1, level_seed -1).
## Art: `win_screen_art` slot (Designer; dark right half for text), else the
## `game_over_art` styling, else dim + themed panel. Text always on the RIGHT half.

var title: Label
var stage_label: Label
var gold_label: Label
var seed_label: Label
var time_label: Label
var new_run_button: Button
var has_art := false
## Which slot the backdrop came from ("" = themed panel).
var art_slot := ""

var _seed := -1
var _gold := 0


func _build() -> void:
	var lay := UiScreen.right_half_layout(root, [skin.win_slot, skin.game_over_slot], skin.screen_dim)
	has_art = lay.has_art
	art_slot = lay.slot
	var col: VBoxContainer = lay.column

	title = UiScreen.label("YOU ESCAPED", 56, skin.win_title_color)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	stage_label = UiScreen.label("", 26)
	stage_label.name = "Stage"
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stage_label)

	var gr := UiScreen.gold_row(skin.coin_slot, skin.gold_color)
	gold_label = gr[1]
	col.add_child(gr[0])

	time_label = UiScreen.label("", 20, Color(0.8, 0.78, 0.72))
	time_label.name = "Time"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(time_label)

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
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_run_button = UiScreen.button("New run")
	new_run_button.name = "NewRun"
	new_run_button.tooltip_text = "Stage 1, fresh stats, new seed"
	new_run_button.pressed.connect(_on_new_run)
	buttons.add_child(new_run_button)
	col.add_child(buttons)


func _connect_bus(b: Node) -> void:
	if b.has_signal(&"run_won"):
		b.run_won.connect(func(_s): show_for_run())


## Snapshot the run and open. Safe to call more than once.
func show_for_run() -> void:
	# End-of-run latch: never open while the other end screen owns the run.
	if bus and bus.has_method(&"claim_run_end") and not bus.claim_run_end(&"won"):
		return
	var stages := int(bus.get_stage()) if bus and bus.has_method(&"get_stage") else 1
	_seed = int(bus.get_run_seed()) if bus and bus.has_method(&"get_run_seed") else -1
	_gold = int(bus.gold) if bus and "gold" in bus else 0
	var secs := int(bus.run_time) if bus and "run_time" in bus else 0
	stage_label.text = "All %d stages cleared" % stages
	gold_label.text = " %d gold" % _gold
	time_label.text = "Time %d:%02d" % [secs / 60, secs % 60]
	seed_label.visible = _seed >= 0
	seed_label.text = "Run seed %d" % _seed
	if not is_open():
		open()
	new_run_button.grab_focus.call_deferred()


## New run: same as game over — fresh stats, stage 1, new seed.
func _on_new_run() -> void:
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(-1, 1)

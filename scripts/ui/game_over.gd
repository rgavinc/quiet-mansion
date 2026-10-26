extends UiScreen
## Game-over screen. Opens on FESignals.player_died (REAL: PlayerStats.died),
## pauses the tree, shows stage reached, gold and the RUN seed (hidden when the
## level has no seed). No continues (Product Director): dying ends the run.
##   New run (primary)      → fresh stats, stage 1, new seed.
##   Retry seed (secondary) → fresh stats, stage 1, the same RUN seed (never the
##                            stage you died on). Disabled when there is no seed.
## Art: `game_over_art` slot (PR #14: boy caught, right half kept dark for text);
## missing → dim + themed panel. Text/buttons always sit on the RIGHT half.

var title: Label
var stage_label: Label
var gold_label: Label
var seed_label: Label
var new_run_button: Button   # primary
var retry_button: Button     # secondary: "Retry seed"
var has_art := false

var _stage := 1
var _gold := 0
var _seed := -1


func _build() -> void:
	var lay := UiScreen.right_half_layout(root, [skin.game_over_slot], skin.screen_dim)
	has_art = lay.has_art
	var col: VBoxContainer = lay.column

	title = UiScreen.label("GAME OVER", 56, skin.title_color)
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
	new_run_button = UiScreen.button("New run")
	new_run_button.name = "NewRun"
	new_run_button.tooltip_text = "Stage 1, fresh stats, new seed"
	new_run_button.pressed.connect(_on_new_run)
	retry_button = UiScreen.button("Retry seed")
	retry_button.name = "RetrySeed"
	retry_button.flat = true   # secondary
	retry_button.pressed.connect(_on_retry)
	buttons.add_child(new_run_button)
	buttons.add_child(retry_button)
	col.add_child(buttons)


func _connect_bus(b: Node) -> void:
	if b.has_signal(&"player_died"):
		b.player_died.connect(show_for_run)


## Snapshot the run and open. Safe to call more than once.
func show_for_run() -> void:
	_stage = int(bus.get_stage()) if bus and bus.has_method(&"get_stage") else 1
	# The RUN seed (stage-1 seed), not a per-stage seed.
	_seed = int(bus.get_run_seed()) if bus and bus.has_method(&"get_run_seed") else -1
	_gold = int(bus.gold) if bus and "gold" in bus else 0
	stage_label.text = "Reached stage %d" % _stage
	gold_label.text = " %d gold" % _gold
	seed_label.visible = _seed >= 0
	seed_label.text = "Run seed %d" % _seed
	retry_button.disabled = _seed < 0
	retry_button.tooltip_text = ("Stage 1, fresh stats, seed %d" % _seed) if _seed >= 0 else "This level has no seed"
	if not is_open():
		open()
	new_run_button.grab_focus.call_deferred()


## Retry seed: same RUN seed, always from stage 1, fresh stats.
func _on_retry() -> void:
	if _seed < 0:
		return
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(_seed, 1)


## New run: new seed (-1 → the level rolls one), stage 1, fresh stats.
func _on_new_run() -> void:
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(-1, 1)

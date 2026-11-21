extends CanvasLayer
## Esc / ui_cancel pause: dims the game, shows the run seed, Resume and New run.
## Frees the mouse. Keyboard / pad: ui_accept on the focused button, ui_cancel resumes.
## Does not open over shop / game over / win. PROCESS_MODE_ALWAYS.

signal opened
signal closed

var skin: HudSkin
var bus: Node
var root: Control
var dim: ColorRect
var panel: PanelContainer
var seed_label: Label
var resume_button: Button
var new_run_button: Button
var _open := false
var _prev_mouse: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	layer = 24
	name = "PauseScreen"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if root == null:
		_build()
	_set_open(false)


func _exit_tree() -> void:
	if _open and is_inside_tree():
		get_tree().paused = false
		Input.mouse_mode = _prev_mouse
	_open = false


func _build() -> void:
	root = Control.new()
	root.name = "PauseRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(UiScreen.THEME_PATH):
		root.theme = load(UiScreen.THEME_PATH)
	add_child(root)
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.name = "PausePanel"
	panel.custom_minimum_size = Vector2(360, 220)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	panel.add_child(col)
	var title := UiScreen.label("Paused", 32, Color(0.95, 0.9, 0.82))
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	seed_label = UiScreen.label("", 16, Color(0.75, 0.72, 0.68))
	seed_label.name = "SeedLabel"
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(seed_label)
	resume_button = UiScreen.button("Resume")
	resume_button.name = "Resume"
	resume_button.pressed.connect(_on_resume)
	col.add_child(resume_button)
	new_run_button = UiScreen.button("New run")
	new_run_button.name = "NewRun"
	new_run_button.pressed.connect(_on_new_run)
	col.add_child(new_run_button)
	# Buttons must keep STOP so they stay clickable (HUD ignore-hook does not apply here).
	resume_button.mouse_filter = Control.MOUSE_FILTER_STOP
	new_run_button.mouse_filter = Control.MOUSE_FILTER_STOP


func is_open() -> bool:
	return _open


func _end_screen_up() -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n is UiScreen and n != self and n.has_method(&"is_open") and n.is_open():
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not event.is_action(&"ui_cancel"):
		return
	if _end_screen_up():
		return
	if _open:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if _open or _end_screen_up():
		return
	_set_open(true)
	_refresh_seed()
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_inside_tree():
		get_tree().paused = true
	if resume_button:
		resume_button.grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_set_open(false)
	Input.mouse_mode = _prev_mouse
	if is_inside_tree():
		get_tree().paused = false
	closed.emit()


func _set_open(v: bool) -> void:
	_open = v
	visible = v
	if root:
		root.visible = v


func _refresh_seed() -> void:
	var seed_n := -1
	var stage := 1
	if bus:
		if bus.has_method(&"get_run_seed"):
			seed_n = int(bus.get_run_seed())
		if bus.has_method(&"get_stage"):
			stage = int(bus.get_stage())
	if seed_n >= 0:
		seed_label.text = "seed %d  ·  stage %d" % [seed_n, stage]
	else:
		seed_label.text = "stage %d" % stage


func _on_resume() -> void:
	close()


func _on_new_run() -> void:
	close()
	if bus and bus.has_method(&"restart_run"):
		bus.restart_run(-1, 1)

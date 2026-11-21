extends CanvasLayer
## Fade-to-black between stages (fade-in on stage_started) and when shop / game over / win open.
## Does not delay the scene swap (corners: no await in FESignals._swap_scene).
## PROCESS_MODE_ALWAYS so it still runs while a UiScreen has paused the tree.

var skin: HudSkin
var bus: Node
var fade: ColorRect
var _tween: Tween
var _screens: Array = []


func _init() -> void:
	layer = 28
	name = "ScreenTransition"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if fade == null:
		fade = ColorRect.new()
		fade.name = "Fade"
		fade.color = Color(0, 0, 0, 0)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(fade)
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)
	if is_inside_tree():
		_find_screens(get_tree().root)
		if not get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.connect(_on_node_added)
	# Cover the first frame of a new stage, then fade in.
	fade.color.a = 1.0
	fade_in()


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for sc in _screens:
		_unhook_screen(sc)
	_screens.clear()
	if _tween:
		_tween.kill()
		_tween = null
	if fade:
		fade.color.a = 0.0


func _on_stage(_n: int) -> void:
	# New stage just appeared: fade in from black.
	if fade:
		fade.color.a = 1.0
	fade_in()


func fade_in() -> void:
	_animate(0.0)


func fade_out() -> void:
	_animate(1.0)


func is_fading() -> bool:
	return fade != null and fade.color.a > 0.01


func _animate(target: float) -> void:
	if fade == null or skin == null:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(fade, "color:a", target, skin.fade_time).set_trans(Tween.TRANS_QUAD)


func _on_node_added(n: Node) -> void:
	if n is UiScreen:
		_hook_screen(n)


func _find_screens(n: Node) -> void:
	if n is UiScreen:
		_hook_screen(n)
	for c in n.get_children():
		_find_screens(c)


func _hook_screen(sc: UiScreen) -> void:
	if _screens.has(sc):
		return
	_screens.append(sc)
	if sc.has_signal(&"opened") and not sc.opened.is_connected(_on_screen_opened):
		sc.opened.connect(_on_screen_opened)
	if sc.has_signal(&"tree_exited") and not sc.tree_exited.is_connected(_on_screen_exited.bind(sc)):
		sc.tree_exited.connect(_on_screen_exited.bind(sc))


func _unhook_screen(sc: Object) -> void:
	if sc == null or not is_instance_valid(sc):
		return
	if sc.has_signal(&"opened") and sc.opened.is_connected(_on_screen_opened):
		sc.opened.disconnect(_on_screen_opened)


func _on_screen_exited(sc: UiScreen) -> void:
	_unhook_screen(sc)
	_screens.erase(sc)


func _on_screen_opened() -> void:
	# Brief black flash then clear so the screen's own dimmer takes over.
	if fade:
		fade.color.a = 0.7
	fade_in()

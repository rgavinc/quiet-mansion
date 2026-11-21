extends Control
## "Stage N" + mood subtitle (HudSkin.stage_moods) at level start: slides and fades in,
## holds, fades out. About 2 s, never blocks input. Plays once per HUD (deferred so
## main.gd has read --stage first) and again on FESignals.stage_started(n).

var skin: HudSkin
var bus: Node
var title: Label
var subtitle: Label
var panel: PanelContainer
var autoplay := true
var _tween: Tween
var _rest_y: float = 0.0


func _enter_tree() -> void:
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	if _tween:
		_tween.kill()
		_tween = null


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()   # centred, upper part of the screen
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_bottom = 0.6
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "BannerPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)
	title = Label.new()
	title.name = "StageTitle"
	title.add_theme_font_size_override(&"font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	subtitle = Label.new()
	subtitle.name = "StageMood"
	subtitle.add_theme_font_size_override(&"font_size", 22)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.85, 0.8, 0.72)
	col.add_child(subtitle)
	# Stay "visible" (alpha 0) so the containers keep their layout while idle.
	modulate.a = 0.0
	if autoplay:
		_autoplay.call_deferred()


func _autoplay() -> void:
	var n: int = bus.get_stage() if bus and bus.has_method(&"get_stage") else 1
	play(n)


func _on_stage(n: int) -> void:
	play(n)


func mood_for(n: int) -> String:
	if skin == null or skin.stage_moods.is_empty():
		return ""
	return skin.stage_moods[clampi(n - 1, 0, skin.stage_moods.size() - 1)]


func play(n: int) -> void:
	if skin == null:
		skin = HudSkin.load_default()
	title.text = "Stage %d" % n
	if subtitle:
		subtitle.text = mood_for(n)
		subtitle.visible = not subtitle.text.is_empty()
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	if panel:
		panel.position.y = -skin.intro_slide
	_tween = create_tween()
	var fade_in := skin.intro_fade_in if skin.intro_fade_in > 0.0 else 0.25
	var hold := skin.intro_hold if skin.intro_hold > 0.0 else skin.banner_hold
	var fade_out := skin.intro_fade_out if skin.intro_fade_out > 0.0 else skin.banner_fade
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, fade_in)
	if panel:
		_tween.tween_property(panel, "position:y", 0.0, fade_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)
	_tween.tween_interval(hold)
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, fade_out)
	if panel:
		_tween.tween_property(panel, "position:y", -skin.intro_slide * 0.5, fade_out).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.set_parallel(false)


func is_showing() -> bool:
	return modulate.a > 0.01

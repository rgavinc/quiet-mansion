extends Control
## "Stage N" title card at level start: fades in, holds skin.banner_hold, fades out.
## Plays once per HUD (i.e. per level load, deferred so PR #13's main.gd has read
## --stage first) and again on FESignals.stage_started(n).

var skin: HudSkin
var bus: Node
var title: Label
var autoplay := true
var _tween: Tween


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()   # centred, upper part of the screen
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_bottom = 0.6
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "BannerPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	title = Label.new()
	title.name = "StageTitle"
	title.add_theme_font_size_override(&"font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	# Stay "visible" (alpha 0) so the containers keep their layout while idle.
	modulate.a = 0.0
	if bus and bus.has_signal(&"stage_started"):
		bus.stage_started.connect(play)
	if autoplay:
		_autoplay.call_deferred()


func _autoplay() -> void:
	var n: int = bus.get_stage() if bus and bus.has_method(&"get_stage") else 1
	play(n)


func play(n: int) -> void:
	title.text = "Stage %d" % n
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_interval(skin.banner_hold)
	_tween.tween_property(self, "modulate:a", 0.0, skin.banner_fade)


func is_showing() -> bool:
	return modulate.a > 0.01

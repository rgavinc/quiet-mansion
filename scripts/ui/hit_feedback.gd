extends CanvasLayer
## Red vignette flash + camera shake when the boy loses a heart.
## Listens to FESignals.health_changed; finishes and hides itself.

var skin: HudSkin
var bus: Node
var flash: JuiceVignette
var last_health: int = -1
var _tween: Tween


func _init() -> void:
	layer = 16
	name = "HitFeedback"


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"health_changed") and not bus.health_changed.is_connected(_on_health):
		bus.health_changed.connect(_on_health)
	if flash == null:
		flash = JuiceVignette.new()
		flash.name = "HitVignette"
		add_child(flash)
		flash.set_tint(skin.hit_vignette)
		flash.set_inner(skin.hit_vignette_inner)
		flash.set_intensity(0.0)
	if bus and "health" in bus:
		last_health = int(bus.health)


func _exit_tree() -> void:
	if bus and bus.has_signal(&"health_changed") and bus.health_changed.is_connected(_on_health):
		bus.health_changed.disconnect(_on_health)
	if _tween:
		_tween.kill()
		_tween = null
	if flash:
		flash.set_intensity(0.0)


func _on_health(current: int, _max_hp: int) -> void:
	if last_health >= 0 and current < last_health:
		play()
	last_health = current


func play() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	_shake()
	if flash:
		flash.set_tint(skin.hit_vignette)
		flash.set_inner(skin.hit_vignette_inner)
		flash.set_intensity(1.0)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_flash, 1.0, 0.0, skin.hit_flash_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_flash(v: float) -> void:
	if flash:
		flash.set_intensity(v)


func is_flashing() -> bool:
	return flash != null and flash.intensity() > 0.01


func _shake() -> void:
	if not is_inside_tree():
		return
	var rig := CameraRig.active_rig(get_tree())
	if rig and rig.has_method(&"shake"):
		rig.shake(skin.hit_shake_amp, skin.hit_shake_time)

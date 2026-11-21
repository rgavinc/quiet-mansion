extends CanvasLayer
## Subtle dark vignette that tightens while any puppet is chasing (FESignals.chasing
## / chase_changed). Hides when the chase ends. Last-heart pulse lives on the HUD hearts.

var skin: HudSkin
var bus: Node
var vignette: JuiceVignette
var _goal := 0.0
var _cur := 0.0


func _init() -> void:
	layer = 14
	name = "ChaseAtmosphere"


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"chase_changed") and not bus.chase_changed.is_connected(_on_chase):
		bus.chase_changed.connect(_on_chase)
	if vignette == null:
		vignette = JuiceVignette.new()
		vignette.name = "ChaseVignette"
		add_child(vignette)
	vignette.set_tint(skin.chase_vignette)
	vignette.set_inner(skin.chase_vignette_inner)
	_sync_goal()


func _exit_tree() -> void:
	if bus and bus.has_signal(&"chase_changed") and bus.chase_changed.is_connected(_on_chase):
		bus.chase_changed.disconnect(_on_chase)
	_cur = 0.0
	_goal = 0.0
	if vignette:
		vignette.set_intensity(0.0)


func _on_chase(_enemy: Node2D, _on: bool) -> void:
	_sync_goal()


func _sync_goal() -> void:
	var n := 0
	if bus and bus.has_method(&"chasing_count"):
		n = int(bus.chasing_count())
	elif bus and "chasing" in bus:
		n = (bus.chasing as Array).size()
	_goal = 1.0 if n > 0 else 0.0


func _process(delta: float) -> void:
	if skin == null:
		return
	var k := 1.0 - exp(-delta / maxf(skin.chase_tighten_time, 0.05))
	_cur = lerpf(_cur, _goal, k)
	if vignette:
		# Tightens (smaller inner) and deepens as the chase holds.
		var inner := lerpf(skin.chase_vignette_inner + 0.2, skin.chase_vignette_inner, _cur)
		vignette.set_inner(inner)
		vignette.set_intensity(_cur)
	if _cur < 0.001 and _goal <= 0.0:
		_cur = 0.0


func intensity() -> float:
	return _cur

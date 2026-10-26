extends Node2D
## Small gauge over an enemy's head that fills toward a startle.
## Driven by FESignals.startle_progress(enemy, 0..1); the placeholder adapter
## integrates over FESignals.startle_time (default 1.0 s, TODO PlayerStats).
## Visible only while that enemy is lit (light on) and progress > 0.

var skin: HudSkin
var bus: Node
var target: Node2D
var progress: float = 0.0


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	top_level = true
	z_as_relative = false
	z_index = 50
	if bus == null:
		bus = UiArt.bus()
	if bus:
		bus.flashlight_toggled.connect(_on_flashlight)
	visible = false


## Light off (RMB toggle, via FESignals.set_flashlight) drops the meter at once.
func _on_flashlight(on: bool) -> void:
	if not on:
		progress = 0.0
		visible = false


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	global_position = target.global_position + Vector2(0, -skin.startle_head_offset)
	var lit: bool = bus.is_lit(target) if bus else true
	var light_on: bool = bus.flashlight_on if bus else true
	visible = light_on and progress > 0.0 and (lit or progress < 1.0)
	queue_redraw()


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var s := skin.startle_size
	var r := Rect2(-s * 0.5, s)
	draw_rect(r.grow(1.5), skin.gauge_back)
	var fill := Rect2(r.position, Vector2(s.x * progress, s.y))
	var c := skin.startle_fill.lerp(skin.startle_full, progress * progress)
	draw_rect(fill, c)
	if progress >= 0.999:
		draw_rect(r.grow(2.5), skin.startle_full, false, 1.5)

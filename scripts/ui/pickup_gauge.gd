extends Node2D
## Radial gauge over the boy while the hold-LMB pickup channels.
## Listens to FESignals.pickup_started / pickup_progress(0..1) / pickup_cancelled /
## pickup_completed. Shows the moment BE reports pickup_started, and the fill is
## exactly the progress BE reports (the gauge never advances on its own clock).
## BE only starts a pickup after its tap_threshold (PlayerStats), so a tap
## (throw / knock) never reaches here and never shows the gauge. No extra FE delay.
## Hides on cancel (with a quick red shake-fade) and on complete.

var skin: HudSkin
var bus: Node
var progress: float = 0.0
var active: bool = false

var _fade: float = 0.0
var _cancel_flash: float = 0.0


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	top_level = true
	z_as_relative = false
	z_index = 50
	if bus == null:
		bus = UiArt.bus()
	if bus:
		bus.pickup_started.connect(func(_t): _start())
		bus.pickup_progress.connect(_on_progress)
		bus.pickup_cancelled.connect(_on_cancel)
		bus.pickup_completed.connect(_on_complete)
	visible = false


func _start() -> void:
	active = true
	progress = 0.0
	_fade = 1.0
	_cancel_flash = 0.0
	visible = true
	queue_redraw()


func _on_progress(p: float) -> void:
	if not active:
		_start()
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func _on_cancel() -> void:
	active = false
	_cancel_flash = 1.0


func _on_complete() -> void:
	active = false
	progress = 1.0
	_cancel_flash = 0.0


func _process(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D if is_inside_tree() else null
	if p:
		global_position = p.global_position + Vector2(0, -skin.pickup_head_offset)
	if not active:
		_fade = move_toward(_fade, 0.0, delta * 5.0)
		_cancel_flash = move_toward(_cancel_flash, 0.0, delta * 4.0)
		if _fade <= 0.0:
			visible = false
			progress = 0.0
	queue_redraw()


func _draw() -> void:
	var r := skin.pickup_radius
	var shake := Vector2(sin(_cancel_flash * 40.0) * 3.0 * _cancel_flash, 0)
	var a := _fade
	draw_circle(shake, r + skin.pickup_width * 0.5 + 1.5, Color(skin.gauge_back, skin.gauge_back.a * a))
	var c := skin.pickup_fill.lerp(skin.throw_blocked, _cancel_flash)
	c.a *= a
	if progress > 0.0:
		draw_arc(shake, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, c, skin.pickup_width, true)
	if progress >= 0.999 and not active:
		draw_circle(shake, r * 0.45, c)

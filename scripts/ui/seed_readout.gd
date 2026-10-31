extends Label
## Small, dim run readout in the bottom-left corner: "seed 123456 · stage 2". The seed is the
## RUN seed (FESignals.get_run_seed(), kept through shop Continue) and the stage is
## FESignals.get_stage(), so it matches what game over / the win screen report. Hidden when the
## level has no seed (hud demo, tests). It lives under HudRoot, so it hides with the rest of the
## HUD under game over / win / shop.
## Refreshed on FESignals.stage_started and once deferred after the level's _ready (main.gd rolls
## the seed in its own _ready, after the HUD's); no polling.

var skin: HudSkin
var bus: Node


func _enter_tree() -> void:
	if bus == null:
		bus = UiArt.bus()
	_wire(true)
	if is_node_ready():
		refresh()


## Method connection (no lambda), only while in the tree.
func _exit_tree() -> void:
	_wire(false)


func _wire(on: bool) -> void:
	if bus == null or not is_instance_valid(bus) or not bus.has_signal(&"stage_started"):
		return
	var connected: bool = bus.is_connected(&"stage_started", _on_stage)
	if on and not connected:
		bus.connect(&"stage_started", _on_stage)
	elif not on and connected:
		bus.disconnect(&"stage_started", _on_stage)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.85, 0.82, 0.92, 0.6))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06, 0.8))
	add_theme_constant_override("outline_size", 3)
	refresh()
	refresh.call_deferred()


func _on_stage(_n: int) -> void:
	refresh()


## "seed 123456 · stage 2"; "" when there is no seed.
static func text_for(run_seed: int, stage: int) -> String:
	return "" if run_seed < 0 else "seed %d · stage %d" % [run_seed, stage]


func refresh() -> void:
	if not is_inside_tree() or bus == null or not is_instance_valid(bus):
		return
	var run_seed: int = bus.get_run_seed() if bus.has_method(&"get_run_seed") else -1
	var stage: int = bus.get_stage() if bus.has_method(&"get_stage") else 1
	text = text_for(run_seed, stage)
	visible = not text.is_empty()

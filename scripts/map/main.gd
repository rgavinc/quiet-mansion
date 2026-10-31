extends Node2D
## Side-scroll mansion built by LevelGenerator from (seed, stage) — Lead owns generation.
## Backend owns puppets/noise; Front End owns flashlight/HUD polish.
## HUD = scenes/ui/hud.tscn (hearts/gold/inventory/arrows, wired via FESignals) and
## World/WorldOverlay = scenes/ui/world_overlay.tscn (ring/startle/pickup/throw line).
##
## Seed: `godot -- --seed=1234 [--stage=1]` (or `--seed 1234`), web `?seed=1234&stage=1`,
## or the exported vars below (seed sweep / tests). Otherwise random.
## FE contract (PR #16): FESignals sets `level_seed` / `stage` on the new instance for Retry
## (same seed), New run (-1 = roll a new one) and shop Continue (stage + 1). The command-line /
## URL seed and stage apply on the FIRST boot only, so they never override a reload.
## Level completion stays GameState.reached_exit (no extra signal).

const HINT := "Space jump · RMB flashlight on/off · hold LMB pick up · tap LMB throw/knock · scroll items"

## -1 = take from args or roll a random one.
@export var level_seed: int = -1
@export var stage: int = 1

## Set once the first main scene has read --seed/--stage (or ?seed/?stage).
static var _boot_args_used := false

var layout: Dictionary = {}
var built: Dictionary = {}
var _status: Label
var _view := Rect2()   # what the camera can show (level, or screen-sized when the level is smaller)


func _ready() -> void:
	randomize()
	if not _boot_args_used:
		_boot_args_used = true
		_read_seed_args()
	if level_seed < 0:
		level_seed = randi() % 1000000
	stage = maxi(stage, 1)
	# A run is 5 stages (docs/PRODUCT.md: stage 5 exit = win screen); clamp defensively anyway.
	layout = LevelGenerator.generate(level_seed, mini(stage, StageTable.stage_count()))
	built = LevelGenerator.build(layout, $World)
	if not built.is_empty():
		layout = built.layout
	_build_camera()
	_build_backdrop()
	_build_hud()
	print("Level seed %d stage %d (attempt %d, fallback %s)" % [level_seed, stage, int(layout.get("attempt", -1)), layout.get("fallback", false)])
	GameState.reached_exit.connect(func(): _status.text = HINT + "\n" + "YOU ESCAPED")
	GameState.died.connect(func(): _status.text = HINT + "\n" + "CAUGHT — you die")
	GameState.noise_made.connect(func(_l, _at): if _status and not GameState.game_over: _status.text = HINT + "\n" + "Noise! Nearby puppets may wake…")


func _read_seed_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		for key in ["seed", "stage"]:
			var v := ""
			if args[i].begins_with("--%s=" % key):
				v = args[i].get_slice("=", 1)
			elif args[i] == "--" + key and i + 1 < args.size():
				v = args[i + 1]
			if v.is_valid_int():
				_set_arg(key, int(v))
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			for part in (q as String).trim_prefix("?").split("&"):
				var kv := part.split("=")
				if kv.size() == 2 and kv[0] in ["seed", "stage"] and kv[1].is_valid_int():
					_set_arg(kv[0], int(kv[1]))


func _set_arg(key: String, v: int) -> void:
	if key == "seed":
		level_seed = absi(v)
	else:
		stage = maxi(v, 1)


func _bounds() -> Rect2:
	return built.get("bounds", Rect2(0, 0, 1280, 720))


func _build_backdrop() -> void:
	# Tiled dark wallpaper behind the level + modulate so the flashlight reads.
	var r := _bounds().grow(64).merge(_view)
	var tex: Texture2D = UiArt.texture("floor_dark")   # manifest slot, never a file path
	if tex:
		var bg := Sprite2D.new()
		bg.name = "Floor"
		bg.texture = tex
		bg.centered = false
		bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		bg.region_enabled = true
		bg.region_rect = Rect2(Vector2.ZERO, r.size)
		bg.position = r.position
		bg.z_index = -20
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		$World.add_child(bg)
		$World.move_child(bg, 0)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.05, 0.08)
		bg.position = r.position
		bg.size = r.size
		bg.z_index = -20
		$World.add_child(bg)
		$World.move_child(bg, 0)
	var dark := CanvasModulate.new()
	dark.color = Color(0.28, 0.26, 0.34, 1)
	$World.add_child(dark)


## Follows the boy at zoom 1 (NoiseBus radii assume it), clamped to the level; a level
## smaller than the screen is centred on that axis.
func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.enabled = true
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	var b := _bounds()
	var vs := get_viewport_rect().size
	var c := b.get_center()
	var lo := Vector2(minf(b.position.x, c.x - vs.x / 2), minf(b.position.y, c.y - vs.y / 2))
	var hi := Vector2(maxf(b.end.x, c.x + vs.x / 2), maxf(b.end.y, c.y + vs.y / 2))
	_view = Rect2(lo, hi - lo)
	cam.limit_left = int(lo.x)
	cam.limit_top = int(lo.y)
	cam.limit_right = int(hi.x)
	cam.limit_bottom = int(hi.y)
	var p: Node = built.get("player")
	if p:
		p.add_child(cam)
	else:
		cam.position = c
		add_child(cam)


func _build_hud() -> void:
	# One themed hint/status line under the hearts; everything else is hud.tscn.
	_status = Label.new()
	_status.name = "Hint"
	_status.position = Vector2(16, 64)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/ui/hud_theme.tres"):
		_status.theme = load("res://assets/ui/hud_theme.tres")
	_status.add_theme_font_size_override("font_size", 14)
	_status.text = HINT
	$UI.add_child(_status)

extends Node2D
## Round 1 mansion layout — Backend owns puppets/noise; Front End owns flashlight/HUD polish.
## HUD = scenes/ui/hud.tscn (hearts/gold/inventory/arrows, wired via FESignals) and
## World/WorldOverlay = scenes/ui/world_overlay.tscn (ring/startle/pickup/throw line).

const HINT := "Space jump · RMB flashlight on/off · hold LMB pick up · tap LMB throw/knock · scroll items"

var _status: Label

func _ready() -> void:
	randomize()
	_build_floor_hint()
	_spawn_player()
	_spawn_exit()
	_spawn_puppets()
	_spawn_obstacles()
	_build_hud()
	GameState.reached_exit.connect(func(): _status.text = HINT + "\n" + "YOU ESCAPED")
	GameState.died.connect(func(): _status.text = HINT + "\n" + "CAUGHT — you die")
	GameState.noise_made.connect(func(_l, _at): if _status and not GameState.game_over: _status.text = HINT + "\n" + "Noise! Nearby puppets may wake…")
	GameState.puppet_alerted.connect(func(n): if _status and not GameState.game_over: _status.text = HINT + "\n" + "Alerted puppets: %d / 3" % n)

func _build_floor_hint() -> void:
	# Tiled dark floor + modulate so the mouse flashlight reads
	var tex: Texture2D = UiArt.texture("floor_dark")   # manifest slot, never a file path
	if tex:
		var floor := Sprite2D.new()
		floor.name = "Floor"
		floor.texture = tex
		floor.centered = false
		floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		floor.region_enabled = true
		floor.region_rect = Rect2(0, 0, 1280, 720)
		floor.z_index = -20
		floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		$World.add_child(floor)
		$World.move_child(floor, 0)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.05, 0.08)
		bg.size = Vector2(1280, 720)
		bg.z_index = -10
		$World.add_child(bg)
	var dark := CanvasModulate.new()
	dark.color = Color(0.28, 0.26, 0.34, 1)
	$World.add_child(dark)
	if not has_node("Camera2D"):
		var cam := Camera2D.new()
		cam.name = "Camera2D"
		cam.position = Vector2(640, 360)
		cam.enabled = true
		add_child(cam)

func _spawn_player() -> void:
	var p := CharacterBody2D.new()
	p.set_script(load("res://scripts/player/player_controller.gd"))
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12
	col.shape = circle
	p.add_child(col)
	$World/Player.add_child(p)
	p.position = Vector2(120, 360)

func _spawn_exit() -> void:
	var ex := Area2D.new()
	ex.set_script(load("res://scripts/world/exit_zone.gd"))
	$World/Exit.add_child(ex)
	ex.position = Vector2(1140, 360)

func _spawn_puppets() -> void:
	# Deterministic-ish “correct” placements: left room, hall, near exit — shuffled lightly
	var spots := [
		Vector2(400, 200),
		Vector2(640, 500),
		Vector2(920, 280),
	]
	spots.shuffle()
	for i in GameState.PUPPET_COUNT:
		var puppet := CharacterBody2D.new()
		puppet.set_script(load("res://scripts/enemies/puppet_hand.gd"))
		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 14
		col.shape = circle
		puppet.add_child(col)
		$World/Puppets.add_child(puppet)
		puppet.position = spots[i]

func _spawn_obstacles() -> void:
	var spots := [
		Vector2(300, 360),
		Vector2(520, 240),
		Vector2(520, 480),
		Vector2(780, 360),
		Vector2(1000, 200),
		Vector2(1000, 520),
	]
	for s in spots:
		var ob := Node2D.new()
		ob.set_script(load("res://scripts/world/obstacle.gd"))
		$World/Obstacles.add_child(ob)
		ob.position = s

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

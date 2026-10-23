extends Node2D
## Round 1 mansion layout — Backend owns puppets/noise; Front End owns flashlight/HUD polish.

var _status: Label

func _ready() -> void:
	randomize()
	_build_floor_hint()
	_spawn_player()
	_spawn_exit()
	_spawn_puppets()
	_spawn_obstacles()
	_build_hud()
	GameState.reached_exit.connect(func(): _status.text = "YOU ESCAPED")
	GameState.died.connect(func(): _status.text = "CAUGHT — you die")
	GameState.noise_made.connect(func(_l, _at): if _status and not GameState.game_over: _status.text = "Noise! Nearby puppets may wake…")
	GameState.puppet_alerted.connect(func(n): if _status and not GameState.game_over: _status.text = "Alerted puppets: %d / 3" % n)

func _build_floor_hint() -> void:
	# Tiled dark floor + modulate so the mouse flashlight reads
	var tex: Texture2D = load("res://assets/art/tiles/floor_dark_32.png")
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
	_status = Label.new()
	_status.position = Vector2(12, 48)
	_status.add_theme_font_size_override("font_size", 16)
	_status.text = "WASD move · mouse aims light · Space/RMB knock nearby props (noisy!)"
	$UI.add_child(_status)
	var alerts := Label.new()
	alerts.name = "AlertHud"
	alerts.position = Vector2(12, 76)
	alerts.add_theme_font_size_override("font_size", 18)
	alerts.text = "Alerts 0 / %d" % GameState.PUPPET_COUNT
	$UI.add_child(alerts)
	GameState.puppet_alerted.connect(func(n): alerts.text = "Alerts %d / %d" % [n, GameState.PUPPET_COUNT])
	if AssetProvenance.uses_ai_assets():
		_status.text = "AI assets in use — WASD · mouse light · Space/RMB knock (noisy!)"

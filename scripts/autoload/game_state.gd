extends Node
## Round 1: reach exit without dying. Noise escalates chases.
## Enemy counts are live (group "enemies"), never a hardcoded number: any level size works.

signal noise_made(level: float, at: Vector2)
signal reached_exit
signal died
signal puppet_alerted(count: int)   # live chasing_count(), sent whenever an enemy starts/stops chasing

var game_over: bool = false
## Kept for FE/tests: how many enemies are hunting the boy right now (no cap).
var alerted_puppets: int:
	get: return chasing_count()

func make_noise(level: float, at: Vector2) -> void:
	if game_over:
		return
	noise_made.emit(level, at)

func on_caught() -> void:
	if game_over:
		return
	game_over = true
	died.emit()

func on_reach_exit() -> void:
	if game_over:
		return
	game_over = true
	reached_exit.emit()

## Enemies call this when they start or stop chasing; emits the live count.
func register_alert() -> void:
	if game_over:
		return
	puppet_alerted.emit(chasing_count())


func _enemies() -> Array:
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return []
	var out: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_queued_for_deletion() and not bool(e.get("gone")):
			out.append(e)
	return out


## Live enemies in the level (group "enemies").
func enemy_count() -> int:
	return _enemies().size()


## Live enemies hunting the boy (Enemy.is_chasing(): CHASE, SEARCH, RECOVER).
func chasing_count() -> int:
	var n := 0
	for e in _enemies():
		if e.has_method(&"is_chasing") and e.is_chasing():
			n += 1
	return n

func reset() -> void:
	game_over = false

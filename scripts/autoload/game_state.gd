extends Node
## Round 1: reach exit without dying. 3 puppet-hands. Noise escalates chases.

signal noise_made(level: float, at: Vector2)
signal reached_exit
signal died
signal puppet_alerted(count: int)

const PUPPET_COUNT := 3

var game_over: bool = false
## True once the RUN has ended (death, or the final-stage win). Unlike game_over it is not
## set by a normal stage exit. Cleared by reset() (New run / Retry / next stage load).
var run_over: bool = false
var alerted_puppets: int = 0

func make_noise(level: float, at: Vector2) -> void:
	if game_over:
		return
	noise_made.emit(level, at)

func on_caught() -> void:
	if game_over:
		return
	game_over = true
	run_over = true
	died.emit()

func on_reach_exit() -> void:
	if game_over:
		return
	game_over = true
	reached_exit.emit()

## Call when the run is won (final stage cleared). Idempotent.
func end_run_won() -> void:
	game_over = true
	run_over = true


func register_alert() -> void:
	if game_over:
		return
	alerted_puppets = mini(alerted_puppets + 1, PUPPET_COUNT)
	puppet_alerted.emit(alerted_puppets)

func reset() -> void:
	game_over = false
	run_over = false
	alerted_puppets = 0

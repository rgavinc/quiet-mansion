extends Node2D
## Test fixture: minimal level shaped like PR #13 main.gd (level_seed -1 rolls a
## new run seed in _ready; `stage` export) with a level-owned Player/Inventory (held
## props). Used by the FE game-over / win / carry-over run-flow tests.

@export var level_seed: int = -1
@export var stage: int = 1


func _ready() -> void:
	if level_seed < 0:
		level_seed = 100000 + randi() % 900000

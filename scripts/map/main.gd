extends Node2D
## Round 1 mansion stub — Front End owns flashlight/HUD; Backend owns puppets/noise.

func _ready() -> void:
	print("Quiet Mansion round 1 — %s puppets, reach the exit" % GameState.PUPPET_COUNT)

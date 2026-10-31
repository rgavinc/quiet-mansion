extends SceneTree
## Walker chase matrix (Lead, QA route gap): seeds x stages x every stair x scene_chase.MODES
## (landing, aligned, boy on the stair, real spawn) + the seed-11 freeze check, real physics, one case at a time. Run with --fixed-fps 60 so it
## isn't paced in real time:
##   godot --headless --fixed-fps 60 -s res://tests/chase_sweep.gd -- --seeds 1000-1029 --stages 1-5
## The loop is tests/chase_sweep_impl.gd, loaded on the first frame (a `-s` script compiles
## before autoloads; see tests/seed_sweep.gd). Prints every failure and a summary; exit code 1 on any stuck walker.

var _impl: RefCounted


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	_impl = load("res://tests/chase_sweep_impl.gd").new()
	_impl.start(self)

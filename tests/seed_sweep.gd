extends SceneTree
## Seed sweep launcher (Lead). The sweep itself is tests/seed_sweep_impl.gd, loaded on the first
## frame: a `-s` script compiles before autoloads are registered, and the generator depends on
## PlayerStats, whose code names the GameState autoload (BE #26), so it must not compile here.
##
##   godot --headless -s res://tests/seed_sweep.gd -- --seeds 1000 --stages 1-5
##   options: --stages 1,2 | 1-5   --boot-every 25   --frames 120   --first-seed 0   --catch 0|1

var _impl: RefCounted


func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	_impl = load("res://tests/seed_sweep_impl.gd").new()
	_impl.start(self)

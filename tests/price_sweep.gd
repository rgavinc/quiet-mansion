extends SceneTree
## Gold / stock sweep for the price retune (Backend). Writes JSON to the path after `--out`:
##   godot --headless --path . -s res://tests/price_sweep.gd -- --out /tmp/gold.json --seeds 1000
## Per stage 1-5 and seed: floor-pile total, vase count + the vase gold the real Vase roll gives
## (global RNG seeded with the level's build_seed, 0.45 chance of 1-3 each), chest count. Per
## stage 1-4 and seed: the shop's stock (Shop.roll_stock) as row ids. Gold generation is Lead's
## and is only read here. The script loads late: a `-s` script compiles before autoloads exist.

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	load("res://tests/price_sweep_impl.gd").new().run(self)

class_name Chest
extends WorldObject
## Treasure chest. Hold LMB on it (the same pickup channel as a vase, but slower:
## "chests take time to open") and it opens instead of going into your hands:
## one random item from ItemDb (deterministic from loot_seed + stage + what is owned; never a
## copy that adds nothing, ItemDb.fallback_gold instead when nothing is left), plus any
## gold_inside, art swaps prop_chest_closed → prop_chest_open, and a modest noise.
## Opens exactly once. Generator: set `stage` and `loot_seed` before adding it.

const SLOT_CLOSED := "prop_chest_closed"
const SLOT_OPEN := "prop_chest_open"

signal opened(item: Item)

## Stage whose item pool to roll from.
@export var stage: int = 1
## -1 = derive from the run seed, stage and position (still the same every replay).
@export var loot_seed: int = -1

var is_open: bool = false
## The item it gave (null until opened).
var granted: Item = null
## Tests: stats node to grant into (default: the PlayerStats autoload).
var stats: Node = null
var _visual: Node = null


func _init() -> void:
	display_name = "Chest"
	art_slot = SLOT_CLOSED
	can_pick_up = true            # opened through the hold-LMB channel
	throwable = false
	breakable = false
	break_on_touch = false
	pickup_time_mult = 1.5        # 1.5 s at base pickup_time: exposed while opening
	noise_radius = NoiseBus.DEFAULT_RADIUS * 0.5   # creak: about half a screen
	noise_loudness = 0.6
	size = Vector2(28, 20)


func _build_visual() -> void:
	var before := get_child_count()
	super._build_visual()
	_visual = get_child(before) if get_child_count() > before else null


## Player pickup channel finished on this chest: open it, never carry it.
func on_hold_complete(by: Node) -> bool:
	open(by)
	return true


## Opens the chest. Returns the granted item (null if it was already open).
func open(_by: Node = null) -> Item:
	if is_open:
		return null
	is_open = true
	can_pick_up = false
	var ps := Item._stats(stats)
	granted = ItemDb.roll_chest(maxi(stage, 1), _seed(), ps)
	if granted and ps:
		ps.grant_item(granted)
	elif ps:
		# Nothing left that another copy would help with: gold instead (never empty).
		gold_inside += ItemDb.fallback_gold(maxi(stage, 1))
	if gold_inside > 0 and ps:
		ps.add_gold(gold_inside)
		gold_inside = 0
	art_slot = SLOT_OPEN
	if _visual and is_instance_valid(_visual):
		remove_child(_visual)
		_visual.queue_free()
		_visual = null
	if is_inside_tree():
		_build_visual()
		var nb := get_node_or_null(^"/root/NoiseBus")
		var mult: float = ps.get_stat(&"noise_mult") if ps else 1.0
		if nb:
			nb.emit_noise(global_position, noise_radius * mult, noise_loudness, self)
	opened.emit(granted)
	return granted


func _seed() -> int:
	if loot_seed >= 0:
		return loot_seed
	var run_seed := -1
	var fe := get_node_or_null(^"/root/FESignals") if is_inside_tree() else null
	if fe and fe.has_method(&"get_run_seed"):
		run_seed = int(fe.get_run_seed())
	return absi(hash([run_seed, stage, roundi(position.x), roundi(position.y)]))

class_name Item
extends Resource
## One shop / chest item. Base-class defaults; every real item's numbers come from
## ONE table (ItemDb.ITEMS) — see docs/BACKEND.md "Items, shop and chests".
## An item changes the boy ONLY through PlayerStats modifiers (source = source_key()),
## so PlayerStats.reset() / remove() undo it completely.

@export var id: String = ""
@export var display_name: String = "Item"
@export var description: String = ""
@export var icon_slot: String = ""        # manifest slot, art looked up by name only
@export var price: int = 5
@export var rarity: String = "common"     # common / uncommon / rare / legendary
## Array of {stat: StringName, add: float, mul: float}. Every stat must be in PlayerStats.BASE.
@export var mods: Array = []

## Runtime: bought from a shop offer (a second buy of the same offer fails).
var sold: bool = false
## Runtime: the stats node this item is applied to (null = not applied).
var _applied_to: Node = null


## Modifier source for this item INSTANCE (two copies of one item stack and are
## removed separately). Always a String, so PlayerStats compares like with like.
func source_key() -> String:
	return "item:%s#%d" % [id, get_instance_id()]


func is_applied() -> bool:
	return _applied_to != null and is_instance_valid(_applied_to)


## Adds this item's modifiers to `stats` (default: the PlayerStats autoload).
## Applying twice is a no-op.
func apply(stats: Node = null) -> void:
	var ps := _stats(stats)
	if ps == null or is_applied():
		return
	_applied_to = ps
	for m in mods:
		ps.add_modifier(StringName(m.stat), float(m.get("add", 0.0)), float(m.get("mul", 1.0)), source_key())
	_on_apply(ps)


## Removes exactly what apply() added.
func remove(stats: Node = null) -> void:
	var ps: Node = _applied_to if is_applied() else _stats(stats)
	if ps == null:
		return
	ps.remove_modifiers_from(source_key())
	_on_remove(ps)
	_applied_to = null


## Hooks for items that need behaviour beyond stat modifiers (none do today).
func _on_apply(_ps: Node) -> void:
	pass


func _on_remove(_ps: Node) -> void:
	pass


## Plain dict for logs / saves / UI.
func to_dict() -> Dictionary:
	return {id = id, display_name = display_name, description = description,
		icon_slot = icon_slot, price = price, rarity = rarity}


static func _stats(stats: Node) -> Node:
	if stats != null:
		return stats
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"PlayerStats") if tree else null

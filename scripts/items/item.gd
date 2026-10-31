class_name Item
extends Resource
## One shop / chest item. Base-class defaults; every real item's numbers come from
## ONE table (ItemDb.ITEMS) — see docs/BACKEND.md "Items, shop and chests".
## Stats: an item changes numbers ONLY through PlayerStats modifiers (source = source_key()),
## so PlayerStats.reset() / remove() undo them completely.
## Behaviour ("default class plus special behaviour"): a behaviour item is a subclass
## (scripts/items/behaviors/*.gd) that overrides the hooks below. The base hooks are
## no-ops, so every stat item is still a plain Item. PlayerStats dispatches each hook
## over owned_items from the real game code (see docs/BACKEND.md "Item behaviour hooks").
## Tunables live in the item's ItemDb row as `params` (copied into `params` here).

@export var id: String = ""
@export var display_name: String = "Item"
@export var description: String = ""
@export var icon_slot: String = ""        # manifest slot, art looked up by name only
@export var price: int = 5
@export var rarity: String = "common"     # common / uncommon / rare / legendary
## Array of {stat: StringName, add: float, mul: float}. Every stat must be in PlayerStats.BASE.
@export var mods: Array = []

## Behaviour tunables from the ItemDb row (`params`). Empty for stat items.
@export var params: Dictionary = {}
## Uses per stage (Flash Bulb, Rabbit's Foot, Music Box). 0 = no charges (FE hides the pip).
@export var max_charges: int = 0
## Copies worth owning (ItemDb.max_copies): shops and chests stop offering it past this.
@export var max_copies: int = 1
## Runtime: uses left this stage. Refilled by PlayerStats.begin_stage(); every change
## re-emits PlayerStats.items_changed(owned_items) so FE can redraw the pips.
var charges: int = 0

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


## Called once when the item is applied / removed (beyond its modifiers).
func _on_apply(_ps: Node) -> void:
	pass


func _on_remove(_ps: Node) -> void:
	pass


# --- behaviour hooks (base = no-op; PlayerStats dispatches them over owned_items) --------
## True for subclasses that override hooks (shop / FE can badge them).
func has_behavior() -> bool:
	return false


## Stage loaded (the level's player is ready). Charges are already refilled.
func on_stage_start(_player: Node) -> void:
	pass


## The boy is about to take `amount` damage. Return the (possibly changed) amount; <= 0 cancels.
func on_hit(amount: int) -> int:
	return amount


## This hit would drop the boy to 0 hearts. Return true to survive it (left on 1 heart).
func on_lethal_hit() -> bool:
	return false


## The boy throws (or knocks) `item` (the held/prop dict) at `target` (Node2D or Vector2).
## May write into `item` (e.g. stun_mult); the dict is what the enemy receives.
func on_throw(_item: Dictionary, _target: Variant) -> void:
	pass


## A noise is being emitted. Return a multiplier for its radius and loudness (1 = unchanged).
func on_noise(_at: Vector2, _radius: float, _loudness: float, _source: Variant) -> float:
	return 1.0


## `enemy`'s light startle just completed (it is about to chase). Return true if this item
## handled it instead (the enemy will not chase).
func on_startle(_enemy: Node) -> bool:
	return false


## Gold inside a vase as it breaks. Return the (possibly changed) amount.
func on_vase_gold(gold: int, _vase: Variant) -> int:
	return gold


## Move-speed multiplier for what the boy is holding (`held` = Inventory.items).
func carry_speed_mult(_held: Array) -> float:
	return 1.0


## Multiplier on a searching enemy's give-up drain (`off_screen`: the enemy is outside the
## 1280x720 view around the boy).
func memory_drain_mult(_enemy: Node, _off_screen: bool) -> float:
	return 1.0


## Max distance (px) at which FE may show a chaser's off-screen arrow. INF = always.
func arrow_reveal_distance() -> float:
	return INF


## Spends one charge; false if none left. Re-emits PlayerStats.items_changed.
func use_charge() -> bool:
	if charges <= 0:
		return false
	charges -= 1
	_charges_changed()
	return true


func set_charges(n: int) -> void:
	if n == charges:
		return
	charges = n
	_charges_changed()


func _charges_changed() -> void:
	if is_applied() and _applied_to.has_method(&"notify_items_changed"):
		_applied_to.notify_items_changed()


## True for a vase: a Vase node, a thrown object carrying a vase, or a vase item dict.
static func is_vase(x: Variant) -> bool:
	if x is Dictionary:
		return str(x.get("script_path", "")).ends_with("vase.gd") or str(x.get("slot", "")) == "vase_idle"
	if x is Object and is_instance_valid(x):
		if x is Vase:
			return true
		if "item" in x and x.get("item") is Dictionary:
			return is_vase(x.get("item"))
	return false


## Plain dict for logs / saves / UI.
func to_dict() -> Dictionary:
	return {id = id, display_name = display_name, description = description,
		icon_slot = icon_slot, price = price, rarity = rarity,
		charges = charges, max_charges = max_charges, max_copies = max_copies, behavior = has_behavior()}


static func _stats(stats: Node) -> Node:
	if stats != null:
		return stats
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"PlayerStats") if tree else null

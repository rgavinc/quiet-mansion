extends Item
## Heavy Vases: a thrown or knocked vase stuns an enemy params.stun_mult x longer;
## carrying any vase slows the boy to params.carry_speed_mult.


func has_behavior() -> bool:
	return true


func on_throw(item: Dictionary, _target: Variant) -> void:
	if Item.is_vase(item):
		item["stun_mult"] = float(item.get("stun_mult", 1.0)) * float(params.get("stun_mult", 2.0))


func carry_speed_mult(held: Array) -> float:
	for h in held:
		if Item.is_vase(h):
			return float(params.get("carry_speed_mult", 0.85))
	return 1.0

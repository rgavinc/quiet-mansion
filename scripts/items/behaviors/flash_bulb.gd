extends Item
## Flash Bulb: once per stage, an enemy whose light startle completes is stunned
## (params.stun_time) instead of chasing, then goes back to calm.


func has_behavior() -> bool:
	return true


func on_startle(enemy: Node) -> bool:
	if enemy == null or not enemy.has_method(&"stun_from_startle") or not use_charge():
		return false
	enemy.stun_from_startle(float(params.get("stun_time", 2.5)))
	return true

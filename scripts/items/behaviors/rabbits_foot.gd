extends Item
## Rabbit's Foot: the first lethal hit each stage leaves the boy on 1 heart (1 charge per
## stage). Downside is a stat row in ItemDb (max_health -1).


func has_behavior() -> bool:
	return true


func on_lethal_hit() -> bool:
	return use_charge()

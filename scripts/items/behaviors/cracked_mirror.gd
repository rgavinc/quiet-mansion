extends Item
## Cracked Mirror: off-screen searchers give up faster (params.offscreen_drain_mult);
## downside: FE shows a chaser's off-screen arrow only within params.arrow_reveal_distance.


func has_behavior() -> bool:
	return true


func memory_drain_mult(_enemy: Node, off_screen: bool) -> float:
	return float(params.get("offscreen_drain_mult", 1.4)) if off_screen else 1.0


func arrow_reveal_distance() -> float:
	return float(params.get("arrow_reveal_distance", 1280.0))

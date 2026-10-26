extends Item
## Greedy Sack: every vase holds gold (an empty one rolls params.gold_min..gold_max), but
## a vase breaking is params.noise_mult x louder (radius and loudness).


func has_behavior() -> bool:
	return true


func on_vase_gold(gold: int, _vase: Variant) -> int:
	if gold >= 1:
		return gold
	return randi_range(int(params.get("gold_min", 1)), int(params.get("gold_max", 3)))


func on_noise(_at: Vector2, _radius: float, _loudness: float, source: Variant) -> float:
	return float(params.get("noise_mult", 1.5)) if Item.is_vase(source) else 1.0

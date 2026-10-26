extends Item
## Music Box: each stage start puts one Music Box lure in the boy's hands (charges = lures
## in hand, 0 or 1). Throw it like any held prop (at the ringed enemy, or toward the aim
## with no enemy ringed); where it lands it plays a loud tune (MusicBoxLure) that pulls
## enemies in range to it. Its cost is the hand slot it takes until thrown.

const LURE_ID := "music_box_lure"


func has_behavior() -> bool:
	return true


## The held-prop dict for one lure (what Inventory holds and thrown_object carries).
func lure_dict() -> Dictionary:
	return {
		id = "%s_%d" % [LURE_ID, get_instance_id()],
		name = display_name,
		slot = str(params.get("world_slot", "music_box_world")),
		throwable = true,
		lure = true,
		lure_time = float(params.get("lure_time", 4.0)),
		lure_interval = float(params.get("lure_interval", 0.5)),
		noise_radius = float(params.get("lure_radius", 900.0)),
		noise_loudness = float(params.get("lure_loudness", 1.2)),
		gold_inside = 0,
		script_path = "",
	}


func on_stage_start(player: Node) -> void:
	var inv: Variant = player.get("inventory") if player != null and "inventory" in player else null
	charges = 0
	if inv is Object and inv.has_method(&"add") and inv.add(lure_dict()):
		charges = 1


func on_throw(item: Dictionary, _target: Variant) -> void:
	if item.get("lure", false) and charges > 0:
		use_charge()

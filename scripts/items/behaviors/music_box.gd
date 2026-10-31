extends Item
## Music Box: each copy gives one lure per stage into the boy's LURE POCKET (PRODUCT.md:
## never a hand / inventory slot, never blocks a vase pickup). charges = this copy's lure
## (0 or 1), refilled by PlayerStats.begin_stage; PlayerStats.lure_charges()/lure_max() sum
## the copies. A tap with nothing ringed throws one the way the boy faces
## (PlayerController._tap -> PlayerStats.next_lure()); where it lands it plays a loud tune
## (MusicBoxLure) that pulls enemies in range to it.

const LURE_ID := "music_box_lure"


func has_behavior() -> bool:
	return true


## The thrown-prop dict for this copy's lure (what thrown_object carries; never in Inventory).
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


## PlayerStats.dispatch_throw calls this on EVERY owned item, so with 2+ Music Boxes each
## copy must only spend for its OWN lure (the id in lure_dict() is per instance): one throw
## spends exactly one copy, the one whose lure flew.
func on_throw(item: Dictionary, _target: Variant) -> void:
	if item.get("lure", false) and owns_lure(item) and charges > 0:
		use_charge()


## True if `item` is this copy's lure.
func owns_lure(item: Dictionary) -> bool:
	return str(item.get("id", "")) == str(lure_dict().id)

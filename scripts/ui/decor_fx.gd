extends Node
## Binds FE candle / curtain effects onto props Lead already placed.
## Looks at groups `fe_candle` / `fe_curtain`, and also at nodes whose `art_slot`
## / `slot` meta or property matches HudSkin.candle_slot or curtain_slot.
## Does not place, spawn, or lay out props.

var skin: HudSkin
var bus: Node
var last_bound: Array = []   # host Node2Ds we attached to, for tests


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	if bus and bus.has_signal(&"stage_started") and not bus.stage_started.is_connected(_on_stage):
		bus.stage_started.connect(_on_stage)
	call_deferred(&"bind")


func _exit_tree() -> void:
	if bus and bus.has_signal(&"stage_started") and bus.stage_started.is_connected(_on_stage):
		bus.stage_started.disconnect(_on_stage)
	last_bound.clear()


func _on_stage(_n: int) -> void:
	call_deferred(&"bind")


func bind() -> int:
	last_bound.clear()
	if not is_inside_tree() or skin == null:
		return 0
	var Candle := load("res://scripts/ui/decor_candle.gd")
	var Curtain := load("res://scripts/ui/decor_curtain.gd")
	for n in _hosts(skin.candle_group, [skin.candle_slot, skin.candle_flame_slot]):
		Candle.attach_to(n, skin)
		last_bound.append(n)
	for n in _hosts(skin.curtain_group, [skin.curtain_slot]):
		Curtain.attach_to(n, skin)
		last_bound.append(n)
	return last_bound.size()


func _hosts(group: StringName, slots: Array) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var seen: Dictionary = {}
	for n in get_tree().get_nodes_in_group(group):
		if n is Node2D and not seen.has(n):
			seen[n] = true
			out.append(n)
	# Manifest slot name, for props that were not (yet) tagged with the group.
	for n in get_tree().get_nodes_in_group(&"world_objects"):
		if not (n is Node2D) or seen.has(n):
			continue
		var slot := _slot_of(n)
		if slot != "" and slot in slots:
			seen[n] = true
			out.append(n)
	return out


func _slot_of(n: Node) -> String:
	if n.has_meta(&"art_slot"):
		return str(n.get_meta(&"art_slot"))
	if n.has_meta(&"slot"):
		return str(n.get_meta(&"slot"))
	if "art_slot" in n:
		return str(n.get("art_slot"))
	if "slot" in n:
		return str(n.get("slot"))
	return ""

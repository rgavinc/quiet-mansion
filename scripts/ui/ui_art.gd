class_name UiArt
extends RefCounted
## Art lookups BY SLOT NAME for UI (never file paths in widgets).
## Reads slot → path from AssetProvenance (assets/ASSETS_MANIFEST.toml).
## Returns null when the slot isn't in the manifest yet, and widgets then
## draw their placeholder shapes.
## TODO(BE-wire): switch to Back End's shared manifest loader when it lands.

static var _cache: Dictionary = {}


static func texture(slot: String) -> Texture2D:
	if slot.is_empty():
		return null
	if _cache.has(slot):
		return _cache[slot]
	var tex: Texture2D = null
	var path := _path_for(slot)
	if not path.is_empty():
		var res_path := path if path.begins_with("res://") else "res://" + path
		if ResourceLoader.exists(res_path):
			var r = load(res_path)
			if r is Texture2D:
				tex = r
	_cache[slot] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


static func _path_for(slot: String) -> String:
	var loop := Engine.get_main_loop() as SceneTree
	var prov: Node = null
	if loop and loop.root:
		prov = loop.root.get_node_or_null("AssetProvenance")
	if prov == null or not ("entries" in prov):
		return ""
	for e in prov.entries:
		if str(e.get("slot", "")) == slot:
			return str(e.get("path", ""))
	return ""


## The FESignals adapter, or null (e.g. in isolated tests before injection).
static func bus() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("FESignals")
	return null

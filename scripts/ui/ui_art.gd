class_name UiArt
extends RefCounted
## Art lookups BY SLOT NAME for UI (never file paths in widgets).
## Slot → path comes from AnimLibrary (BE's single manifest loader over
## assets/ASSETS_MANIFEST.toml). Returns null when the slot isn't in the manifest
## yet (or its PNG is missing), and callers then draw their placeholder shapes.

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


## SpriteFrames with one animation named after `slot`, or null when the slot or its
## PNG is missing (checked first, so no AnimLibrary warnings before art lands).
static func frames(slot: String) -> SpriteFrames:
	if texture(slot) == null:
		return null
	var sf := AnimLibrary.frames_for([slot])
	return sf if sf.has_animation(slot) and sf.get_frame_count(slot) > 0 else null


## First frame of a slot's strip as a texture (icons / stills), or null.
static func first_frame(slot: String) -> Texture2D:
	var sf := frames(slot)
	return sf.get_frame_texture(slot, 0) if sf else null


static func clear_cache() -> void:
	_cache.clear()


static func _path_for(slot: String) -> String:
	if not AnimLibrary.has_slot(slot):
		return ""
	return str(AnimLibrary.meta(slot).get("path", ""))


## The FESignals adapter, or null (e.g. in isolated tests before injection).
static func bus() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("FESignals")
	return null

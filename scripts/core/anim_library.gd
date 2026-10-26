class_name AnimLibrary
extends RefCounted
## The ONE animation loader. Reads assets/ASSETS_MANIFEST.toml (single source of truth)
## and builds SpriteFrames from horizontal PNG strips. Code asks by slot name only:
##   var sf := AnimLibrary.frames_for(["boy_idle", "boy_run"])   # anim names = slot names
##   var meta := AnimLibrary.meta("boy_carry")  # pivot, frame_size, hand_points, ...
## Swapping art = drop a same-named PNG on the same grid; frame count/fps change in the manifest only.

const MANIFEST := "res://assets/ASSETS_MANIFEST.toml"

static var _entries: Dictionary = {}   # slot -> Dictionary
static var _loaded := false


static func reload() -> void:
	_entries.clear()
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		push_error("AnimLibrary: manifest missing")
		return
	var cur: Dictionary = {}
	for raw in FileAccess.get_file_as_string(MANIFEST).split("\n"):
		var t := raw.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		if t == "[[asset]]":
			_commit(cur)
			cur = {}
			continue
		var eq := t.find("=")
		if eq < 0:
			continue
		cur[t.substr(0, eq).strip_edges()] = _parse_value(t.substr(eq + 1).strip_edges())
	_commit(cur)


static func _commit(d: Dictionary) -> void:
	if d.has("slot"):
		if not d.has("hand_points"):
			d["hand_points"] = _hand_points_from_notes(str(d.get("notes", "")))
		_entries[str(d.slot)] = d


static func _parse_value(v: String) -> Variant:
	if v.begins_with("\""):
		var end := v.find("\"", 1)
		return v.substr(1, end - 1) if end > 0 else v.trim_prefix("\"")
	var hash := v.find(" #")
	if hash >= 0:
		v = v.substr(0, hash).strip_edges()
	if v == "true": return true
	if v == "false": return false
	if v.begins_with("["):
		var arr = JSON.parse_string(v)
		return arr if arr is Array else []
	if v.is_valid_int(): return v.to_int()
	if v.is_valid_float(): return v.to_float()
	return v


## Fallback until hand points are a structured field: "Hand point per frame: 46,56 46,57 ..."
static func _hand_points_from_notes(notes: String) -> Array:
	var i := notes.find("Hand point per frame")
	if i < 0:
		return []
	var tail := notes.substr(notes.find(":", i) + 1)
	var pts: Array = []
	for tok in tail.strip_edges().split(" ", false):
		var xy := tok.split(",")
		if xy.size() == 2 and xy[0].is_valid_int() and xy[1].is_valid_int():
			pts.append([xy[0].to_int(), xy[1].to_int()])
		else:
			break
	return pts


static func has_slot(slot: String) -> bool:
	if not _loaded: reload()
	return _entries.has(slot)


static func meta(slot: String) -> Dictionary:
	if not _loaded: reload()
	return _entries.get(slot, {})


static func pivot(slot: String) -> Vector2:
	var p: Array = meta(slot).get("pivot", [])
	return Vector2(p[0], p[1]) if p.size() == 2 else Vector2.ZERO


static func hand_point(slot: String, frame: int) -> Vector2:
	var hp: Array = meta(slot).get("hand_points", [])
	if hp.is_empty():
		return Vector2.ZERO
	var p: Array = hp[clampi(frame, 0, hp.size() - 1)]
	return Vector2(p[0], p[1])


## Adds one animation (named after the slot) to `sf`. Returns false (never crashes) if missing.
static func add_to(sf: SpriteFrames, slot: String) -> bool:
	var m := meta(slot)
	if m.is_empty():
		push_warning("AnimLibrary: unknown slot %s" % slot)
		return false
	var tex: Texture2D = load("res://" + str(m.path)) if ResourceLoader.exists("res://" + str(m.path)) else null
	if tex == null:
		push_warning("AnimLibrary: missing texture for %s" % slot)
		return false
	var fs: Array = m.get("frame_size", [tex.get_width(), tex.get_height()])
	var fw: int = int(fs[0])
	var fh: int = int(fs[1])
	var n: int = int(m.get("frames", 1))
	n = clampi(n, 1, maxi(1, tex.get_width() / maxi(fw, 1)))  # never read past the strip
	if sf.has_animation(slot):
		sf.remove_animation(slot)
	sf.add_animation(slot)
	sf.set_animation_speed(slot, float(m.get("fps", 8)))
	sf.set_animation_loop(slot, bool(m.get("loop", true)))
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame(slot, at)
	return true


static func frames_for(slots: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for s in slots:
		add_to(sf, str(s))
	return sf


## Sprite offset so the manifest pivot lands on the node origin (feet).
static func offset_for(slot: String) -> Vector2:
	var fs: Array = meta(slot).get("frame_size", [0, 0])
	return Vector2(fs[0], fs[1]) * 0.5 - pivot(slot)

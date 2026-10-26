extends RefCounted
## AnimLibrary — every animated manifest slot builds with the declared frame count.


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["all_strips_build", test_all_strips_build],
		["hand_points_parsed", test_hand_points],
		["unknown_slot_safe", test_unknown_safe],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func test_all_strips_build() -> String:
	AnimLibrary.reload()
	var n := 0
	for slot in AnimLibrary._entries:
		var m: Dictionary = AnimLibrary._entries[slot]
		if not m.has("frames"):
			continue
		n += 1
		var sf := SpriteFrames.new()
		if not AnimLibrary.add_to(sf, slot):
			return "could not build %s" % slot
		if sf.get_frame_count(slot) != int(m.frames):
			return "%s: manifest says %d frames, strip has %d" % [slot, m.frames, sf.get_frame_count(slot)]
	return "" if n > 0 else "no animated slots found"


func test_hand_points() -> String:
	if not AnimLibrary.has_slot("boy_carry"):
		return ""
	var p := AnimLibrary.hand_point("boy_carry", 0)
	return "" if p != Vector2.ZERO else "boy_carry hand point missing"


func test_unknown_safe() -> String:
	var sf := SpriteFrames.new()
	return "" if not AnimLibrary.add_to(sf, "no_such_slot") else "unknown slot returned true"

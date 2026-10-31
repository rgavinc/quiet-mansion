extends RefCounted
## AnimLibrary — every animated manifest slot builds with the declared frame count.


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["all_strips_build", test_all_strips_build],
		["hand_points_parsed", test_hand_points],
		["eye_points_match_frames", test_eye_points],
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
	for slot in AnimLibrary.animated_slots():
		var m: Dictionary = AnimLibrary.meta(slot)
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


## Every slot that declares eye_points: one entry per frame, each entry a list of [x, y] inside the frame ([] = eyes hidden).
func test_eye_points() -> String:
	AnimLibrary.reload()
	var n := 0
	for slot in AnimLibrary.animated_slots():
		var m: Dictionary = AnimLibrary.meta(slot)
		if not m.has("eye_points"):
			continue
		n += 1
		var ep: Array = m.eye_points
		if ep.size() != int(m.frames):
			return "%s: eye_points has %d entries, frames = %d" % [slot, ep.size(), m.frames]
		var fs: Array = m.frame_size
		for i in ep.size():
			for pt in ep[i]:
				if pt.size() != 2 or pt[0] < 0 or pt[1] < 0 or pt[0] >= fs[0] or pt[1] >= fs[1]:
					return "%s frame %d: bad eye point %s" % [slot, i, str(pt)]
	if not AnimLibrary.has_slot("vfx_eye_glint"):
		return "vfx_eye_glint slot missing"
	if not AnimLibrary.has_slot("vfx_eye_glint_calm"):
		return "vfx_eye_glint_calm slot missing"
	var hunt: Dictionary = AnimLibrary.meta("vfx_eye_glint")
	var calm: Dictionary = AnimLibrary.meta("vfx_eye_glint_calm")
	for k in ["frame_size", "frames", "pivot"]:
		if calm.get(k) != hunt.get(k):
			return "vfx_eye_glint_calm %s %s differs from vfx_eye_glint %s" % [k, str(calm.get(k)), str(hunt.get(k))]
	return "" if n >= 6 else "expected eye_points on 6 puppet slots, found %d" % n

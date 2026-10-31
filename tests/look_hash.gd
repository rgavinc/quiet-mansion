class_name LookHash
extends RefCounted
## Compares generated layouts with tests/fixtures/layout_hashes_pr13.txt ("stage seed md5" lines).

const FIXTURE := "res://tests/fixtures/layout_hashes_pr13.txt"


static func hash_of(seed_value: int, stage: int) -> String:
	var L := LevelGenerator.generate(seed_value, stage)
	L.erase("reject_reasons")
	return var_to_str(L).md5_text()


## Mismatch descriptions for seeds 0..seeds_per_stage-1 of every stage (empty = identical).
static func check(seeds_per_stage: int) -> PackedStringArray:
	var bad := PackedStringArray()
	var seen := 0
	for line in FileAccess.get_file_as_string(FIXTURE).split("\n", false):
		if line.begins_with("#"):
			continue
		var p := line.split(" ")
		if p.size() != 3 or int(p[1]) >= seeds_per_stage:
			continue
		seen += 1
		if hash_of(int(p[1]), int(p[0])) != p[2]:
			bad.append("stage %s seed %s" % [p[0], p[1]])
	if seen != seeds_per_stage * 5:
		bad.append("fixture has %d of %d expected lines" % [seen, seeds_per_stage * 5])
	return bad

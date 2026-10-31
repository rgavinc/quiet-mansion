class_name LookHash
extends RefCounted
## Layout fingerprint for the determinism / separate-stream tests.


static func hash_of(seed_value: int, stage: int) -> String:
	var L := LevelGenerator.generate(seed_value, stage)
	L.erase("reject_reasons")
	return var_to_str(L).md5_text()

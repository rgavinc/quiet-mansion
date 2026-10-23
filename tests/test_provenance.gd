extends RefCounted
## AssetProvenance — watermark gate (art + audio manifest).


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["scaffold_has_ai", test_scaffold_has_ai],
		["uses_ai_true", test_uses_ai_true],
	]
	var passed := 0
	for item in checks:
		var err: String = item[1].call()
		if err.is_empty():
			passed += 1
		else:
			failures.append("%s: %s" % [item[0], err])
	return {"passed": passed, "total": checks.size(), "failures": failures}


func _make_prov() -> Node:
	var n: Node = load("res://scripts/autoload/asset_provenance.gd").new()
	n.reload()
	return n


func test_scaffold_has_ai() -> String:
	var p := _make_prov()
	if p.ai_remaining <= 0 or p.entries.is_empty():
		var msg := "expected AI entries remaining=%s entries=%s" % [p.ai_remaining, p.entries.size()]
		p.free(); return msg
	p.free(); return ""


func test_uses_ai_true() -> String:
	var p := _make_prov()
	if not p.uses_ai_assets():
		p.free(); return "uses_ai_assets should be true on scaffold"
	p.free(); return ""

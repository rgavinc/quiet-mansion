extends Node
## Reads assets/ASSETS_MANIFEST.toml — watermark while any art/audio entry is still ai.

signal provenance_changed(ai_remaining: int)

var ai_remaining: int = 0
var entries: Array = []

func _ready() -> void:
	reload()

func reload() -> void:
	entries.clear()
	ai_remaining = 0
	var path := "res://assets/ASSETS_MANIFEST.toml"
	if not FileAccess.file_exists(path):
		ai_remaining = 1
		provenance_changed.emit(ai_remaining)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	# Minimal TOML table parse: [[asset]] blocks with path / status
	var current: Dictionary = {}
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("[[asset]]"):
			if current.has("path"):
				_commit(current)
			current = {}
		elif t.begins_with("path"):
			current["path"] = t.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		elif t.begins_with("status"):
			current["status"] = t.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		elif t.begins_with("slot"):
			current["slot"] = t.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	if current.has("path"):
		_commit(current)
	provenance_changed.emit(ai_remaining)

func _commit(d: Dictionary) -> void:
	entries.append(d)
	if str(d.get("status", "ai")) == "ai":
		ai_remaining += 1

func uses_ai_assets() -> bool:
	return ai_remaining > 0

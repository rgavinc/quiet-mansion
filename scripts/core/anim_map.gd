class_name AnimMap
extends Resource
## Maps an anim_state name to a SpriteFrames animation (manifest slot).
## If the preferred name is missing, resolve() returns `fallback` so current
## placeholder art keeps playing. Designer/FE can retarget states by editing
## the .tres (assets/anim_maps/) or swapping this resource; no gameplay code.

const PLAYER_PATH := "res://assets/anim_maps/player.tres"
const ENEMY_PATH := "res://assets/anim_maps/enemy.tres"

## Preferred SpriteFrames animation name for each anim_state.
@export var names: Dictionary = {}


## Boy defaults: new clip names (walk, fall, land, hide, caught, …) fall back
## to the existing boy_* slots until those strips are in the manifest.
const PLAYER_DEFAULTS := {
	"idle": "boy_idle",
	"walk": "boy_walk",
	"run": "boy_run",
	"jump": "boy_jump",
	"fall": "boy_fall",
	"land": "boy_land",
	"climb": "boy_climb_stairs",
	"carry_idle": "boy_carry_idle",
	"carry_walk": "boy_carry",
	"throw": "boy_throw",
	"hide": "boy_hide",
	"hurt": "boy_hurt",
	"caught": "boy_caught",
	"pickup": "boy_pickup",
}

## Enemy defaults use logical clip names (idle, patrol, alert, …). Current
## puppet slots are supplied as resolve() fallbacks from Enemy (anim_calm, …).
const ENEMY_DEFAULTS := {
	"idle": "idle",
	"patrol": "patrol",
	"alert": "alert",
	"chase": "chase",
	"search": "search",
	"stunned": "stunned",
	"reach_windup": "reach_windup",
	"reach_strike": "reach_strike",
	"rattle": "rattle",
	"recover": "recover",
}


func _lookup(state: StringName) -> String:
	if names.has(state):
		return str(names[state])
	var key := String(state)
	if names.has(key):
		return str(names[key])
	return ""


## Preferred clip for `state` if it exists on `frames`; otherwise `fallback`.
## Never crashes on a missing name — placeholder art keeps working.
func resolve(state: StringName, frames: SpriteFrames = null, fallback: String = "") -> String:
	var wanted := _lookup(state)
	if frames == null:
		return wanted if not wanted.is_empty() else fallback
	if not wanted.is_empty() and frames.has_animation(wanted):
		return wanted
	if not fallback.is_empty() and frames.has_animation(fallback):
		return fallback
	return wanted if not wanted.is_empty() else fallback


static func _from_defaults(defaults: Dictionary) -> AnimMap:
	var m := AnimMap.new()
	m.names = defaults.duplicate()
	return m


static func _load_or_default(path: String, defaults: Dictionary) -> AnimMap:
	if ResourceLoader.exists(path):
		var r: Resource = load(path)
		if r is AnimMap:
			var m := r as AnimMap
			if m.names.is_empty():
				m.names = defaults.duplicate()
			return m
	return _from_defaults(defaults)


static func player_map() -> AnimMap:
	return _load_or_default(PLAYER_PATH, PLAYER_DEFAULTS)


static func enemy_map() -> AnimMap:
	return _load_or_default(ENEMY_PATH, ENEMY_DEFAULTS)

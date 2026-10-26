class_name HudSkin
extends Resource
## Restylable UI skin values (NOT art slots). Edit `assets/ui/hud_skin.tres`
## in the inspector or as text; no code changes needed. Panel/label styling
## lives in the Godot Theme `assets/ui/hud_theme.tres`.

const DEFAULT_PATH := "res://assets/ui/hud_skin.tres"

@export_group("Hearts & gold")
@export var heart_full: Color = Color(0.86, 0.16, 0.22)
@export var heart_empty: Color = Color(0.22, 0.12, 0.16)
@export var heart_outline: Color = Color(0.05, 0.02, 0.04)
@export var heart_size: float = 26.0
@export var gold_color: Color = Color(1.0, 0.78, 0.22)
@export var gold_outline: Color = Color(0.35, 0.22, 0.04)
@export var icon_size: float = 24.0
@export var pop_scale: float = 1.35
@export var pop_time: float = 0.18

@export_group("Selection ring")
## Ring colour per enemy type id (see FESignals.enemy_type_id). Unknown ids use `ring_default`.
@export var ring_colors: Dictionary = {
	"puppet_hand": Color(0.95, 0.35, 0.35),
}
@export var ring_default: Color = Color(0.95, 0.95, 0.85)
@export var ring_radius: Vector2 = Vector2(26, 9)
@export var ring_width: float = 2.5
## Y offset from the enemy origin to its feet line.
@export var ring_feet_offset: float = 26.0
## Faint glow on the selected enemy while the flashlight is off.
@export var dark_glow_energy: float = 0.45
@export var dark_glow_scale: float = 0.9

@export_group("Startle meter")
@export var startle_fill: Color = Color(1.0, 0.85, 0.3)
@export var startle_full: Color = Color(1.0, 0.25, 0.2)
@export var gauge_back: Color = Color(0.05, 0.04, 0.07, 0.8)
@export var startle_size: Vector2 = Vector2(36, 5)
@export var startle_head_offset: float = 44.0

@export_group("Pickup gauge")
@export var pickup_fill: Color = Color(0.55, 0.9, 1.0)
@export var pickup_radius: float = 12.0
@export var pickup_width: float = 4.0
@export var pickup_head_offset: float = 48.0

@export_group("Throw line")
@export var throw_clear: Color = Color(1.0, 1.0, 1.0, 0.65)
@export var throw_blocked: Color = Color(1.0, 0.2, 0.2, 0.85)
@export var throw_dash: float = 8.0

@export_group("Off-screen arrows")
@export var arrow_color: Color = Color(1.0, 0.3, 0.3)
@export var arrow_size: float = 22.0
@export var arrow_margin: float = 44.0
@export var arrow_gauge: Color = Color(1.0, 0.85, 0.3)

@export_group("Inventory strip")
@export var slot_size: float = 44.0
@export var slot_back: Color = Color(0.07, 0.05, 0.09, 0.85)
@export var slot_border: Color = Color(0.45, 0.38, 0.3)
@export var slot_selected: Color = Color(1.0, 0.85, 0.35)

@export_group("Camera nudge")
## Fraction of the distance to the selected enemy the camera leans toward.
@export var nudge_strength: float = 0.12
@export var nudge_max: float = 48.0
@export var nudge_speed: float = 4.0


func ring_color_for(type_id: String) -> Color:
	if ring_colors.has(type_id):
		return ring_colors[type_id]
	return ring_default


static func load_default() -> HudSkin:
	if ResourceLoader.exists(DEFAULT_PATH):
		var r = load(DEFAULT_PATH)
		if r is HudSkin:
			return r
	return HudSkin.new()

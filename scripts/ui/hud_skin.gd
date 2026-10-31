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

@export_group("Camera rig")
## Critically damped follow, seconds to (mostly) settle per axis. X ≈ the old Camera2D
## smoothing speed 6; Y is slower so a floor change (stairs) glides instead of lurching.
@export var camera_smooth_x: float = 0.18
@export var camera_smooth_y: float = 0.36
## Vertical follow speed cap (px/s): a big vertical step (teleport-sized) can't whip the view.
@export var camera_max_speed_y: float = 420.0


@export_group("Dark glints")
## Eye glints + dim silhouette on puppets OUTSIDE the flashlight light on dark stages
## (scripts/ui/dark_glints.gd, docs/DESIGN.md "Eye glint"). Art comes from the manifest slots below.
@export var glints_enabled: bool = true
## Calm / return puppets get the soft amber glint; every hunting state gets the ember one;
## a stunned puppet (eyes shut) gets none.
@export var glint_calm_slot: String = "vfx_eye_glint_calm"
@export var glint_hunting_slot: String = "vfx_eye_glint"
## Glint opacity. QA: at 40 % the blink / dim frames fail contrast, so DarkGlints never
## draws below GLINT_ALPHA_MIN whatever is set here.
@export_range(0.6, 1.0) var glint_alpha: float = 0.9
const GLINT_ALPHA_MIN := 0.6
## Faint flat silhouette of the puppet's current frame (unshaded) so its shape reads on near-black.
@export var silhouette_color: Color = Color(0.45, 0.55, 0.85)
@export_range(0.0, 1.0) var silhouette_alpha: float = 0.2
## Active when the stage ambient luminance (StageLook / the level's StageAmbient CanvasModulate)
## is BELOW this. StageTable: stage 4 ~0.17, stage 5 ~0.056, so 0.1 means stage 5 only (PD).
@export var dark_ambient_threshold: float = 0.1
## Until a level reports an ambient: active from this stage on.
@export var dark_fallback_stage: int = 5
## The flashlight's soft blob also counts as light within this fraction of its radius.
@export_range(0.0, 1.0) var blob_lit_fraction: float = 0.55

@export_group("Seed readout")
## Dim-looking but fully opaque text with a hard dark outline, readable over the stage 5 floor.
@export var readout_color: Color = Color(0.72, 0.70, 0.80, 1.0)
@export var readout_outline: Color = Color(0.02, 0.01, 0.04, 1.0)
@export var readout_outline_size: int = 5
@export var readout_shadow: Color = Color(0.0, 0.0, 0.0, 0.9)


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

@export_group("Screens")
## Merchant shop: offers rolled per visit.
@export var shop_offer_count: int = 4
## Art slots (PR #14 names). Missing slot → themed panel / placeholder shapes.
@export var shop_backdrop_slot: String = "shop_backdrop"
@export var merchant_slot: String = "merchant_idle"
@export var game_over_slot: String = "game_over_art"
## Win screen art (Designer, not merged yet); missing → game_over_slot styling → panel.
@export var win_slot: String = "win_screen_art"
@export var win_title_color: Color = Color(1.0, 0.8, 0.3)
@export var coin_slot: String = "gold_coin"
@export var sparkle_slot: String = "gold_pickup_sparkle"
## Merchant x / counter-top y in shop_backdrop pixels (320x180 still).
@export var merchant_x: float = 172.0
@export var counter_y: float = 110.0
@export var screen_dim: Color = Color(0.02, 0.01, 0.03, 0.82)
@export var title_color: Color = Color(0.85, 0.2, 0.2)
@export var rarity_colors: Dictionary = {
	# Designer's rarity palette (docs/DESIGN.md, item icon rims in PR #29).
	"common": Color("#b9b2c4"),
	"uncommon": Color("#5fd08a"),
	"rare": Color("#5aa8ff"),
	"epic": Color(0.8, 0.45, 1.0),   # not in BE's ItemDb; kept for safety
	"legendary": Color("#ffb640"),
}

@export_group("Alert HUD")
@export var alert_calm: Color = Color(0.75, 0.72, 0.68)
@export var alert_hot: Color = Color(1.0, 0.25, 0.2)
## Pips drawn up to this many enemies; beyond it the numbers carry it.
@export var alert_max_pips: int = 16

@export_group("Stage banner")
@export var banner_hold: float = 1.2
@export var banner_fade: float = 0.6

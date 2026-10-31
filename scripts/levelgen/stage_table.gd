class_name StageTable
extends RefCounted
## Per-stage content budget for LevelGenerator. Lead owns; Product tunes.
## Stage 1: 3 floors, ~3 screens wide (240 tiles = 3840px), exit on the top floor at the far
## end, nothing hostile within a screen of the start. Stages 2-5 scale width/floors/content
## until the difficulty pass. Enemy types t2..t5 have no script yet and build as puppet_hand
## with their table movement mode.
##
## Product call (Oct 25): stages 1-3 use only `walk` enemies (gravity, floors, stairs only).
## The `float` tier (slow drift through floors, the scary payoff) appears only at stages 4-5.
##
## Keys (all required per stage):
##   floors                  stacked floor bands (3-4; start on floor 0, exit on the top floor)
##   width_tiles             [min, max] level width in tiles (screen = 80 tiles = 1280px)
##   stairs_per_link         stairs between each pair of adjacent floors [min, max]
##   solid_wall_chance       chance an interior wall has NO doorway (forces a detour by stairs)
##   furniture_chance        per room: chance of a solid furniture block
##   tall_furniture_chance   share of furniture taller than 2 tiles (blocks walking; detour needed)
##   enemies / props / gold_piles / chests   the content budget: EXACT counts, every level
##                           gets all of them or it is rerolled
##   enemy_weights           type id (ENEMY_TYPES) -> weight
##   vase_ratio              share of props that are vases (rest are generic obstacles)
##   gold_amount             [min, max] gold per pile
##   gold_floor_min          (optional) guaranteed floor-pile total per level; the generator raises the smallest
##                           piles to reach it. Default piles x gold_amount min. PD: stage 1 = 6 (was 4)
##   safe_radius             no enemy within this many px of the start, any floor (>= 1280 = one screen)

## Enemy types. movement: `walk` = gravity + floors + stairs (LevelNav routes);
## `float` = drifts, ignores gravity, drifts through floor slabs (not blocked by slabs; BE PR #26). min_stage enforced by
## LevelGenerator: a type is never rolled before its min_stage.
const ENEMY_TYPES := {
	"puppet_hand": {script = "res://scripts/enemies/puppet_hand.gd", movement = &"walk", min_stage = 1},
	"t2": {script = "", movement = &"walk", min_stage = 2},
	"t3": {script = "", movement = &"walk", min_stage = 3},
	"t4": {script = "", movement = &"float", min_stage = 4},
	"t5": {script = "", movement = &"float", min_stage = 5},
}

## Stages per run (docs/PRODUCT.md: 5; clearing stage 5 wins). FE caps the run with this
## (FESignals.MAX_STAGES); a test keeps it equal to STAGES.size().
const STAGE_COUNT := 5

const STAGES := {
	1: {
		floors = 3, width_tiles = [232, 248], stairs_per_link = [2, 3],
		solid_wall_chance = 0.15, furniture_chance = 0.5, tall_furniture_chance = 0.0,
		enemies = 4, props = 18, gold_piles = 4, chests = 1,
		enemy_weights = {"puppet_hand": 1.0},
		vase_ratio = 0.6, gold_amount = [1, 3], gold_floor_min = 6,
		safe_radius = 1280.0,
	},
	2: {
		floors = 3, width_tiles = [272, 288], stairs_per_link = [2, 3],
		solid_wall_chance = 0.2, furniture_chance = 0.45, tall_furniture_chance = 0.0,
		enemies = 6, props = 22, gold_piles = 5, chests = 1,
		enemy_weights = {"puppet_hand": 0.8, "t2": 0.2},
		vase_ratio = 0.55, gold_amount = [2, 4],
		safe_radius = 1280.0,
	},
	3: {
		floors = 4, width_tiles = [312, 328], stairs_per_link = [2, 3],
		solid_wall_chance = 0.25, furniture_chance = 0.5, tall_furniture_chance = 0.12,
		enemies = 8, props = 28, gold_piles = 6, chests = 2,
		enemy_weights = {"puppet_hand": 0.6, "t2": 0.3, "t3": 0.1},
		vase_ratio = 0.5, gold_amount = [2, 5],
		safe_radius = 1280.0,
	},
	4: {
		floors = 4, width_tiles = [352, 368], stairs_per_link = [2, 3],
		solid_wall_chance = 0.3, furniture_chance = 0.5, tall_furniture_chance = 0.15,
		enemies = 10, props = 32, gold_piles = 7, chests = 2,
		enemy_weights = {"puppet_hand": 0.4, "t2": 0.3, "t3": 0.2, "t4": 0.1},
		vase_ratio = 0.5, gold_amount = [3, 6],
		safe_radius = 1280.0,
	},
	5: {
		floors = 4, width_tiles = [392, 408], stairs_per_link = [2, 3],
		solid_wall_chance = 0.35, furniture_chance = 0.5, tall_furniture_chance = 0.18,
		enemies = 12, props = 36, gold_piles = 8, chests = 3,
		enemy_weights = {"puppet_hand": 0.3, "t2": 0.25, "t3": 0.2, "t4": 0.15, "t5": 0.1},
		vase_ratio = 0.45, gold_amount = [4, 8],
		safe_radius = 1280.0,
	},
}


## Per-stage look (PRODUCT.md "Stage mood"): one table, applied by StageLook on build.
##   ambient            CanvasModulate colour: the light every canvas item gets without the flashlight
##   tint               modulate on the painted tiles and furniture sprites (warm -> cold)
##   flashlight_energy  multiplier on the flashlight Beam energy (lighter ambient -> 1.0)
## Stage 1 warm; every later stage darker (lower ambient luminance) and colder (blue share rises);
## stage 5 is nearly black, so the flashlight is the main light.
const LOOKS := {
	1: {ambient = Color(0.50, 0.42, 0.34), tint = Color(1.00, 0.93, 0.80), flashlight_energy = 1.0},
	2: {ambient = Color(0.38, 0.33, 0.31), tint = Color(1.00, 0.96, 0.90), flashlight_energy = 1.0},
	3: {ambient = Color(0.27, 0.26, 0.30), tint = Color(0.95, 0.97, 1.00), flashlight_energy = 1.1},
	4: {ambient = Color(0.15, 0.17, 0.24), tint = Color(0.85, 0.93, 1.00), flashlight_energy = 1.3},
	5: {ambient = Color(0.045, 0.055, 0.10), tint = Color(0.80, 0.90, 1.00), flashlight_energy = 1.6},
}


## Look for `stage`, clamped to 1..5 (a copy).
static func look(stage: int) -> Dictionary:
	return (LOOKS[clampi(stage, 1, LOOKS.size())] as Dictionary).duplicate(true)


## Content budget for a stage: {enemies, props, gold, chests}.
static func budget(stage: int) -> Dictionary:
	return budget_of(params(stage))


static func budget_of(P: Dictionary) -> Dictionary:
	return {enemies = int(P.get("enemies", 0)), props = int(P.get("props", 0)),
			gold = int(P.get("gold_piles", 0)), chests = int(P.get("chests", 0))}


## Guaranteed floor-pile gold total for a level built with params P (PD gold floor).
static func gold_floor_min(P: Dictionary) -> int:
	var ga: Array = P.get("gold_amount", [1, 1])
	return maxi(int(P.get("gold_floor_min", 0)), int(P.get("gold_piles", 0)) * int(ga[0]))


## Worst-roll total gold of a level (PD "Gold floor"): its floor piles plus the guaranteed part of
## vases (each hides gold only with p 0.45, so 0 at worst) and chests (they give an item, `gold_inside` 0).
static func worst_roll_gold(L: Dictionary) -> int:
	var t := 0
	for g in L.get("gold", []):
		t += int(g.amount)
	return t


## Cheapest offer the shop after `stage` can show: min ItemDb.shop_price over the stage's pool.
static func cheapest_shop_price(stage: int) -> int:
	var best := 1 << 30
	for id in ItemDb.pool_for_stage(stage):
		best = mini(best, ItemDb.shop_price(id, stage))
	return best


## Params for `stage`, clamped to 1..5. Deep copy so callers can override keys.
static func params(stage: int) -> Dictionary:
	var s := clampi(stage, 1, STAGES.size())
	return (STAGES[s] as Dictionary).duplicate(true)


static func stage_count() -> int:
	return STAGE_COUNT


## Type info with safe defaults for unknown ids.
static func enemy_type(id: String) -> Dictionary:
	var t: Dictionary = ENEMY_TYPES.get(id, ENEMY_TYPES["puppet_hand"])
	return t


static func movement_for(id: String) -> StringName:
	return enemy_type(id).get("movement", &"walk")


## EnemyDef for a type id (unknown ids -> puppet_hand). A fresh resource per call.
static func enemy_def(id: String) -> EnemyDef:
	var key := id if ENEMY_TYPES.has(id) else "puppet_hand"
	var t: Dictionary = ENEMY_TYPES[key]
	var d := EnemyDef.new()
	d.type_id = StringName(key)
	d.movement = t.get("movement", &"walk")
	d.min_stage = int(t.get("min_stage", 1))
	d.script_path = script_for(key)
	return d


## Script to instance for a type; types without their own script yet use puppet_hand.
static func script_for(id: String) -> String:
	var s: String = enemy_type(id).get("script", "")
	return s if s != "" and ResourceLoader.exists(s) else str(ENEMY_TYPES["puppet_hand"].script)

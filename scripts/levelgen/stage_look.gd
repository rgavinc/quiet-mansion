class_name StageLook
extends RefCounted
## Applies StageTable.look(stage) to a built level: a CanvasModulate for the ambient light, a
## warm/cold tint on the painted tiles and furniture sprites, and a flashlight Beam boost so the
## flashlight stays the main light on the dark stages, and (dark stages) a faint StageRim on floor edges,
## stair rails and furniture tops so the level stays navigable outside the cone. Purely visual. Lead owns.
##
## `StageLook.ambient` (float 0..1, 1 = full light) is the ambient brightness of the stage on screen:
## the luminance of that stage's CanvasModulate colour (StageTable.ambient_level), strictly decreasing
## from stage 1 (~0.43) to stage 5 (~0.06). apply() sets it when a level is built (it stays at that
## value until the next build); `StageLook.ambient_of(stage)` reads it for any stage without a level,
## and the built level carries it as meta "ambient". Front End reads it to decide when to draw eye
## glints (e.g. glints only below some threshold). Read-only for everyone else.

## Ambient brightness of the stage on screen, 0..1 (1 = full light); 1.0 before any level is built.
static var ambient: float = 1.0

const AMBIENT_NODE := "StageAmbient"
const TILE_LAYERS := ["TilesBack", "TilesStairs", "TilesFront"]


## Ambient brightness (0..1, 1 = full light) of any stage, without building it.
static func ambient_of(stage: int) -> float:
	return StageTable.ambient_level(stage)


## `layout` (the built level's layout) feeds the rim; without it no rim is drawn.
static func apply(level: Node2D, stage: int, player: Node = null, layout: Dictionary = {}) -> Dictionary:
	var look := StageTable.look(stage)
	ambient = StageTable.ambient_level(stage)
	level.set_meta("ambient", ambient)
	StageRim.build(level, layout, float(look.get("rim_alpha", 0.0)))
	var amb := level.get_node_or_null(AMBIENT_NODE) as CanvasModulate
	if amb == null:
		amb = CanvasModulate.new()
		amb.name = AMBIENT_NODE
		level.add_child(amb)
	amb.color = look.ambient
	for n in TILE_LAYERS:
		var l := level.get_node_or_null(n) as CanvasItem
		if l:
			l.modulate = look.tint
	var furn := level.get_node_or_null(FurnitureSkin.ROOT) as CanvasItem
	if furn:
		furn.modulate = look.tint
	if player:
		var beam := player.get_node_or_null("Flashlight/Beam") as PointLight2D
		if beam:
			if not beam.has_meta(&"base_energy"):
				beam.set_meta(&"base_energy", beam.energy)
			beam.energy = float(beam.get_meta(&"base_energy")) * float(look.flashlight_energy)
	level.set_meta("stage_look", look)
	return look

class_name StageLook
extends RefCounted
## Applies StageTable.look(stage) to a built level: a CanvasModulate for the ambient light, a
## warm/cold tint on the painted tiles and furniture sprites, and a flashlight Beam boost so the
## flashlight stays the main light on the dark stages. Purely visual. Lead owns.

const AMBIENT_NODE := "StageAmbient"
const TILE_LAYERS := ["TilesBack", "TilesStairs", "TilesFront"]


static func apply(level: Node2D, stage: int, player: Node = null) -> Dictionary:
	var look := StageTable.look(stage)
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

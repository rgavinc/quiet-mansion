extends Node
## NoiseBus — every sound event goes through here. Each source decides its own radius
## (WorldObject.noise_radius). Enemies listen regardless of being on screen; the light
## never reaches off screen, but noise does.

signal noise(at: Vector2, radius: float, loudness: float, source: Node)

## Default radius for a breakable: a bit more than half the 1280px screen, so a break
## reaches slightly off screen.
const DEFAULT_RADIUS := 760.0


func emit_noise(at: Vector2, radius: float = DEFAULT_RADIUS, loudness: float = 1.0, source: Node = null) -> void:
	if radius <= 0.0:
		return
	var gs := get_node_or_null(^"/root/GameState")
	if gs and gs.game_over:
		return
	# Item hooks (e.g. Greedy Sack: vase breaks are louder).
	var ps := get_node_or_null(^"/root/PlayerStats")
	if ps and ps.has_method(&"noise_hook_mult"):
		var m: float = ps.noise_hook_mult(at, radius, loudness, source)
		radius *= m
		loudness *= m
	noise.emit(at, radius, loudness, source)
	if gs:
		gs.noise_made.emit(loudness, at)  # legacy listeners (HUD status text)


func can_hear(listener_pos: Vector2, at: Vector2, radius: float, hearing_mult: float = 1.0) -> bool:
	return listener_pos.distance_to(at) <= radius * hearing_mult

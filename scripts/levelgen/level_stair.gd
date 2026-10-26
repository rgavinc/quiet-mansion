class_name LevelStair
extends Stair
## Lead (#13): the Stair node a generated level uses. Same as BE's Stair except where the
## climb can be entered from the UPPER floor: only from the top landing side (where the upper
## floor actually meets the stair top), never from the gallery side across the slab opening.
## BE's trigger covers the whole run on both bands, so a boy on the gallery slab behind the
## far rail wall pressing down was "inside" it and got approached kinematically across the
## opening (QA B2). Lower-floor entry and on-the-line re-grab are unchanged. The boy's
## controller and the no-LevelNav enemy fallback both ask `is_near`/`contains`, so this is
## a data-side fix: no BE file changes.

## How far onto the top landing (px) an upper-floor entry may start: the 3-tile landing.
const LANDING_REACH := 48.0


func contains(p: Vector2) -> bool:
	if on_line(p):
		return super.contains(p) or _on_top_landing(p)   # on the stairs / its top end: BE behaviour
	return upper_entry_ok(global_bottom(), global_top(), p) and (super.contains(p) or _on_top_landing(p))


## Upper band (above the stair's half-height) entry is allowed only from the top landing side:
## x at or beyond the stair top (rising right: x >= top.x - 1; rising left mirrored) and
## within LANDING_REACH of it, or already on the stair line. Lower band: unchanged.
static func upper_entry_ok(b: Vector2, t: Vector2, p: Vector2) -> bool:
	if p.y > (b.y + t.y) * 0.5:
		return true
	var d := signf(t.x - b.x)   # +1 rising right
	return (p.x - t.x) * d >= -1.0


func _on_top_landing(p: Vector2) -> bool:
	var t := global_top()
	var d := signf(t.x - global_bottom().x)
	var along := (p.x - t.x) * d
	return along >= -1.0 and along <= LANDING_REACH and p.y <= t.y + 2.0 and p.y >= t.y - absf(t.y - global_bottom().y)

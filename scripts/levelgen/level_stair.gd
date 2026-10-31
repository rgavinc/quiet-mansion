class_name LevelStair
extends Stair
## Generated-level stair (Lead): BE's Stair with the trigger cut to the two floors it joins.
## BE's trigger rect spans one rise above the top end and includes its top edge, so a boy
## standing on the floor ABOVE a stacked stair counted as "in" it and down walked him
## kinematically through the solid slab (QA #13 b1). Here, off the stair line:
##  * upper floor (to_floor band, feet <= top.y + 2 and below the next slab): only on the top
##    landing side (never over the hole), within LANDING_REACH of the top end;
##  * lower floor (from_floor band): BE's run-wide trigger;
##  * anything at or above the slab of the floor above the top is never inside.
## entry_t follows the same bands, so down only ever starts from this stair's own top landing.

const LANDING_REACH := 48.0
const SLAB_PX := 16.0


func contains(p: Vector2) -> bool:
	return contains_pts(global_bottom(), global_top(), p, on_line(p), super.contains(p))


## Pure form for tests / probes: `line` = on the stair line, `base` = inside BE's trigger rect.
static func contains_pts(b: Vector2, t: Vector2, p: Vector2, line: bool, base: bool) -> bool:
	var rise := absf(t.y - b.y)
	if p.y <= t.y - rise + SLAB_PX:   # the floor above this stair's top (or its slab): never
		return false
	if line:
		return base or top_landing(b, t, p)
	if p.y <= t.y + 2.0:   # upper floor band
		return upper_entry_ok(b, t, p) and (base or top_landing(b, t, p))
	return base   # lower floor band


## Kept for callers/tests from round 1: true when p is not on the hole side of the top end.
static func upper_entry_ok(b: Vector2, t: Vector2, p: Vector2) -> bool:
	if p.y > t.y + 2.0:
		return true
	var d := signf(t.x - b.x)
	return (p.x - t.x) * d >= -1.0


static func top_landing(b: Vector2, t: Vector2, p: Vector2) -> bool:
	var d := signf(t.x - b.x)
	var along := (p.x - t.x) * d
	var rise := absf(t.y - b.y)
	return along >= -1.0 and along <= LANDING_REACH and p.y <= t.y + 2.0 and p.y > t.y - rise + SLAB_PX


func _on_top_landing(p: Vector2) -> bool:
	return top_landing(global_bottom(), global_top(), p)


## Off the line: the top end only from the upper floor band, else the bottom end.
func entry_t(p: Vector2) -> float:
	if on_line(p):
		return t_at(p)
	return 1.0 if p.y <= global_top().y + 2.0 else 0.0

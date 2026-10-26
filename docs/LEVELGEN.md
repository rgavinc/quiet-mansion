# Level layout contract (Lead owns; generator builds to this)

All numbers are in pixels unless noted. Tile = 16px.

## Floors
- A level is 1-4 floors stacked vertically. Each floor band is 10 tiles (160px) tall.
- The bottom tile row of each band is the floor slab: solid StaticBody2D / TileMap collision on physics layer 1 (`world`).
- Ceiling: the slab of the floor above. The top floor gets its own 1-tile ceiling.
- Floor N's walkable surface y = level_origin_y - N * 160 (N = 0 is ground floor).

## Movement constants (from PlayerStats)
- gravity 980 px/s^2 (project setting `physics/2d/default_gravity`).
- jump_velocity 320 -> apex ~52px (3.25 tiles). Clears a 2-tile (32px) prop, never a puppet, never a floor.

## Rooms
- A room is 20-40 tiles wide, one floor tall. Rooms on the same floor join through a doorway 3 tiles high in the shared wall.
- Room kits from Designer: width multiple of 4 tiles, height exactly 10 tiles, floor slab included, doorway gaps at x=0 and x=width on rows 6-8 (counted from top, 0-based).

## Stairs
- The only way between floors. An `Area2D` in group `stairs`, 4 tiles wide. The climb rises exactly one floor (160px), from the lower slab top to the upper slab top. The trigger area covers both bands (lower band + upper band = 320px tall) so you can enter it from either floor. `from_floor` = lower floor index, `to_floor` = from_floor + 1; the generator sets both and the validator uses them to build the floor graph.
- Player presses up/down inside it to climb (boy_climb_stairs anim); jump is disabled while climbing.

## Enemies
- Default movement is `walk`: gravity, floor collision, and they change floors only via stairs (same floor graph as the player).
- `EnemyDef.movement = &"float"` is reserved for a later-stage type (stage 4+) that ignores gravity but is still blocked by slabs and walls.

## Generator guarantees (validator rejects + rerolls, fallback to known-good layout after 20 tries)
- Exit is reachable from start using walk + stairs only (no forced jump over anything taller than 2 tiles, no forced pickup/throw).
- Every stair connects two existing floors.
- No enemy spawn within 1 screen (480px) of the start, or in line of sight of it.
- Same seed + stage always yields the same level.

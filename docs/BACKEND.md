# Backend — Quiet Mansion (round 1)

## Owned

| Path | Role |
|------|------|
| `scripts/autoload/game_state.gd` | Exit win, caught lose, noise bus, 3 puppets |
| `scripts/player/player_controller.gd` | WASD + knock (Space/RMB) |
| `scripts/player/flashlight.gd` | Mouse-aim cone |
| `scripts/enemies/enemy_base.gd` | `Enemy` base: state machine, senses, walk/float movement, stairs, hits |
| `scripts/enemies/puppet_hand.gd` | Type 1 (`puppet_hand`): an `Enemy` that only sets its type id and art slots |
| `scripts/world/obstacle.gd` | Break → `make_noise` |
| `scripts/world/exit_zone.gd` | Reach → win |
| `scripts/map/main.gd` | Round 1 layout wiring |

## Loop

Noise alerts puppets within hear radius. Knocking a calm puppet has a 50% kill chance; miss or enraged miss escalates. More noise while chased can wake the rest.

## PlayerStats (redesign foundation, step 1)
- Autoload `PlayerStats` (`scripts/autoload/player_stats.gd`) is the only place player numbers live (`BASE` dict).
- Read: `PlayerStats.get_stat(&"pickup_time")`. Items change stats only via `add_modifier(stat, add, mul, source)` / `remove_modifiers_from(source)`.
- Health: 3 hits (`take_hit`) = `died` + `GameState.on_caught()`. Gold: `add_gold`, `try_spend`.
- Signals for FE: `health_changed(current, max)`, `gold_changed(current, delta)`, `stat_changed(stat, value)`, `died`.
- Input map actions (no hard-coded keys): `move_left/right/up/down`, `jump` (Space), `flashlight_toggle` (RMB toggle), `interact` (LMB: tap < `tap_threshold` = throw, hold = pickup), `inv_next`/`inv_prev` (wheel).

## NoiseBus, WorldObject, Inventory, pickup and throw (foundation step 2)
- `NoiseBus.emit_noise(at, radius, loudness, source)`: every sound goes here. Enemies hear it if they're inside `radius`, on screen or not. `DEFAULT_RADIUS` is 760px, slightly past the screen edge.
- `WorldObject` (`scripts/world/world_object.gd`) is the base for all props. Override the defaults in a subclass `_init()`: `can_pick_up`, `throwable`, `breakable`, `break_on_touch`, `noise_radius`, `pickup_time_mult`, `gold_inside`, `blocks_throws`, `art_slot`.
- `Vase` is pickable and throwable, uses the default radius, and has a 45% chance of 1 to 3 gold. `obstacle.gd` is a generic breakable that can't be picked up.
- Player: a LMB tap throws the held item at `FESignals.selected_enemy`. With empty hands, a tap knocks over the nearest prop you're facing. Holding LMB longer than `tap_threshold` starts a pickup that lasts `pickup_time * pickup_time_mult`. During a pickup you can't move or toggle the light. The pickup cancels if you leave range, get hit, or let go. The wheel cycles the `Inventory` (capacity is `inventory_slots`).
- A thrown object flies at the target. Physics bodies (walls) and props with `blocks_throws` stop it. It always shatters with its own noise radius where it stops, so a miss is still loud. A calm puppet that gets hit dies, and an enraged one is stunned for 1.5s.
- Hovering the mouse over a lit puppet selects it through `FESignals.select_enemy`. The selection stays when the light goes off.
- Not done yet: the jump and gravity wait for Lead's floor layout.

## Items, shop and chests
- `Item` (`scripts/items/item.gd`, a Resource) has `id`, `display_name`, `description`, `icon_slot`, `price`, `rarity` and `mods` (`[{stat, add, mul}]`). `apply()` and `remove()` only call `PlayerStats.add_modifier` / `remove_modifiers_from`. Each instance uses its own source key (`item:<id>#<instance>`), so two copies stack and come off separately. A second `apply()` does nothing. `to_dict()` gives the FE offer fields.
- `ItemDb` (`scripts/items/item_db.gd`) is the single table: 20 trade-off items. Each one has at least one upside and one downside, and only uses stats that gameplay reads. `ItemDb.make(id)` returns a fresh instance.
- Rarity: common (weight 60, stage 1+), uncommon (30, 1+), rare (14, 2+), legendary (6, 4+).
- `Shop.roll_stock(stage, seed) -> Array[Item]` returns 4 different items, weighted by rarity and gated by stage. The same (stage, seed) always gives the same stock. FE shows the first `shop_offer_count` (3).
- `Shop.buy(item) -> bool` spends through `try_spend`. It then marks the item `sold` and calls `PlayerStats.grant_item` (apply + add to `owned_items` + `items_changed`). It returns false and changes nothing if gold is short or the item is already sold or applied.
- `PlayerStats.owned_items`: items stay owned across Continue (PlayerStats is an autoload). `reset()` clears them along with every modifier. Signal: `items_changed(items)`. Helpers: `owns(id)` and `has_minimap()`.
- Max health: a higher max heals by the same amount. A lower max only clamps current health, so it never costs you an extra heart.
- New MIN floors keep stacked downsides sane: move_speed 60, climb_speed 30, pickup_range 16, light_range 80, light_angle_deg 10, light_detect_mult / noise_mult 0.2, gold_find_mult 0.1.
- `Chest` (`scripts/world/chest.gd`, a WorldObject) opens through the normal LMB hold channel (`pickup_time × 1.5`), even when the inventory is full, via the new `WorldObject.on_hold_complete(by)` hook. It opens only once. It grants one item from `ItemDb.roll_chest(stage, seed)`. The seed is `loot_seed`, or a hash of run seed + stage + position. It also adds `gold_inside` and swaps the art from `prop_chest_closed` to `prop_chest_open`. It makes a creak: `DEFAULT_RADIUS × 0.5 × noise_mult`, loudness 0.6. Signal: `opened(item)`.
- Stats waiting on other work: `light_detect_mult` and `light_startle_time` only matter once the enemy state machine (PR #26) lands. Nothing draws a minimap yet: FE should show it when `PlayerStats.has_minimap()` (or `stat_changed(&"minimap", ...)`).

## Jump, stairs, animation (foundation step 3)
- `PlayerController.side_scroll` turns on gravity (`PlayerStats.gravity` 980), the Space jump (`jump_velocity` 320, about 52px, so you can't jump to the floor above), and stairs. The generator sets it to true. The old top-down map leaves it off.
- `Stair` (`scripts/world/stair.gd`) is an `Area2D` with local `bottom` and `top` points. Up or down anywhere inside its trigger enters `CLIMB` (see "Stairs" below), you move along the line at `climb_speed`, and you step off at either end. There's no jumping during pickup or climbing.
- The boy, the puppet and the exit door get their animations only from manifest slots through `AnimLibrary` (`boy_idle/run/jump/pickup/carry/throw/climb_stairs/hurt`, `puppet_calm/startle/chase`, `exit_door`). No BE script loads an art path anymore.

## Enemy state machine (`scripts/enemies/enemy_base.gd`, `class_name Enemy`)
Every enemy type is an `Enemy` subclass (or a plain `Enemy` with an `EnemyDef`) that overrides only what differs. `puppet_hand.gd` is type 1 and only sets `type_id`, `movement` and its three art slots.

| State | What it does | Leaves when |
|------|------|------|
| `CALM` | Idles / patrols `patrol_radius` around `home`. Light on it builds `startle` 0→1 over `PlayerStats` `light_startle_time` (1.0 s); light off resets it to 0. | startle hits 1 → `STARTLED`; a noise in range → `CHASE` |
| `STARTLED` | Plays `puppet_startle` once and holds the last frame; waits `startle_reaction_time` (0.35 s). | → `CHASE` |
| `CHASE` | Runs at `chase_speed` to the boy. Memory stays 1 while it sees him or while a noise / light lets it track him without sight (`noise_track_time` 3 s, `light_track_time` 1 s). | loses him → `SEARCH`; lands a hit → `RECOVER`; throw → `STUNNED` |
| `SEARCH` | Goes to `last_known`; `memory` drains, faster the farther the boy is: rate = `(1 / memory_time) * clamp(distance / give_up_distance, 0.25, 4)`. | sees / hears him → `CHASE`; memory 0 → `RETURN` |
| `RETURN` | Walks home (counts as calm: light can startle it, a throw kills it). | home → `CALM` |
| `RECOVER` | After a landed hit: shoves the boy `shove_distance`, backs off at `backoff_speed` for `recover_time` (1.5 s) and can't hit. | → `CHASE` / `SEARCH` |
| `STUNNED` | A throw hit a non-calm enemy: stands still `stun_time` (1.5 s), holding the startle frame. | → `CHASE` / `SEARCH` |

- Noise (`NoiseBus.noise`, radius × `hearing_mult`) is worse than light: instant `CHASE` for every enemy in range, so several chase at once. A calm enemy hit by a throw or knock dies; any other one is stunned.
- Hits: only the `Hitbox` `Area2D` (`hit_radius` 18) overlapping the boy, in `CHASE` / `SEARCH`. Bodies stay solid (layers world 1 / player 2 / enemy 4).
- Off-screen enemies run the same `_physics_process`; nothing depends on rendering.
- `is_chasing()` = from chase start until give-up or death (CHASE, SEARCH and the RECOVER / STUNNED pauses inside it). `enraged` (legacy, FE polls it) returns the same value.

### Tunables (exports; an `EnemyDef` can set any of them)
`type_id, movement, walk_speed 45, chase_speed 95, float_speed 45, climb_speed 80, hear_radius, hearing_mult 1, sight_range 560, memory_time 4, give_up_distance 900, noise_track_time 3, light_track_time 1, startle_reaction_time 0.35, recover_time 1.5, backoff_speed 60, stun_time 1.5, patrol_radius 0, shove_distance 48, hit_radius 18, anim_calm / anim_startle / anim_chase`.

### EnemyDef plug-in
Set `def` (any `Resource`) before the enemy enters the tree. `apply_def()` copies every field in `DEF_FIELDS` the resource actually has, duck-typed, so an `EnemyDef` class (not written yet) just has to use these names. `movement = &"float"` (stage 4+) makes the enemy ignore gravity and drift straight through slabs and walls; its chase art is `<anim_chase>_float` (`puppet_chase_float`) when the manifest has that slot, else `anim_chase`.

### FE signals (all from BE now)
- `FESignals.report_startle(enemy, 0..1)` whenever startle changes (1 on `STARTLED`, 0 on chase).
- `FESignals.report_chase(enemy, true)` on chase start; `false` on give-up (`RETURN`) and in `_exit_tree` (death / level unload), so FE never keeps a freed enemy.
- `FESignals.report_chase_memory(enemy, memory)` every hunting frame (1 while tracking, draining in `SEARCH`).
- `GameState.puppet_alerted(count)` fires whenever an enemy starts or stops chasing. `GameState.chasing_count()` / `enemy_count()` / `alerted_puppets` are live counts from group `enemies`. There's no `PUPPET_COUNT` cap anymore.

### Floors and stairs (walk movement, side-scroll)
- Gravity from `PlayerStats.gravity`; floor changes only by stairs, on and off screen.
- With Lead's `LevelNav.current` set (PR #13), the enemy asks `nav.next_waypoint(me, target)` and climbs the stair it names. Without it (unit tests, the old map) it scans group `stairs` for the nearest stair toward the target's floor. `LevelNav` is looked up by path, so this compiles before and after #13. `nav_override` is a test hook.
- `Stair` trigger = an `Area2D` rectangle derived only from `bottom` / `top`: x = the stair's run, y = from one rise above the top down to the lower slab (320 px for a 160 px rise). Any width or angle works (4 tiles now, 15 tiles per PRODUCT.md). Player and enemies use the same `Stair.trigger_rect()`. Entering anywhere in it walks you along the floor to the stair end first (no snap), then climbs.
- Top-down (`side_scroll` off) enemies move freely in 2D with no gravity.

### Test hooks and tests
`sight_override`, `lit_override`, `floor_override` (-1 real, 0/1 forced) and `nav_override`. Tests: `tests/test_enemy_fsm.gd` (sync, `tick()`), `tests/scene_enemy.gd` (real physics: hit back-off, walker gravity + stairs, walker without stairs, float through floors). A check that hits a runtime script error counts as failed.

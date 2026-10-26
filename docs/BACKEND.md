# Backend — Quiet Mansion (round 1)

## Owned

| Path | Role |
|------|------|
| `scripts/autoload/game_state.gd` | Exit win, caught lose, noise bus, 3 puppets |
| `scripts/player/player_controller.gd` | WASD + knock (Space/RMB) |
| `scripts/player/flashlight.gd` | Mouse-aim cone |
| `scripts/enemies/puppet_hand.gd` | Hear noise → enrage → chase / catch |
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
- `Stair` (`scripts/world/stair.gd`) is an `Area2D` with local `bottom` and `top` points. Up or down while you're on it enters `CLIMB`, you move along the line at `climb_speed`, and you step off at either end. There's no jumping during pickup or climbing.
- The boy, the puppet and the exit door get their animations only from manifest slots through `AnimLibrary` (`boy_idle/run/jump/pickup/carry/throw/climb_stairs/hurt`, `puppet_calm/startle/chase`, `exit_door`). No BE script loads an art path anymore.

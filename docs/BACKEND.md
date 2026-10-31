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
- Player: a LMB tap throws the held item at `FESignals.selected_enemy`. With empty hands, a tap knocks over the nearest prop you're facing. Holding LMB longer than `tap_threshold` starts a pickup that lasts `pickup_time * pickup_time_mult`. During a pickup you can't move or toggle the light. The pickup cancels if you leave range, get hit, or let go, and a cancel ends the press completely (`_cancel_pickup` clears the held flag and time): even with the button still down, nothing resumes; a new press starts from 0 (PRODUCT.md "Holds", first-look blocker). The wheel cycles the `Inventory` (capacity is `inventory_slots`).
- A thrown object flies at the target. Physics bodies (walls) and props with `blocks_throws` stop it. It always shatters with its own noise radius where it stops, so a miss is still loud. A calm puppet that gets hit dies, and an enraged one is stunned for 1.5s.
- Hovering the mouse over a lit puppet selects it through `FESignals.select_enemy`. The selection stays when the light goes off.
- Not done yet: the jump and gravity wait for Lead's floor layout.

## Items, shop and chests
- `Item` (`scripts/items/item.gd`, a Resource) has `id`, `display_name`, `description`, `icon_slot`, `price`, `rarity` and `mods` (`[{stat, add, mul}]`). `apply()` and `remove()` only call `PlayerStats.add_modifier` / `remove_modifiers_from`. Each instance uses its own source key (`item:<id>#<instance>`), so two copies stack and come off separately. A second `apply()` does nothing. `to_dict()` gives the FE offer fields.
- `ItemDb` (`scripts/items/item_db.gd`) is the single table: 20 trade-off items (14 stat items + 6 behaviour items, see below). Each one has at least one upside and one downside, and only uses stats that gameplay reads. `ItemDb.make(id)` returns a fresh instance.
- Rarity: common (weight 60, stage 1+), uncommon (30, 1+), rare (14, 2+), legendary (6, 4+).
- `Shop.roll_stock(stage, seed) -> Array[Item]` returns 4 different items, weighted by rarity and gated by stage, each priced `ItemDb.shop_price(id, stage)` (see Gold economy). The same (stage, seed) always gives the same stock. The shop shows all 4 offers (`STOCK_SIZE`; FE #34).
- `Shop.buy(item) -> bool` spends through `try_spend`. It then marks the item `sold` and calls `PlayerStats.grant_item` (apply + add to `owned_items` + `items_changed`). It returns false and changes nothing if gold is short or the item is already sold or applied.
- `PlayerStats.owned_items`: items stay owned across Continue (PlayerStats is an autoload). `reset()` clears them along with every modifier. Signal: `items_changed(items)`. Helpers: `owns(id)` and `has_minimap()`.
- Max health: a higher max heals by the same amount. A lower max only clamps current health, so it never costs you an extra heart.
- Stat caps (PRODUCT.md "Stat caps"): `PlayerStats.STAT_BOUNDS` is the one table, a `[min, max]` per multiplier stat on its effective value (all items stacked) relative to base; `PlayerStats.clamp_mult(stat, m)` applies it. `get_stat` clamps the BASE stats; the hook dispatchers clamp the rest, and for noise and move speed the bound is on stat × hook (Greedy Sack's vase noise, Heavy Vases' carry slow).

  | Stat | min | max | Effective range |
  |---|---|---|---|
  | `noise_mult` (+ `on_noise` hooks) | ×0.3 | ×3.0 | PD's numbers |
  | `light_range` | ×0.5 | ×2.0 | 130–520 px |
  | `light_detect_mult` | ×0.3 | ×3.0 | startle takes 3.3× to 0.33× as long |
  | `move_speed` (+ `carry_speed_mult` hooks) | ×0.5 | ×2.0 | 70–280 px/s |
  | `climb_speed` | ×0.4 | ×2.5 | 36–225 px/s |
  | `pickup_time` | ×0.3 | ×3.0 | 0.3–3 s (× the target's `pickup_time_mult`) |
  | `pickup_range` | ×0.5 | ×2.0 | 20–80 px |
  | `gold_find_mult` | ×0.25 | ×3.0 | |
  | `give_up_speed` (`memory_drain_mult` hooks, no BASE row) | ×0.3 | ×3.0 | searching enemies' memory drain |
  | `stun_mult` (Heavy Vases, ×2 per copy) | ×0.5 | ×2.5 | PD: ×2.5 total whatever the copies (1 copy ×2, 2+ copies ×2.5) |
  | `item_noise_mult` (`on_noise` hooks: Greedy Sack vase break, ×1.5 per copy) | ×0.5 | ×2.0 | then `noise_mult` above on stat × hooks |
  | `item_carry_mult` (`carry_speed_mult` hooks: Heavy Vases, ×0.85 per copy) | ×0.7 | ×1.0 | then `move_speed` above on stat × hooks |

  Stacked behaviour effects (PD): every behaviour effect that multiplies across copies has a row above, bounding the product of all copies. `stun_mult` is clamped in `PlayerStats.dispatch_throw` after the hooks write it and again in `Enemy.on_hit_by_throw` where the stun is computed. `item_noise_mult` / `item_carry_mult` are clamped in `noise_hook_mult` / `carry_speed_mult`, and Cracked Mirror's ×1.4 off-screen drain uses `give_up_speed`. Effects that don't multiply: Greedy Sack gold (it only fills empty vases), Cracked Mirror arrow distance (min), and Flash Bulb / Rabbit's Foot / Music Box (one copy per event).

  Additive stats keep the absolute `MIN` floors (max_health 1, pickup_time 0.1 s, tap_threshold 0.05 s, light_startle_time 0.2 s, inventory_slots 1, light_angle_deg 10). Tests: each bound stat stacked 10× at ×2 / ×0.5 lands exactly on its own max / min; 10 Greedy Sacks / Cracked Mirrors / Heavy Vases clamp through the hooks; every stat an item multiplies must have a bound.
- Item text: `desc` in ItemDb holds tokens, not numbers, for every percentage; `ItemDb.describe(row)` fills them from the row's own mods / params (`{mul:stat}` = \|mul−1\|, `{inv:stat}` = \|1/mul−1\| for time-based effects like `light_detect_mult` ×0.6 → "67% longer", `{add:stat}`, `{param:key}` = \|param−1\|). `test_items` rejects hand-written "N%" and checks every % against the effect measured through PlayerStats with the item granted.
- `Chest` (`scripts/world/chest.gd`, a WorldObject) opens through the normal LMB hold channel (`pickup_time × 1.5`), even when the inventory is full, via the new `WorldObject.on_hold_complete(by)` hook. It opens only once. It grants one item from `ItemDb.roll_chest(stage, seed)`. The seed is `loot_seed`, or a hash of run seed + stage + position. It also adds `gold_inside` and swaps the art from `prop_chest_closed` to `prop_chest_open`. It makes a creak: `DEFAULT_RADIUS × 0.5 × noise_mult`, loudness 0.6. Signal: `opened(item)`.
- Stats waiting on other work: `light_detect_mult` and `light_startle_time` only matter once the enemy state machine (PR #26) lands. Nothing draws a minimap yet: FE should show it when `PlayerStats.has_minimap()` (or `stat_changed(&"minimap", ...)`).

## Item behaviour hooks (`be/item-behaviors`)
Behaviour items are ItemDb rows with `script` (an `Item` subclass in `scripts/items/behaviors/`), `params` (every tunable; scripts read only `params`), optional `charges` (uses per stage) and `downside_behavior` (the cost is in the hook, not a stat mod). `ItemDb.make()` loads the script, deep-copies `params`, sets `max_charges`/`charges`.

Hooks on `Item` (base = no-op) and where they are dispatched (all iterate `PlayerStats.owned_items`):

| Hook | Dispatcher | Called from |
|---|---|---|
| `on_stage_start(player)` | `PlayerStats.begin_stage(player)` (refills charges first, then emits `items_changed` once) | end of `PlayerController._ready` (every stage builds a fresh player: main.gd and #13's LevelGenerator both) |
| `on_hit(amount) -> int` (≤0 cancels) / `on_lethal_hit() -> bool` | inside `PlayerStats.take_hit` | enemy hits |
| `on_throw(item_dict, target)` (may write into the dict) | `PlayerStats.dispatch_throw` | `PlayerController._throw` (throw_at / throw_toward) and `_try_knock` |
| `on_noise(at, radius, loudness, source) -> mult` | `PlayerStats.noise_hook_mult` | `NoiseBus.emit_noise` (scales radius and loudness) |
| `on_startle(enemy) -> bool` (true = handled, no chase) | `PlayerStats.startle_handled` | `Enemy.tick` STARTLED → chase |
| `on_vase_gold(gold, vase) -> int` | `PlayerStats.vase_gold` | `WorldObject.break_apart` and `thrown_object._shatter` (vases only, `Item.is_vase`) |
| `carry_speed_mult(held) -> mult` | `PlayerStats.carry_speed_mult` | `PlayerController.move_speed()` |
| `memory_drain_mult(enemy, off_screen) -> mult` | `PlayerStats.memory_drain_mult` | `Enemy._tick_hunt` SEARCH drain (`Enemy.is_off_screen()`: \|dx\|>640 or \|dy\|>360 from the boy) |
| `arrow_reveal_distance() -> float` | `PlayerStats.arrow_reveal_distance()` (min over items; `INF` with none) | FE off-screen arrows |

Charges: `Item.charges` / `max_charges` (0/0 for plain items; also in `to_dict()`). `use_charge()` / `set_charges()` re-emit `PlayerStats.items_changed(owned_items)`; so does `begin_stage`. Stacked copies: each copy has its own charges (the FE tile sums them, e.g. 1/2), and one event spends at most one copy. `on_lethal_hit` / `on_startle` stop at the first item that handles the event (Rabbit's Foot, Flash Bulb). `on_throw` goes to every item, so Music Box spends only when the thrown dict is its OWN lure (`owns_lure`: the lure id is per instance). Tests: Music Box ×2 (QA repro), Rabbit's Foot ×2, Flash Bulb ×4. Hooks without charges (on_noise, carry, give-up, Heavy Vases' stun tag) stack as passive effects, bounded per effect by `STAT_BOUNDS` (see Stat caps). Vase gold doesn't stack.

| Item | Rarity | Base price | Upside | Cost | Tunables (`params`) |
|---|---|---|---|---|---|
| Rabbit's Foot `rabbits_foot` | rare | 14 | first lethal hit each stage leaves 1 heart (1 charge) | -1 max heart | — |
| Music Box `music_box` | uncommon | 9 | each stage starts with a lure in hand (charge = lure in hand); thrown (at the ringed enemy, or 320 px in the FACING direction, `Vector2(facing, 0)`, with none ringed — never the last mouse aim) it lands (`MusicBoxLure`) and pulses a noise every 0.5 s for 4 s; hearers SEARCH toward the lure, not the boy (`Enemy.hear_lure`) | takes a hand slot until thrown; doesn't kill/stun | lure_time 4, lure_interval 0.5, lure_radius 900, lure_loudness 1.2, world_slot |
| Heavy Vases `heavy_vases` | common | 6 | vase throw/knock stun ×2 (`stun_mult` in the dict) | move ×0.85 while any vase is held | stun_mult 2, carry_speed_mult 0.85 |
| Flash Bulb `flash_bulb` | rare | 14 | once per stage a completed startle stuns 2.5 s, then CALM (no chase, no FE chase report) | light_range ×0.9 | stun_time 2.5 |
| Cracked Mirror `cracked_mirror` | uncommon | 9 | off-screen SEARCH memory drains ×1.4 | arrows hidden beyond 1280 px | offscreen_drain_mult 1.4, arrow_reveal_distance 1280 |
| Greedy Sack `greedy_sack` | legendary | 22 | empty vases roll 1–3 gold | vase-break noise ×1.5 | gold_min 1, gold_max 3, noise_mult 1.5 |

Removed (PD's binding decision): dim_filter, lucky_coin, strong_arm, wide_lens, spring_socks, golden_heart. Their icons stay in the manifest as spares. Pool mix is exactly 6 common / 7 uncommon / 5 rare / 2 legendary (`ItemDb.MIX`, asserted in `test_items`); no kept item changed rarity. Extra Heart's cost changed from noise ×1.15 to climb ×0.85. Noise budget: only sneakers, grandfather_watch and greedy_sack pay with louder noise, and it is their only downside (test enforces ≤3 noise-cost items).

| Rarity | Items (base price) |
|---|---|
| common (6) | bright_bulb 7, soft_shoes 7, quick_hands 6, sneakers 6, banister_gloves 5, heavy_vases 6 |
| uncommon (7) | extra_heart 10, minimap 12, big_pockets 10, thick_sweater 9, gold_magnet 11, music_box 9, cracked_mirror 9 |
| rare (5) | night_eyes 15, ghost_slippers 16, grandfather_watch 15, rabbits_foot 14, flash_bulb 14 |
| legendary (2) | shadow_cloak 26, greedy_sack 22 |

Art: the Music Box uses ONE slot, `music_box_world` (Designer PR #30), in flight and landed (`MusicBoxLure.add_visual`: AnimatedSprite2D via AnimLibrary with the manifest pivot, or an amber 12×10 ColorRect when the slot is missing). Icons are `item_icon_<id>`; FE's letter tile covers missing ones.

## Gold economy — PROVISIONAL (pending Lead's per-stage numbers from the #13 sweep)
Model (`StageTable` stages 1–5 as of #13 @316edf3; Monte Carlo, 20k runs): ground floor = rand(rooms_min..max) rooms of 5–10 units × 4 tiles; every floor has the same width; props per room = round(width_tiles × prop_density); a prop is a vase with p = vase_ratio; a vase holds gold with p 0.45, amount 1–3; loose piles = count × rand(amount range); chests give items, not gold; gold_find_mult 1. Lead's rework (≥3 floors / ~240 tiles on stage 1) will raise these.

Everything collected:

| Stage | Vases | Vase gold | Pile gold | Mean | p10 | p90 | Cumulative mean |
|---|---|---|---|---|---|---|---|
| 1 | 9.0 | 8.1 | 6.0 | 14.1 | 9 | 20 | 14.1 |
| 2 | 12.4 | 11.1 | 12.0 | 23.2 | 17 | 30 | 37.2 |
| 3 | 19.0 | 17.1 | 17.5 | 34.6 | 26 | 44 | 71.9 |
| 4 | 24.7 | 22.2 | 27.0 | 49.2 | 40 | 59 | 121.1 |
| 5 | 33.0 | 29.6 | 42.0 | 71.6 | 60 | 84 | 192.7 |

Prices: offer = round(row price × `ItemDb.PRICE_SCALE[shop-1]`), `PRICE_SCALE = [1.1, 1.6, 2.2, 2.9]` for the shops after stages 1–4 (stage 5 is the win; no shop). Retune that one array (or row prices) when real numbers land. Check with "realistic" income = all piles + ~50% of vase gold, 4-offer stock rolled with the real weights:

| Shop | Realistic income mean (p10–p90) | Mean offer | Mean cheapest of 4 | P(afford ≥1 from this stage's gold) | P(≥1 with carry, buying the cheapest each shop) |
|---|---|---|---|---|---|
| 1 | 10.1 (7–14) | 8.7 | 6.7 | 0.92 | 0.92 |
| 2 | 17.6 (13–22) | 13.6 | 9.5 | 1.0 | 1.0 |
| 3 | 26.1 (20–32) | 18.6 | 12.7 | 1.0 | 1.0 |
| 4 | 38.1 (32–45) | 25.4 | 16.5 | 1.0 | 1.0 |

So ≈1 item per shop (income / mean offer 1.16, 1.29, 1.40, 1.50); a rare (shop 2: 22–26 g, shop 3: 31–35 g) or legendary (shop 4: 64–75 g) needs saving across shops. (Scale was lowered from [1.2, 1.8, 2.5, 3.3] when the 6/7/5/2 mix made the average offer pricier.) Greedy Sack adds ≈1.1 g per vase (≈+27 g on stage 4, +36 on stage 5) but can only be bought at shop 4, where little is left to spend on — flag for Designer. Script: re-run the Monte Carlo with the real per-stage numbers and adjust `PRICE_SCALE` so income/mean offer ≈ 1.2–1.5.

## Jump, stairs, animation (foundation step 3)
- `PlayerController.side_scroll` turns on gravity (`PlayerStats.gravity` 980), the Space jump (`jump_velocity` 320, about 52px, so you can't jump to the floor above), and stairs. The generator sets it to true. The old top-down map leaves it off.
- `Stair` (`scripts/world/stair.gd`) is an `Area2D` with local `bottom` and `top` points. Up or down anywhere inside its trigger enters `CLIMB` (see "Stairs" below), you move along the line at `climb_speed`, and you step off at either end. There's no jumping during pickup or climbing.
- The boy, the puppet and the exit door get their animations only from manifest slots through `AnimLibrary` (`boy_idle/run/jump/pickup/carry/throw/climb_stairs/hurt`, `puppet_calm/startle/chase`, `exit_door`). No BE script loads an art path anymore.

## Enemy state machine (`scripts/enemies/enemy_base.gd`, `class_name Enemy`)
Every enemy type is an `Enemy` subclass (or a plain `Enemy` with an `EnemyDef`) that overrides only what differs. `puppet_hand.gd` is type 1 and only sets `type_id`, `movement` and its three art slots.

| State | What it does | Leaves when |
|------|------|------|
| `CALM` | Idles / patrols `patrol_radius` around `home`. Light on it builds `startle` 0→1 over `PlayerStats` `light_startle_time` (1.0 s); light off resets it to 0. | startle hits 1 → `STARTLED`; a noise in range → `CHASE` |
| `STARTLED` | Plays `puppet_startle` once and holds the last frame; waits `startle_delay()`: the scream animation's length (manifest `frames / fps`, 7 / 14 = 0.5 s for the puppet), so the chase starts as the scream ends. | → `CHASE` |
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
`type_id, movement, walk_speed 45, chase_speed 95, float_speed 45, climb_speed 80, hear_radius, hearing_mult 1, sight_range 560, memory_time 4, give_up_distance 900, noise_track_time 3, light_track_time 1, startle_reaction_time 0 (= use the startle anim length), recover_time 1.5, backoff_speed 60, stun_time 1.5, patrol_radius 0, shove_distance 48, hit_radius 18, anim_calm / anim_startle / anim_chase`.

### Startle → chase delay
`startle_delay()` = `startle_reaction_time` when it's > 0 (a per-type override in an `EnemyDef`, in seconds). At 0 or below (the default) it's `Enemy.startle_anim_length(anim_startle)` = the slot's `frames / fps` from `ASSETS_MANIFEST.toml` via `AnimLibrary`, so re-timing the scream art re-times the chase with no code change. A missing slot, or one with no frames or fps, falls back to `STARTLE_FALLBACK_TIME` (0.5 s). Measured on real frames: lit 1.00 s → `STARTLED`, then `CHASE` 30 frames (0.50 s) later.

### Ledge backstop (walkers)
Lead's stair-opening rail (#13) is the real fix; this is a backup that holds anywhere. Every frame a grounded side-scroll walker moves, `_ledge_ahead()` casts a ray straight down just ahead of its feet (half its collider width + 2 px + this frame's step) against `LAYER_WORLD`, from `LEDGE_PROBE_LIFT` (4 px) above the feet to `LEDGE_PROBE_DEPTH` (24 px) below them. No floor there means a floor edge or opening, so:
- `CALM` patrol turns back (`_patrol_dir` flips).
- `CHASE`, `SEARCH`, `RETURN` and the `RECOVER` back-off stop at the edge (`velocity.x = 0`, `ledge_stopped = true`) and never step off; they change floors only by stairs. A boy across a gap is waited for, and `SEARCH` memory drains as usual.
- Not applied within ~one body width of a stair entry it's heading for (the stair top sits at the opening), to floaters, to top-down enemies, or when `floor_override` is set (sync tests have no slabs).

### Feet come from the real collider (QA B1)
`_feet()` is the bottom-centre of the enemy's movement `CollisionShape2D` (its first enabled direct `CollisionShape2D` child with a shape), computed with the shape's global transform: `cs.global_transform * (0, half_height)`. Half extents come from `shape_half_extents()`: circle radius, capsule `height / 2` (height includes the caps), rectangle `size / 2`. So it's right both for a shape centred on the origin (the old map, older tests) and for Lead's generator, which puts the circle at `(0, -r)` so the origin is the feet. With no collider, the feet are the origin.
- `_feet()` drives the ledge ray, the stair trigger checks (`s.contains(feet)`, `rect.has_point(feet)`, the entry-x checks), the `LevelNav` and own-floor lookups (`next_waypoint(feet, ...)`, `floor_of(feet)`), the goal-x steering and the climb (`_tick_climb` moves the feet, then sets `global_position = feet - _feet_offset()`).
- `_feet_offset()` = feet − origin. `_foot()` (still used by tests) is now its y: 14 for a centred r=14 circle, 0 for the generator's.
- `_foot_half_width()` is the shape's half width (circle/capsule radius, rect half x), scaled.
- Before the fix, an offset shape put the ray start 10 px inside the slab, so `_ledge_ahead()` was true every frame and every generated walker froze; stair feet checks were 14 px low.

### Sprite anchored to the real feet
The manifest pivot is the art's feet, so `_play()` sets `Anim.offset = AnimLibrary.offset_for(slot) + _feet_offset()` (origin -> feet from the collider, same math as `_feet()`), for every slot, walkers and floaters. A centred r=14 circle (tests, the old map, #13's generator) puts the feet 14px below the origin; without the term the art floated 14px. `tick()` re-applies the offset if the collider changes after `_ready`. Pivot row 63 sinks the bottom art row 1px into the floor. Tests: `sprite_feet_*`, `sprite_art_bottom_pixel_on_floor_*` in `tests/scene_enemy.gd` (pivot lands on the collider bottom for centred and (0,-14) shapes; the lowest opaque PNG row of every slot sits within 1px of the slab top).

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
`sight_override`, `lit_override`, `floor_override` (-1 real, 0/1 forced) and `nav_override`. Tests: `tests/test_enemy_fsm.gd` (sync, `tick()`), `tests/scene_enemy.gd` (real physics: hit back-off, walker gravity + stairs, walker without stairs, float through floors, startle → chase on real frames, walker turns at a floor gap while a floater crosses it; and, for a centred collider and one offset to `(0,-14)` with the origin at the feet: flat-floor chase moves >150 px in 600 frames with `ledge_stopped` false on most frames, the gap holds, and a stair climb ends with the collider bottom on the upper floor within 1 px). A check that hits a runtime script error counts as failed.

# FRONTEND — Quiet Mansion (round 1)

## Owns
- Flashlight feel (mouse aim, cone + `PointLight2D` blob), floor/darkness presentation, HUD copy/alerts
- Backend owns puppets, noise, obstacles, exit trigger scripts

## Player UX
- **WASD** move, **mouse** aims flashlight
- On-screen hint (exact text, `HINT` in `scripts/map/main.gd`): `Space jump · RMB flashlight on/off · hold LMB pick up · tap LMB throw/knock · scroll items`
- **RMB** toggles the light. **Tap LMB** throws the held item at the ringed enemy, or knocks a prop in range with empty hands (noisy, can wake puppets). **Hold LMB** picks up
- Reach the exit without being caught
- Watermark while any art/audio in `ASSETS_MANIFEST.toml` is still `ai`

## Replace art
FE code never loads an art file by path. It asks for a manifest **slot** (`UiArt.texture(slot)` → `AnimLibrary.meta(slot).path`): floor tiles = `floor_dark`, flashlight blob = `flashlight_blob`, UI = `ui_*` / `icon_*`. Overwrite manifest paths in place. Labeled stills: `assets/replace_me/boy_side_idle.png`, `boy_mid_jump.png`, `puppet_hand_calm.png`, `puppet_hand_enraged.png`. See `docs/DESIGN.md`.

## Web / Pages
Export preset **`Web`** lives in `export_presets.cfg` (tracked for CI). Actions runs `godot --export-release "Web" build/web/index.html` on push to `main`. Renderer is **GL Compatibility** for WebGL 2.

---

# Checkpoint 1 HUD & overlays (FE, Oct 25)

Everything FE draws listens to **one adapter**, `scripts/ui/fe_signals.gd`
(autoload `FESignals`). Back End's foundation (`PlayerStats`, `NoiseBus`,
`Enemy` state machine, pickup/throw, `Inventory`) is **not on `development`
yet**, so every signal below is a **placeholder** marked `TODO(BE-wire)` in
that file. Wired for real: `_wire_backend()` explicitly connects `PlayerStats.health_changed` / `gold_changed` (autoload order puts `PlayerStats` before `FESignals`) and reads `light_startle_time`, `pickup_time`, `tap_threshold`. BE's `player_controller` calls `FESignals.set_flashlight(on)` on every RMB toggle (PR #4). FE adds no input fallback; ring, glow and startle meter react to that call. When BE lands, only `FESignals._wire_backend()` changes; widgets stay
as they are.

## Pieces and what they listen to

| Piece | Script / scene | Listens to (`FESignals`) | Notes |
|---|---|---|---|
| Hearts + gold | `scripts/ui/health_gold_hud.gd` (in `scenes/ui/hud.tscn`) | `health_changed(current, max_hp)`, `gold_changed(amount, delta)` | Max hearts follow `max_hp`. Panels/labels styled by `assets/ui/hud_theme.tres`; pop on change |
| Inventory strip | `scripts/ui/inventory_strip.gd` (in `hud.tscn`) | `inventory_changed(items)`, `inventory_selected(index)` | Items are `{id, slot, name, throwable}`. Icon by slot name (`icon_<slot>` then `<slot>`), letter placeholder if not in the manifest. Empty inventory shows one dim slot and never indexes |
| Off-screen chaser arrows | `scripts/ui/offscreen_arrows.gd` (in `hud.tscn`) | `chasing` list (via `chase_changed`), `chase_memory_changed(enemy, ratio)` | Gauge = BE chase memory if reported, else `1 - distance / give_up_distance`. Arrows stack when several share an edge |
| Selection ring | `scripts/ui/selection_ring.gd` (in `scenes/ui/world_overlay.tscn`) | `enemy_selected(enemy)`, `flashlight_toggled(on)` | One at a time. Stays when light is off; selected enemy gets a faint `PointLight2D` glow while dark. Colour = `HudSkin.ring_colors[type_id]`, else `ring_default` |
| Startle meter | `scripts/ui/startle_meter.gd` (spawned per enemy by `world_overlay.gd`) | `startle_progress(enemy, 0..1)` | Placeholder: `FESignals.report_lit(enemy, lit)` integrates over `startle_time` (1.0 s). Shown only while the light is on; `set_flashlight(false)` hides and resets it at once |
| Camera nudge | `scripts/ui/camera_nudge.gd` (in `world_overlay.tscn`) | `selected_enemy` (pulled) | Eases `Camera2D.offset` toward the selected enemy (`nudge_strength`, capped at `nudge_max`) and back |
| Pickup gauge | `scripts/ui/pickup_gauge.gd` (in `world_overlay.tscn`) | `pickup_started`, `pickup_progress(0..1)`, `pickup_cancelled`, `pickup_completed` | Radial over the boy (group `player`). Shows the moment BE sends `pickup_started`, which `player_controller` only does after LMB passes `PlayerStats.tap_threshold` (0.2 s), so a tap never shows it. No extra FE delay. The fill is the `pickup_progress` BE reports. Red shake-fade on cancel |
| Throw line | `scripts/ui/throw_line.gd` (in `world_overlay.tscn`) | `selected_enemy`, `selected_item()` | Shown exactly when `FESignals.can_throw()`: holding something and an enemy is ringed, hidden otherwise. Physics ray (excluding boy and target) → red + X where a wall/prop blocks |

| Alert counter | `scripts/ui/alert_hud.gd` (in `hud.tscn`, top-right under the watermark) | `chase_changed` + 10 Hz poll of `chasing_count()` / `enemy_total()` | "Chasing N / M", **no cap**. Pips up to `alert_max_pips` (16, two rows), numbers only beyond that. Registry = groups `enemies` ∪ `puppets`; chasing = `report_chase` once BE sends any, else each enemy's `is_chasing()` / `enraged` |
| Stage banner | `scripts/ui/stage_banner.gd` (in `hud.tscn`) | `stage_started(n)` + once per level load (deferred) | "Stage N" card: fade in 0.25 s, hold `banner_hold`, fade `banner_fade` |
| Game over | `scenes/ui/game_over.tscn` (`scripts/ui/game_over.gd`) | `player_died` (REAL: `PlayerStats.died`) | Pauses the tree. No continues: dying ends the run. Shows stage reached, gold and the **run** seed (hidden when the level has no `level_seed`). **New run** (primary) = stage 1, fresh stats, new seed (`level_seed = -1` → the level rolls one). **Retry seed** (secondary) = stage 1, fresh stats, the same run seed, never the stage you died on; disabled when there is no seed. Art `game_over_art`, text/buttons on the right half; no slot → dim + themed panel on the right half |
| Stage clear + shop | `scenes/ui/shop.tscn` (`scripts/ui/shop.gd`) | `stage_cleared(stage)` (REAL: `GameState.reached_exit` on stages 1–4) | Pauses the tree. `shop_offer_count` (3) offers from `get_shop_offer`; buy → `buy_offer`; SOLD state; "Not enough gold" feedback; empty source → message, no errors. Continue → `next_stage()`. Art `shop_backdrop` + animated `merchant_idle` at backdrop x=172 / counter y=110; offers in the left column, title/gold/Continue in the right column, so the merchant band is clear. Coin `gold_coin` (spinning), buy sparkle `gold_pickup_sparkle`, icons by `icon_slot`. Every slot falls back (themed panels, drawn merchant, drawn coin, letter tile) |
| Win screen | `scenes/ui/win_screen.tscn` (`scripts/ui/win_screen.gd`) | `run_won(stage)` (REAL: `GameState.reached_exit` on stage `MAX_STAGES` = 5) | Shown **instead of** the shop after stage 5 (docs/PRODUCT.md "Run end"). Pauses the tree, captures the mouse. Shows the run seed, gold, stages cleared and run time (unpaused play), and one primary **New run** (same as game over: `PlayerStats.reset()`, stage 1, `level_seed = -1`). Art `win_screen_art` (Designer, dark right half), else `game_over_art`, else dim + themed panel; text on the right half |

**Screens and input.** Screens are their own `CanvasLayer` (layer 20, `PROCESS_MODE_ALWAYS`) outside `HudRoot`, so HUD stays mouse-ignore while a screen's root is `MOUSE_FILTER_STOP` and eats clicks. Opening pauses `get_tree()`, closing unpauses, and freeing an open screen unpauses too. Base class `UiScreen` (`scripts/ui/ui_screen.gd`).

**Shop adapter (`FESignals`).** Offers mirror BE's `Item` exactly: `{id, display_name, description, icon_slot, price, rarity, item}` (`item` = the real Item, or null for stubs). `get_shop_offer(count)` calls `Shop.roll_stock(stage, seed) -> Array[Item]` if a `/root/Shop` autoload or a global class `Shop` exists, else `shop_stub` (demo only), else `[]`. `buy_offer(offer)` calls `Shop.buy(item) -> bool` when the Shop is there (BE spends via `PlayerStats.try_spend` and applies), else `try_spend(price)` (PlayerStats when wired) and `item.apply()`. TODO(BE-wire): once `Shop` is on development the class lookup can become a direct call.

**Run flow.** `get_stage()` / `get_seed()` read the level scene's `stage` / `level_seed` exports (PR #13 `main.gd`), else an FE stage counter and seed -1 (hidden). `restart_run(seed)` always starts a fresh run at stage 1: `PlayerStats.reset()` (3 hearts, 0 gold, all item modifiers cleared) plus the FE inventory. `get_run_seed()` is the run's seed (in PR #13 `level_seed` is the run seed and each stage's level = run seed + stage), captured once and kept through `next_stage()`, which loads stage + 1 of the same run seed.

**Carry-over between stages (docs/PRODUCT.md).** Shop Continue **keeps** hearts (incl. max), gold and bought/chest items (they are `PlayerStats` modifiers, which `next_stage()` never resets). Held props (vases etc.) belong to the level and are **dropped**: the player's `Inventory` lives in the level scene, so re-instancing empties it, and the FE inventory mirror is cleared. Only a new run (`restart_run`) resets stats.

**Run length.** `FESignals.MAX_STAGES = 5` is the one FE cap (TODO(Lead): point at the stage/difficulty table, e.g. PR #13 `StageTable.stage_count()`, once it is on development). `on_reached_exit()` routes `GameState.reached_exit` to `stage_cleared` (shop) on stages 1–4 and `run_won` (win screen) on stage 5. Repeat exit triggers on the same level are ignored, `next_stage()` at stage 5 ends the run instead of loading, and `_swap_scene` refuses any stage outside 1..5, so stage 6 can never load.

 Both reset GameState, re-instance the current scene file with `level_seed` / `stage` set when those properties exist, and unpause. `announce_stage(n)` lets BE / the generator re-show the banner. `stage_cleared` stays on `GameState.reached_exit` (Lead: no separate stage-complete signal).

**Enemy lifetime (QA #18):** `FESignals` tracks every enemy it references (`tree_exiting`, one-shot) and drops its selection, lit, startle, chase and chase-memory entries the moment it dies or is freed. `_process` also prunes anything already freed. Widgets read `FESignals.get_selected_enemy()` (never a freed node) and check `is_instance_valid()` on untyped values before typed assignment, so the ring, startle meter, camera nudge, throw line and off-screen arrows just let go of a dead enemy.

World overlays draw in a follow-viewport `CanvasLayer`, so the level's
`CanvasModulate` darkness never hides them.

## Using it in a level
The real game `scenes/main.tscn` already does this: `HUD` (hud.tscn), `GameOver` and `Shop` at the root, `World/WorldOverlay`, `AIWatermark` top-right. The old text HUD is gone; `main.gd` keeps one themed hint/status line.

1. `FESignals` is an autoload (already in `project.godot`).
2. Instance `scenes/ui/hud.tscn`, `scenes/ui/game_over.tscn` and `scenes/ui/shop.tscn` once at the scene root.
3. Instance `scenes/ui/world_overlay.tscn` under the world node. The boy must be in group `player`, and the camera is the viewport's current `Camera2D`.
4. BE calls `FESignals.set_health / set_gold / select_enemy / report_lit or report_startle / report_chase / report_chase_memory / report_pickup_* / set_items / select_item`, or connects its own signals to them in `_wire_backend()`.

Enemy type id for ring colours comes from `get_type_id()`, then a `type_id` property, then `enemy_type` meta, then group `puppets` → `puppet_hand`.

## Restyle without code
- `assets/ui/hud_skin.tres` (`HudSkin`): heart/gold colours, ring colours per enemy type, gauge colours/sizes, arrow size and margin, inventory slot size, camera nudge strength.
- `assets/ui/hud_theme.tres` (Godot Theme): panel style box, label font colour and outline, the `HudSlot` and `HudSlotSelected` slot styles.
- Optional art slots. If one of these is added to `ASSETS_MANIFEST.toml` (as `ai` first), the UI uses it instead of the drawn placeholder: `ui_heart_full`, `ui_heart_empty`, `ui_gold`, and `icon_<item slot>`. FE added **no PNGs** in this PR, so the manifest and watermark are unchanged.

## Input map (Product names)
`jump` (Space), `flashlight_toggle` (RMB), `interact` (LMB: hold = pickup, tap < 0.2 s = throw or knock), `inv_next` (wheel down), `inv_prev` (wheel up), plus `move_left/right/up/down`. The `[input]` block is copied byte-for-byte from BE PR #1 (`be/player-stats`), so the two PRs merge cleanly. The round-1 `player_controller.gd` still hard-codes its keys (BE-owned).

## Demo
`scenes/ui/hud_demo.tscn` fakes BE so you can see every piece: A/D to move, aim with the mouse, RMB for the light, hold LMB on a vase to pick it up, tap LMB to throw (holding + ringed) or knock a vase (empty hands), scroll the wheel to switch items. Debug-only keys: H hit, J heal, G +gold, C send the far enemy chasing, K die (game over), E reach the exit (shop, or the win screen on stage 5), R reset. The demo shop uses 5 **placeholder** items (`PLACEHOLDER_ITEMS` in `hud_demo.gd`, PR #14 icon slots) via `FESignals.shop_stub`; the real game has no stub.

## Tests
`tests/test_fe_ui.gd` is in `tests/run_tests.gd`. It covers hearts/max, gold, empty-safe inventory and wrap-around, ring colour lookup and default, single selection, the ring persisting with the light off (with glow), startle timing, pickup cancel hiding the gauge, edge-arrow clamping, the nudge cap, throw ray blocking, and the input actions existing. Also: throw line only when holding and ringed, the pickup gauge showing at once on `pickup_started` with the fill following BE progress, a real `player_controller` tap never showing it while a hold does, the flashlight toggle, the startle meter hiding on `set_flashlight(false)`, hearts and gold wired to a real `PlayerStats`, `main.tscn` having HUD/WorldOverlay/watermark plus the exact hint, manifest slots resolving, and no hard-coded art paths in FE scripts. Screens: game over opens on `PlayerStats.died` and pauses (text on the right half, seed hidden with no seed, themed fallback with no art); the shop opens on `GameState.reached_exit`, a buy deducts via `PlayerStats.try_spend`, is sold out after, and is rejected without enough gold; the adapter calls a BE-shaped `Shop.roll_stock` / `buy`; an empty item source logs no errors; the shop panels stay clear of the merchant at x=172; the alert count reaches 7/12, 12/12 and 25/25 and drops freed enemies; the banner shows and fades; and `main.tscn` has GameOver/Shop/WinScreen with mouse-ignore HUD additions. No continues (against `tests/fixtures/fake_level.tscn`, a PR #13-shaped level): New run and Retry seed both give stage 1, 3/3 hearts, 0 gold, no item modifiers and an empty inventory; New run rolls a different seed, Retry seed replays the run seed (even if the level reported a different per-stage seed); Retry seed is disabled with no seed; shop Continue keeps the run seed, hearts and gold. Win / run length: the stage 5 exit opens the win screen (paused, mouse-capturing, seed + gold on the right half, art slot `win_screen_art` → `game_over_art` → panel) and not the shop; stages 1–4 open the shop, played through the real Continue button 1→5; a double or stale trigger on stage 5 (GameState re-fired, `next_stage`, a direct stage-6 swap) never advances and opens the win screen once; win **New run** gives stage 1 with fresh stats and a new seed; Continue drops held props (the level's `Player/Inventory` and the HUD mirror) and keeps gold, hearts and bought max-heart modifiers.

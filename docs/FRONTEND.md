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

**Enemy lifetime (QA #18):** `FESignals` tracks every enemy it references (`tree_exiting`, one-shot) and drops its selection, lit, startle, chase and chase-memory entries the moment it dies or is freed. `_process` also prunes anything already freed. Widgets read `FESignals.get_selected_enemy()` (never a freed node) and check `is_instance_valid()` on untyped values before typed assignment, so the ring, startle meter, camera nudge, throw line and off-screen arrows just let go of a dead enemy.

World overlays draw in a follow-viewport `CanvasLayer`, so the level's
`CanvasModulate` darkness never hides them.

## Using it in a level
The real game `scenes/main.tscn` already does this: `HUD` (hud.tscn) at the root, `World/WorldOverlay`, `AIWatermark` top-right. The old text HUD is gone; `main.gd` keeps one themed hint/status line.

1. `FESignals` is an autoload (already in `project.godot`).
2. Instance `scenes/ui/hud.tscn` once at the scene root.
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
`scenes/ui/hud_demo.tscn` fakes BE so you can see every piece: A/D to move, aim with the mouse, RMB for the light, hold LMB on a vase to pick it up, tap LMB to throw (holding + ringed) or knock a vase (empty hands), scroll the wheel to switch items. Debug-only keys: H hit, J heal, G +gold, C send the far enemy chasing, R reset.

## Tests
`tests/test_fe_ui.gd` is in `tests/run_tests.gd`. It covers hearts/max, gold, empty-safe inventory and wrap-around, ring colour lookup and default, single selection, the ring persisting with the light off (with glow), startle timing, pickup cancel hiding the gauge, edge-arrow clamping, the nudge cap, throw ray blocking, and the input actions existing. Also: throw line only when holding and ringed, the pickup gauge showing at once on `pickup_started` with the fill following BE progress, a real `player_controller` tap never showing it while a hold does, the flashlight toggle, the startle meter hiding on `set_flashlight(false)`, hearts and gold wired to a real `PlayerStats`, `main.tscn` having HUD/WorldOverlay/watermark plus the exact hint, manifest slots resolving, and no hard-coded art paths in FE scripts.

# DESIGN — Quiet Mansion (round 1)

Style: Dead Cells / fancy modern SNES — full-color creepy, flashlight as bright focus. ~64×64 characters, ~32×32 tiles.

## Replace loop
1. Open `assets/replace_me/` — labeled stills (`boy_side_idle`, `boy_mid_jump`, `puppet_hand_calm`, `puppet_hand_enraged`, …).
2. Overwrite the matching `assets/art/...` path from `ASSETS_MANIFEST.toml`.
3. Flip `status` to `"human"`. Watermark stays until art+audio are all human.

## Slots
| Slot | Path | Size | Notes |
|------|------|------|-------|
| boy_side_idle | art/characters/boy_side_idle.png | 64² | side view + flashlight |
| boy_mid_jump | art/characters/boy_mid_jump.png | 64² | mid-air |
| puppet_hand_calm | art/characters/puppet_hand_calm.png | 64² | friendly float |
| puppet_hand_enraged | art/characters/puppet_hand_enraged.png | 64² | mouth + teeth |
| exit_door | art/props/exit_door.png | 64² | round exit |
| floor_dark | art/tiles/floor_dark_32.png | 32² | mansion floor |

### Animated / strip slots (status = "ai", templates in `assets/replace_me/<slot>_template.png`)
| Slot | Path | Size | Notes |
|------|------|------|-------|
| boy_idle | art/characters/boy_idle.png | 64² | 6f @8fps loop, pivot [32, 63]: idle loop |
| boy_run | art/characters/boy_run.png | 64² | 8f @12fps loop, pivot [32, 63]: run cycle |
| boy_jump | art/characters/boy_jump.png | 64² | 4f @10fps, pivot [32, 63]: takeoff/rise/apex/fall |
| boy_pickup | art/characters/boy_pickup.png | 64² | 6f @10fps loop, pivot [32, 63]: crouch-reach loop, hand_points |
| boy_carry | art/characters/boy_carry.png | 64² | 6f @10fps loop, pivot [32, 63]: carry walk, hand_points |
| boy_throw | art/characters/boy_throw.png | 64² | 4f @12fps, pivot [32, 63]: overhead throw, hand_points |
| boy_climb_stairs | art/characters/boy_climb_stairs.png | 64² | 8f @10fps loop, pivot [32, 60]: stairs up-right, pivot y=60 |
| boy_hurt | art/characters/boy_hurt.png | 64² | 3f @12fps, pivot [32, 63]: hit flash + knock-back |
| puppet_calm | art/characters/puppet_calm.png | 64² | 6f @8fps loop, pivot [32, 63]: calm float, finger lag, blink |
| puppet_startle | art/characters/puppet_startle.png | 64² | 7f @14fps, pivot [32, 63]: hero startle: anticipation, flash+smear impact, jaw splits, teeth, red glint; hold frame 6 |
| puppet_chase | art/characters/puppet_chase.png | 64² | 8f @14fps loop, pivot [32, 63]: enraged snap loop, claws, red rim |
| vase_idle | art/props/vase_idle.png | 32² | still, pivot [16, 31]: standing |
| vase_thrown | art/props/vase_thrown.png | 32² | 4f @16fps loop, pivot [16, 16]: spin, centre pivot |
| vase_shatter_enemy | art/props/vase_shatter_enemy.png | 32² | 6f @14fps, pivot [16, 31]: breaks on enemy |
| vase_shatter_wall | art/props/vase_shatter_wall.png | 32² | 6f @14fps, pivot [16, 31]: breaks on wall |
| gold_coin | art/props/gold_coin.png | 16² | 6f @12fps loop, pivot [8, 8]: spin loop, centre pivot |
| gold_pickup_sparkle | art/props/gold_pickup_sparkle.png | 32² | 6f @14fps, pivot [16, 16]: pickup burst, centre pivot |
| vase_gold_burst | art/props/vase_gold_burst.png | 32² | 6f @14fps, pivot [16, 31]: vase breaks, coins spill and land |
| merchant_idle | art/characters/merchant_idle.png | 64² | 6f @8fps loop, pivot [32, 63]: mask merchant, lantern, beckon |
| shop_backdrop | art/ui/shop_backdrop.png | 320x180 | still, pivot [160, 90]: shop interior still |
| game_over_art | art/ui/game_over_art.png | 320x180 | still, pivot [160, 90]: boy caught by hands still; right half free for text |
| item_icon_extra_heart | art/ui/icons/item_icon_extra_heart.png | 32² | still, pivot [16, 16]: +1 heart |
| item_icon_minimap | art/ui/icons/item_icon_minimap.png | 32² | still, pivot [16, 16]: minimap |
| item_icon_bright_bulb | art/ui/icons/item_icon_bright_bulb.png | 32² | still, pivot [16, 16]: light startles faster |
| item_icon_soft_shoes | art/ui/icons/item_icon_soft_shoes.png | 32² | still, pivot [16, 16]: quieter steps |
| item_icon_lucky_coin | art/ui/icons/item_icon_lucky_coin.png | 32² | still, pivot [16, 16]: more gold |
| exit_door_stage1 | art/props/exit_door_stage1.png | 48x64 | 4f @6fps loop, pivot [24, 63]: stage-1 stone-arch exit, green lamp, glow loop |
| bg_stage1_far | art/backgrounds/bg_stage1_far.png | 320x180 | still, pivot [0, 0]: storm sky + moonlit windows, tiles in x, scroll 0.15 |
| bg_stage1_mid | art/backgrounds/bg_stage1_mid.png | 320x180 | still, pivot [0, 0]: dim gallery portraits/columns, window gaps transparent, tiles in x, scroll 0.45 |
| bg_stage1_near_fog | art/backgrounds/bg_stage1_near_fog.png | 320x180 | still, pivot [0, 0]: semi-transparent foreground fog, tiles in x, scroll 1.2 |
| prop_candelabra | art/props/prop_candelabra.png | 32x64 | 4f @8fps loop, pivot [16, 63]: flame flicker |
| prop_portrait | art/props/prop_portrait.png | 32² | still, pivot [16, 16]: wall-hung portrait |
| prop_grandfather_clock | art/props/prop_grandfather_clock.png | 32x64 | still, pivot [16, 63] |
| prop_cobweb | art/props/prop_cobweb.png | 32² | still, pivot [0, 0]: top-left corner, flip_h for top-right |
| prop_chest_closed | art/props/prop_chest_closed.png | 32² | still, pivot [16, 31] |
| prop_chest_open | art/props/prop_chest_open.png | 32² | still, pivot [16, 31]: same footprint, gold inside |

## Stage 1 environment — built to `docs/LEVELGEN.md`
Numbers used (from LEVELGEN on `development`): **tile = 16 px**; a floor band is **10 tiles = 160 px** (floors 160 px apart, floor N surface at `level_origin_y − N·160`), bottom row of the band = floor slab (collision); top floor gets a 1-tile ceiling. Rooms 20–40 tiles wide, kits multiple of 4 wide × exactly 10 tall. **Doorways 3 tiles high in band rows 6–8** (0-based from the top). **Stair = 4 tiles (64 px) wide, rises exactly 160 px** (one floor) from the lower slab top to the upper slab top; trigger covers both bands (320 px tall). Jump apex ≈ 52 px clears 2-tile props; furniture taller than 2 tiles blocks.

Suggested band dressing (rows 0–8 above the slab): row 0 `ceiling_trim`, rows 1–5 wallpaper, row 6 `wainscot_rail`, row 7 `wainscot_panel`, row 8 `wainscot_skirting`, row 9 `floor_top` (slab; `floor_fill` for the top-floor ceiling / solid fill). Room dividers: `wall_column` with `wall_column_top` in row 0; at a doorway put `door_lintel` in row 5, leave rows 6–8 open and overlay `door_post_left`/`door_post_right` on the tiles either side (`door_head_side`/`door_head_mid` for a wider opening). Where a stair opening cuts the upper slab, end the slab with `slab_end_left`/`slab_end_right`. Mock: `/workspace/qm-style-target/stage1_mock.png` (3 floors, 640×496 at 1×; not in the repo).

### `tiles_stage1` atlas (`art/tiles/tiles_stage1.png`, 128×208, 16 px tiles, 8 columns × 13 rows, index = row·8 + col)
Manifest fields: `tile_size`, `columns`, `rows`, `tile_names` (one name per index), `stair_stamp = [col, row, w, h]`. No `frames` (not an animation). Template: `assets/replace_me/tiles_stage1_template.png` (magenta grid, cyan stair block, yellow nosing line).

| Index | Tile | Index | Tile | Index | Tile |
|---|---|---|---|---|---|
| 0 | floor_top | 8 | wallpaper_damask | 16 | wall_column |
| 1 | floor_top_alt | 9 | wallpaper_stripe | 17 | wall_column_top |
| 2 | floor_fill | 10 | wallpaper_torn | 18 | door_lintel |
| 3 | floor_fill_alt | 11 | wallpaper_stained | 19 | door_post_left |
| 4 | ceiling_trim | 12 | wallpaper_teal | 20 | door_post_right |
| 5 | ceiling_trim_hook | 13 | wainscot_rail | 21 | door_head_side |
| 6 | slab_end_left | 14 | wainscot_panel | 22 | door_head_mid |
| 7 | slab_end_right | 15 | wainscot_skirting | 23 | empty |

Indices 24–103 (rows 3–12): columns 0–3 are **one 4×10-tile stair stamp** (`stair_r<row>_c<col>`, row 0–9 / col 0–3 within the stamp; columns 4–7 are `empty`). The stamp rises to the **right**: its top row sits in the upper floor's slab row (top edge = upper floor surface) and its bottom edge sits on the lower floor surface; 10 steps of 16 px rise × ~6.4 px run, carpet runner, banister, newel post at the bottom-left. **Flip_h** for a stair rising to the left. Paint the 4 opening tiles of the upper slab behind it with wallpaper.

⚠ Slope mismatch (flag for code/anim owner, not changed here): LEVELGEN's stair is 64 px run × 160 px rise (≈68°), but `boy_climb_stairs` was drawn for a 6/4 step (≈34°). Either widen the stair (≈15 tiles for 34°) or treat climbing as a steep ladder-like move; the stair stamp follows LEVELGEN exactly.

`flashlight_blob` (`art/ui/light_blob.png`, 128², centre pivot [64, 64]) now has a template: `assets/replace_me/flashlight_blob_template.png` (centre cross, 1/8–1/2 radius rings). Keep it white with radial alpha; code tints it.

## How to replace an animation
Animated slots (`boy_idle`, `boy_run`, `boy_jump`, `boy_pickup`, `boy_carry`, `boy_throw`, `boy_climb_stairs`, `boy_hurt`, `puppet_calm`, `puppet_startle`, `puppet_chase`, `vase_*`) are **one horizontal PNG strip** per slot: frames left→right, no padding, transparent background. Frame data lives only in `assets/ASSETS_MANIFEST.toml` (`frame_size`, `frames`, `fps`, `loop`, `pivot`, plus `hand_points` for `boy_pickup`/`boy_carry`/`boy_throw`: one `[x, y]` per frame, frame-local pixels, where held/thrown objects attach).
1. Open `assets/replace_me/<slot>_template.png` in your editor (same pixel size as the strip) and draw on a new layer over it. Guides: magenta box = one frame; cyan row = feet line (pivot y); dotted cyan column + white dot = pivot (bottom-centre); orange/red cross = that frame's `hand_points` entry (pickup/carry/throw); green dots on `boy_climb_stairs` = stair slope. The faint figure underneath is the current AI frame.
2. Keep the same frame size and frame count — or change `frames` (and `fps`/`loop` if needed) in the manifest to match what you drew. Keep feet on the feet line so the pivot still works. For slots with `hand_points`, keep exactly one point per frame: if the hand moves in your drawing, update that frame's `[x, y]`.
3. Hide the template layer and export over the `path` listed in the manifest (no frame info in filenames).
4. Flip that entry's `status` to `"human"`.

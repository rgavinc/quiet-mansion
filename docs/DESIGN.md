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
| puppet_startle | art/characters/puppet_startle.png | 64² | 7f @14fps, pivot [32, 63]: hero startle: anticipation, flash+smear impact, scream mouth ~½ face height with red inner mouth + big teeth readable at 1×, red glint; hold frame 6 |
| puppet_chase | art/characters/puppet_chase.png | 64² | 8f @14fps loop, pivot [32, 63]: enraged **scuttle** — fingers walk like legs on the floor (alternating pairs, feet on y≈62), forward lean + body bob on contacts 0/4, scream mouth snaps on 4 |
| puppet_chase_float | art/characters/puppet_chase_float.png | 64² | 8f @14fps loop, pivot [32, 63]: previous floating snap loop, kept for the stage 4–5 float tier |
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

## How to replace an animation
Animated slots (`boy_idle`, `boy_run`, `boy_jump`, `boy_pickup`, `boy_carry`, `boy_throw`, `boy_climb_stairs`, `boy_hurt`, `puppet_calm`, `puppet_startle`, `puppet_chase`, `puppet_chase_float`, `vase_*`) are **one horizontal PNG strip** per slot: frames left→right, no padding, transparent background. Frame data lives only in `assets/ASSETS_MANIFEST.toml` (`frame_size`, `frames`, `fps`, `loop`, `pivot`, plus `hand_points` for `boy_pickup`/`boy_carry`/`boy_throw`: one `[x, y]` per frame, frame-local pixels, where held/thrown objects attach).
1. Open `assets/replace_me/<slot>_template.png` in your editor (same pixel size as the strip) and draw on a new layer over it. Guides: magenta box = one frame; cyan row = feet line (pivot y); dotted cyan column + white dot = pivot (bottom-centre); orange/red cross = that frame's `hand_points` entry (pickup/carry/throw); green dots on `boy_climb_stairs` = stair slope. The faint figure underneath is the current AI frame.
2. Keep the same frame size and frame count — or change `frames` (and `fps`/`loop` if needed) in the manifest to match what you drew. Keep feet on the feet line so the pivot still works. For slots with `hand_points`, keep exactly one point per frame: if the hand moves in your drawing, update that frame's `[x, y]`.
3. Hide the template layer and export over the `path` listed in the manifest (no frame info in filenames).
4. Flip that entry's `status` to `"human"`.

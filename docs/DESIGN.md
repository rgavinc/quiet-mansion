# DESIGN — Quiet Mansion (round 1)

Style: Dead Cells / fancy modern SNES — full-color creepy, flashlight as bright focus. ~64×64 characters, ~32×32 tiles.

## Replace loop
1. Open `assets/replace_me/` — labeled stills (`boy_side_idle`, `boy_mid_jump`, `puppet_hand_calm`, `puppet_hand_enraged`, …).
2. Overwrite the matching `assets/art/...` path from `ASSETS_MANIFEST.toml`.
3. Flip `status` to `"human"`. Watermark stays until art+audio are all human.

## Slots (round 1)
| Slot | Path | Size | Notes |
|------|------|------|-------|
| boy_side_idle | art/characters/boy_side_idle.png | 64² | side view + flashlight |
| boy_mid_jump | art/characters/boy_mid_jump.png | 64² | mid-air |
| puppet_hand_calm | art/characters/puppet_hand_calm.png | 64² | friendly float |
| puppet_hand_enraged | art/characters/puppet_hand_enraged.png | 64² | mouth + teeth |
| exit_door | art/props/exit_door.png | 64² | round exit |
| floor_dark | art/tiles/floor_dark_32.png | 32² | mansion floor |

## How to replace an animation
Animated slots (`boy_idle`, `boy_run`, `boy_jump`, `boy_pickup`, `boy_carry`, `boy_throw`, `boy_climb_stairs`, `boy_hurt`, `puppet_calm`, `puppet_startle`, `puppet_chase`, `vase_*`) are **one horizontal PNG strip** per slot: frames left→right, no padding, transparent background. Frame data lives only in `assets/ASSETS_MANIFEST.toml` (`frame_size`, `frames`, `fps`, `loop`, `pivot`).
1. Open `assets/replace_me/<slot>_template.png` in your editor (same pixel size as the strip) and draw on a new layer over it. Guides: magenta box = one frame; cyan row = feet line (pivot y); dotted cyan column + white dot = pivot (bottom-centre); orange/red cross = hand point where held/thrown objects attach (pickup/carry/throw); green dots on `boy_climb_stairs` = stair slope. The faint figure underneath is the current AI frame.
2. Keep the same frame size and frame count — or change `frames` (and `fps`/`loop` if needed) in the manifest to match what you drew. Keep feet on the feet line so the pivot still works.
3. Hide the template layer and export over the `path` listed in the manifest (no frame info in filenames).
4. Flip that entry's `status` to `"human"`.

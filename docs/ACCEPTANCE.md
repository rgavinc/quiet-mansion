# Acceptance — Quiet Mansion round 1

> **Owner:** QA. Release gate for round 1. Numbers mirror `docs/PRODUCT.md` + `GameState`.

Nothing ships (Pages showcase included) until this bar is green. AI art/audio may ship under watermark; **going live without watermark** requires the manifest gate below.

---

## Locked numbers / rules

| Rule | Value |
|------|------:|
| Puppets in round 1 | **3** (`GameState.PUPPET_COUNT`) |
| Win | Reach exit without dying |
| Lose | Caught by a puppet (`on_caught`) |
| Move | Keyboard |
| Flashlight | Mouse-aim cone |
| Manifest | **art + audio only** (`assets/ASSETS_MANIFEST.toml`) |

---

## Shippable checklist

### Gameplay
- [ ] Round 1 layout has **exactly 3** puppet-hand monsters
- [ ] Player moves with keys; flashlight aims with mouse
- [ ] Reaching the exit wins; being caught loses
- [ ] Noise can alert puppets (escalation path exists)
- [ ] After win/lose, further catch/exit/noise no-ops

### Provenance / watermark
- [ ] Every art + audio path used in round 1 is in `assets/ASSETS_MANIFEST.toml`
- [ ] Boot shows **“AI assets in use”** while any entry is `ai`
- [ ] Watermark clears only at 100% `human` (fonts/VFX not in manifest)
- [ ] `assets/replace_me/` labeled stills match slots (`boy_side_idle`, `boy_mid_jump`, `puppet_hand_calm`, `puppet_hand_enraged`, …)

### Repo / tests
- [ ] PRODUCT + this file are source of truth
- [ ] Headless suite under `tests/` passes on Godot **4.7.2**

---

## Automated bar

1. `PUPPET_COUNT == 3`  
2. `on_reach_exit` → game over + `reached_exit`  
3. `on_caught` → game over + `died`  
4. Game over blocks second win/lose / alert growth past settle  
5. `register_alert` caps at 3  
6. AssetProvenance sees AI on scaffold; `uses_ai_assets()` true  

**Run:** `godot --headless --path . -s res://tests/run_tests.gd`

**Status:** Automated suite landed by QA. Play smoke + Lead review still required before QA signs round 1.

## 11. Art quality and human-replaceability (added 2026-10-25 from Gavin)

Art must look great AND be trivially swappable by a human artist.

- [ ] Every sprite/animation lives as a labeled file in `assets/replace_me/` (e.g. `boy_pickup_strip_8f_32x48.png`), one horizontal strip per animation.
- [ ] Frame size, frame count, FPS, pivot/feet point, and loop flag are declared in one data file (no magic numbers in scenes or scripts).
- [ ] `assets/replace_me/README.md` lists every slot: what it is, size, frames, palette notes, and a reference still.
- [ ] Replacing a file with a same-size PNG requires zero code or scene edits. Test: swap every slot for a generated placeholder; game boots, all animations play, no errors.
- [ ] Wrong-size replacement fails loudly with a clear message naming the file, never a silent crash.
- [ ] Each entry is tracked in `assets/ASSETS_MANIFEST.toml`; watermark disappears only when all are `human`.
- [ ] Look pass: animations read clearly (pickup looks vulnerable, enemy tiers distinguishable by silhouette), judged in a QA play pass before Gavin sees it.

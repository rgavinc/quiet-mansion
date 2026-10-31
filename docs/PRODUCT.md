# Product — Quiet Mansion (round 1, v2 direction)

> **Owner:** Product Director · **Repo:** https://github.com/rgavinc/quiet-mansion
> **Engine:** Godot 4.7.2 · 2D side-scroller · Pages: https://rgavinc.github.io/quiet-mansion/
> Source of truth for vision. Release bar: `docs/ACCEPTANCE.md`. Work split: bottom of this file.

## Direction change (Oct 25)

Moving from top-down to a **side-scroller with multiple floors**, like Home Alone on SNES: walk left/right, go up and down between levels (stairs/ladders/doors). Look and motion target **Dead Cells**: fluid animation, lighting, particles, screen effects. Round 1 still = reach the exit without dying, then the shop.

## Core rules

### Flashlight and targeting
- Mouse aims, **right mouse button** toggles the light. **Space = jump.**
- Hovering the beam over an enemy **selects** it: ring around it plus a slight camera nudge toward it. Hovering another enemy moves the selection; only one at a time.
- The selected enemy keeps its ring and stays **faintly visible with the light off**. The selected enemy is also the throw target.
- Holding the beam on an enemy for **1.0 s** startles it and it chases. Show build-up both with a small gauge and with the puppet visibly twitching/opening.
- The light affects **on-screen only**.

### Off-screen chasers
- A chasing enemy off-screen shows a **Smash-style edge arrow** with a gauge on it.
- The gauge drains as you get farther away. At empty, the enemy gives up and walks back to its home spot.

### Objects and noise
- Objects are everywhere (vases first). Touching one instead of jumping over breaks it with an animation and a **noise radius**.
- Noise is much worse than light: every enemy in the radius starts chasing, so several can chase at once.
- Each object type has its own noise radius. Default radius is **slightly larger than the screen**, so vase noise reaches just off-screen.
- Some objects can be picked up (vase yes, not all). Objects can hold gold.

### Simulation
- All enemies exist in the level at all times. Off-screen ones skip rendering and animation but still hear noise and run chase/return logic.

### Player, gold, HUD
- **3 hits = dead**, then a game-over screen.
- Gold is found in the world, inside objects, and in chests.
- HUD shows styled health and gold that match the art; no plain default UI.

### Shop and items (Brotato-style)
- After round 1: a merchant sells **random items** from the pool.
- **20 starting items.** Chests in levels also drop items.
- Example items: +max health, map item that shows a mini-map, softer light that takes longer than 1 s to startle.

## Code structure (required)

- **`ObjectDef` base**: defaults for noise radius, breakable, pickup-able, gold contents, break FX/SFX. Subclasses like `Vase` override only what differs.
- **`ItemDef` base**: name, rarity, price, icon, description, plus an `apply(stats)` hook for each item's special rules.
- **`PlayerStats` in one place** (autoload/resource): max HP, startle time, move speed, noise multiplier, light radius, has_minimap, and so on. Items and objects read from and change this one place; no stats hard-coded in scattered scripts.
- Numbers live in data resources (`.tres`) so they can be tuned without code changes.

## AI provenance (unchanged)
All new art and audio go in `assets/ASSETS_MANIFEST.toml` as `ai` with labeled stills in `assets/replace_me/` (e.g. `boy_side_run_03`, `boy_mid_jump`, `boy_climb`, `puppet_hand_startled`, `vase_break_02`). The watermark stays until everything is `human`.

## Work split

| Owner | Work |
|------|------|
| **Lead** | Side-scroller multi-floor architecture; class layout for `ObjectDef`, `ItemDef`, and `PlayerStats`; on-/off-screen simulation design; reviews every PR; resolves FE/BE conflicts |
| **Back End** | Movement, jump, and climb between floors; enemy AI (idle, startle, chase, give-up, return); noise radius system; 1 s startle timer; health and death; gold; chests; base classes and the vase subclass; item pool of 20 with the shop roll |
| **Front End** | Selection ring plus camera nudge; faint visibility when the light is off; startle gauge; off-screen arrow with distance gauge; styled HP and gold HUD; game-over screen; shop UI; mini-map item UI |
| **Designer** | Dead Cells-quality animation sets: boy (idle, run, jump, climb, hit, death) and puppet (calm, startled, chase, bite, return); vase plus break animation; chest; gold; merchant; side-view mansion tiles for 2–3 floors; light and particle FX; 20 item icons; HUD art. Every asset listed in the manifest |
| **QA** | Rewrite ACCEPTANCE for v2; automated tests for startle timing, noise radius (multiple chasers), off-screen give-up, 3-hit death, item `apply` through `PlayerStats`, and object default overrides; play smoke on Pages |
| **Product** | Owns this spec, answers scope questions, reviews round 1 against it before Gavin's review |

**Order:** Lead lands the skeleton and class stubs first → Backend and Designer work in parallel → FE wires against both → QA gates. One floor of side-scrolling with a vase plus one puppet working end to end comes before the full round 1.

## Run structure, generation, quality bar (Oct 25 addendum)

### Stages and enemies
- **5 stages** per run. Reaching the exit clears the stage, then the merchant shop, then the next stage.
- Each stage is harder: more enemies, faster startle, wider patrols, fewer safe paths, and more valuable loot.
- **Support up to 5 enemy types**, introduced progressively with harder stats (speed, hearing range, startle time, give-up distance, damage). Puppet-hand is type 1. Each type is an `Enemy` subclass that overrides only the stats and behaviors that differ.

### Procedural generation
- Each stage is generated from a **seed** using a fixed content budget per stage (enemy count and types, objects, gold, chests).
- Hard constraints, checked after generation; if a check fails, reroll:
  - The exit is reachable from spawn (path check over floors and stairs).
  - No enemy spawns within a safe radius of the player spawn.
  - Every chest and gold pickup is reachable.
  - No overlapping props or blocked stairs, and nothing spawns inside geometry.
- The seed is shown on the game-over and pause screens so bugs can be reproduced.

### Risk in every action
Every player action carries a cost or risk: light can startle, touching objects makes noise, a missed knock-over aggros the enemy, breaking a vase for gold is loud, and chests take time to open. Nothing is free.

### QA quality bar (raised)
- QA does **not** call anything done or ask Gavin to review until it is presentable, fun, and challenging. A passing test suite is not enough.
- Required before any review ping:
  - **Soak test:** at least 1,000 seeded generations per stage headless, with zero crashes and zero constraint failures.
  - **Bot playthroughs:** scripted runs reach the exit on a sample of seeds, which proves every stage is completable.
  - **Manual play:** at least 10 full human-style runs on the `/development/` build, with notes on fun, difficulty curve, and moments that felt unfair or boring, filed in `docs/PLAYTEST.md`.
- Product signs off on fun and difficulty after QA, then Gavin reviews.

### Ownership calls
- **Foundation code** (`PlayerStats`, `Item`, `WorldObject`, `Enemy` state machine, `NoiseBus`, level generator plus validator): **Back End builds it, Lead reviews it.** Lead does not write a second copy.
- Branching: all work lands on `development` (Pages `/development/`). It merges to `main` only after QA and Product sign off.

## Controls (locked, Oct 25)

| Input | Action |
|------|--------|
| A / D (or arrows) | Move |
| W / S at stairs or ladders | Climb up or down between floors |
| Space | Jump |
| Mouse | Aim the flashlight |
| Right mouse button | Toggle the flashlight |
| Hold left mouse button | Pick up (about a 1 s channel) |
| Scroll wheel | Cycle held items and objects |
| Left mouse click (with something held and an enemy selected) | Throw or use the held thing |
| Left mouse click on a knockable prop in range (nothing held) | Knock it over in the facing direction. If it lands on an enemy it can kill it; a miss makes noise and can startle the enemy |

### Picking up
- Hold LMB on a pickup in range. A gauge fills over about **1.0 s**, and while it fills the player is **locked into the pickup action**.
- Moving out of range or releasing LMB cancels it. This is meant to be risky: you're exposed while channeling.
- You can pick up **objects** (like a vase) and **usable items**. Both go into a small held inventory, and the scroll wheel cycles through it.

### Throwing (vase first)
- A held vase can be thrown at the **currently selected enemy** (the one with the ring).
- Walls and props can block the throw. A blocked throw or a miss breaks the vase where it lands, which makes noise there.
- A hit can stun or kill, depending on the object and enemy stats. A miss can startle the target or pull in nearby enemies.
- Throw values (damage, arc, accuracy, noise on impact) live in the object's `WorldObject` data and default from the base.

### Final ownership (generator)
- **Level generator, validator, seed sweep CI, and `docs/LEVELGEN.md`: Lead.** Back End owns the foundation (stats, items, objects, enemies, `NoiseBus`) plus the pickup, inventory, and throw systems. FE owns the pickup gauge, inventory strip and scroll UI, and the throw aim and arc preview.

## Input decisions (Product call, Oct 25)
- **Flashlight:** right mouse **toggles** on and off (Gavin's original brief has the light turned off and the ring staying).
- **Throw:** **tap** left mouse (under 0.2 s) throws the held item at the ringed enemy. **Holding** left mouse starts a pickup. With no enemy selected, a tap does nothing; it never errors and never auto-throws.
- All of these are input-map actions (`flashlight_toggle`, `jump`, `interact`, `inv_next`, `inv_prev`) so they can be rebound later.

## Art: looks great, easy to replace (required)

Gavin's rule: the art should look Dead Cells quality, and a human artist must be able to swap it in **without touching code or scenes**. The team agreed on the following (this replaces the earlier folder-per-animation draft):

- **One source of truth: `assets/ASSETS_MANIFEST.toml`.** Each slot holds `frame_size`, `frames`, `fps`, `loop`, `pivot`, and the `ai`/`human` flag. No per-character config files and no frame counts in filenames.
- **Sheets:** one horizontal PNG strip per animation, named by slot (e.g. `boy_run.png`). Frames are 64×64 for the boy and big enemies and 32×32 for lesser enemies and props. The pivot sits bottom-center on the feet line, with no padding.
- **Code asks for slot names only** (`boy/run`, `vase/shatter_wall`), never file paths. One shared loader (Back End) builds animations from the manifest, and FE uses that same loader.
- **Templates:** each slot has a labeled template in `assets/replace_me/` showing the frame grid, feet line, and hand point, plus a plain-words pose label.
- **Replace flow:** draw over the template, save with the same name, adjust `frames`/`fps` in the manifest if needed, and flip the slot to `human`. That's it.
- **Docs and guards:** `assets/README.md` (Lead) lists every slot's size, frame count, and pivot, generated from the manifest. CI fails if a sheet's size doesn't match its manifest entry. QA tests that every slot loads and animates with placeholder art.
- UI skin values (ring colors, gauges, HUD) go in a separate theme file, since they aren't art slots.

## Product decisions (Oct 25 evening)
- **Enemy movement:** puppets on stages 1–3 walk with gravity and change floors only by stairs (on and off screen, via `LevelNav`). Floating enemies are stage 4+ only, marked solely by `EnemyDef.movement = &"float"`.
- **Taking a hit:** a catch costs 1 heart and shoves the boy (with collision). The puppet then backs off/flinches ~1.5s so one contact never chains into a death. Catches go only through the puppet's hit `Area2D`; bodies stay solid.
- **Knocking:** a left-mouse tap only targets knockable props, never puppets directly.
- **Pickup timing:** measured from button-down; `pickup_time` = 1.0s; a tap (<0.2s) never shows the gauge.
- **No continues:** death ends the run. *New run* (primary) = stage 1, 3 hearts, 0 gold, no items, new seed. *Retry seed* = same run seed, same fresh start at stage 1.
- **Carry-over between stages:** hearts, gold, and bought/chest items carry over. Held props (vases etc.) belong to the level and are dropped.
- **Run end:** clearing stage 5's exit shows a win screen (stages cleared, time, seed, gold, New run), not the shop.
- **Pause (after the Wednesday checklist):** Esc pauses and shows the run seed, Resume and New run; mouse released.
- **Stairs:** 15 tiles (240px) diagonal per floor (~34°) plus a 3-tile landing at each end (21 tiles total). Landings are kept clear.
- **Stage 1 size:** at least 3 floors, ~3 screens wide; exit on a different floor than the start; no puppet within one screen of the start.
- **Seed sweep:** 1,000 seeds per stage.
- **Merge rule:** an author's "ready" message ends with "frozen at `<sha>`"; Lead merges only that sha; follow-ups go on a new branch. Nothing merges until QA posts a pass on that frozen sha (the pass is the go-ahead; no hold message needed).
- **Wednesday first-look checklist:** generated multi-floor stage 1 start-to-exit; walking/stair-taking chasers; off-screen arrows that drain and give up; 1s light startle with visible twitch; vase noise pulling multiple chasers; vase gold and throws at the ringed puppet; styled game-over; merchant with a few working items.
- **Startle timing:** holding the light on a puppet for 1.0s startles it; the chase starts when the scream animation finishes (~0.5s, from manifest frames/fps), giving a short read-and-run window.
- **Floaters** (`movement = &"float"`, stage 4+) drift through floors and slabs.
- **Give-up gauge** drains faster the farther the boy is from the chaser.
- **Hit pacing (stage 1 baseline):** with the 1.5s back-off, one puppet takes 3 hearts in ~7s; per-stage tuning happens in the PD fun pass.
- **Item pool (20):** 6 behavior items replace 6 stat items. New: `rabbits_foot` (rare; first lethal hit each stage leaves 1 heart, start each stage -1 heart), `music_box` (uncommon; loud throwable lure), `heavy_vases` (common; longer vase stun, carrying slows), `flash_bulb` (rare; once per stage a startle stuns instead of enrages), `cracked_mirror` (uncommon; chasers give up 40% faster, arrows hidden until close via `arrow_reveal_distance()`), `greedy_sack` (legendary; every vase has gold, breaks 50% louder). Removed (icons kept as spares): `dim_filter`, `lucky_coin`, `strong_arm`, `wide_lens`, `spring_socks`, `golden_heart`. Split: 6 common / 7 uncommon / 5 rare / 2 legendary. Vary downsides beyond "more noise". Prices are set from the measured gold per stage (target: about one item affordable per shop).
- **Stair opening:** a visible gallery rail with real collision spans the upper-floor opening (x+9 to x+17) and blocks both the boy and walkers; floaters pass through. Walkers also turn back at ledges as a backup.
- **Music Box exception:** when the lure pocket has a charge (`tap_throws_lure()`), a left-mouse tap with no enemy ringed throws a lure, arcing in the facing direction; HUD shows "tap: throw lure" only when a tap would actually throw one. All other throws still need a ringed enemy.
- **Shop pace:** a careful player affords ~1 item per shop; greed (vases, chests) should earn a second. Tune after #13's gold sweep.
- **Holds:** a hit or leaving range cancels a pickup/chest hold completely; a new press is required (first-look blocker).
- **Stat caps:** every stat has a min and max in the central stats table (e.g. noise ×0.3–×3).
- **Stacked behavior caps:** Heavy Vases' stun is capped at ×2.5 total, and every behavior effect that multiplies across copies gets a bound in the same central stats table.
- **Upper bounds for every stacking stat:** `max_health` ≤ 6 hearts, `invuln_time` 0.5–2.0s, `inventory_slots` ≤ 5, `light_startle_time` 0.4–1.5s, `light_angle_deg` ≤ 70°. All live in the central stats table.
- **Honest item text:** all description numbers come from the effective, capped value, including what the next copy would add. No hand-typed numbers. At a cap, hide the zero clause or say "(at limit)" instead of showing "0%" or "-0".
- **Max useful copies:** each item gets a `max_copies` field. Shops and chests stop offering an item once another copy would add nothing. Music Box `max_copies` is 3.
- **Music Box charges don't use hand slots:** lures are held in their own pocket, shown as pips, so owning boxes never blocks picking up vases.
- **Perching has risk:** a walker under a boy on 1- or 2-tile furniture reaches up and catches him after a telegraphed ~0.6s reach (so a quick hop-off escapes). 3-tile furniture is out of reach, but climbing onto any furniture makes a creak noise.
- **No safe camping:** if a walker can't reach the boy for 3s it rattles the furniture: each rattle is a loud noise that draws other enemies, and after 3 more seconds the boy is shaken off toward the walker. 3-tile furniture buys ~6s, not a hiding spot.
- **Rails can't be cleared:** at capped stats, no spot the boy can stand on (floor or furniture) may let any jump clear a rail. Rail height or furniture placement must guarantee this, and CI checks running jumps from furniture.
- **Walker routing:** walkers pick the shortest route by distance, not by stair count.
- **Gold floor:** every stage's worst-roll total gold (floor + vases + chests) is at least that stage's cheapest shop price, checked in the seed sweep. Stage 1 floor gold minimum rises from 4 to 6.
- **Item text:** description percentages are generated from the item's modifiers, never hand-written.

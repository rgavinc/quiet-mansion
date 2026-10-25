# Product — Quiet Mansion (round 1, v2 direction)

> **Owner:** Product Director · **Repo:** https://github.com/rgavinc/quiet-mansion
> **Engine:** Godot 4.7.2 · 2D side-scroller · Pages: https://rgavinc.github.io/quiet-mansion/
> Source of truth for vision. Release bar: `docs/ACCEPTANCE.md`. Work split: bottom of this file.

## Direction change (Oct 25)

Moving from top-down to a **side-scroller with multiple floors**, like Home Alone on SNES: walk left/right, go up and down between levels (stairs/ladders/doors). Look and motion target **Dead Cells**: fluid animation, lighting, particles, screen effects. Round 1 still = reach the exit without dying, then the shop.

## Core rules

### Flashlight and targeting
- Mouse aims, **Space** toggles the light.
- Hovering the beam over an enemy **selects** it: ring around it plus a slight camera nudge toward it. Hovering another enemy moves the selection; only one at a time.
- The selected enemy keeps its ring and stays **faintly visible with the light off**.
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

# Acceptance: Quiet Mansion (release gate)

> **Owner:** QA. Work lands on `development` first and is checked on the `/development/` Pages build. Nothing merges to `main`, and nobody asks Gavin to review, until **every** section below passes.
>
> "Done" means it is presentable, fun, and challenging. Passing tests alone is not enough.

---

## 1. Structure

| Rule | Bar |
|------|-----|
| View | 2D side-scroller with multiple floors connected by stairs (Home Alone SNES style) |
| Stages | **5**, each harder than the last |
| Level complete | Reaching the exit completes the level |
| Enemy types | Up to **5**, each with harder stats than the one before |
| Health | 3 hits and you're dead, then the Game Over screen |
| Between levels | A shopkeeper sells random items |
| Items | **20** to start, from the shop and from chests |

## 2. Every action has a risk (design gate)

QA rejects any action that has no downside. Each one must have a cost in the build:

| Action | Reward | Risk that must exist |
|--------|--------|----------------------|
| Shine the flashlight on an enemy | Selects it and reveals it | After about 1s it startles and chases you |
| Turn the light off (Space) | Hides you | You can't see hazards, only the last selected enemy stays dimly visible |
| Touch or break a vase | It may drop gold | A large noise radius that reaches slightly off-screen and pulls every enemy inside it |
| Knock something onto an enemy | Kills it | A miss startles it or makes noise and can pull more enemies |
| Open a chest | An item | Noise or a trap risk, tuned per stage |
| Pick up gold | Money for the shop | Its spot is placed near danger |
| Hop over an obstacle | Quiet | A mistimed jump touches it and makes noise |

## 3. Flashlight and selection

- [ ] Aiming at an enemy draws a ring around it and nudges the camera a little toward it
- [ ] Hovering another enemy moves the selection, so only one is selected at a time
- [ ] The selection ring stays, and the enemy stays faintly visible, after the light is turned off
- [ ] Keeping the light on an enemy shows a startle buildup (a meter or visible body tells), then it chases at about 1s (the base value comes from `PlayerStats`)
- [ ] The light has no effect on enemies that are off-screen
- [ ] A chasing enemy that is off-screen shows an edge arrow, Smash-style, with a gauge that drains as you get farther away. When the gauge is empty the enemy gives up and walks home

## 4. Noise and enemies

- [ ] All enemies run their logic off-screen (hearing, chasing, returning home) but don't render there
- [ ] Each object type has its own noise radius. The default is slightly larger than the screen
- [ ] Several enemies can chase at once, and making more noise while being chased pulls more of them
- [ ] An enemy that gives up always returns to its original spot and never gets stuck

## 5. Data and architecture (must be easy to tune)

- [ ] One stats source (`PlayerStats`) holds health, gold, startle time, noise multipliers, and so on. Every system reads from it and nothing hard-codes these numbers
- [ ] `WorldObject` base class with defaults. Subclasses like vases and chests override only what differs (pickup, loot, radius)
- [ ] `Item` base class with defaults plus a per-item `apply()`. All 20 items are data files that change stats only through `PlayerStats`
- [ ] Enemy types 1 to 5 are data-driven, with stats that go up each tier

## 6. Procedural generation (no crashes, no unfair layouts)

Each generated level has the same amount of content for its stage (the same enemies, obstacles, and loot budget), placed randomly but always in a way that makes sense.

Automated seed sweep, which must pass before every merge to `main`:

- [ ] **1,000 seeds per stage (5,000 total)** generate with no error or crash
- [ ] The exit can always be reached from the spawn point (pathfinding over floors and stairs)
- [ ] There's a safe spawn: no enemy is inside the startle or hearing radius at the start
- [ ] No object, enemy, or gold overlaps another or sits inside a wall, and no stair is blocked
- [ ] Every stage's content counts match its budget exactly
- [ ] There's at least one quiet route to the exit (the level can be finished without forced noise), so a run can always be beaten
- [ ] Generation is deterministic: the same seed gives the same layout, so any bug report can be reproduced

## 7. Playthroughs (fun and challenge gate)

- [ ] **Automated bot runs:** a scripted runner plays at least 200 seeded runs per stage, mixing careless and careful play. No soft-locks, a careful bot reaches the exit, and a careless bot dies or gets chased. If careless play wins too easily, the stage is too easy
- [ ] Each harder stage measurably cuts the careless-bot clear rate
- [ ] **Manual play pass by QA:** at least 10 full runs on `/development/`, covering all 5 stages, with notes on tension, fairness, and anything dull or cheap. These notes go in `docs/QA_PLAYTEST.md`
- [ ] No action feels risk-free, and no death feels unavoidable

## 8. Look and feel

- [ ] Characters are clearly animated (idle, walk or run, jump, stairs, hurt, death, and the puppet's calm, startle, and enraged states), aiming for a Dead Cells–style atmosphere
- [ ] Break, startle, and noise VFX make each risk readable
- [ ] The health and gold HUD is styled to fit the game, not plain default UI
- [ ] The AI watermark shows while any art or audio entry in `assets/ASSETS_MANIFEST.toml` is still `ai`

## 9. Sign-off

| Step | Who |
|------|-----|
| Code review on `development` | Lead |
| Seed sweep, bot runs, and headless suite green | QA |
| Manual play pass recorded in `docs/QA_PLAYTEST.md` | QA |
| Product pass against PRODUCT | Product Director |
| Merge `development` into `main` and ask Gavin to review | Only after all of the above |

**Status:** Bar rewritten for the side-scroller expansion. **Not ready for Gavin.**

## 10. Controls, pickup and throw (added 2026-10-25 from Gavin)

Controls: A/D move, **Space = jump**, **Right mouse = flashlight**, **Left mouse (hold) = pick up**, **Scroll wheel = cycle held items/objects**, vase throw targets the currently ringed enemy.

- [ ] Pickup requires holding LMB ~1.0s (value in PlayerStats); a gauge is visible the whole time.
- [ ] While picking up the player is committed: cannot move, jump, or use the flashlight.
- [ ] Leaving pickup range (or releasing LMB) cancels the pickup and resets progress.
- [ ] Taking a hit or a startle during pickup is possible and fair (risk is real, never a guaranteed hit).
- [ ] Scroll wheel cycles held objects/usable items; empty inventory scroll is a safe no-op.
- [ ] Throwing a vase at the selected (ringed) enemy: projectile is blocked by walls/props; a miss or block still breaks and emits full noise at impact.
- [ ] Throw with no enemy selected never errors (defined behavior: no-op or throw forward; document which).
- [ ] Generation sweep: no level forces a pickup or a throw on the only route to the exit.

# Feedback Preview — Known Issues

This is an explicitly incomplete feedback preview, not a QA-cleared release.
Gavin authorized pushing and deploying this preview with disclosed QA gaps.

## Included changes
- PR #59: shop keyboard/controller support (prior QA is shop-only).
- PR #60: level-generation changes. **NOT QA-cleared**; geometry checks are not proof of playable escape.
- PR #61 at `38179dc668b258cb858d72b267b0f2aa93d91845`: player speed floors (105, 100 carrying) and a hard six-second give-up cap after the walker loses sight. Safeguards are implemented; real-chase fairness is **unverified**.

## Corners cut: skipped checks, known gaps and deferred features
- All four PR #60 neighbouring-step onward-movement cases remain **UNVERIFIED**. Landing on another step is acceptable; regaining control and safely continuing to the floor or an escape route without a stuck state, forced damage or endless rattling has not been established.
- The escape-tactic table is incomplete, including away-stairs and corrected line-of-sight/hiding coverage. Full physics and tactic sweeps are deferred to save usage.
- No new real-chase tactic rerun for #61; older hiding/broken-sight results slightly exceeded the intended 30–50% give-up range and may need retuning.
- The regression test ensuring reach waits for the boy to regain control is missing.
- QA probe files are missing and not committed, limiting reproducibility.
- Controller navigation outside the shop is unverified.
- Stage-5 eye-glint overlay integration and visibility checks are unfinished.
- Pause screen is unfinished.
- Distinct later-stage tilesets are deferred.
- Shop-price retune is pending.
- Product Director has not supplied stage-1 fun/playthrough signoff.
- No interactive browser/gameplay clearance has been performed by this deployment worker. HTTP availability is not gameplay clearance.

## Evidence boundaries
- #59 shop-scope QA previously passed at `2dee80955150231624c2e0b27beefc542ed07abf`.
- #60 prior 423 unit tests and 5,000 generated-layout geometry checks were reported passing at `30fabefa5d7a9f9a2cc02d2fd563d3833ea367a3`; these do not prove safe onward movement or fair chases.
- Back End reported 405 tests and four clean boots for #61. This worker did not rerun that suite; CI was still in progress when #61 was merged for this explicitly unverified preview.
- A fresh Godot 4.7.2 headless import and 180-frame startup of integrated gameplay commit `45aa91d030a98bbbc6d1074b28ec0adc602de79b` both exited 0 with no error lines. This only checks basic startup, not playability. This handoff changes documentation only.
- The existing `/development/` HTML and its JS/PCK/WASM assets returned HTTP 200 during preparation. Delivery of the final development commit must be confirmed separately from its Pages workflow; cached or older live assets do not prove final-commit deployment.

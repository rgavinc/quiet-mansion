# Product — Quiet Mansion (round 1)

> **Owner:** Product Director  
> **Repo:** https://github.com/rgavinc/quiet-mansion  
> **Engine:** Godot 4.7.2 · 2D · public `main` · GitHub Pages showcase  
> **Source of truth for vision.** Release bar: `docs/ACCEPTANCE.md`.

## Vision

Creepy stealth roguelite with Limbo tension and a Dead Cells / fancy modern-SNES sprite look. A boy explores a mansion with a **mouse-aimed flashlight** (keys move). Noise has consequences: breakables and missed knock-overs can wake **puppet-hand** monsters (calm → enraged when startled). Treasure funds between-run upgrades later. Layouts are randomized with a **fixed content budget** so density always feels intentional. **This milestone is round 1 only.**

## Round 1 loop

Reach the **exit** without dying. **3** puppet-hand monsters. Use the flashlight cone to see; stay quiet. Optional: knock something onto a monster to kill it — miss and you may aggro it (and neighbors).

## Locked rules

| Rule | Value |
|------|------:|
| View / art | 2D full-color creepy; flashlight is the bright focus |
| Hero / prop scale | ~64×64 / ~32×32 |
| Move / aim | Keys move · mouse aims flashlight cone |
| Round 1 win | Reach the exit without dying |
| Round 1 lose | Caught / killed by a puppet |
| Puppets (r1) | Exactly **3** |
| Noise | Loud actions alert nearby puppets; while chased, more noise can pull more |
| AI bootstrap | Art + audio may start as AI; fonts/VFX not tracked |

## Out of scope (round 1)

- Multi-round meta, shops, upgrade trees  
- Large multi-floor mansion  
- Full procedural variety beyond one seeded round-1 layout budget  

## AI provenance

- Registry: `assets/ASSETS_MANIFEST.toml` (art + audio only)  
- Labeled stills: `assets/replace_me/` (e.g. `boy_side_idle`, `boy_mid_jump`, `puppet_hand_calm`, `puppet_hand_enraged`)  
- In-game watermark until every tracked entry is `human`  

## Ownership

| Area | Owner |
|------|--------|
| Vision + this doc | Product Director |
| Repo, reviews, Pages | Lead Full Stack Programmer |
| Stealth / noise / puppets / win-lose | Back End Programmer |
| Map / HUD / flashlight aim UX | Front End Programer |
| Pixel pack + replace slots | Designer |
| ACCEPTANCE + tests | Quality Assurance And Testing |

## Success for this milestone

1. Playable round 1: move, aim light, reach exit or die clearly.  
2. 3 puppets + readable noise/aggro feedback.  
3. Manifest + watermark correct; replace slots obvious.  
4. Pages deploy once Lead’s `workflow` grant lands.  

## Change control

Tune fear/noise/economy in this file first, then implement. Do not silently diverge from PRODUCT.

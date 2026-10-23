# Quiet Mansion

2D stealth roguelite in **Godot 4.7.2**. Creepy full-color Dead Cells / fancy-SNES sprites (~64×64 heroes). Limbo-adjacent vibe: flashlight is how you see.

**Round 1:** reach the exit without dying. **3** puppet-hand monsters. Mouse aims the flashlight cone; WASD/arrows move. Noise draws nearby puppets; startled puppets enrage.

## Play

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/)
2. Import this folder → run `scenes/main.tscn`

## Controls (round 1)

| Input | Action |
|-------|--------|
| WASD / arrows | Move |
| Mouse | Aim flashlight cone |

## AI asset tracking

- Registry: [`assets/ASSETS_MANIFEST.toml`](assets/ASSETS_MANIFEST.toml) — **art + audio only**
- Watermark until every entry is `human`
- Labeled stills in `assets/replace_me/` (`boy_side_idle`, `boy_mid_jump`, `puppet_hand_calm`, `puppet_hand_enraged`, …)

## Ownership

Same split as Supply Siege / TD-RTS: Lead reviews, Backend loops, Front End HUD/aim, Designer pack, QA acceptance, Product vision.

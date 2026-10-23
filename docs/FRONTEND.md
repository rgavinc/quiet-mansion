# FRONTEND — Quiet Mansion (round 1)

## Owns
- Flashlight feel (mouse aim, cone + `PointLight2D` blob), floor/darkness presentation, HUD copy/alerts
- Backend owns puppets, noise, obstacles, exit trigger scripts

## Player UX
- **WASD** move, **mouse** aims flashlight
- **Space / RMB** knock nearby props (noisy — can wake puppets)
- Reach the exit without being caught
- Watermark while any art/audio in `ASSETS_MANIFEST.toml` is still `ai`

## Replace art
Overwrite manifest paths in place. Labeled stills: `assets/replace_me/boy_side_idle.png`, `boy_mid_jump.png`, `puppet_hand_calm.png`, `puppet_hand_enraged.png`. See `docs/DESIGN.md`.

## Web / Pages
Export preset **`Web`** lives in `export_presets.cfg` (tracked for CI). Actions runs `godot --export-release "Web" build/web/index.html` on push to `main`. Renderer is **GL Compatibility** for WebGL 2.

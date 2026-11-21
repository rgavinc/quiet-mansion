extends Node2D
## Reusable FE candle effect: looping flame wobble + a tiny flickering PointLight2D.
## Attach to any prop node (Lead places the candelabra / candle sprite). Does not
## draw a second body by default. Art is manifest-only (HudSkin.candle_flame_slot).

const META := &"fe_candle_fx"

var skin: HudSkin
var flame: AnimatedSprite2D
var light: PointLight2D
var _phase: float = 0.0


## Add the flicker component under `host` if one is not already there. Returns it.
static func attach_to(host: Node2D, skin: HudSkin = null) -> Node2D:
	if host == null or not is_instance_valid(host):
		return null
	for c in host.get_children():
		if c is Node2D and c.get_meta(META, false):
			return c
	var fx: Node2D = load("res://scripts/ui/decor_candle.gd").new()
	if skin:
		fx.skin = skin
	fx.name = "FeCandleFx"
	fx.set_meta(META, true)
	host.add_child(fx)
	return fx


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	set_meta(META, true)
	_phase = randf() * TAU
	var fr := UiArt.frames(skin.candle_flame_slot)
	flame = AnimatedSprite2D.new()
	flame.name = "Flame"
	if fr:
		flame.sprite_frames = fr
		flame.animation = skin.candle_flame_slot
		flame.offset = AnimLibrary.offset_for(skin.candle_flame_slot)
		flame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		flame.play()
	# Sit just above the host sprite if we can measure one; otherwise a short lift.
	flame.position = Vector2(0, _flame_y())
	add_child(flame)
	light = PointLight2D.new()
	light.name = "Glow"
	light.position = flame.position + Vector2(0, 2)
	light.energy = skin.candle_light_energy
	light.color = Color(1.0, 0.78, 0.45, 1)
	light.texture_scale = 0.55
	var blob := UiArt.texture("flashlight_blob")
	if blob:
		light.texture = blob
	light.shadow_enabled = false
	add_child(light)


func _flame_y() -> float:
	var host := get_parent() as Node2D
	if host:
		for c in host.get_children():
			if c == self:
				continue
			if c is Sprite2D and (c as Sprite2D).texture:
				var spr := c as Sprite2D
				var sz := spr.texture.get_size()
				return spr.position.y - sz.y * 0.45
			if c is AnimatedSprite2D:
				return (c as Node2D).position.y - 12.0
	return -18.0


func _process(delta: float) -> void:
	_phase += delta * 8.0
	if light:
		light.energy = skin.candle_light_energy * (0.82 + 0.18 * sin(_phase) + 0.06 * sin(_phase * 2.7))
	if flame:
		flame.rotation = 0.06 * sin(_phase * 0.7)
		flame.scale = Vector2.ONE * (0.95 + 0.08 * sin(_phase * 1.3))

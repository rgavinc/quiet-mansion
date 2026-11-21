extends Node2D
## Mouse-aim flashlight. Front End owns feel; PlayerController parents this node.
## Visual only: gameplay reach and cone width (PlayerStats.light_range /
## light_angle_deg) are not read or written here.

const SHADER_PATH := "res://assets/shaders/flashlight_beam.gdshader"
## Cookie art is authored along +X with the emitter at this pixel (manifest notes).
const COOKIE_PIVOT := Vector2(18, 80)
const HAZE_SIZE := Vector2(256, 160)


func _ready() -> void:
	# Soft cone ahead of the boy. Shadows are enabled here;
	# FE LightOccluders attaches occluders to the built furniture/walls.
	var skin := HudSkin.load_default()
	var cookie := _cookie_texture(skin)
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.energy = 1.5
	beam.color = Color(1.0, 0.95, 0.75, 1)
	beam.texture = cookie
	beam.texture_scale = skin.cone_texture_scale
	beam.position = Vector2.ZERO
	beam.offset = cookie_offset(cookie, skin.cone_texture_scale)
	beam.shadow_enabled = skin.light_shadows
	beam.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	beam.shadow_filter_smooth = skin.light_shadow_smooth
	beam.shadow_color = Color(0, 0, 0, 0.72)
	add_child(beam)
	_add_haze(skin)
	_add_dust(skin)


func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())


## Shift a PointLight2D cookie so the authored emitter pivot sits on the light.
static func cookie_offset(tex: Texture2D, scale: float) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var sz := tex.get_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		return Vector2.ZERO
	# PointLight2D centres the texture; offset is in world px (texture px × scale).
	var pivot := COOKIE_PIVOT
	if sz.x != 256.0 or sz.y != 160.0:
		pivot = Vector2(sz.x * (COOKIE_PIVOT.x / 256.0), sz.y * 0.5)
	return (sz * 0.5 - pivot) * scale


func _cookie_texture(skin: HudSkin) -> Texture2D:
	var cone_tex := UiArt.texture(skin.flashlight_cone_slot)
	if cone_tex:
		return cone_tex
	var blob := UiArt.texture("flashlight_blob")
	if blob:
		return blob
	return _soft_cookie()


## Runtime fallback cookie if the manifest slot is missing.
func _soft_cookie() -> Texture2D:
	var w := 256
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pivot := COOKIE_PIVOT
	var length := float(w) - pivot.x
	var half := deg_to_rad(20.0)
	for y in h:
		for x in w:
			var dx := float(x) - pivot.x
			var dy := float(y) - pivot.y
			var dist := Vector2(dx, dy).length()
			var glow := pow(1.0 - dist / 22.0, 1.4) if dist < 22.0 else 0.0
			var a := 0.0
			if dx <= 0.0:
				a = glow * 0.95
			else:
				var ang := absf(atan2(dy, dx))
				var edge := 1.0 - smoothstep(half * 0.42, half, ang)
				var along := dist / length
				var lf := 1.0 - smoothstep(0.22, 1.02, along)
				var core := exp(-ang / (half * 0.28)) * exp(-along * 1.25)
				a = maxf(maxf(lf * edge, core), glow * 0.8)
			if a > 0.001:
				img.set_pixel(x, y, Color(1.0, 0.925, 0.77, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _add_haze(skin: HudSkin) -> void:
	# Soft volumetric overlay. Replaces the old hard-edged Polygon2D "Cone".
	if get_node_or_null("Cone") != null:
		return
	var haze := Sprite2D.new()
	haze.name = "Cone"
	var img := Image.create(int(HAZE_SIZE.x), int(HAZE_SIZE.y), false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	haze.texture = ImageTexture.create_from_image(img)
	haze.centered = true
	var scale := skin.cone_texture_scale
	haze.scale = Vector2(scale, scale)
	# Sprite is centred; shift so the left-centre (emitter) sits on the origin.
	haze.position = Vector2(HAZE_SIZE.x * 0.5 * scale, 0.0)
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(SHADER_PATH):
		mat.shader = load(SHADER_PATH)
		mat.set_shader_parameter("noise_tex", _noise_tex())
		mat.set_shader_parameter("haze_amount", skin.beam_haze)
		mat.set_shader_parameter("dust_amount", skin.beam_dust)
	haze.material = mat
	haze.z_index = 4
	add_child(haze)


func _add_dust(skin: HudSkin) -> void:
	if get_node_or_null("Dust") != null:
		return
	var dust := GPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 16
	dust.lifetime = 2.6
	dust.preprocess = 1.4
	dust.local_coords = true
	dust.position = Vector2(96, 0)
	dust.z_index = 5
	var mote := UiArt.texture("vfx_dust_mote")
	if mote:
		dust.texture = mote
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(88, 16, 0)
	mat.direction = Vector3(1, 0, 0)
	mat.spread = 16.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 20.0
	mat.gravity = Vector3(0, -3, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.5
	mat.color = Color(1.0, 0.95, 0.8, 0.32)
	dust.process_material = mat
	add_child(dust)


func _noise_tex() -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.07
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := (n.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

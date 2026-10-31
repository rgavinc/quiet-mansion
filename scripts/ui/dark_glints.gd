extends Node2D
## Dark-stage puppet visibility: puppets OUTSIDE the flashlight light get faint eye glints and a
## dim flat silhouette, drawn unshaded above the lighting. Read-only: it only looks at the
## `enemies` group (Enemy.state, the "Anim" AnimatedSprite2D's animation / frame / flip_h) and
## the player's `lights()` query; it never writes to an enemy.
##
## Art is manifest-only: `vfx_eye_glint` / `vfx_eye_glint_calm` (via AnimLibrary) and the puppet's
## own current frame for the silhouette. Eye positions are `AnimLibrary.meta(slot).eye_points`
## for the puppet's CURRENT animation slot and frame (docs/DESIGN.md "Eye glint").
##
## Lives in WorldOverlay's follow-viewport CanvasLayer, so the level's CanvasModulate darkness
## and world lights never touch it; its material is also CanvasItemMaterial UNSHADED.
## Free-safe: nothing per enemy is kept except a phase number, pruned when the enemy is gone.

const SILHOUETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(0.45, 0.55, 0.85, 0.2);
void fragment() {
	COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).a);
}
"""

var skin: HudSkin
var bus: Node

var _t := 0.0
var _phase: Dictionary = {}      # enemy instance_id -> glint frame offset
var _next_phase := 0
var _glint_frames: SpriteFrames
var _active := false
var _ambient_node: CanvasModulate
var _ambient_check := 0
var _stage_look_script: Script
var _stage_look_checked := false
var _sil_material: ShaderMaterial
var _sil: Node2D
## What the last frame drew, for tests / debugging: {glints: [{slot, frame, rect}], silhouettes: int}
var last_draw: Dictionary = {"glints": [], "silhouettes": []}


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	if bus == null:
		bus = UiArt.bus()
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	z_index = -1   # under the ring / meters / gauge (same layer)
	_sil_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SILHOUETTE_SHADER
	_sil_material.shader = sh
	_sil = Node2D.new()   # own canvas item: the silhouette needs the flat-tint shader, glints don't
	_sil.name = "Silhouettes"
	_sil.material = _sil_material
	_sil.z_index = -1     # under the glints
	add_child(_sil)
	_sil.draw.connect(_draw_silhouettes)
	_glint_frames = AnimLibrary.frames_for([skin.glint_calm_slot, skin.glint_hunting_slot])
	_wire(true)


func _enter_tree() -> void:
	if is_node_ready():
		_wire(true)


## Method connection (no lambda), only while in the tree.
func _exit_tree() -> void:
	_wire(false)


func _wire(on: bool) -> void:
	if bus == null or not is_instance_valid(bus) or not bus.has_signal(&"stage_started"):
		return
	var connected: bool = bus.is_connected(&"stage_started", _on_stage)
	if on and not connected:
		bus.connect(&"stage_started", _on_stage)
	elif not on and connected:
		bus.disconnect(&"stage_started", _on_stage)


func _on_stage(_n: int) -> void:
	_ambient_node = null
	_ambient_check = 0
	_phase.clear()
	queue_redraw()


# --- pure helpers (static: unit-tested without a scene) ---------------------------------
## The glint slot for an enemy state: calm/return -> calm glint, stunned -> "" (eyes shut),
## everything else (and any unknown state) -> hunting glint.
static func glint_slot_for(state: Variant, sk: HudSkin) -> String:
	if state is int or state is float:
		match int(state):
			Enemy.State.CALM, Enemy.State.RETURN:
				return sk.glint_calm_slot
			Enemy.State.STUNNED:
				return ""
	return sk.glint_hunting_slot


## Alpha actually drawn: the skin value clamped into [GLINT_ALPHA_MIN, 1].
static func effective_alpha(sk: HudSkin) -> float:
	return clampf(sk.glint_alpha, HudSkin.GLINT_ALPHA_MIN, 1.0)


## Eye pixels of `slot` frame `frame` in the frame as DRAWN (x mirrored when flipped:
## x' = frame_w - 1 - x, an exact pixel mirror). [] when the eyes are shut on that frame, when
## the slot has no eye_points, or when the manifest entry is malformed (count != frames).
static func eye_pixels(slot: String, frame: int, flipped: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var m := AnimLibrary.meta(slot)
	var pts: Variant = m.get("eye_points", null)
	if not (pts is Array) or (pts as Array).size() != int(m.get("frames", -1)):
		return out
	if frame < 0 or frame >= (pts as Array).size():
		return out
	var fs: Array = m.get("frame_size", [])
	if flipped and fs.size() != 2:
		return out
	var entry: Variant = (pts as Array)[frame]
	if not (entry is Array):
		return out
	for p in entry:
		if p is Array and (p as Array).size() == 2:
			var x := float(p[0])
			out.append(Vector2((float(fs[0]) - 1.0 - x) if flipped else x, float(p[1])))
	return out


## Glint loop frame for a puppet: 6 fps (manifest), `phase` frames ahead so a crowd never blinks
## in unison.
static func glint_frame(t: float, fps: float, frames: int, phase: int) -> int:
	if frames <= 0:
		return 0
	return posmod(int(floor(t * fps)) + phase, frames)


# --- activation --------------------------------------------------------------------------
## Stage ambient luminance 0..1 if the level reports one, else -1:
##  1. a `StageLook` global class that exposes a float `ambient` (Lead's #52 follow-up),
##  2. the level's `StageAmbient` CanvasModulate (what StageLook.apply adds today).
func current_ambient() -> float:
	var sl := _stage_look()
	if sl != null:
		var v: Variant = sl.get(&"ambient")
		if v is float:
			return clampf(v, 0.0, 1.0)
		if v is Color:
			return (v as Color).get_luminance()
	if _ambient_node == null or not is_instance_valid(_ambient_node):
		_ambient_node = null
		if _ambient_check <= 0 and is_inside_tree():
			_ambient_check = 30
			var root: Node = get_parent() if get_parent() != null else self
			_ambient_node = root.find_child("StageAmbient", true, false) as CanvasModulate
		_ambient_check -= 1
	if _ambient_node != null:
		return _ambient_node.color.get_luminance()
	return -1.0


func _stage_look() -> Script:
	if not _stage_look_checked:
		_stage_look_checked = true
		for c in ProjectSettings.get_global_class_list():
			if c.get("class", "") == "StageLook":
				var s = load(str(c.get("path", "")))
				if s is Script and "ambient" in s:
					_stage_look_script = s
				break
	return _stage_look_script


func _stage() -> int:
	return bus.get_stage() if bus != null and is_instance_valid(bus) and bus.has_method(&"get_stage") else 1


## Dark stage? ambient below the skin threshold when known, else stage >= the skin fallback.
func darkness_active() -> bool:
	if not skin.glints_enabled:
		return false
	var amb := current_ambient()
	if amb >= 0.0:
		return amb < skin.dark_ambient_threshold
	return _stage() >= skin.dark_fallback_stage


# --- light query --------------------------------------------------------------------------
func _player() -> Node2D:
	if not is_inside_tree():
		return null
	var p := get_tree().get_first_node_in_group(&"player")
	return p as Node2D


## True when world point `p` is in the flashlight's light: the player's own cone query
## (`lights()`: on, in range, in angle; what startle uses) or inside the inner part of the soft
## beam blob. No player = nothing lights it.
func is_lit(p: Vector2) -> bool:
	var pl := _player()
	if pl == null or not pl.has_method(&"lights"):
		return false
	if pl.lights(p):
		return true
	if not pl.has_method(&"light_on") or not pl.light_on():
		return false
	var beam := pl.get_node_or_null(^"Flashlight/Beam") as PointLight2D
	if beam != null and beam.texture != null and beam.visible and beam.is_visible_in_tree():
		var radius := beam.texture.get_width() * 0.5 * beam.texture_scale * skin.blob_lit_fraction
		return beam.global_position.distance_to(p) <= radius
	return false


# --- per-enemy plans ---------------------------------------------------------------------
func _anim_of(e: Node) -> AnimatedSprite2D:
	return e.get_node_or_null(^"Anim") as AnimatedSprite2D


func _usable(e: Variant) -> bool:
	return e != null and is_instance_valid(e) and e is Node2D and (e as Node2D).is_inside_tree() \
			and not (e as Node).is_queued_for_deletion() and (e as CanvasItem).is_visible_in_tree()


## Sprite-frame centre in world space: the point the light test uses.
func _centre_of(spr: AnimatedSprite2D) -> Vector2:
	return spr.global_transform * (spr.offset if spr.centered else spr.offset + _frame_size(spr) * 0.5)


func _frame_size(spr: AnimatedSprite2D) -> Vector2:
	if spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
		return Vector2.ZERO
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	return tex.get_size() if tex != null else Vector2.ZERO


func phase_for(e: Node) -> int:
	var id := e.get_instance_id()
	if not _phase.has(id):
		_phase[id] = _next_phase
		_next_phase += 1
	return int(_phase[id])


## Glints for one enemy (world-space draw rects), [] when it is lit, shut-eyed, or has no
## usable eye_points. Each: {slot, frame, rect: Rect2}.
func glints_for(e: Node2D) -> Array:
	var out: Array = []
	var spr := _anim_of(e)
	if spr == null or spr.sprite_frames == null:
		return out
	var slot := glint_slot_for(e.get(&"state"), skin)
	if slot.is_empty() or not _glint_frames.has_animation(slot):
		return out
	var anim := str(spr.animation)
	var eyes := eye_pixels(anim, spr.frame, spr.flip_h)
	if eyes.is_empty():
		return out
	var meta := AnimLibrary.meta(slot)
	var n := _glint_frames.get_frame_count(slot)
	var gf := glint_frame(_t, float(meta.get("fps", 6)), n, phase_for(e))
	var gs := _frame_size_of(meta)
	var piv := AnimLibrary.pivot(slot)
	var tl := _frame_topleft(spr)
	var sc := spr.global_transform.get_scale().abs()
	for p in eyes:
		var at := spr.global_transform * (tl + p)   # world pos of the eye pixel's top-left corner
		out.append({"slot": slot, "frame": gf, "rect": Rect2(at - piv * sc, gs * sc)})
	return out


func _frame_size_of(meta: Dictionary) -> Vector2:
	var fs: Array = meta.get("frame_size", [7, 7])
	return Vector2(float(fs[0]), float(fs[1]))


func _frame_topleft(spr: AnimatedSprite2D) -> Vector2:
	return spr.offset - (_frame_size(spr) * 0.5 if spr.centered else Vector2.ZERO)


## Silhouette of the enemy's current frame as {texture, xform: Transform2D, rect: Rect2}, or {}.
func silhouette_for(e: Node2D) -> Dictionary:
	var spr := _anim_of(e)
	if spr == null or spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
		return {}
	var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
	if tex == null:
		return {}
	var size := tex.get_size()
	var tl := _frame_topleft(spr)
	var rect := Rect2(tl, size)
	if spr.flip_h:
		rect = Rect2(tl.x + size.x, tl.y, -size.x, size.y)
	return {"texture": tex, "xform": spr.global_transform, "rect": rect}


## Draw plan for the current frame: glints + silhouettes of every live enemy outside the light.
func plan() -> Dictionary:
	var out := {"glints": [], "silhouettes": []}
	if not is_inside_tree() or not darkness_active():
		return out
	var live := {}
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not _usable(e):
			continue
		live[e.get_instance_id()] = true
		var spr := _anim_of(e)
		if spr == null or is_lit(_centre_of(spr)):
			continue
		out.glints.append_array(glints_for(e))
		var s := silhouette_for(e)
		if not s.is_empty():
			out.silhouettes.append(s)
	for id in _phase.keys():
		if not live.has(id):
			_phase.erase(id)
	return out


func _process(delta: float) -> void:
	_t += delta
	var was: bool = not (last_draw.glints.is_empty() and last_draw.silhouettes.is_empty())
	if is_inside_tree() and darkness_active():
		_replan()
	elif was:
		last_draw = {"glints": [], "silhouettes": []}
		queue_redraw()
		_sil.queue_redraw()


func _replan() -> void:
	last_draw = plan()
	queue_redraw()
	_sil.queue_redraw()


func _draw() -> void:
	var a := effective_alpha(skin)
	for g in last_draw.glints:
		var tex := _glint_frames.get_frame_texture(g.slot, g.frame)
		if tex != null:
			draw_texture_rect(tex, (g.rect as Rect2), false, Color(1, 1, 1, a))


func _draw_silhouettes() -> void:
	_sil_material.set_shader_parameter(&"tint", Color(skin.silhouette_color.r, skin.silhouette_color.g,
			skin.silhouette_color.b, skin.silhouette_alpha))
	for s in last_draw.silhouettes:
		_sil.draw_set_transform_matrix(_sil.global_transform.affine_inverse() * (s.xform as Transform2D))
		_sil.draw_texture_rect(s.texture as Texture2D, s.rect as Rect2, false)
	_sil.draw_set_transform_matrix(Transform2D.IDENTITY)

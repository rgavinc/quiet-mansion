extends Node2D
## Reusable FE curtain sway: a cheap vertex-sway shader attached to a prop's sprite.
## Lead places the curtain / drape; this only adds the motion.

const META := &"fe_curtain_fx"
const SWAY := """
shader_type canvas_item;
uniform float time_scale = 1.1;
uniform float amplitude = 0.045;
void vertex() {
	float w = sin(TIME * time_scale + VERTEX.y * 0.12) * amplitude * UV.y;
	VERTEX.x += w * 24.0;
}
"""

var skin: HudSkin
var _mat: ShaderMaterial


## Apply the sway shader to `host` (or its first Sprite2D / AnimatedSprite2D). Idempotent.
static func attach_to(host: Node2D, skin: HudSkin = null) -> Node2D:
	if host == null or not is_instance_valid(host):
		return null
	for c in host.get_children():
		if c is Node2D and c.get_meta(META, false):
			return c
	if host.get_meta(META, false) and host.material is ShaderMaterial:
		return host
	var fx: Node2D = load("res://scripts/ui/decor_curtain.gd").new()
	if skin:
		fx.skin = skin
	fx.name = "FeCurtainFx"
	fx.set_meta(META, true)
	host.add_child(fx)
	fx._apply()
	return fx


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	set_meta(META, true)
	_apply()


func _shader_mat() -> ShaderMaterial:
	if _mat:
		return _mat
	var sh := Shader.new()
	sh.code = SWAY
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	return _mat


func _apply() -> void:
	var target := _find_sprite(get_parent() if get_parent() is Node2D else self)
	if target == null:
		return
	if target.material is ShaderMaterial and str((target.material as ShaderMaterial).shader.code).contains("time_scale"):
		return
	target.material = _shader_mat()


func _find_sprite(n: Node) -> CanvasItem:
	if n == null:
		return null
	if n is Sprite2D or n is AnimatedSprite2D:
		return n
	for c in n.get_children():
		if c == self:
			continue
		var found := _find_sprite(c)
		if found:
			return found
	return null


func has_sway() -> bool:
	var target := _find_sprite(get_parent() if get_parent() is Node2D else self)
	return target != null and target.material is ShaderMaterial

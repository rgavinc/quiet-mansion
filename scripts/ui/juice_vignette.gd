class_name JuiceVignette
extends ColorRect
## Full-screen vignette used by hit flash and chase atmosphere. Shader is inline
## (no art path). Intensity 0 hides it.

const SHADER_CODE := """
shader_type canvas_item;
uniform float inner : hint_range(0.0, 1.0) = 0.4;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.05, 1.0);
void fragment() {
	float d = distance(UV, vec2(0.5, 0.5));
	float v = smoothstep(inner, 1.05, d * 1.45);
	COLOR = vec4(tint.rgb, tint.a * intensity * v);
}
"""

var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0)
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	set_intensity(0.0)


func set_tint(c: Color) -> void:
	if _mat:
		_mat.set_shader_parameter(&"tint", c)


func set_inner(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter(&"inner", v)


func set_intensity(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter(&"intensity", clampf(v, 0.0, 1.0))
	visible = v > 0.001
	modulate.a = 1.0


func intensity() -> float:
	return float(_mat.get_shader_parameter(&"intensity")) if _mat else 0.0

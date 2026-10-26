class_name HudIcon
extends Control
## Small HUD icon. Uses the manifest texture for `slot` when it exists,
## otherwise draws a placeholder shape (heart / coin / item letter).
## `pop` is animated by the HUD for the change "pop" (drawn scale, so it is
## container-safe).

enum Kind { HEART, COIN, ITEM }

@export var kind: Kind = Kind.HEART
## Manifest slot name, e.g. "ui_heart_full". Empty = placeholder only.
@export var slot: String = ""
@export var filled: bool = true:
	set(v):
		filled = v
		queue_redraw()
@export var label_text: String = "":
	set(v):
		label_text = v
		queue_redraw()

var skin: HudSkin
var pop: float = 1.0:
	set(v):
		pop = v
		queue_redraw()


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	var s := skin.heart_size if kind == Kind.HEART else skin.icon_size
	if kind == Kind.ITEM:
		s = skin.slot_size - 12.0
	custom_minimum_size = Vector2(s, s)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func do_pop() -> void:
	var tw := create_tween()
	tw.tween_property(self, "pop", skin.pop_scale, skin.pop_time * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "pop", 1.0, skin.pop_time * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _draw() -> void:
	var c := size * 0.5
	draw_set_transform(c, 0.0, Vector2(pop, pop))
	var r := minf(size.x, size.y) * 0.5
	var slot_name := slot
	if kind == Kind.HEART and not slot.is_empty():
		slot_name = slot if filled else slot.replace("_full", "_empty")
	var tex := UiArt.texture(slot_name)
	if tex:
		var tex_rect := Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
		draw_texture_rect(tex, tex_rect, false)
		return
	match kind:
		Kind.HEART:
			_draw_heart(r)
		Kind.COIN:
			draw_circle(Vector2.ZERO, r, skin.gold_outline)
			draw_circle(Vector2.ZERO, r - 2.5, skin.gold_color)
			draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.22, skin.gold_color.lightened(0.5))
			draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 20, skin.gold_outline.lerp(skin.gold_color, 0.5), 1.5)
		Kind.ITEM:
			draw_circle(Vector2.ZERO, r * 0.8, skin.slot_border)
			if not label_text.is_empty():
				var font := get_theme_default_font()
				var fs := int(r)
				var txt := label_text.substr(0, 1).to_upper()
				var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, Vector2(-tw.x * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.85))


func _heart_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * float(i) / 32.0
		# Classic heart curve, scaled to r.
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(Vector2(x, y + 1.5) * (r / 17.0))
	return pts


func _draw_heart(r: float) -> void:
	var outer := _heart_points(r)
	draw_colored_polygon(outer, skin.heart_outline)
	var inner := _heart_points(r - 2.5)
	draw_colored_polygon(inner, skin.heart_full if filled else skin.heart_empty)
	if filled:
		draw_circle(Vector2(-r * 0.35, -r * 0.3), r * 0.16, skin.heart_full.lightened(0.45))

extends Node2D
## Shard burst + puff when a vase (or other vase-like breakable) breaks.
## Hooks NoiseBus.noise and plays when Item.is_vase(source). WorldObject.break_apart()
## has no `broke` signal; that would be the cleaner BE hook (emit after `broken = true`,
## before queue_free, with the world position).

var skin: HudSkin
var last_played: int = 0
var _live: Array = []


func _enter_tree() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	var nb := _bus()
	if nb and not nb.noise.is_connected(_on_noise):
		nb.noise.connect(_on_noise)


func _exit_tree() -> void:
	var nb := _bus()
	if nb and nb.noise.is_connected(_on_noise):
		nb.noise.disconnect(_on_noise)
	for n in _live:
		if is_instance_valid(n):
			n.queue_free()
	_live.clear()


func _bus() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null(^"/root/NoiseBus") if loop else null


func _on_noise(at: Vector2, _radius: float, _loudness: float, source: Node) -> void:
	if source != null and is_instance_valid(source) and Item.is_vase(source):
		play_at(at)


func play_at(at: Vector2) -> void:
	if skin == null:
		skin = HudSkin.load_default()
	last_played += 1
	var holder := Node2D.new()
	holder.name = "Shatter_%d" % last_played
	holder.global_position = at
	# Prefer the overlay (us) so the burst sits in the unshaded overlay layer.
	add_child(holder)
	_live.append(holder)
	var frames := UiArt.frames(skin.shatter_slot)
	if frames:
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = skin.shatter_slot
		spr.offset = AnimLibrary.offset_for(skin.shatter_slot)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(spr)
		spr.play()
		spr.animation_finished.connect(_free_holder.bind(holder))
	# Always spawn a cheap shard puff so the effect reads even without the strip.
	var puff := CPUParticles2D.new()
	puff.name = "Shards"
	puff.emitting = false
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.amount = 14
	puff.lifetime = skin.shatter_lifetime
	puff.direction = Vector2(0, -1)
	puff.spread = 80.0
	puff.initial_velocity_min = 40.0
	puff.initial_velocity_max = 110.0
	puff.gravity = Vector2(0, 280)
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.8
	puff.color = Color(0.85, 0.82, 0.78, 0.95)
	var mote := UiArt.texture("vfx_dust_mote")
	if mote:
		puff.texture = mote
	holder.add_child(puff)
	puff.emitting = true
	if frames == null:
		var tw := holder.create_tween()
		tw.tween_interval(skin.shatter_lifetime + 0.05)
		tw.tween_callback(_free_holder.bind(holder))


func _free_holder(holder: Node) -> void:
	_live.erase(holder)
	if is_instance_valid(holder):
		holder.queue_free()

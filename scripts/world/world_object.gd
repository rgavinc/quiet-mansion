class_name WorldObject
extends Node2D
## Base class for every interactable prop. Subclasses override the defaults below
## in _init() (or via the inspector). Back End owns.

@export var art_slot: String = ""            # manifest slot; art looked up by name only
@export var display_name: String = "Object"
@export var can_pick_up: bool = false
@export var throwable: bool = false
@export var breakable: bool = true
@export var break_on_touch: bool = true      # walking into it breaks it
@export var touch_radius: float = 12.0
@export var blocks_throws: bool = true       # thrown things shatter on it
@export var noise_radius: float = NoiseBus.DEFAULT_RADIUS
@export var noise_loudness: float = 1.0
@export var pickup_time_mult: float = 1.0    # x PlayerStats.pickup_time
@export var gold_inside: int = 0
@export var size: Vector2 = Vector2(20, 20)  # placeholder draw size

var broken: bool = false


func _ready() -> void:
	add_to_group("world_objects")
	add_to_group("obstacles")
	_build_visual()


func _build_visual() -> void:
	if art_slot != "" and AnimLibrary.has_slot(art_slot):
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = AnimLibrary.frames_for([art_slot])
		spr.animation = art_slot
		spr.offset = AnimLibrary.offset_for(art_slot)
		spr.play()
		add_child(spr)
	else:
		var r := ColorRect.new()
		r.size = size
		r.position = -size * 0.5
		r.color = Color(0.45, 0.35, 0.25)
		add_child(r)


func _physics_process(_delta: float) -> void:
	if broken or not break_on_touch:
		return
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p and p.global_position.distance_to(global_position) <= touch_radius:
		break_apart()


## Item dictionary that goes into Inventory when picked up.
func to_item() -> Dictionary:
	return {
		id = "%s_%d" % [display_name.to_snake_case(), get_instance_id()],
		name = display_name,
		slot = art_slot,
		throwable = throwable,
		script_path = get_script().resource_path,
		noise_radius = noise_radius,
		gold_inside = gold_inside,
	}


func break_apart() -> void:
	if broken or not breakable:
		return
	broken = true
	NoiseBus.emit_noise(global_position, noise_radius * PlayerStats.get_stat(&"noise_mult"), noise_loudness, self)
	_drop_gold(global_position, gold_inside)
	queue_free()


static func _drop_gold(at: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		PlayerStats.add_gold(amount)
		return
	var g := Node2D.new()
	g.set_script(load("res://scripts/world/gold_pickup.gd"))
	g.set("amount", amount)
	tree.current_scene.add_child.call_deferred(g)
	g.set_deferred("global_position", at)

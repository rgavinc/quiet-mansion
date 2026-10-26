extends CanvasLayer
## Screen-space FE HUD root: hearts + gold (top-left), alert counter (top-right),
## inventory strip (bottom-centre), off-screen chaser arrows (full screen), and
## the "Stage N" intro banner. Game-over / shop screens are separate layers.
## Instance `scenes/ui/hud.tscn` once per level. All data via FESignals.

const HealthGoldHud := preload("res://scripts/ui/health_gold_hud.gd")
const InventoryStrip := preload("res://scripts/ui/inventory_strip.gd")
const OffscreenArrows := preload("res://scripts/ui/offscreen_arrows.gd")
const AlertHud := preload("res://scripts/ui/alert_hud.gd")
const StageBanner := preload("res://scripts/ui/stage_banner.gd")

var skin: HudSkin
var health_gold: Control
var inventory: Control
var arrows: Control
var alert: Control
var banner: Control


func _ready() -> void:
	if skin == null:
		skin = HudSkin.load_default()
	var root := Control.new()
	root.name = "HudRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists("res://assets/ui/hud_theme.tres"):
		root.theme = load("res://assets/ui/hud_theme.tres")
	add_child(root)

	arrows = OffscreenArrows.new()
	arrows.name = "OffscreenArrows"
	arrows.skin = skin
	root.add_child(arrows)
	arrows.set_anchors_preset(Control.PRESET_FULL_RECT)

	health_gold = HealthGoldHud.new()
	health_gold.name = "HealthGold"
	health_gold.skin = skin
	root.add_child(health_gold)
	health_gold.set_anchors_preset(Control.PRESET_TOP_LEFT)

	inventory = InventoryStrip.new()
	inventory.name = "Inventory"
	inventory.skin = skin
	root.add_child(inventory)
	inventory.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	inventory.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inventory.grow_vertical = Control.GROW_DIRECTION_BEGIN
	alert = AlertHud.new()
	alert.name = "AlertHud"
	alert.skin = skin
	root.add_child(alert)
	alert.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	alert.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	banner = StageBanner.new()
	banner.name = "StageBanner"
	banner.skin = skin
	root.add_child(banner)
	# Display-only HUD: never eat clicks meant for the game (LMB pickup/throw).
	_ignore_mouse(root)
	child_entered_tree.connect(_ignore_mouse)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is Control and is_ancestor_of(n):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

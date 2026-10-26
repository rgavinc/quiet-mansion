extends CanvasLayer
## Screen-space FE HUD root: hearts + gold (top-left), alert counter (top-right),
## inventory strip (bottom-centre) with the "tap: throw lure" hint above it, owned items
## (under hearts + gold), minimap (top-right, Minimap item only), off-screen chaser arrows
## (full screen), and the "Stage N" intro banner. Game-over / shop screens are separate layers.
## Instance `scenes/ui/hud.tscn` once per level. All data via FESignals.

const HealthGoldHud := preload("res://scripts/ui/health_gold_hud.gd")
const InventoryStrip := preload("res://scripts/ui/inventory_strip.gd")
const OffscreenArrows := preload("res://scripts/ui/offscreen_arrows.gd")
const AlertHud := preload("res://scripts/ui/alert_hud.gd")
const StageBanner := preload("res://scripts/ui/stage_banner.gd")
const OwnedItemsStrip := preload("res://scripts/ui/owned_items_strip.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")
const LureHint := preload("res://scripts/ui/lure_hint.gd")

var skin: HudSkin
## PlayerStats for the item widgets (tests); null = each widget uses /root/PlayerStats.
var stats: Node
var health_gold: Control
var inventory: Control
var arrows: Control
var alert: Control
var banner: Control
var owned_items: Control
var minimap: Control
var lure_hint: Control
var hud_root: Control
## End screens (UiScreen: game over, win, shop) seen in the tree; the HUD hides while any is open.
var _screens: Array = []


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
	hud_root = root

	arrows = OffscreenArrows.new()
	arrows.name = "OffscreenArrows"
	arrows.skin = skin
	if stats:
		arrows.stats = stats
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

	owned_items = OwnedItemsStrip.new()
	owned_items.name = "OwnedItems"
	owned_items.skin = skin
	if stats:
		owned_items.stats = stats
	root.add_child(owned_items)
	owned_items.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	owned_items.position = Vector2(14, 112)   # under hearts/gold and the level's 2-line Hint (16, 64)

	lure_hint = LureHint.new()
	lure_hint.name = "LureHint"
	lure_hint.skin = skin
	root.add_child(lure_hint)
	lure_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	lure_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lure_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lure_hint.offset_bottom = -(skin.slot_size + 48.0)   # above the strip's name label

	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.skin = skin
	if stats:
		minimap.stats = stats
	root.add_child(minimap)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap.offset_top = 100.0   # under the alert counter and its pips
	minimap.offset_right = -8.0

	banner = StageBanner.new()
	banner.name = "StageBanner"
	banner.skin = skin
	root.add_child(banner)
	# Display-only HUD: never eat clicks meant for the game (LMB pickup/throw).
	_ignore_mouse(root)
	child_entered_tree.connect(_ignore_mouse)
	get_tree().node_added.connect(_on_node_added)
	_find_screens(get_tree().root)


## Hide every HUD widget while an end screen (game over / win / shop) is up.
func end_screen_open() -> bool:
	for sc in _screens:
		if is_instance_valid(sc) and sc.is_inside_tree() and sc.is_open():
			return true
	return false


func _update_end_screens() -> void:
	_screens = _screens.filter(func(sc): return is_instance_valid(sc))
	if hud_root:
		hud_root.visible = not end_screen_open()


func _track_screen(sc: UiScreen) -> void:
	if _screens.has(sc):
		return
	_screens.append(sc)
	for sig in [&"opened", &"closed", &"tree_exited"]:
		if not sc.is_connected(sig, _update_end_screens):
			sc.connect(sig, _update_end_screens)
	_update_end_screens()


func _find_screens(n: Node) -> void:
	if n is UiScreen:
		_track_screen(n)
	for c in n.get_children():
		_find_screens(c)


func _on_node_added(n: Node) -> void:
	if n is UiScreen:
		_track_screen(n)
	if n is Control and is_ancestor_of(n):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

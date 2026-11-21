extends CanvasLayer
## Screen-space FE HUD root: hearts + gold (top-left), alert counter (top-right),
## a bottom HUD bar holding the control hints, inventory strip ("Hold LMB to pick up"
## / item name) and seed readout, the "tap: throw lure" hint above the strip, Music Box
## lure pocket pips beside it, owned items
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
const LurePocket := preload("res://scripts/ui/lure_pocket.gd")
const SeedReadout := preload("res://scripts/ui/seed_readout.gd")

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
var lure_pocket: Control
var seed_readout: Label
var hud_root: Control
## Bottom chrome the control hints and item strip sit in, so they stay out of the play space.
var hint_bar: ColorRect
var control_hint: Label
var hit_feedback: CanvasLayer
var chase_atmosphere: CanvasLayer
var screen_transition: CanvasLayer
var pause_screen: CanvasLayer
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

	hint_bar = ColorRect.new()
	hint_bar.name = "HintBar"
	hint_bar.color = skin.hud_bar_color
	hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_bar)
	hint_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	hint_bar.offset_top = -skin.hud_bar_height
	hint_bar.offset_bottom = 0.0
	hint_bar.offset_left = 0.0
	hint_bar.offset_right = 0.0

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
	owned_items.position = Vector2(14, 62)   # under hearts/gold; control hints moved to the bottom bar

	lure_hint = LureHint.new()
	if stats:
		lure_hint.stats = stats
	lure_hint.name = "LureHint"
	lure_hint.skin = skin
	root.add_child(lure_hint)
	lure_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	lure_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lure_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lure_hint.offset_bottom = -(skin.slot_size + 48.0)   # above the strip's name label

	lure_pocket = LurePocket.new()   # Music Box pocket pips, right of the hand slots
	lure_pocket.name = "LurePocket"
	lure_pocket.skin = skin
	if stats:
		lure_pocket.stats = stats
	lure_pocket.anchor_strip = inventory
	root.add_child(lure_pocket)

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

	seed_readout = SeedReadout.new()
	seed_readout.name = "SeedReadout"
	root.add_child(seed_readout)
	seed_readout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	seed_readout.grow_vertical = Control.GROW_DIRECTION_BEGIN
	seed_readout.offset_left = 12.0
	seed_readout.offset_bottom = -8.0

	banner = StageBanner.new()
	banner.name = "StageBanner"
	banner.skin = skin
	root.add_child(banner)
	# Juice layers are children of this CanvasLayer but not of HudRoot, so they
	# free with the HUD. The ignore-hook skips them (pause buttons must stay clickable).
	_mount_juice()
	# Display-only HUD: never eat clicks meant for the game (LMB pickup/throw).
	_ignore_mouse(root)
	child_entered_tree.connect(_on_hud_child)
	get_tree().node_added.connect(_on_node_added)
	_find_screens(get_tree().root)


## Take the level's control-hint / status Label out of the play space and put it
## on the bottom HUD bar (left of the item slots, above the seed readout).
func mount_control_hint(label: Label) -> void:
	if label == null:
		return
	control_hint = label
	if hint_bar == null or not is_instance_valid(hint_bar):
		return
	var prev := label.get_parent()
	if prev:
		prev.remove_child(label)
	hint_bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_left = 14.0
	label.offset_bottom = -28.0   # above the seed readout in the same bar
	label.offset_right = 0.0
	label.offset_top = -52.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)


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
	if n is Control and is_ancestor_of(n) and not _juice_owns(n):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _mount_juice() -> void:
	hit_feedback = load("res://scripts/ui/hit_feedback.gd").new()
	hit_feedback.skin = skin
	add_child(hit_feedback)
	chase_atmosphere = load("res://scripts/ui/chase_atmosphere.gd").new()
	chase_atmosphere.skin = skin
	add_child(chase_atmosphere)
	screen_transition = load("res://scripts/ui/screen_transition.gd").new()
	screen_transition.skin = skin
	add_child(screen_transition)
	pause_screen = load("res://scripts/ui/pause_screen.gd").new()
	pause_screen.skin = skin
	add_child(pause_screen)


func _juice_owns(n: Node) -> bool:
	for j in [pause_screen, hit_feedback, chase_atmosphere, screen_transition]:
		if j != null and is_instance_valid(j) and (j == n or j.is_ancestor_of(n)):
			return true
	return false


func _on_hud_child(n: Node) -> void:
	if _juice_owns(n):
		return
	_ignore_mouse(n)


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

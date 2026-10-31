extends RefCounted
## FE dark-stage puppet visibility (scripts/ui/dark_glints.gd): glint choice by enemy state,
## manifest eye_points placement (flip-aware, `[]` = nothing), hidden in the flashlight light,
## stage / ambient activation, alpha floor, silhouette, clean frees. Read-only against enemies.

const DG := preload("res://scripts/ui/dark_glints.gd")
const FE := "res://scripts/ui/fe_signals.gd"
const PUPPET_SLOTS := ["puppet_calm", "puppet_startle", "puppet_chase", "puppet_chase_float", "puppet_reach_up", "puppet_rattle"]


func run_all() -> Dictionary:
	var failures: PackedStringArray = []
	var checks := [
		["glint_slot_by_enemy_state_stunned_none_unknown_hunting", test_state_mapping],
		["eye_pixels_flip_is_exact_mirror_for_every_slot_and_frame", test_flip_mirror],
		["empty_eye_points_frames_draw_nothing", test_empty_frames],
		["glint_centres_on_the_eye_pixel_flipped_and_unflipped", test_placement],
		["two_eyes_per_entry_and_slot_follows_current_animation", test_two_eyes_current_anim],
		["hidden_in_the_light_shown_outside_and_with_light_off", test_light_gate],
		["flashlight_blob_counts_as_light_near_its_centre", test_blob_gate],
		["active_by_stage_fallback_and_by_stage_ambient", test_activation],
		["alpha_never_below_60_percent", test_alpha],
		["per_puppet_phase_offsets_desync_the_loop", test_phase],
		["silhouette_is_current_frame_flat_tint_low_alpha_unshaded", test_silhouette],
		["nothing_drawn_when_inactive_and_node_is_unshaded", test_inactive_and_unshaded],
		["freeing_an_enemy_mid_glint_leaves_no_orphans_or_errors", test_free_clean],
		["stage_signal_connects_by_method_and_disconnects_on_exit", test_disconnect],
		["seed_readout_is_opaque_with_hard_outline", test_readout_style],
		["no_art_pixels_in_script_only_manifest_slots", test_manifest_only],
	]
	for c in checks:
		var err: String = c[1].call()
		if not err.is_empty():
			failures.append("%s: %s" % [c[0], err])
	return {"passed": checks.size() - failures.size(), "total": checks.size(), "failures": failures}


# --- fakes -------------------------------------------------------------------------------
class FakeEnemy extends Node2D:
	var state: int = 0
	var spr: AnimatedSprite2D
	func _init() -> void:
		add_to_group("enemies")
	func _ready() -> void:
		spr = AnimatedSprite2D.new()
		spr.name = "Anim"
		spr.sprite_frames = AnimLibrary.frames_for(["puppet_calm", "puppet_startle", "puppet_chase", "puppet_chase_float", "puppet_reach_up", "puppet_rattle"])
		spr.offset = AnimLibrary.offset_for("puppet_calm")
		add_child(spr)
		show_frame("puppet_calm", 0)
	func show_frame(slot: String, frame: int, flip: bool = false) -> void:
		spr.animation = slot
		spr.frame = frame
		spr.flip_h = flip


class FakePlayer extends Node2D:
	var lit_rect := Rect2()
	var on := true
	func _init() -> void:
		add_to_group("player")
	func lights(p: Vector2) -> bool:
		return on and lit_rect.has_point(p)
	func light_on() -> bool:
		return on


class _ErrCount extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		errors.append("%s:%d %s %s" % [file, line, code, rationale])


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A dark-stage DarkGlints (stage 5 on a fresh bus) plus cleanup list.
func _rig(stage: int = 5) -> Dictionary:
	var bus: Node = load(FE).new()
	bus.set("stage", stage)
	_root().add_child(bus)
	var dg: Node2D = DG.new()
	dg.set("bus", bus)
	_root().add_child(dg)
	return {"bus": bus, "dg": dg, "free": [dg, bus]}


func _enemy(at: Vector2, state: int = 0) -> FakeEnemy:
	var e := FakeEnemy.new()
	e.position = at
	e.state = state
	_root().add_child(e)
	return e


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()


# --- tests -------------------------------------------------------------------------------
func test_state_mapping() -> String:
	var sk := HudSkin.new()
	var want := {
		Enemy.State.CALM: sk.glint_calm_slot, Enemy.State.RETURN: sk.glint_calm_slot,
		Enemy.State.STUNNED: "",
		Enemy.State.STARTLED: sk.glint_hunting_slot, Enemy.State.CHASE: sk.glint_hunting_slot,
		Enemy.State.SEARCH: sk.glint_hunting_slot, Enemy.State.REACH: sk.glint_hunting_slot,
		Enemy.State.RATTLE: sk.glint_hunting_slot, Enemy.State.RECOVER: sk.glint_hunting_slot,
	}
	if want.size() != Enemy.State.size():
		return "mapping table must cover every Enemy.State (%d vs %d)" % [want.size(), Enemy.State.size()]
	for s in want:
		var got: String = DG.glint_slot_for(s, sk)
		if got != want[s]:
			return "state %s: slot '%s', want '%s'" % [Enemy.State.keys()[s], got, want[s]]
	if sk.glint_calm_slot != "vfx_eye_glint_calm" or sk.glint_hunting_slot != "vfx_eye_glint":
		return "default slots must be the manifest's vfx_eye_glint_calm / vfx_eye_glint"
	for odd in [99, -1, null, "chase"]:
		if DG.glint_slot_for(odd, sk) != sk.glint_hunting_slot:
			return "unknown state %s must give the hunting glint" % [odd]
	return ""


func test_flip_mirror() -> String:
	for slot in PUPPET_SLOTS:
		var m := AnimLibrary.meta(slot)
		var fw: int = int(m.frame_size[0])
		var n: int = int(m.frames)
		for f in n:
			var a: Array[Vector2] = DG.eye_pixels(slot, f, false)
			var b: Array[Vector2] = DG.eye_pixels(slot, f, true)
			var raw: Array = m.eye_points[f]
			if a.size() != raw.size() or b.size() != raw.size():
				return "%s f%d: %d / %d points, manifest has %d" % [slot, f, a.size(), b.size(), raw.size()]
			for i in raw.size():
				if a[i] != Vector2(raw[i][0], raw[i][1]):
					return "%s f%d: unflipped point %s != manifest %s" % [slot, f, a[i], raw[i]]
				if b[i] != Vector2(fw - 1 - raw[i][0], raw[i][1]):
					return "%s f%d: flipped point %s, want x' = %d - 1 - x" % [slot, f, b[i], fw]
	return ""


func test_empty_frames() -> String:
	var r := _rig()
	var e := _enemy(Vector2(100, 100))
	var err := ""
	for pair in [["puppet_calm", 3], ["puppet_startle", 1]]:
		if not (AnimLibrary.meta(pair[0]).eye_points[pair[1]] as Array).is_empty():
			err = "fixture: %s frame %d should be [] in the manifest" % pair
			break
		for flip in [false, true]:
			e.show_frame(pair[0], pair[1], flip)
			if not (r.dg.glints_for(e) as Array).is_empty():
				err = "%s f%d flip %s must draw nothing" % [pair[0], pair[1], flip]
		# the next open frame does draw
		e.show_frame(pair[0], 0)
		if (r.dg.glints_for(e) as Array).is_empty() and not err.is_empty():
			err = "frame 0 should draw"
	# malformed / missing eye_points: draw nothing rather than guess
	if not DG.eye_pixels("vfx_eye_glint", 0, false).is_empty() or not DG.eye_pixels("no_such_slot", 0, true).is_empty():
		err = "slots without eye_points must give no points"
	if not DG.eye_pixels("puppet_calm", 99, false).is_empty() or not DG.eye_pixels("puppet_calm", -1, false).is_empty():
		err = "out-of-range frame must give no points"
	_free(r.free + [e])
	return err


## The glint pixel (3,3) must overlay the eye pixel as the sprite is drawn.
func test_placement() -> String:
	var r := _rig()
	var e := _enemy(Vector2(400, 300))
	var err := ""
	var piv := AnimLibrary.pivot("vfx_eye_glint")
	for flip in [false, true]:
		for pair in [["puppet_calm", 0], ["puppet_chase", 2], ["puppet_rattle", 5]]:
			e.show_frame(pair[0], pair[1], flip)
			e.state = Enemy.State.CHASE
			var gl: Array = r.dg.glints_for(e)
			var pts: Array = AnimLibrary.meta(pair[0]).eye_points[pair[1]]
			if gl.size() != pts.size() or gl.is_empty():
				err = "%s f%d: %d glints for %d eyes" % [pair[0], pair[1], gl.size(), pts.size()]
				break
			var fs: Array = AnimLibrary.meta(pair[0]).frame_size
			var centre: Vector2 = e.position + e.spr.offset   # world centre of the centred frame
			for i in pts.size():
				# independent of the production maths: eye pixel centre relative to the frame centre
				var dx: float = float(pts[i][0]) + 0.5 - fs[0] * 0.5
				if flip:
					dx = -dx
				var dy: float = float(pts[i][1]) + 0.5 - fs[1] * 0.5
				var want := centre + Vector2(dx, dy)
				var rect: Rect2 = gl[i].rect
				var got := rect.position + piv + Vector2(0.5, 0.5)   # centre of glint pixel (3,3)
				if got.distance_to(want) > 0.01:
					err = "%s f%d flip %s eye %d: glint centre %s, eye %s" % [pair[0], pair[1], flip, i, got, want]
					break
				if rect.size != Vector2(7, 7):
					err = "glint must draw 7x7, got %s" % rect.size
			if not err.is_empty():
				break
		if not err.is_empty():
			break
	_free(r.free + [e])
	return err


func test_two_eyes_current_anim() -> String:
	var r := _rig()
	var e := _enemy(Vector2(0, 0), Enemy.State.CHASE)
	var err := ""
	e.show_frame("puppet_chase", 3)
	var gl: Array = r.dg.glints_for(e)
	if gl.size() != 2 or gl[0].slot != "vfx_eye_glint":
		err = "chase f3 should give 2 hunting glints, got %s" % [gl.map(func(g): return g.slot)]
	e.state = Enemy.State.CALM
	e.show_frame("puppet_calm", 0)
	gl = r.dg.glints_for(e)
	if err.is_empty() and (gl.size() != 2 or gl[0].slot != "vfx_eye_glint_calm"):
		err = "calm f0 should give 2 calm glints"
	e.state = Enemy.State.STUNNED
	e.show_frame("puppet_startle", 6)
	if err.is_empty() and not (r.dg.glints_for(e) as Array).is_empty():
		err = "stunned must draw no glint"
	# same frame, different slot -> different eye points (positions come from the slot)
	var a: Array[Vector2] = DG.eye_pixels("puppet_chase", 0, false)
	var b: Array[Vector2] = DG.eye_pixels("puppet_calm", 0, false)
	if err.is_empty() and a == b:
		err = "fixture: chase and calm eye points should differ"
	_free(r.free + [e])
	return err


func test_light_gate() -> String:
	var r := _rig()
	var pl := FakePlayer.new()
	_root().add_child(pl)
	var e := _enemy(Vector2(500, 500), Enemy.State.CHASE)
	e.show_frame("puppet_chase", 0)
	var err := ""
	var centre: Vector2 = e.position + e.spr.offset
	pl.lit_rect = Rect2(centre - Vector2(50, 50), Vector2(100, 100))
	var plan: Dictionary = r.dg.plan()
	if not (plan.glints.is_empty() and plan.silhouettes.is_empty()):
		err = "in the light: no glints, no silhouette (got %d / %d)" % [plan.glints.size(), plan.silhouettes.size()]
	pl.lit_rect = Rect2(Vector2(5000, 5000), Vector2(10, 10))
	plan = r.dg.plan()
	if err.is_empty() and (plan.glints.size() != 2 or plan.silhouettes.size() != 1):
		err = "outside the light: 2 glints + 1 silhouette, got %d / %d" % [plan.glints.size(), plan.silhouettes.size()]
	pl.lit_rect = Rect2(centre - Vector2(50, 50), Vector2(100, 100))
	pl.on = false   # light off: nothing is lit
	plan = r.dg.plan()
	if err.is_empty() and plan.glints.size() != 2:
		err = "flashlight off: glints show"
	pl.on = true
	_root().remove_child(pl)   # no player at all
	plan = r.dg.plan()
	if err.is_empty() and plan.glints.size() != 2:
		err = "no player: nothing lights the puppet, glints show"
	pl.free()
	# two puppets, one lit and one not: only the dark one is drawn
	var pl2 := FakePlayer.new()
	_root().add_child(pl2)
	var e2 := _enemy(Vector2(900, 500), Enemy.State.CALM)
	pl2.lit_rect = Rect2(centre - Vector2(50, 50), Vector2(100, 100))
	plan = r.dg.plan()
	if err.is_empty() and (plan.glints.size() != 2 or plan.glints[0].slot != "vfx_eye_glint_calm" or plan.silhouettes.size() != 1):
		err = "only the unlit calm puppet should draw (calm glint x2 + 1 silhouette), got %d glints" % plan.glints.size()
	_free(r.free + [e, e2, pl2])
	return err


func test_blob_gate() -> String:
	var r := _rig()
	var pl := FakePlayer.new()
	pl.on = true
	_root().add_child(pl)
	var fl := Node2D.new()
	fl.name = "Flashlight"
	pl.add_child(fl)
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.texture = UiArt.texture("flashlight_blob")
	beam.texture_scale = 2.8
	fl.add_child(beam)
	pl.position = Vector2(1000, 1000)   # cone rect is empty: only the blob can light things
	var near := _enemy(Vector2(1010, 1030), Enemy.State.CHASE)
	var far := _enemy(Vector2(1010 + 400, 1030), Enemy.State.CHASE)
	near.show_frame("puppet_chase", 0)
	far.show_frame("puppet_chase", 0)
	var err := ""
	if beam.texture == null:
		err = "fixture: flashlight_blob slot missing"
	elif not r.dg.is_lit(near.position + near.spr.offset):
		err = "a puppet at the beam centre is lit"
	elif r.dg.is_lit(far.position + far.spr.offset):
		err = "a puppet 400px away is not lit"
	_free(r.free + [near, far, pl])
	return err


func test_activation() -> String:
	var err := ""
	for pair in [[1, false], [2, false], [3, false], [4, false], [5, true]]:
		var r := _rig(pair[0])
		var dg: Node2D = r.dg
		if dg.current_ambient() >= 0.0:
			err = "fixture: no ambient expected without a StageAmbient node"
		elif dg.darkness_active() != pair[1]:
			err = "stage %d fallback: active %s, want %s" % [pair[0], dg.darkness_active(), pair[1]]
		_free(r.free)
		if not err.is_empty():
			return err
	# a level-reported ambient wins over the stage number
	var holder := Node2D.new()
	_root().add_child(holder)
	var amb := CanvasModulate.new()
	amb.name = "StageAmbient"
	holder.add_child(amb)
	var r2 := _rig(1)
	_root().remove_child(r2.dg)
	holder.add_child(r2.dg)   # sibling of the ambient node, like WorldOverlay under the level
	var dg2: Node2D = r2.dg
	amb.color = Color(0.045, 0.055, 0.10)   # stage-5 look
	if not dg2.darkness_active():
		err = "dark StageAmbient (%.3f) should activate even on stage 1" % dg2.current_ambient()
	amb.color = Color(0.50, 0.42, 0.34)      # stage-1 look
	# PD: with the real StageTable looks, only stage 5 is dark enough for glints.
	if err.is_empty():
		for s in range(1, 6):
			amb.color = StageTable.look(s).ambient
			if dg2.darkness_active() != (s == 5):
				err = "real stage %d ambient (%.3f): active %s, want %s" % [s, dg2.current_ambient(), dg2.darkness_active(), s == 5]
				break
	amb.color = Color(0.50, 0.42, 0.34)
	if err.is_empty() and dg2.darkness_active():
		err = "light StageAmbient (%.3f) should deactivate even on stage 5" % dg2.current_ambient()
	amb.color = Color(0.15, 0.17, 0.24)      # stage 4 look: just under the 0.2 threshold
	if err.is_empty() and not dg2.darkness_active():
		err = "stage 4 ambient %.3f should be active" % dg2.current_ambient()
	amb.color = Color(0.27, 0.26, 0.30)      # stage 3 look
	if err.is_empty() and dg2.darkness_active():
		err = "stage 3 ambient %.3f should be inactive" % dg2.current_ambient()
	dg2.skin.glints_enabled = false
	amb.color = Color(0.0, 0.0, 0.0)
	if err.is_empty() and dg2.darkness_active():
		err = "glints_enabled=false must switch it off"
	dg2.skin.glints_enabled = true
	_free([holder, r2.bus])
	return err


func test_alpha() -> String:
	var sk := HudSkin.new()
	if DG.effective_alpha(sk) < 0.6:
		return "default alpha %.2f below 0.6" % DG.effective_alpha(sk)
	var tres := HudSkin.load_default()
	if DG.effective_alpha(tres) < 0.6:
		return "hud_skin.tres alpha below 0.6"
	for bad in [0.0, 0.4, 0.59, -3.0]:
		sk.glint_alpha = bad
		if DG.effective_alpha(sk) < 0.6:
			return "alpha %.2f must clamp up to 0.6, got %.2f" % [bad, DG.effective_alpha(sk)]
	sk.glint_alpha = 5.0
	if DG.effective_alpha(sk) != 1.0:
		return "alpha above 1 must clamp to 1"
	return ""


func test_phase() -> String:
	# static: loop wraps, 6 fps, phase shifts it
	var frames := 6
	if DG.glint_frame(0.0, 6.0, frames, 0) != 0 or DG.glint_frame(0.5, 6.0, frames, 0) != 3 \
			or DG.glint_frame(1.0, 6.0, frames, 0) != 0 or DG.glint_frame(0.0, 6.0, frames, 2) != 2 \
			or DG.glint_frame(1.0 / 6.0, 6.0, frames, 5) != 0:
		return "glint_frame maths wrong"
	var r := _rig()
	var es: Array = []
	for i in 6:
		var e := _enemy(Vector2(100 * i, 0), Enemy.State.CHASE)
		e.show_frame("puppet_chase", 0)
		es.append(e)
	var seen := {}
	for e in es:
		seen[(r.dg.glints_for(e)[0] as Dictionary).frame] = true
	var err := ""
	if seen.size() < 6:
		err = "6 puppets at the same time should show 6 different glint frames, got %d" % seen.size()
	_free(r.free + es)
	return err


func test_silhouette() -> String:
	var r := _rig()
	var dg: Node2D = r.dg
	var e := _enemy(Vector2(200, 200), Enemy.State.CHASE)
	e.show_frame("puppet_chase", 2)
	var err := ""
	var s: Dictionary = dg.silhouette_for(e)
	var want_tex: Texture2D = e.spr.sprite_frames.get_frame_texture("puppet_chase", 2)
	if s.is_empty() or s.texture != want_tex:
		err = "silhouette must be the current frame's texture"
	elif (s.rect as Rect2).size.x <= 0.0:
		err = "unflipped silhouette rect should have positive width"
	else:
		e.show_frame("puppet_chase", 2, true)
		var sf: Dictionary = dg.silhouette_for(e)
		if (sf.rect as Rect2).size.x >= 0.0 or absf((sf.rect as Rect2).size.x) != (s.rect as Rect2).size.x:
			err = "flipped silhouette must mirror (negative width)"
	var sk: HudSkin = dg.skin
	if err.is_empty() and (sk.silhouette_alpha > 0.35 or sk.silhouette_alpha <= 0.0):
		err = "silhouette alpha %.2f should be subtle (0..0.35]" % sk.silhouette_alpha
	var sil: Node2D = dg.get_node("Silhouettes")
	var sm := sil.material as ShaderMaterial
	if err.is_empty() and (sm == null or not sm.shader.code.contains("unshaded")):
		err = "silhouette must use an unshaded flat-tint shader"
	if err.is_empty() and sm.shader.code.contains("res://"):
		err = "silhouette shader must not load art"
	_free(r.free + [e])
	return err


func test_inactive_and_unshaded() -> String:
	var r := _rig(2)   # bright stage
	var dg: Node2D = r.dg
	var e := _enemy(Vector2(200, 200), Enemy.State.CHASE)
	var err := ""
	var plan: Dictionary = dg.plan()
	if not (plan.glints.is_empty() and plan.silhouettes.is_empty()):
		err = "stage 2 must draw nothing"
	dg._process(0.1)
	if err.is_empty() and not (dg.last_draw.glints.is_empty() and dg.last_draw.silhouettes.is_empty()):
		err = "inactive _process must leave last_draw empty"
	var m := dg.material as CanvasItemMaterial
	if err.is_empty() and (m == null or m.light_mode != CanvasItemMaterial.LIGHT_MODE_UNSHADED):
		err = "DarkGlints must use an UNSHADED CanvasItemMaterial"
	var wo: Node2D = load("res://scenes/ui/world_overlay.tscn").instantiate()
	wo.set("bus", r.bus)
	_root().add_child(wo)
	var layer: CanvasLayer = wo.get("layer")
	if err.is_empty() and (wo.get("dark_glints") == null or wo.get("dark_glints").get_parent() != layer):
		err = "WorldOverlay must host DarkGlints in its own CanvasLayer (above the world's CanvasModulate)"
	if err.is_empty() and layer.layer < 1:
		err = "overlay layer must sit above the world canvas"
	_free(r.free + [e, wo])
	return err


## QA #18-style: kill an enemy between plan and draw; nothing logs, nothing leaks.
func test_free_clean() -> String:
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var r := _rig()
	var dg: Node2D = r.dg
	var es: Array = []
	for i in 3:
		var e := _enemy(Vector2(100 * i, 50), Enemy.State.CHASE)
		e.show_frame("puppet_chase", i)
		es.append(e)
	var log := _ErrCount.new()
	OS.add_logger(log)
	var err := ""
	dg._process(0.1)
	if dg.last_draw.glints.size() != 6 or dg.last_draw.silhouettes.size() != 3:
		err = "setup: 3 puppets should give 6 glints + 3 silhouettes, got %d / %d" % [dg.last_draw.glints.size(), dg.last_draw.silhouettes.size()]
	es[1].free()   # killed after the plan, before the next frame
	dg.notification(CanvasItem.NOTIFICATION_DRAW)   # real draw pass over the stale plan
	dg.get_node("Silhouettes").notification(CanvasItem.NOTIFICATION_DRAW)
	es[2].queue_free()   # queued: skipped at once
	dg._process(0.1)
	if err.is_empty() and (dg.last_draw.glints.size() != 2 or dg.last_draw.silhouettes.size() != 1):
		err = "after freeing 2 of 3: want 2 glints + 1 silhouette, got %d / %d" % [dg.last_draw.glints.size(), dg.last_draw.silhouettes.size()]
	if err.is_empty() and dg.get("_phase").size() != 1:
		err = "phase table must be pruned to live enemies, has %d" % dg.get("_phase").size()
	es[0].free()
	dg._process(0.1)
	OS.remove_logger(log)
	if err.is_empty() and not log.errors.is_empty():
		err = "errors: %s" % [log.errors]
	if err.is_empty() and dg.get("_phase").size() != 0:
		err = "phase table not empty after all enemies were freed"
	if is_instance_valid(es[2]):
		es[2].free()
	_free(r.free)
	var orphans_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if err.is_empty() and orphans_after > orphans_before:
		err = "orphan nodes grew %d -> %d" % [orphans_before, orphans_after]
	return err


func test_disconnect() -> String:
	var bus: Node = load(FE).new()
	_root().add_child(bus)
	var dg: Node2D = DG.new()
	dg.set("bus", bus)
	_root().add_child(dg)
	var err := ""
	if not bus.is_connected(&"stage_started", dg._on_stage):
		err = "DarkGlints should listen to stage_started while in the tree"
	_root().remove_child(dg)
	if err.is_empty() and bus.is_connected(&"stage_started", dg._on_stage):
		err = "DarkGlints must disconnect on _exit_tree"
	dg.free()
	bus.free()
	return err


func test_readout_style() -> String:
	var ro: Label = load("res://scripts/ui/seed_readout.gd").new()
	_root().add_child(ro)
	var err := ""
	var col := ro.get_theme_color("font_color")
	var out := ro.get_theme_color("font_outline_color")
	if col.a < 1.0:
		err = "readout text must be fully opaque (was 60%%), alpha %.2f" % col.a
	elif out.a < 1.0 or ro.get_theme_constant("outline_size") < 4:
		err = "readout needs a solid dark outline (alpha %.2f, size %d)" % [out.a, ro.get_theme_constant("outline_size")]
	elif ro.get_theme_font_size("font_size") > 14:
		err = "readout must stay small"
	elif col.get_luminance() > 0.85 or col.get_luminance() < 0.4:
		err = "readout colour should stay dim-looking but legible (luminance %.2f)" % col.get_luminance()
	else:
		# contrast against its own outline (what it sits on): WCAG ratio >= 7
		var l1 := _rel_lum(col)
		var l2 := _rel_lum(out)
		var ratio := (l1 + 0.05) / (l2 + 0.05)
		if ratio < 7.0:
			err = "text/outline contrast %.1f:1 too low" % ratio
	ro.free()
	return err


static func _rel_lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func test_manifest_only() -> String:
	var src := FileAccess.get_file_as_string("res://scripts/ui/dark_glints.gd")
	for bad in ["res://assets/", "Image.create", "set_pixel", "PlaceholderTexture", "GradientTexture"]:
		if src.contains(bad):
			return "dark_glints.gd must load art only through manifest slots (found '%s')" % bad
	for slot in ["vfx_eye_glint", "vfx_eye_glint_calm"]:
		if not AnimLibrary.has_slot(slot):
			return "manifest slot %s missing" % slot
	return ""

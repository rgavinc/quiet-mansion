extends "res://scripts/enemies/enemy_base.gd"
## Puppet hand: the stage 1-3 walker. All behaviour is the Enemy state machine
## (enemy_base.gd); this only sets the puppet's defaults and art slots. Back End owns.


func _init() -> void:
	type_id = &"puppet_hand"
	movement = MOVE_WALK
	anim_calm = "puppet_calm"
	anim_startle = "puppet_startle"
	anim_chase = "puppet_chase"
	anim_reach = "puppet_reach_up"   # manifest hit_frame / reach_height_px (PR #40); else 0.6 s / 40 px


func _ready() -> void:
	add_to_group("puppets")
	super._ready()

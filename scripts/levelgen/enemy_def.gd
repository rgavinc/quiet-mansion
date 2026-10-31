class_name EnemyDef
extends Resource
## Enemy definition (Lead owns the data; BE's `Enemy.apply_def` copies matching fields).
## Built from StageTable.ENEMY_TYPES by `StageTable.enemy_def(id)`; every generated enemy node
## gets one as `def` (no stand-in fill: the node count is exactly the stage table's `enemies`).
## `movement`: &"walk" (stages 1-3+, gravity, floors, stairs) or &"float" (stages 4-5 only,
## drifts through floor slabs, BE PR #26).

@export var type_id: StringName = &"puppet_hand"
@export var movement: StringName = &"walk"
@export var min_stage: int = 1
## Scene script for the body. Types without art/script yet use puppet_hand's body (an `Enemy`).
@export var script_path: String = ""

extends Node2D
class_name VillainView
## Gameplay adapter for the self-contained procedural rig. Origin matches the player anchor.
const RIG_SCENE = preload("res://character/villain.tscn")
var rig
var aim := 0.0
var off_aim := 0.0

func _ready() -> void:
	rig = RIG_SCENE.instantiate(); add_child(rig)
	set_items()
	Run.build_changed.connect(set_items)

func set_items() -> void:
	rig.set_items(Run.build.items,Run.ammo_id(),Run.FRAMES[Run.build.frame].id,Run.build.off)

func prepare_for_play() -> void: rig.prepare_for_play()

func set_state(state: Dictionary) -> void:
	aim = float(state.get("aim",aim)); off_aim = float(state.get("off_aim",aim))
	var complete = state.duplicate(); complete.off_aim = off_aim
	rig.set_state(complete)

func shoulder_global() -> Vector2: return rig.shoulder_global()
func muzzle_global(gun_index: int = 0, shot_index: int = -1) -> Vector2: return rig.muzzle_global(gun_index,shot_index)
func off_shoulder_global() -> Vector2: return rig.off_shoulder_global()
func off_muzzle_global(shot_index: int = -1) -> Vector2: return rig.off_muzzle_global(shot_index)
func anchor(node_name: String) -> Vector2: return rig.anchor_global(node_name)
func visual_bounds() -> Rect2: return rig.visual_bounds()

func gun_back_global(gun_index: int = 0) -> Vector2:
	# Measure hits from the shoulder so nearby enemies cannot hide inside a long barrel.
	var flip = -1.0 if cos(aim)<0.0 else 1.0
	var direction = Vector2(cos(aim),sin(aim))
	var perpendicular = Vector2(-flip*sin(aim),flip*cos(aim))
	return shoulder_global()-direction*4.0+perpendicular*rig.gun_offset(gun_index)

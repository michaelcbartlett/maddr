extends Node2D
class_name VillainView
## Gameplay adapter. The y-sort origin is the character's contact with the street.
const RIG_SCENE = preload("res://character/villain.tscn")
const FOOT_OFFSET := 16.5
var rig
var aim := 0.0
var off_aim := 0.0

func _ready() -> void:
	rig = RIG_SCENE.instantiate(); rig.position=Vector2(0,-FOOT_OFFSET); add_child(rig)
	set_items()
	Run.build_changed.connect(set_items)

func set_items() -> void:
	rig.set_items(Run.build.items,Run.primary_weapon_id(),Run.FRAMES[Run.build.frame].id,Run.arm_off())
	var secondary := Run.melee_spec(); var primary := Run.primary_melee_spec()
	rig.set_state({"melee_reach":secondary.get("reach",0.0),"primary_melee_reach":primary.get("reach",0.0)})

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
func visual_bounds() -> Rect2: return rig.transform*rig.visual_bounds()
func ground_global() -> Vector2: return global_position
func feet_global() -> Vector2: return rig.to_global(Vector2(0,FOOT_OFFSET))

func set_ground_lift(height: float) -> void:
	# Airborne poses lift the artwork; the sort point stays on its ground plane.
	rig.position=Vector2(0,-FOOT_OFFSET-height/maxf(scale.y,0.001))

func gun_back_global(gun_index: int = 0) -> Vector2:
	# Measure hits from the shoulder so nearby enemies cannot hide inside a long barrel.
	var flip = -1.0 if cos(aim)<0.0 else 1.0
	var direction = Vector2(cos(aim),sin(aim))
	var perpendicular = Vector2(-flip*sin(aim),flip*cos(aim))
	return shoulder_global()-direction*4.0+perpendicular*rig.gun_offset(gun_index)

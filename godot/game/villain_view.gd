extends Node2D
class_name VillainView
## Gameplay adapter. The y-sort origin is the character's contact with the street.
const RIG_SCENE = preload("res://character/villain.tscn")
const FOOT_OFFSET := 16.5
const WALK_LEAN := PI/45.0  # 4 degrees, about five pixels at head height.
const SPRINT_LEAN := PI/36.0
var rig
var aim := 0.0
var off_aim := 0.0
var movement_lean := 0.0
var _lean_clock := -1.0
var _ground_lift := 0.0

func _ready() -> void:
	rig = RIG_SCENE.instantiate(); rig.position=Vector2(0,-FOOT_OFFSET); add_child(rig)
	set_items()
	Run.build_changed.connect(set_items)

func set_items() -> void:
	rig.set_items(Run.build.items,Run.primary_weapon_id(),Run.FRAMES[Run.build.frame].id,Run.arm_off())
	var secondary := Run.melee_spec(); var primary := Run.primary_melee_spec()
	rig.set_state({"melee_reach":secondary.get("reach",0.0),"primary_melee_reach":primary.get("reach",0.0)})

func prepare_for_play() -> void:
	movement_lean=0.0; _lean_clock=-1.0; _apply_visual_transform()
	rig.prepare_for_play()

func set_state(state: Dictionary) -> void:
	aim = float(state.get("aim",aim)); off_aim = float(state.get("off_aim",aim))
	var complete = state.duplicate(); complete.off_aim = off_aim
	_update_movement_lean(complete)
	rig.set_state(complete)

func _update_movement_lean(state: Dictionary) -> void:
	# Arena samples the rig several times when firing/meleeing. Integrate once
	# per game clock tick, so weapon count never changes the easing speed.
	var clock: float=state.get("time",maxf(0.0,_lean_clock))
	var dt := clampf(clock-_lean_clock,0.0,0.1) if _lean_clock>=0.0 else 0.0
	if clock<_lean_clock: movement_lean=0.0; dt=0.0
	_lean_clock=clock
	var posed: bool=state.get("reaction","")!="" or state.get("zap",false) or state.get("dash_dir",Vector2.ZERO)!=Vector2.ZERO or float(state.get("shove",-1.0))>=0.0 or _ground_lift>0.0
	if posed:
		movement_lean=0.0
	else:
		var velocity: Vector2=state.get("move_velocity",Vector2.ZERO)
		var speed := maxf(1.0,float(state.get("move_speed",210.0)))
		var limit := SPRINT_LEAN if state.get("sprinting",false) else WALK_LEAN
		var target := limit*clampf(velocity.x/speed,-1.0,1.0) if state.get("moving",false) else 0.0
		var rate := 16.0 if is_zero_approx(target) else 12.0
		movement_lean=lerpf(movement_lean,target,1.0-exp(-rate*dt))
		if absf(movement_lean)<0.00001: movement_lean=0.0
	_apply_visual_transform()

func _apply_visual_transform() -> void:
	# Rotate around the feet, never around the gameplay/y-sort origin. All sprite
	# layers and worn gear inherit this transform; weapon pivots keep world aim.
	rig.rotation=movement_lean
	rig.position=-Vector2(0,FOOT_OFFSET).rotated(movement_lean)-Vector2(0,_ground_lift/maxf(scale.y,0.001))

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
	_ground_lift=height
	if height>0.0: movement_lean=0.0
	_apply_visual_transform()

func gun_back_global(gun_index: int = 0) -> Vector2:
	# Measure hits from the shoulder so nearby enemies cannot hide inside a long barrel.
	var flip = -1.0 if cos(aim)<0.0 else 1.0
	var direction = Vector2(cos(aim),sin(aim))
	var perpendicular = Vector2(-flip*sin(aim),flip*cos(aim))
	return shoulder_global()-direction*4.0+perpendicular*rig.gun_offset(gun_index)

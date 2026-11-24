extends SceneTree
## Foot pivot, world-space aim, shoulder sockets, easing and reflection invariants.
const Scientist=preload("res://character/scientist_sprites.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)

func _pose(view,clock: float,velocity: Vector2,angle:=0.0,extra: Dictionary={}) -> void:
	var state={"time":clock,"moving":velocity.length_squared()>0,"move_velocity":velocity,"move_speed":210.,
		"aim":angle,"off_aim":angle+PI,"reaction":"","zap":false,"dash_dir":Vector2.ZERO,"shove":-1.,"sprinting":false,"recoil":0.,"recoil2":0.}
	state.merge(extra,true);view.set_state(state)

func _run() -> void:
	var run=root.get_node("Run");run.new_run()
	var scene=load("res://game/main.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.set_process(false);scene._show("play");var a=scene.arena;a.set_process(false);var view=a.villain
	view.prepare_for_play()
	for i in 31:_pose(view,i/60.,Vector2(210,0))
	_check(view.movement_lean>deg_to_rad(3.8) and view.movement_lean<=view.WALK_LEAN,"walking uses the stronger four-degree lean")
	_check(view.rig.to_global(Vector2(0,-50)).x>view.ground_global().x+3.,"the upper body moves into the lean")
	var held: float=view.movement_lean
	for i in 8:_pose(view,.5,Vector2(210,0))
	_check(view.movement_lean==held,"repeated pose/muzzle samples in one frame do not accelerate the lean")
	for size in [.55,1.,1.6]:
		view.scale=Vector2.ONE*size
		for direction in [-1.,1.]:
			for i in 40:_pose(view,1.+i/60.+(2. if direction>0 else 0.),Vector2(210*direction,0))
			_check(signf(view.movement_lean)==direction,"lean follows travel independently of facing")
			_check(view.feet_global().distance_to(view.ground_global())<.002,"lean keeps the foot pivot grounded at every pill size")
			for step in 25:
				var angle: float=-PI+step*TAU/24.
				_pose(view,5.+step/60.,Vector2(210*direction,0),angle,{"recoil":.8})
				var barrel: Vector2=view.rig.gun.global_transform.x.normalized()
				_check(absf(barrel.angle_to(Vector2.from_angle(angle)))<.0001,"lean preserves world-space main gun direction")
				var shoulder: Vector2=Scientist.pose_point(view.rig._native_near_pose,"shoulder")
				_check(view.rig.near_arm.to_global(shoulder).distance_to(view.shoulder_global())<.002,"arm socket stays on its transformed shoulder through turns and recoil")
				_check(view.muzzle_global().distance_to(view.rig.anchor_global("gun.muzzle"))<.002,"shot source stays attached to the drawn muzzle")
	view.scale=Vector2.ONE
	for i in 40:_pose(view,10.+i/60.,Vector2(-210,0))
	var previous: float=view.movement_lean
	_pose(view,10.+40./60.,Vector2(210,0))
	_check(view.movement_lean<0 and view.movement_lean>previous,"a direction reversal eases across upright")
	for i in 50:_pose(view,11.+i/60.,Vector2.ZERO)
	_check(is_zero_approx(view.movement_lean),"stopping settles fully upright")
	for i in 45:_pose(view,13.+i/60.,Vector2(52.5,0))
	_check(is_equal_approx(view.movement_lean,view.WALK_LEAN*.25),"analog walking scales the lean")
	for i in 45:_pose(view,14.+i/60.,Vector2(300,0),0.,{"sprinting":true})
	_check(view.movement_lean>view.WALK_LEAN and view.movement_lean<=view.SPRINT_LEAN,"sprinting adds only a small bounded extra lean")
	for extra in [{"reaction":"hurt"},{"zap":true},{"dash_dir":Vector2.RIGHT},{"shove":.4}]:
		for i in 30:_pose(view,16.+i/60.,Vector2(210,0))
		_pose(view,16.5,Vector2(210,0),0.,extra)
		_check(view.movement_lean==0,"authored actions keep their own pose")
	for i in 30:_pose(view,18.+i/60.,Vector2(210,0))
	view.scale=Vector2.ONE*1.6;view.set_ground_lift(40)
	_pose(view,18.5,Vector2(210,0))
	_check(view.movement_lean==0 and absf(view.feet_global().y-view.ground_global().y+40)<.002,"airborne poses lift from the ground without inheriting lean")
	view.set_ground_lift(0);view.scale=Vector2.ONE
	# Both gun slots must keep the same world-space aiming contract.
	run.build.items=["bionic_arm","offhand"];run.build.off={"kind":"gun","ammo":0,"frame":0,"items":[]};run.recompute()
	for i in 40:_pose(view,20.+i/60.,Vector2(210,0))
	for i in 25:
		var angle: float=-PI+i*TAU/24.
		_pose(view,21.+i/60.,Vector2(210,0),angle)
		_check(absf(view.rig.off_gun.global_transform.x.angle_to(Vector2.from_angle(angle+PI)))<.0001,"rear gun also compensates its aim")
		_check(view.rig.bionic_support.to_global(view.rig.bionic_support.tip).distance_to(view.off_shoulder_global())<.002,"third arm stays connected through turns and lean")
	# Reflection sprites inherit each live transformed layer, including the lean.
	for i in 40:_pose(view,23.+i/60.,Vector2(210,0))
	a.water_reflections.enabled=true
	a.water_reflections.sync(a.actors,Rect2(Vector2.ZERO,Vector2(a.AW,a.AH)),24.)
	var entry: Dictionary=a.water_reflections.entries[view.get_instance_id()]
	var reflected: Sprite2D=entry.sprites[view.rig.body.get_instance_id()]
	var point: Vector2=view.rig.body.to_global(Vector2(64,40))
	var mirror: Vector2=reflected.to_global(Vector2(64,40));var foot: Vector2=view.ground_global()
	_check(absf(point.x-mirror.x)<.002 and absf((mirror.y-foot.y)+(point.y-foot.y)*.65)<.002,"puddle reflection mirrors the leaning body around the planted feet")
	# Actual gameplay movement, including a blocked move, feeds the visual target.
	run.new_run();scene._start_wave();a.spawn_t=1000.;a.civ_t=1000.;a.crate_t=1000.
	root.get_node("Controls").aim_src="pad";Input.action_press("move_right")
	for i in 35:a._process(1./60.)
	_check(a.P.move_velocity.x>0 and view.movement_lean>0,"real walking drives the lean")
	a.walls=[{"rect":Rect2(a.P.x+a.P.r,a.P.y-70,30,140),"open":false}]
	for i in 40:a._process(1./60.)
	_check(absf(a.P.move_velocity.x)<.01 and absf(view.movement_lean)<.001,"pressing into a wall settles upright instead of leaning without moving")
	Input.action_release("move_right")
	scene.free()
	print("MOVEMENT LEAN TESTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

extends SceneTree
## Regression coverage for walking laser attachment, recoil timing, swept shots and particle lights.
var scene
var arena
var run
var controls
var checks := 0
var failures := 0
var _screenshot := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	seed(7331)
	run = root.get_node("Run"); controls = root.get_node("Controls")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false)
	_screenshot = OS.get_cmdline_user_args().has("--screenshots")
	for sustained in [false,true]:
		for facing in [1,-1]:
			for dt in [1.0/60.0,0.05]: _test_beams(sustained,facing,dt)
	_test_projectile_origins()
	_test_laser_bolt()
	_test_projectile_sweeps()
	_test_sustained_damage()
	_test_particles()
	if _screenshot: await _capture_examples()
	print("GUN EFFECT TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _reset(items: Array = [], ammo: int = 0, frame: int = 0, off = null) -> void:
	for action in ["fire","fire_off","move_left","move_right"]: Input.action_release(action)
	run.new_run(); run.build.items = items.duplicate(); run.build.ammo = ammo; run.build.frame = frame; run.build.off = off
	scene._start_wave(); controls.aim_src = "pad"
	arena.P.x = Levels.SPAWN.x; arena.P.y = Levels.SPAWN.y; arena._sync(0.0)
	arena.spawn_t = 1000; arena.civ_t = 1000; arena.crate_t = 1000
	arena.P.inv = 0.0; arena.banner_t = 0.0
	arena.gun_cd.fill(0.0); arena.P.off_cd = 0.0

func _test_beams(sustained: bool, facing: int, dt: float) -> void:
	var items: Array = ["scope","drill","gLaser","split","boots","lens"]   # lens: lasers are beams, not bolts
	if sustained: items.append("sustain")
	_reset(items,0,2,{"ammo":0,"frame":0,"items":["scope"]})
	Input.action_press("move_right" if facing>0 else "move_left"); Input.action_press("fire"); Input.action_press("fire_off")
	var observed_poses = {}; var observed_beams := 0
	for frame in 80:
		arena.P.aim = (0.0 if facing>0 else PI)+sin(frame*0.12)*0.35
		arena._process(dt)
		observed_poses[arena.villain.rig.pose] = true
		if sustained:
			_check(arena.beams.filter(func(beam): return beam.sus).size()==run.S.guns.size()*run.D.shots,"held beam survives every rendered step, including 20 FPS")
		var live_keys = {}
		for beam in arena.beams:
			observed_beams += 1
			var origin = arena._shot_muzzle(beam.source,beam.shot)
			_check(origin.distance_to(Vector2(beam.x1,beam.y1))<0.0001,"beam stays attached through walking, aim and recoil")
			if beam.sus:
				var key = str(beam.source)+":"+str(beam.shot)
				_check(not live_keys.has(key),"one sustained beam per nozzle")
				live_keys[key] = true
	_check(observed_beams>0,"walking test actually fires beams")
	_check(observed_poses.size()==8,"attachment is checked across all eight walk poses")
	Input.action_release("fire"); Input.action_release("fire_off")
	Input.action_release("move_right"); Input.action_release("move_left")
	var kills = run.kills
	for frame in 12: arena._process(0.05)
	_check(arena.beams.is_empty(),"released beams expire")
	_check(run.kills==kills,"fading visuals do not deal extra damage")
	# Geometry and clock remain unchanged after the rig's own process callback.
	var rig = arena.villain.rig; var time = rig.t; var muzzle = rig.muzzle_global()
	rig._process(0.5)
	_check(rig.t==time and rig.muzzle_global()==muzzle,"game owns the rig clock, with no post-sync drift")
	# A stationary pulse stays attached when the body moves before the next shot.
	var origin = arena.villain.muzzle_global(); var back = arena.villain.shoulder_global()
	arena.fire_gun("laser",arena.P.aim,1.0,origin.x,origin.y,null,back.x,back.y,0)
	arena.P.x += 14; arena.P.walk += 1; arena.P.recoil = 1.0
	arena._sync(0.0)
	_check(Vector2(arena.beams.back().x1,arena.beams.back().y1).distance_to(arena._shot_muzzle(0,int(run.D.shots)-1))<0.0001,"pulse tail follows its current nozzle")

## Without a Focusing Lens the Laser fires a red bolt that stops at the first cop; with it, a piercing beam.
func _test_laser_bolt() -> void:
	_reset()
	var origin = arena.villain.muzzle_global(); var back = arena.villain.shoulder_global()
	var near = arena.make_enemy("riot", origin.x + 60, origin.y); near.hp = 10000; near.max_hp = 10000
	var far = arena.make_enemy("riot", origin.x + 110, origin.y); far.hp = 10000; far.max_hp = 10000
	arena.fire_gun("laser", 0.0, 1.0, origin.x, origin.y, null, back.x, back.y, 0)
	_check(arena.beams.is_empty() and arena.projs.size() == 1 and arena.projs[0].type == "bolt", "a lens-less laser fires one bolt, no beam")
	_check(arena.projs[0].color == Color("#ff4a4a"), "the bolt is laser red")
	for frame in 30: arena._update_projs(1.0 / 60.0)
	_check(near.hp < 10000 and far.hp == 10000, "the bolt stops at the first cop")
	run.build.items = ["lens"]; run.recompute()
	near.hp = 10000; far.hp = 10000
	arena.fire_gun("laser", 0.0, 1.0, origin.x, origin.y, null, back.x, back.y, 0)
	_check(arena.beams.size() == 1 and near.hp < 10000 and far.hp < 10000, "with the lens the laser is a beam that hits both")

func _test_projectile_origins() -> void:
	_reset(["split","gBullet","gRazor","scope","drill"],1,1,{"ammo":2,"frame":0,"items":[]})
	arena.P.aim = 0.3; arena.P.walk = 2.0; arena.P.moving = true
	arena._fire_weapons(1.0/60.0,true,true)
	_check(arena.P.recoil==1.0 and arena.P.recoil2==1.0,"both recoils are committed before emission")
	var rig = arena.villain.rig
	for projectile in arena.projs:
		var frame: Dictionary = rig._off_frame if projectile.source==-1 else rig._gun_frame
		var sprite: Sprite2D = rig.off_gun if projectile.source==-1 else rig.gun
		var muzzle: Dictionary = frame.muzzles[0 if projectile.source==-1 else projectile.source]
		var row = muzzle.nozzles[mini(projectile.shot,muzzle.nozzles.size()-1)]
		var expected = sprite.to_global(Vector2(35+muzzle.x,59+muzzle.y+row))
		_check(expected.distance_to(Vector2(projectile.x,projectile.y))<0.0001,"projectile spawns on its rendered nozzle after recoil: "+str(expected.distance_to(Vector2(projectile.x,projectile.y))))
	_check(rig._gun_frame.muzzles[1].x==rig._gun_frame.anchors.barrelEnd.x,"extra bullet barrel uses its own short muzzle")
	_check(rig._gun_frame.muzzles[2].x==rig._gun_frame.anchors.barrelEnd.x+8,"extra razor muzzle is past its saw teeth")
	_check(arena.gun_flashes.all(func(duration): return duration>0.0),"every firing barrel gets a flash")
	var first = arena.projs[0]; var spawn = Vector2(first.x,first.y)
	arena._update_projs(1.0/60.0)
	_check(first.trail[0]==spawn,"first tracer segment starts at the muzzle")
	var position = Vector2(first.x,first.y)
	arena.P.x += 40; arena._sync(0.0)
	_check(Vector2(first.x,first.y)==position,"flying projectiles leave the weapon independently")

func _target(x: float, y: float, radius: float = 11.0):
	var enemy = arena.make_enemy("cop",x,y); enemy.hp = 10000; enemy.max_hp = 10000; enemy.r = radius
	return enemy

func _fire_test_projectile(type: String, x: float, y: float) -> void:
	arena.fire_gun(type,0.0,1.0,x,y,null,x,y)
	# Isolate collision geometry from the normal bullet dispersion.
	for projectile in arena.projs: projectile.vx = 620.0 if type=="bullet" else 380.0; projectile.vy = 0.0

func _test_projectile_sweeps() -> void:
	_reset([],1)
	var target = _target(115,200)
	_fire_test_projectile("bullet",100,200)
	arena._update_projs(0.05)
	_check(target.hp<10000 and arena.projs.is_empty(),"fast bullets hit enemies crossed between frames")
	_check(not arena.blaster_fx.impacts.is_empty(),"enemy hit emits a lit impact")
	_reset([],1)
	target = _target(135,200)
	arena.walls = [{"rect":Rect2(115,180,1,40),"open":false,"door":false}]
	_fire_test_projectile("bullet",100,200); arena._update_projs(0.05)
	_check(target.hp==10000 and arena.projs.is_empty(),"thin walls stop a shot before an enemy behind them")
	_check(is_equal_approx(arena.blaster_fx.impacts.back().position.x,115.0-maxf(3.0,run.D.width/3.5)),"wall sparks appear on the collision surface")
	_check(is_equal_approx(arena.ray_len(100,200,1,0,300),15.0),"laser ends exactly at the wall")
	# A weapon can extend beyond a narrow wall; emission still respects its shoulder side.
	for ammo in ["laser","bullet","razor"]:
		arena.fire_gun(ammo,0.0,1.0,150,200,null,100,200)
	_check(arena.projs.is_empty() and arena.beams.is_empty() and target.hp==10000,"long barrels cannot shoot through a wall between shoulder and muzzle")
	_reset(["drill"],1)
	var far = _target(135,200,1); var near = _target(120,200,1)
	_fire_test_projectile("bullet",100,200); var projectile = arena.projs[0]
	arena._update_projs(0.05)
	_check(near.hp<10000 and far.hp<10000,"piercing shots hit both crossed targets")
	_check(projectile.hit.keys()[0]==near,"swept hits resolve in travel order")
	_reset([],2)
	_fire_test_projectile("razor",arena.AW-36,200); projectile = arena.projs[0]
	arena._update_projs(0.05)
	_check(projectile.vx<0 and projectile.bounces==1,"razor reflects once on reaching the arena wall")
	_check(projectile.x<=arena.AW-20-projectile.r,"ricochet remains inside the arena")
	arena._update_projs(0.05)
	_check(projectile.vx<0 and projectile.bounces==1,"ricochet does not repeatedly flip outside the wall")

func _test_sustained_damage() -> void:
	var damage: Array = []
	for fps in [60,20]:
		_reset(["sustain"])
		run.S.crit = 0.0
		var muzzle = arena.villain.muzzle_global()
		var target = _target(muzzle.x+100,muzzle.y)
		for frame in fps: arena._fire_weapons(1.0/fps,true,false)
		damage.append(10000.0-target.hp)
	_check(is_equal_approx(damage[0],damage[1]),"continuous laser DPS agrees at 60 and 20 FPS: "+str(damage))

func _test_particles() -> void:
	var fx = arena.blaster_fx; fx.clear()
	for i in 100: fx.impact(Vector2(200,200),Vector2.UP,Color("#ff4a4a"))
	_check(fx.particles.size()==fx.MAX_PARTICLES and fx.impacts.size()==fx.MAX_IMPACTS,"particle and impact counts are bounded")
	arena.lights.begin(); fx.add_lights(arena.lights)
	_check(arena.lights.count()==9,"particle lighting uses a bounded light budget")
	_check(arena.lights._lights[0].color==Color("#ff4a4a"),"impact light matches the blaster color")
	fx.update(1.0)
	_check(fx.particles.is_empty() and fx.impacts.is_empty(),"sparks and impact lights expire")

func _capture_examples() -> void:
	for ammo in [0,1,2]:
		_reset(["scope","boots"],ammo,0)
		arena.P.aim = 0.0; arena.P.moving = true; arena.P.walk = 1.0
		arena._sync(0.0)
		var muzzle = arena.villain.muzzle_global()
		_target(muzzle.x+100,muzzle.y,12)
		arena._fire_weapons(1.0/60.0,true,false)
		if ammo>0: arena._update_projs(0.12 if ammo==1 else 0.20)
		arena._sync(0.0); arena.cam.reset_smoothing(); arena.cam.force_update_scroll()
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/blaster-%d.png" % ammo)
		var count = arena.blaster_fx.particles.size()
		for frame in 3: await process_frame
		_check(arena.blaster_fx.particles.size()==count,"rendering does not emit simulation particles")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error("FAIL: "+label)

extends SceneTree
## Fitts's-law check on targets: nothing needs impossible aim, lone enemies can be shot before they arrive,
## and a shot-width upgrade is big enough to feel.
const Aim := preload("res://game/aim_model.gd")
const REACH := 280.0
const MAX_BITS := 4.6
var checks := 0
var failures := 0
var a
var run
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _foe(kind: String):
	for e in a.enemies: e.queue_free()
	a.enemies.clear(); a.projs.clear(); a.walls = []
	var e = a.make_enemy(kind,1000,550); e.spd = minf(float(run.ET[kind].spd)*1.2,193.0) if not e.ranged else float(run.ET[kind].spd); return e
func _build(items: Array, frame := 0) -> void:
	run.build.ammo = 0; run.build.frame = frame; run.build.items = items.duplicate(); run.recompute()
## A real bolt flying straight up past the target, `offset` from its middle.
func _hits(e, offset: float, r: float) -> bool:
	e.hp = 900.0; a.projs = [{"type":"bolt","x":1000.0+offset,"y":750.0,"vx":0.0,"vy":-900.0,"r":r,"dmg":5.0,"mul":1.0,"pierce":0,"life":1.0,"hit":{},"spin":0.0,"bounces":0,"trail":PackedVector2Array(),"color":Color.RED,"source":-1,"shot":0}]
	for i in 30: a._update_projs(1.0/60.0)
	return e.hp < 900.0
func _run() -> void:
	run = root.get_node("Run"); run.new_run()
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false); a.state = "play"; a.P.x = 300.0; a.P.y = 550.0
	_build([]); run.wave = 1
	# the model agrees with real shots
	for copies in 3:
		var items := []; items.resize(copies); items.fill("flare"); _build(items)
		var r: float = run.shot_radius("laser"); var e = _foe("cop"); var half: float = Aim.half_width(e,r,PI/2.0)
		_check(_hits(e,half-1.5,r) and not _hits(e,half+1.5,r),"a real bolt agrees with the model's width, %d flares (%.1f)" % [copies,half])
	_build([])
	_check(Aim.bits(_foe("cop"),3.0,400.0)>Aim.bits(_foe("cop"),3.0,200.0),"farther is harder")
	print("  enemy         bits  aim s   kill s  arrives s   (starter blaster, %d units, quarter turn)" % REACH)
	for kind in ["cop","k9","undercover","det","interceptor","riot","swat","swat_shield","drone","robodog","guard"]:
		var e = _foe(kind); var r: float = run.shot_radius("laser")
		var bits: float = Aim.bits(e,r,REACH); var kill: float = Aim.kill_seconds(e,r,REACH,run.D.dmg,run.D.cd,900.0); var arrive: float = REACH/maxf(1.0,e.spd)
		print("  %-12s %5.2f  %5.2f  %6.2f  %6.2f%s" % [kind,bits,Aim.seconds(bits),kill,arrive,"   <- reaches you first" if kill>arrive and not e.ranged else ""])
		_check(bits<MAX_BITS,"%s is not a pixel hunt (%.2f bits)" % [kind,bits])
		_check(Aim.seconds(bits)+REACH/900.0<arrive,"%s can be shot at least once on the way in" % kind)
	for wave in [1,2,3]:
		run.wave = wave; var e = _foe("cop")
		_check(Aim.kill_seconds(e,run.shot_radius("laser"),REACH,run.D.dmg,run.D.cd,900.0)<REACH/e.spd,"a lone cop falls before he arrives on wave %d" % wave)
	run.wave = 1
	# shot width
	print("  frame        flares  shot r   cop target  bits")
	for frame in run.FRAMES.size():
		var last := 0.0; var base := 0.0; var last_bits := 99.0
		for copies in 4:
			var items := []; items.resize(copies); items.fill("flare"); _build(items,frame)
			var e = _foe("cop"); var r: float = run.shot_radius("laser"); var bits: float = Aim.bits(e,r,REACH); var target: float = 2.0*Aim.half_width(e,r,PI/2.0)
			if copies == 0: base = r
			else:
				_check(is_equal_approx(r,base*(1.0+copies)),"%s: every flare widens the shot" % run.FRAMES[frame].id)
				_check(target>last*1.1,"%s: flare %d widens a cop by over 10%%" % [run.FRAMES[frame].id,copies])
				_check(bits<last_bits,"%s: flare %d makes aiming easier" % [run.FRAMES[frame].id,copies])
			print("  %-12s %4d   %6.1f  %8.1f   %5.2f" % [run.FRAMES[frame].id,copies,r,target,bits])
			last = target; last_bits = bits
	_build(["flare","flare","flare"])
	a.enemies.clear(); a.walls = [{"rect":Rect2(1000,562,60,60),"open":false}]
	a.projs = [{"type":"bolt","x":900.0,"y":550.0,"vx":900.0,"vy":0.0,"r":run.shot_radius("laser"),"dmg":5.0,"mul":1.0,"pierce":0,"life":0.5,"hit":{},"spin":0.0,"bounces":0,"trail":PackedVector2Array(),"color":Color.RED,"source":-1,"shot":0}]
	for i in 15: a._update_projs(1.0/60.0)
	_check(a.projs.size()==1 and a.projs[0].x>1080.0,"a wide shot still slips past a car")
	print("AIM DIFFICULTY TESTS: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

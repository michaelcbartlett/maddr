extends SceneTree
## Palm shove: facing only, frame-rate independent, slams, bowling, heavies, cancels and slot rules.
var checks := 0
var failures := 0
var a
var run
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _fresh() -> void:
	for e in a.enemies: e.queue_free()
	a.enemies.clear(); a.ebul.clear(); a.walls = []; a.shove.reset(); a.P.x = 800.0; a.P.y = 550.0; a.P.aim = 0.0; a.P.disguise_t = 0.0
func _foe(kind: String, x: float, y: float):
	var e = a.make_enemy(kind,x,y); e.hp = 500.0; e.max_hp = 500.0; return e
func _push(fps := 60, seconds := 0.6) -> void:
	a.shove.press()
	for i in int(seconds*fps): a.shove.update(a,1.0/fps,run,false)
func _gap(e) -> float: return Vector2(e.x-a.P.x,e.y-a.P.y).length()

func _run() -> void:
	run = root.get_node("Run"); run.new_run(); run.build.off = null
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false); a.state = "play"
	_fresh(); a.nav.configure([],Vector2(a.AW,a.AH))
	var front = _foe("cop",860,550); var behind = _foe("cop",740,550); var side = _foe("cop",800,640)
	_push()
	_check(_gap(front)>170.0,"pushes what he faces (%.0f)" % _gap(front))
	_check(absf(_gap(behind)-60.0)<0.1 and absf(_gap(side)-90.0)<0.1,"ignores what is behind and beside him")
	_check(front.hp == 500.0,"a plain push does no damage")
	_fresh(); a.P.aim = PI; behind = _foe("cop",740,550); _push(); _check(_gap(behind)>170.0,"works facing left")
	var ends := []
	for fps in [30,60,144]:
		_fresh(); front = _foe("cop",860,550); _push(fps); ends.append(_gap(front))
	_check(ends.max()-ends.min()<1.0,"same distance at any frame rate %s" % str(ends))
	_fresh(); var far = _foe("cop",1000,550); _push(); _check(absf(_gap(far)-200.0)<0.1,"out of reach is untouched")
	_fresh(); var heavy = _foe("riot",860,550); _push(); _check(_gap(heavy)>75.0 and _gap(heavy)<130.0,"heavies budge less (%.0f)" % _gap(heavy))
	_fresh(); a.walls = [{"rect":Rect2(920,450,40,200),"open":false}]; a.nav.configure(a.walls,Vector2(a.AW,a.AH))
	front = _foe("cop",860,550); _push()
	_check(front.hp<500.0 and front.stun_t>0.3,"a wall slam hurts and stuns")
	_check(front.x<=920.0-front.r+0.5,"and he stops at the wall (%.0f)" % front.x)
	_fresh(); a.walls = [{"rect":Rect2(835,450,12,200),"open":false}]; a.nav.configure(a.walls,Vector2(a.AW,a.AH))
	front = _foe("cop",880,550); _push(); _check(absf(front.x-880.0)<0.1,"no pushing through a wall")
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH))
	_fresh(); front = _foe("cop",860,550); var pin = _foe("cop",945,550); _push()
	_check(pin.hp<500.0 and front.hp<500.0 and pin.x>950.0,"driven into another enemy: both hurt, both move")
	_fresh(); a.P.x = a.AW-120.0; front = _foe("cop",a.AW-60.0,550); _push(); _check(front.x<=a.AW and front.hp<500.0,"the arena edge counts as a wall")
	_fresh(); front = _foe("cop",840,550); front.action_phase = "swing"; front.action_t = 1.0; _push(60,0.2)
	_check(front.action_phase == "" and front.stun_t>0.0,"breaks a wind-up")
	var at: float = front.x; front.tick(0.1); _check(front.x == at,"stunned enemies do not act")
	for i in 60: front.tick(1.0/60.0)
	_check(front.stun_t == 0.0,"and they recover")
	_fresh(); a.shove.press(); a.shove.update(a,0.016,run,false); _check(a.shove.active(),"press starts it")
	for i in 30: a.shove.update(a,1.0/60.0,run,false)
	a.shove.press(); a.shove.update(a,0.016,run,false); _check(not a.shove.active(),"cooldown holds")
	for i in 40: a.shove.update(a,1.0/60.0,run,false)
	a.shove.press(); a.shove.update(a,0.016,run,false); _check(a.shove.active(),"ready again after a second")
	_fresh(); run.build.off = {"kind":"gun","ammo":0,"frame":0,"items":[]}; a.shove.press(); a.shove.update(a,0.016,run,false)
	_check(not a.shove.active(),"a full off hand keeps its own LT action"); run.build.off = null
	_fresh(); a.shove.press(); a.shove.update(a,0.016,run,true); _check(not a.shove.active(),"not while dashing")
	_fresh(); front = _foe("cop",860,550); front.ally = true; _push(); _check(absf(_gap(front)-60.0)<0.1,"allies are left alone")
	# The stick decides, even mid-swing, and the arm, wave and hit agree.
	_fresh(); front = _foe("cop",860,550); behind = _foe("cop",740,550); a.shove.press()
	for i in 36: a.shove.update(a,1.0/60.0,run,false,0.0 if i<3 else PI)
	_check(_gap(behind)>150.0 and absf(_gap(front)-60.0)<0.1,"a flick during the wind-up redirects the push")
	_fresh()
	for degrees in [0,45,90,135,180,-135,-90,-45]:
		_fresh(); var dir := Vector2.from_angle(deg_to_rad(degrees)); front = _foe("cop",800+dir.x*60,550+dir.y*60)
		a.shove.press()
		for i in 30: a.shove.update(a,1.0/60.0,run,false,dir.angle())
		_check((Vector2(front.x,front.y)-Vector2(800,550)).normalized().dot(dir)>0.99 and _gap(front)>150.0,"pushes along the stick at %d" % degrees)
	# Either or: no shot leaves during a shove, and held fire resumes after it.
	_fresh(); run.build.ammo = run.AMMO.find_custom(func(x): return x.id == "bullet"); run.recompute()
	a.gun_cd = [0.0]; a.gun_flashes = [0.0]; a.projs.clear(); a.beams.clear()
	Input.action_press("fire"); a.shove.press(); a.wave_t = 50.0
	a._update_play(1.0/60.0); _check(a.shove.active(),"shove starts while fire is held")
	for i in 14:
		a.gun_cd = [0.0]; a._update_play(1.0/60.0)
	_check(a.projs.is_empty() and a.P.firing_t<=0.0,"nothing fires mid-shove")
	for i in 20: a._update_play(1.0/60.0)
	_check(not a.shove.active() and not a.projs.is_empty(),"held fire resumes afterwards"); Input.action_release("fire")
	var rig = a.villain.rig
	for facing in [0.0,PI]:
		rig.set_state({"aim":facing,"time":5.0,"shove":-1.0}); rig.set_state({"time":6.0})
		rig.set_state({"shove":0.45,"shove_aim":facing})
		_check(rig.rest_pivot.visible and rig.gun.visible,"the off arm pushes while the gun stays up")
		_check(rig.rest_arm.texture == load("res://character/scientist_sprites.gd").worn_part(("far" if facing == 0.0 else "near")+"_shove",4,rig.gear),"uses the drawn palm")
		var front_of: bool = rig.rest_pivot.get_index()>rig.body_root.get_index()
		_check(front_of == (facing != 0.0),"on the correct side of his body")
		rig.set_state({"shove":-1.0})
	print("SHOVE TESTS: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

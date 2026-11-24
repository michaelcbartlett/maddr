extends SceneTree
## The detective keeps revolver range, steadies before firing, and runs when the villain closes in.
var checks := 0
var failures := 0
var a
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _spawn(at: Vector2):
	for e in a.enemies: e.queue_free()
	a.enemies.clear(); a.ebul.clear(); a.walls = []
	var e = a.make_enemy("det",at.x,at.y); e.shoot_cd = 2.0; e.action_cd = 0.0; e.action_phase = ""
	return e
func _tick(e, dt: float) -> void:
	var before := Vector2(e.x,e.y); e.tick(dt)
	if not a.walls.is_empty(): a.collide_walls(e,e.r,before)
func _distance(e) -> float: return Vector2(e.x-a.P.x,e.y-a.P.y).length()
func _steps(e, n: int, each = null) -> void:
	for i in n:
		_tick(e,1.0/60.0)
		if each != null: each.call()

func _run() -> void:
	seed(4)
	root.get_node("Run").new_run()
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	a.state = "play"; a.P.x = 800.0; a.P.y = 550.0; a.P.disguise_t = 0.0
	_check(root.get_node("Run").ET.det.behavior == "marksman","detective uses his own behavior")
	var e = _spawn(Vector2(1250,550)); _steps(e,300)
	_check(_distance(e)<300.0 and _distance(e)>170.0,"he walks in to revolver range and stops (%.0f)" % _distance(e))
	e = _spawn(Vector2(950,550)); e.action_cd = 9.0; e.shoot_cd = 9.0; _steps(e,90)
	_check(_distance(e)>165.0,"he backs off when a little too close (%.0f)" % _distance(e))
	# steady, then one shot
	e = _spawn(Vector2(1030,550)); e.shoot_cd = 0.5
	_steps(e,6); _check(e.action_phase == "aim","he plants and aims before firing")
	var at := Vector2(e.x,e.y); _steps(e,20); _check(Vector2(e.x,e.y).distance_to(at)<0.5 and a.ebul.is_empty(),"rooted while aiming, no early shot")
	_steps(e,12); _check(a.ebul.size()==1,"one shot per aim (%d)" % a.ebul.size())
	_steps(e,60); _check(a.ebul.size()==1,"then he waits before the next")
	# flee
	e = _spawn(Vector2(880,550)); var hp: float = a.P.hp
	_steps(e,2); _check(e.action_phase == "flee","closing in makes him run")
	var start := _distance(e); _steps(e,40)
	_check(_distance(e)>start+45.0,"he opens the gap (%.0f -> %.0f)" % [start,_distance(e)])
	_check(a.ebul.is_empty() and a.P.hp == hp,"no shooting and no contact damage while running")
	_check((e.face>0)==(e.x>a.P.x),"he faces where he runs")
	_steps(e,120); _check(e.action_phase != "flee","he stops running once clear (%.0f)" % _distance(e))
	# chase: he tires
	e = _spawn(Vector2(860,550)); var longest := [0.0,0.0]
	for i in 420:
		a.P.x = e.x-55.0; a.P.y = e.y; if a.P.x<60.0: a.P.x = 60.0
		e.tick(1.0/60.0)
		longest[0] = longest[0]+1.0/60.0 if e.action_phase == "flee" else 0.0; longest[1] = maxf(longest[1],longest[0])
	_check(longest[1]<=2.3,"a chase always ends: he tires (%.2fs)" % longest[1])
	# cornered
	a.P.x = 150.0; a.P.y = 150.0; e = _spawn(Vector2(70,70)); var phases := {}
	_steps(e,200,func(): phases[e.action_phase] = true)
	_check(e.x>=27.0 and e.y>=27.0 and e.x<=a.AW-27.0,"he never leaves the arena (%.0f, %.0f)" % [e.x,e.y])
	_check(phases.has("flee"),"he tries to run even in a corner")
	# boxed in on every side
	a.P.x = 800.0; a.P.y = 550.0; e = _spawn(Vector2(860,550))
	a.walls = [{"rect":Rect2(900,480,20,140),"open":false},{"rect":Rect2(820,470,100,20),"open":false},{"rect":Rect2(820,612,100,20),"open":false}]
	phases.clear(); _steps(e,160,func(): phases[e.action_phase] = true)
	_check(phases.has("cornered") and not a.ebul.is_empty(),"boxed in, he turns and fires")
	# disguise cancels it
	e = _spawn(Vector2(880,550)); _steps(e,3); a.P.disguise_t = 2.0; e.tick(1.0/60.0)
	_check(e.action_phase == "","a disguise calms him down"); a.P.disguise_t = 0.0
	# frame rate independence
	var ends := []
	for fps in [30,60,144]:
		a.P.x = 800.0; a.P.y = 550.0; e = _spawn(Vector2(880,550))
		for i in int(fps*0.8): e.tick(1.0/fps)
		ends.append(_distance(e))
	_check(ends.max()-ends.min()<30.0,"he flees the same distance at any frame rate %s" % str(ends))
	print("DETECTIVE TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

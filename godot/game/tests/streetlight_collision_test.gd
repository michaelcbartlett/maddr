extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	root.get_node("Controls").aim_src="pad"
	var bases: Array=a.walls.filter(func(w): return w.get("kind","")=="lamp_post")
	_check(bases.size()==20,"all twenty opening streetlights have solid bases")
	for base in bases:
		_check(not base.open and not base.has("prop_index"),"streetlight bases are solid fixtures, independent of destructible cars")
	var base: Rect2=bases[0].rect
	for radius in [6.05,11.0,17.6]:
		a.P.r=radius; a.P.x=base.position.x-60; a.P.y=base.get_center().y
		Input.action_press("move_right")
		for frame in 90: a._process(1.0/60.0)
		Input.action_release("move_right")
		_check(absf(a.P.x-(base.position.x-radius))<0.1,"walking is blocked at the foot with radius %.2f"%radius)
	a.P.r=11.0
	Input.action_press("move_up")
	for frame in 25: a._process(1.0/60.0)
	Input.action_release("move_up"); Input.action_press("move_right")
	for frame in 65: a._process(1.0/60.0)
	Input.action_release("move_right")
	_check(a.P.x>base.end.x+40 and a.P.y<base.position.y-a.P.r,"walking around the small base remains possible")
	a.P.x=base.position.x-100; a.P.y=base.get_center().y; a.dash.reset(); a.dash.press()
	Input.action_press("move_right")
	for frame in 22: a._process(1.0/60.0)
	Input.action_release("move_right")
	_check(a.P.x<=base.position.x-a.P.r+0.1,"a phase dash cannot tunnel through the base")
	_check(not a.nav.clear_segment(base.get_center()-Vector2(50,0),base.get_center()+Vector2(50,0),0),"navigation sees the same solid base")
	a.arena_level.build_blank()
	_check(a.arena_level.walls.size()==1 and a.arena_level.walls[0].get("kind","")=="lamp_post","the blank studio's walk-around lamp is solid too")
	print("STREETLIGHT COLLISION TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)

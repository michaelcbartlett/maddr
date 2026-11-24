extends SceneTree
## Shots, blades and bars agree with the tall sprites; cop health follows its flat per-wave curve.
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
	a.enemies.clear(); a.projs.clear(); a.beams.clear(); a.walls = []
	var e = a.make_enemy(kind,1000,550); e.hp = 900.0; e.max_hp = 900.0; return e
func _bolt(y: float, r := 3.0) -> void:
	a.projs = [{"type":"bolt","x":800.0,"y":y,"vx":900.0,"vy":0.0,"r":r,"dmg":5.0,"mul":1.0,"pierce":0,"life":1.0,"hit":{},"spin":0.0,"bounces":0,"trail":PackedVector2Array(),"color":Color.RED,"source":-1,"shot":0}]
	for i in 30: a._update_projectiles(1.0/60.0)
func _run() -> void:
	run = root.get_node("Run"); run.new_run()
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false); a.state = "play"; a.P.x = 300.0; a.P.y = 550.0
	var Geometry = load("res://game/shot_geometry.gd")
	for kind in ["cop","det"]:
		var e = _foe(kind); var view = load("res://enemies/enemy_view.gd")
		var shape: Dictionary = view.hurt_shape(e); var head: float = view.head_y(e); var foot: float = view.foot_y(e)
		_check(foot-head>74.0 and foot-head<96.0,"%s body is its drawn height (%.0f)" % [kind,foot-head])
		_check(absf((shape.low.y+shape.r)-foot)<0.1 and absf((shape.high.y-shape.r)-head)<0.1,"%s hit area spans feet to hat" % kind)
		for share in [0.06,0.3,0.55,0.8,0.96]:
			var y := lerpf(foot,head,share)
			_check(Geometry.body_fraction(Vector2(800,y),Vector2(1200,y),shape,3.0)>=0.0,"%s is hit at %d%% of his height" % [kind,int(share*100)])
		_check(Geometry.body_fraction(Vector2(800,head-8),Vector2(1200,head-8),shape,3.0)<0.0,"%s: over the hat misses" % kind)
		_check(Geometry.body_fraction(Vector2(800,foot+8),Vector2(1200,foot+8),shape,3.0)<0.0,"%s: under the feet misses" % kind)
		_check(Geometry.body_fraction(Vector2(970,400),Vector2(970,700),shape,3.0)<0.0,"%s: past the shoulder misses" % kind)
		_check(head-8.0<foot-74.0,"%s health bar clears the head" % kind)
		var tall: float = foot-head; e.shrunk_t = 1.0
		_check(absf((view.foot_y(e)-view.head_y(e))-tall*0.5)<0.1,"%s shrinks with his art" % kind)
	_check(a.bullet_hits_player(Vector2(300,525),4.0) and a.bullet_hits_player(Vector2(300,550),4.0) and not a.bullet_hits_player(Vector2(300,485),4.0) and not a.bullet_hits_player(Vector2(300,562),4.0) and not a.bullet_hits_player(Vector2(318,530),4.0),"bullets strike his torso but not the air around him")
	# cop: one shot from the starting blaster, then +2 per wave
	run.new_run(); run.build.ammo = 0; run.build.frame = 0; run.recompute()
	for wave in [1,2,3,5,10]:
		run.wave = wave; var e = a.make_enemy("cop",900,550)
		_check(is_equal_approx(e.max_hp,(3.0+2.0*(wave-1))*run.tough_mult()),"cop health on wave %d (%.1f)" % [wave,e.max_hp])
	for tier in range(1,run.DIFFICULTY.size()+1):
		run.difficulty = tier; run.wave = 1
		_check(a.make_enemy("cop",900,550).max_hp<=run.D.dmg,"the starter blaster one-shots a wave 1 cop on difficulty %d" % tier)
	print("HITBOX TESTS: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

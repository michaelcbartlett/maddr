extends SceneTree
## Gore: spray, stains, pools, gib rules, machines bleed oil, caps and reset. --render-check also saves a screenshot.
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _run() -> void:
	var run = root.get_node("Run"); run.new_run()
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); var a = scene.arena; a.set_process(false); scene._start_wave()
	run.S.crit = 0.0; run.S.lifesuck = 0.0
	var g = a.gore
	var make := func(kind: String, at: Vector2):
		return a.make_enemy(kind, a.P.x + at.x, a.P.y + at.y)
	var cop = make.call("cop", Vector2(90, 0)); cop.hp = 20.0; cop.max_hp = 20.0
	a.hit(cop, 5.0, {"kx": 1.0, "ky": 0.0})
	_check(g.drops.size() >= 2 and g.drops.all(func(d): return d.c == g.FLESH), "a wound sprays blood")
	for i in 60: g.update(1.0 / 30)
	_check(g.drops.is_empty() and not g.batches.is_empty(), "drops land as stains")
	a.hit(cop, 16.0)
	_check(cop.dead and g.pools.size() == 1 and g.gibs.is_empty(), "an ordinary kill leaves a pool, no gibs")
	_check(not cop.gfx.get("skip_corpse", false), "an ordinary kill keeps the corpse")
	var torn = make.call("cop", Vector2(-90, 0)); a.explode(torn.x, torn.y, torn.max_hp * 4.0, 40.0, Color.ORANGE)
	_check(torn.dead and not g.gibs.is_empty() and torn.gfx.get("skip_corpse", false), "explosive overkill tears the body apart")
	g.reset()
	var dog = make.call("robodog", Vector2(0, 90)); a.hit(dog, dog.max_hp * 3.0)
	_check(g.pools.is_empty() and g.drops.all(func(d): return d.c == g.OIL), "machines spill oil, never blood")
	g.reset()
	var ash = make.call("cop", Vector2(0, -90)); ash.disint = true; a.kill(ash)
	_check(g.drops.is_empty() and g.pools.is_empty(), "a vaporized body leaves no blood")
	var at := Vector2(a.P.x, a.P.y)
	for i in 900:
		g.spray(at, 10, Vector2.ZERO, 3, 100, g.FLESH); g.stain(at, 2, g.FLESH); g.pool(at, 9); g.burst(at, 9, Vector2.ZERO, 1, g.MEAT, g.FLESH)
	_check(g.drops.size() <= g.MAX_DROPS and g.gibs.size() <= g.MAX_GIBS and g.pools.size() <= g.MAX_POOLS and g.batches.size() <= g.MAX_BATCHES, "every list is capped")
	var began := Time.get_ticks_usec()
	for i in 30: g.update(1.0 / 60)
	print("gore update at caps: %.2f ms" % ((Time.get_ticks_usec() - began) / 30000.0))
	g.reset()
	_check(g.drops.is_empty() and g.batches.is_empty() and g.pools.is_empty(), "reset clears everything")
	a.P.inv = 0.0; a.P.hp = 100.0; a.hurt_player(10)
	_check(not g.drops.is_empty(), "the doctor bleeds too")
	if "--render-check" in OS.get_cmdline_user_args():
		g.reset()
		for i in 6:
			var e = make.call("cop", Vector2(110, 0).rotated(i * TAU / 6))
			if i % 2: a.explode(e.x, e.y, e.max_hp * 4.0, 30.0, Color.ORANGE)
			else: a.hit(e, e.max_hp * 1.1)
		for i in 60: g.update(1.0 / 60)
		a.booms.clear(); a.parts.clear(); a.nums.clear()
		var last = make.call("cop", Vector2(60, 50)); a.hit(last, last.max_hp * 3.0, {"kx": 1.0})
		for i in 8: g.update(1.0 / 60)
		a._sync(0.016); scene.pause_s.visible = false; scene.hud.visible = false
		for i in 4: await process_frame; scene.pause_s.visible = false
		root.get_texture().get_image().save_png("res://test-results/gore.png")
	print("gore: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

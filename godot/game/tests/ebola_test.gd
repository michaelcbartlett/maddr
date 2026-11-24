extends SceneTree
## The actual corpse owns the infection: no invisible area can outlive its body.
const Corpse = preload("res://enemies/enemy_corpse.gd")
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items: Array = ["ebola"]) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.recompute(); scene._start_wave()
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH)); a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; run.S.crit = 0.0
	await process_frame

func _enemy(kind := "cop", point := Vector2(550,350)):
	var enemy = a.make_enemy(kind,point.x,point.y)
	enemy.hp = 1000; enemy.max_hp = 1000; enemy.spd = 0; enemy.atk_cd = 1000
	return enemy

func _bodies() -> Array:
	return a.actors.get_children().filter(func(n): return n.is_in_group("enemy_corpses") and not n.is_queued_for_deletion())

func _kill(enemy, proc := true):
	a.hit(enemy,enemy.hp+100,{"proc":proc}); a._sync(0)
	await process_frame; await process_frame
	var bodies := _bodies()
	for body in bodies: body.set_process(false)
	return bodies[-1] if not bodies.is_empty() else null

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	await _start([])
	_check(run.item_available(run.ITEM.ebola) and int(run.ITEM.ebola.t) == 2, "Ebola Ammo is a purchasable Rare upgrade")
	run.scrap = 100; run.offers = [{"it":run.ITEM.ebola,"price":32,"sold":false}]
	_check(run.buy(0) and run.scrap == 68 and run.S.ebola == 1.0, "buying Ebola Ammo equips its coating")
	var infected = _enemy()
	a.hit(infected,1,{"proc":true})
	_check(infected.ebola_t == 8.0 and infected.ebola_dps == 4.0, "a weapon hit infects a living enemy")
	var hp: float = infected.hp
	for i in 60: infected.tick(1.0/60.0)
	_check(infected.hp < hp, "infection deals damage over time")
	await _start(["ebola","ebola"])
	infected = _enemy(); a.hit(infected,1,{"proc":true})
	_check(infected.ebola_dps == 8.0, "additional copies strengthen the infection")
	await _start()
	var body = await _kill(_enemy())
	_check(body != null and body.mode == "ebola" and body.infection_dps == 4.0, "a lethal coated hit leaves an infectious visible body")
	var touch = _enemy("cop",body.position+Vector2(8,0))
	var far = _enemy("cop",body.position+Vector2(110,0))
	body.spread_infection()
	_check(touch.ebola_t > 0 and far.ebola_t == 0, "walking over a body infects; standing away does not")
	var crossing = _enemy("cop",body.position+Vector2(80,0)); crossing.px = body.position.x-80; crossing.py = body.position.y
	body.spread_infection()
	_check(crossing.ebola_t > 0, "crossing the whole body between frames still infects")
	for kind in ["drone","robodog","interceptor","tank"]:
		var machine = _enemy(kind,body.position)
		a.hit(machine,1,{"proc":true}); body.spread_infection()
		_check(machine.ebola_t == 0, "%s cannot catch infection from shots or bodies" % kind)
	var ally = _enemy("cop",body.position); ally.ally = true
	var civilian = _enemy("civ",body.position); civilian.civ = true
	body.spread_infection()
	_check(ally.ebola_t == 0 and civilian.ebola_t == 0, "bodies do not infect allies or civilians")
	# Contact during the fade is still contagious; the exact end of that fade stops it.
	body.t = body.hold+0.59; touch.ebola_t = 0; body.spread_infection()
	_check(touch.ebola_t > 0, "a fading body remains contagious while still visible")
	touch.ebola_t = 0; body._process(0.02); body.spread_infection()
	_check(body.is_queued_for_deletion() and touch.ebola_t == 0, "infection stops at the same instant the body disappears")
	await process_frame
	_check(not is_instance_valid(body), "the expired infection body is removed")
	# Infection inherited from another corpse can leave a new infectious corpse.
	var inherited = await _kill(crossing,false)
	_check(inherited != null and inherited.infection_dps == 4.0, "an infected enemy can continue the corpse-to-enemy chain")
	await _start([])
	var ordinary = await _kill(_enemy(),false)
	_check(ordinary != null and ordinary.infection_dps == 0, "normal kills never leave infectious bodies")
	await _start()
	var frozen = _enemy(); frozen.frozen_t = 5.0
	var shards = await _kill(frozen)
	_check(shards.mode == "shatter" and shards.infection_dps == 0, "shattered enemies leave no infectious body")
	await _start()
	var vaporized = _enemy(); vaporized.disint = true
	var vapor = await _kill(vaporized)
	_check(vapor.mode == "vaporize" and vapor.infection_dps == 0, "vaporized enemies leave no infectious body")
	await _start()
	body = await _kill(_enemy())
	var target = _enemy("cop",body.position+Vector2(15,0))
	a.walls = [{"rect":Rect2(body.position+Vector2(5,-30),Vector2(3,60)),"open":false}]
	a.nav.configure(a.walls,Vector2(a.AW,a.AH)); body.spread_infection()
	_check(target.ebola_t == 0, "body contact does not infect through a wall")
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH))
	if OS.get_cmdline_user_args().has("--screenshots"):
		a.P.x = body.position.x-65; a.P.y = body.position.y+20; a.P.inv = 0
		body.t = 0.6; body.spread_infection(); body.queue_redraw(); a.banner_t = 0; a.siren_t = 0
		a.cam.zoom = Vector2.ONE*2; a._sync(0); a.cam.force_update_scroll()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-results")
		root.get_texture().get_image().save_png("res://test-results/ebola-corpses.png")
	a.end_wave(); target.ebola_t = 0; body.spread_infection()
	_check(target.ebola_t == 0, "bodies stop infecting once the wave ends")
	scene._start_wave(); await process_frame
	_check(_bodies().is_empty(), "bodies and their infection areas never carry into the next wave")
	print("EBOLA TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

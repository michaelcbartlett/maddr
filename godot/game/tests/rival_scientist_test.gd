extends SceneTree
const Rival = preload("res://game/rival_scientist.gd")
var checks := 0
var failures := 0
var run
var scene
var a
var controls

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)

func _start() -> void:
	run.new_run(); run.wave = 18; run.theme_order = ["street"]; a.start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.wave_t = 1000; a.P.inv = 1000
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH)); a.P.x = 800; a.P.y = 550

func _boss():
	var e = a.make_enemy("boss",1150,550); a.boss = e; e.action_cd = 0.0
	return e

func _ticks(e, seconds: float) -> void:
	for frame in ceili(seconds*60): e.tick(1.0/60.0)

func _run() -> void:
	seed(18018); run = root.get_node("Run"); controls = root.get_node("Controls")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	_start()
	_check(run.boss_for(18).id == "vex" and run.boss_for(15).id == "glacia" and run.boss_for(20).id == "paragon", "Vex is an additional late boss and preserves the other encounters")
	var e = _boss()
	var sheet := EnemyArt.sheet(e.spr)
	_check(e.hero == "vex" and sheet.frames.has("deploy") and sheet.anchors.attack[1].has("muzzle_f"), "rival scientist has her own art, gadget poses and two muzzle anchors")
	e.tick(0.01)
	_check(e.action_phase == "vex_aim" and a.ebul.is_empty(), "laser volley starts with a warning, without immediate damage")
	var locked: Vector2 = e.action_target
	a.P.y += 130; _ticks(e,0.86)
	_check(e.action_phase == "vex_burst" and a.ebul.size() == 2, "first volley fires a laser from each blaster")
	for i in 2:
		var bullet: Dictionary = a.ebul[i]
		var muzzle := EnemyView.muzzle_world(e,"muzzle" if i == 0 else "muzzle_f")
		_check(muzzle.distance_to(Vector2(bullet.x,bullet.y)) < 0.01, "laser %d starts at its own barrel" % i)
		var velocity := Vector2(bullet.vx,bullet.vy)
		_check(absf(velocity.normalized().cross((locked-muzzle).normalized())) < 0.001, "laser %d commits to the warned position instead of tracking a dodge" % i)
	_check(e.gfx.flash.life > 0 and e.gfx.flash_far.life > 0, "both laser blasters have shader muzzle flashes")
	_ticks(e,0.5)
	_check(a.ebul.size() == 6, "normal volley contains exactly three laser pairs")
	_ticks(e,0.25)
	_check(e.action_phase == "vex_recover", "laser volley is followed by a stationary recovery opening")
	var hp: float = e.hp; a.hit(e,10.0)
	_check(e.hp < hp, "the scientist remains damageable during recovery")
	_start(); e = _boss(); e.hp = e.max_hp*0.4; e.tick(0.01); _ticks(e,1.85)
	_check(a.ebul.size() == 8 and e.action_phase == "vex_recover", "low health adds one laser pair while retaining warning and recovery")
	# Real deployment cycle: announced positions, destructible sentries, then timed mines.
	_start(); e = _boss(); e.attack_cycle = 1; e.tick(0.01)
	_check(e.action_phase == "vex_deploy" and e.gadget_targets.size() == 2 and a.enemies.size() == 1, "sentry positions are announced a second before deployment")
	for point in e.gadget_targets: _check(point.distance_to(Vector2(a.P.x,a.P.y)) >= 85 and not a.in_wall(point.x,point.y,18), "gadgets deploy at safe, open positions")
	_ticks(e,1.05)
	var sentries: Array = a.enemies.filter(func(o): return o.type == "vex_sentry" and not o.dead)
	_check(sentries.size() == 2 and sentries.all(func(o): return o.summoner_id == e.get_instance_id()), "she deploys two owned laser sentries")
	for sentry in sentries:
		sentry.shoot_cd = 0.0; sentry.tick(0.01)
	_check(a.ebul.size() > 0 and a.ebul.all(func(b): return b.get("laser_bolt",false)), "sentries fire their own visible laser bolts")
	for repeat in 4:
		e.action_phase = ""; e.attack_cycle = 1; e.action_cd = 0; e.tick(0.01); _ticks(e,1.05)
	_check(a.enemies.filter(func(o): return o.type == "vex_sentry" and not o.dead).size() == 2, "repeated deployments cannot flood the arena with sentries")
	e.action_phase = ""; e.attack_cycle = 3; e.action_cd = 0; e.tick(0.01); _ticks(e,1.05)
	var mines: Array = a.enemies.filter(func(o): return o.type == "vex_mine" and not o.dead)
	_check(mines.size() == 2, "her other gadget places two timed shock mines")
	var mine = mines[0]; a.P.x = mine.x; a.P.y = mine.y; a.P.inv = 0
	hp = a.P.hp; mine.tick(1.8)
	_check(a.P.hp == hp and not mine.dead, "a mine does not detonate during its two-second countdown")
	mine.tick(0.25)
	_check(mine.dead and a.P.hp < hp, "the warned mine blast damages a player who stays inside it")
	a.hit(mines[1],100000)
	_check(mines[1].dead, "shooting a mine disarms it")
	a.hit(sentries[0],100000)
	_check(sentries[0].dead, "laser sentries can be destroyed")
	var ordinary = a.make_enemy("cop",500,500)
	a.hit(e,100000)
	_check(sentries.all(func(o): return o.dead) and a.ebul.all(func(b): return b.get("summoner_id",0) != e.get_instance_id() or b.t <= 0), "defeating Vex disables her remaining gadgets and lasers")
	_check(not ordinary.dead, "her shutdown does not erase ordinary enemies")
	# Walls, control effects and disguise must not create an unavoidable or stale attack.
	_start(); e = _boss(); e.tick(0.01)
	e.frozen_t = 1.0; var timer: float = e.action_t; e.tick(0.25)
	_check(e.action_t == timer and a.ebul.is_empty(), "freezing pauses the attack warning")
	e.frozen_t = 0; a.P.disguise_t = 1.0; e.tick(0.1)
	_check(e.action_phase == "vex_recover" and e.burst_left == 0, "disguise cancels her committed volley")
	a.P.disguise_t = 0; e.action_phase = ""; e.action_cd = 0; e.tick(0.01)
	a.walls = [{"rect":Rect2(970,350,35,450),"open":false}]; a.nav.configure(a.walls,Vector2(a.AW,a.AH)); _ticks(e,1.4)
	_check(a.ebul.is_empty(), "twin blasters cannot emit through cover")
	# Monocle I -> II, max-range pad crosshair, mouse-following reticle, selling and offer cap.
	_start(); run.scrap = 1000
	_check(run.aim_guide_level() == 0, "fresh runs have no aiming monocle")
	for level in [1,2]:
		run.offers = [{"it":run.ITEM.telescope,"price":14,"sold":false}]
		_check(run.buy(0) and run.aim_guide_level() == level, "purchase upgrades the monocle to level %d" % level)
		controls.aim_src = "pad"; a.P.aim = 0.4; a._sync_villain()
		var origin: Vector2 = a.villain.muzzle_global(0) if level == 2 else a.villain.shoulder_global()
		var reach: float = run.D.range if level == 2 else minf(run.D.range,170)
		_check(a.aim_marker_position().distance_to(origin+Vector2.from_angle(a.P.aim)*reach) < 0.01, "level %d controller marker uses the intended range" % level)
	_check(not run.item_available(run.ITEM.telescope), "shops stop offering the monocle after level II")
	controls.aim_src = "mouse"
	_check(a.aim_marker_position().distance_to(a.get_global_mouse_position()) < 0.01, "level II follows the actual mouse position")
	run.build.items.append("scope"); run.recompute(); controls.aim_src = "pad"
	_check(is_equal_approx(a.aim_marker_position().distance_to(a.villain.muzzle_global(0)),run.D.range), "controller crosshair follows range upgrades")
	run.sell("telescope"); _check(run.aim_guide_level() == 1 and run.item_available(run.ITEM.telescope), "selling level II restores the first-level guide and upgrade offer")
	run.sell("telescope"); _check(run.aim_guide_level() == 0, "selling the final monocle removes the guide")
	if OS.get_cmdline_user_args().has("--screenshots"): await _captures()
	print("RIVAL SCIENTIST / MONOCLE TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)

func _captures() -> void:
	_start(); run.theme_order = ["spyhq"]; a.start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.P.inv = 1000; a.P.x = 650; a.P.y = 550
	a.banner_t = 0; a.siren_t = 0; a.wave_t = 48
	run.build.items = ["telescope","telescope"]; run.recompute(); a.villain.set_items()
	controls.aim_src = "pad"; a.P.aim = 0
	var e = a.make_enemy("boss",1010,535); a.boss = e; e.action_cd = 0; e.tick(0.01)
	a._sync(0); scene._show("play"); a.set_process(false); await _shot("rival-vex-aim")
	Rival._placements(e,false,2)
	for fixture in [["vex_sentry",930,400],["vex_sentry",1130,630],["vex_mine",770,630]]:
		var gadget = a.make_enemy(fixture[0],fixture[1],fixture[2]); gadget.summoner_id = e.get_instance_id(); gadget.action_t = 1.2; gadget.shoot_cd = 0.5; gadget.sync()
	e.action_t = 0; e.tick(0.01); a._sync(0); await _shot("rival-vex-blasters")
	e.action_phase = "vex_deploy"; e.gadget_targets = Rival._placements(e,false,2); e.sync(); a._sync(0); await _shot("rival-vex-gadgets")

func _shot(name: String) -> void:
	a.cam.force_update_scroll()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/"+name+".png")

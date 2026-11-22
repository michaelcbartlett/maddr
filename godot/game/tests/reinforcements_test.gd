extends SceneTree
## Exercises enemy attacks, spawn budgets, consumable economy and real combat input; optional GPU captures.
var checks := 0
var failures := 0
var run
var scene
var a

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", label)

func _start(wave := 1) -> void:
	Input.action_release("fire"); Input.action_release("consume"); Input.action_release("consume_cycle")
	run.new_run(); run.wave = wave; run.theme_order = ["street"]; a.start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.wave_t = 1000; a.P.inv = 1000
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH))
	a.P.x = 800; a.P.y = 550

func _run() -> void:
	seed(8801)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	_start()
	# Every new type has complete rendering and setup at its actual spawn wave.
	for row in run.SPAWN_TABLE:
		run.wave = int(row[2])
		var e = a.make_enemy(row[0], 1100, 550); e.sync()
		_check(e.hp > 0 and EnemyArt.sheet(EnemyView.sprite_key(e)).frames.has("attack"), "%s has gameplay stats and animated art" % row[0])
	_start()
	for n in 100: _check(a.pick_type() == "cop", "the opening wave stays basic")
	# Explicitly distinguish the SWAT officer who carries BOTH pieces of equipment.
	var shield = a.make_enemy("swat_shield",1000,550); shield.hp = 1000; shield.max_hp = 1000; shield.aim_dir = Vector2.LEFT
	a.hit(shield,20.0,{"proc":true,"kx":1.0,"ky":0.0})
	_check(is_equal_approx(shield.hp,993.0), "front shield blocks 65% of direct weapon damage")
	shield.aim_dir = Vector2.RIGHT; a.hit(shield,20.0,{"proc":true,"kx":1.0,"ky":0.0})
	_check(is_equal_approx(shield.hp,973.0), "flanking deals full damage")
	shield.aim_dir = Vector2.LEFT; a.hit(shield,20.0,{"element":"lightning"})
	_check(is_equal_approx(shield.hp,953.0), "lightning bypasses the shield")
	shield.frozen_t = 1.0; a.hit(shield,20.0,{"proc":true})
	_check(shield.hp <= 933.0, "freezing disables shield protection")
	_start()
	for kind in ["undercover","swat","swat_shield","guard"]:
		var e = a.make_enemy(kind,1080,550); e.shoot_cd = 0.0
		a.ebul.clear()
		for frame in 40: e.tick(1.0/60.0)
		_check(a.ebul.size() == int(run.ET[kind].burst), "%s fires a full rifle/pistol burst then pauses" % kind)
		e.dead = true
	# Bullets and the shader flash share the actual attack frame's barrel tip, in both facings.
	for sprite in ["undercover","undercover_hood","swat","swat_shield","guard","det"]:
		for facing in [-1,1]:
			_start()
			var type: String = "undercover" if sprite.begins_with("undercover") else sprite
			var e = a.make_enemy(type,800-facing*200,550); e.spr = sprite
			e.face = facing; e.aim_dir = Vector2(facing,0); e.shoot_cd = 0
			e.tick(0.01)
			_check(not a.ebul.is_empty(), "%s facing %d fires" % [sprite,facing])
			if a.ebul.is_empty(): continue
			var muzzle := EnemyView.muzzle_world(e)
			var bullet: Dictionary = a.ebul[0]
			_check(muzzle.distance_to(Vector2(bullet.x,bullet.y)) < 0.01, "%s bullets originate at the barrel, facing %d" % [sprite,facing])
			_check(e.gfx.flash.position.distance_to(EnemyView.muzzle_local(e)) < 0.01 and e.gfx.flash.life > 0 and e.gfx.flash.light.energy > 0 and e.gfx.flash.material is ShaderMaterial, "%s has a lit shader muzzle flash at the same barrel tip" % sprite)
	# A prop blocks firing completely, including a burst already in progress.
	_start()
	var rifle = a.make_enemy("guard",1100,550); rifle.shoot_cd = 0
	a.walls = [{"rect":Rect2(940,450,25,220),"open":false}]; a.nav.configure(a.walls,Vector2(a.AW,a.AH)); a.ebul.clear()
	for frame in 45: rifle.tick(1.0/60.0)
	_check(a.ebul.is_empty(), "rifle squads cannot fire through obstacles")
	_start()
	var car = a.make_enemy("interceptor",1100,550); car.action_cd = 0.0
	car.tick(0.01)
	_check(car.action_phase == "windup", "car warns before accelerating")
	var locked: Vector2 = car.action_dir
	a.P.y += 180
	for frame in 58: car.tick(1.0/60.0)
	_check(car.action_phase == "rush" and car.action_dir == locked, "car commits to a dodgeable straight line")
	var before := Vector2(car.x,car.y); car.tick(0.1)
	_check(before.distance_to(Vector2(car.x,car.y)) > 40.0, "car accelerates beyond walking speed")
	a.walls = [{"rect":Rect2(car.x-55,400,20,400),"open":false}]; a.nav.configure(a.walls,Vector2(a.AW,a.AH))
	for frame in 15: car.tick(1.0/60.0)
	_check(car.action_phase == "recover", "car crashes and recovers at a wall")
	_start()
	var robot = a.make_enemy("robodog",1050,550); robot.action_cd = 0; robot.tick(0.01)
	_check(robot.action_phase == "windup" and robot.damage_taken("lightning") == 2.0 and robot.damage_taken("poison") == 0.0, "robot dog warns before lunging and has mechanical resistances")
	_start()
	var tank = a.make_enemy("tank",1200,550); tank.action_cd = 0; tank.tick(0.01)
	var cannon_origin := Vector2(tank.x,tank.y)
	_check(tank.action_phase == "windup", "tank paints a cannon warning before firing")
	for frame in 68: tank.tick(1.0/60.0)
	_check(a.ebul.size() == 1 and a.ebul[0].has("blast"), "tank launches an explosive cannon shell")
	_check(tank.r >= 100 and is_equal_approx(a.ebul[0].x,cannon_origin.x-184.0) and is_equal_approx(a.ebul[0].y,cannon_origin.y-59.0), "giant tank collision and shell origin match the larger projected hull and cannon")
	var projection = preload("res://enemies/vehicle_view.gd").new()
	for angle in [0.0,PI/4.0,PI/2.0,PI,PI*1.5,PI*1.75]:
		projection.heading = Vector2.from_angle(angle)
		var ground: Vector2 = projection._q(30,20,0)
		var roof: Vector2 = projection._q(30,20,45)
		_check(is_equal_approx(roof.x,ground.x) and is_equal_approx(roof.y,ground.y-45), "vehicle roofs stay screen-up at heading %.2f" % angle)
	a.P.inv = 0; var hp: float = a.P.hp
	for frame in 110: a._update_play(1.0/60.0)
	_check(a.P.hp < hp, "a cannon shell damages the villain at its blast destination")
	_start(20)
	var saved_table: Array = run.SPAWN_TABLE
	run.SPAWN_TABLE = [["tank",10,1,0],["interceptor",10,1,0],["cop",1,1,0]]
	for i in 70: a.spawn_group()
	_check(a.markers.filter(func(m): return m.type == "tank").size() <= 1, "only one tank can be pending or alive")
	_check(a.markers.filter(func(m): return m.type == "interceptor").size() <= 2, "only two cars can be pending or alive")
	for m in a.markers: _check(not a.in_wall(m.x,m.y,run.ET[m.type].r), "heavy units spawn clear of props")
	a.markers.clear()
	for theme in ["street","harbour","bank","rooftop","police","museum","spyhq"]:
		a.level = theme
		var seen := {}
		for i in 200: seen[a.pick_type()] = true
		if theme in ["street","harbour"]:
			_check(seen.has("interceptor") and seen.has("tank"), "cars and tanks are available on %s" % theme)
		else:
			_check(not seen.has("interceptor") and not seen.has("tank"), "cars and tanks never spawn on %s" % theme)
	run.SPAWN_TABLE = saved_table
	# Supplies are separate from modules and survive wave transitions.
	_start(); run.scrap = 1000
	for kind in run.CONSUMABLE_IDS:
		_check(not run.buy_consumable(kind), "%s refills need its kit first" % kind)
	for kit in ["kit_disguise","kit_grenade"]:
		var it: Dictionary = run.ITEM[kit]
		_check(run.item_available(it), "%s is offered before it is owned" % kit)
		run.offers = [{"it":it,"price":run.wave_price(it.c),"sold":false}]
		_check(run.buy(0) and run.consumable_charges[it.consumable] == 3, "%s gives 3 charges" % kit)
		_check(not run.item_available(it) and not run.build.items.has(kit), "%s is a one-time unlock, not a module" % kit)
	for kind in run.CONSUMABLE_IDS: run.consumable_charges[kind] = 0
	run.selected_consumable = "disguise"
	for kind in run.CONSUMABLE_IDS:
		var cash: int = run.scrap
		_check(run.buy_consumable(kind) and run.scrap == cash-run.wave_price(run.CONSUMABLE_PRICES[kind]), "%s purchase pays the displayed price" % kind)
		_check(not run.CNT.has(kind) and not run.build.items.has(kind), "%s never occupies a module or arm slot" % kind)
	_check(run.selected_consumable == "disguise", "the first supply bought becomes active")
	run.cycle_consumable(); _check(run.selected_consumable == "grenade", "cycling selects another carried supply")
	run.buy_consumable("grenade"); run.buy_consumable("grenade")
	var cash: int = run.scrap
	_check(not run.buy_consumable("grenade") and run.scrap == cash and run.consumable_charges.grenade == 3, "full pockets reject a fourth grenade without charging scrap")
	run.wave = 2; a.start_wave()
	_check(run.consumable_charges.grenade == 3, "unused charges survive the next wave")
	# Disguise breaks every hostile AI family, including a committed boss attack.
	_start(20); run.consumable_charges.disguise = 1
	for kind in ["cop","det","swat_shield","interceptor","robodog","guard","tank","boss"]:
		var e = a.make_enemy(kind,1000,550)
		e.action_phase = "windup"; e.action_t = 0.5; e.charging = 0.5
	_check(a.consumables.activate(a) and run.consumable_charges.disguise == 0, "using disguise spends exactly one charge")
	a.ebul.clear()
	for frame in 120:
		for e in a.enemies: e.tick(1.0/60.0)
	_check(a.ebul.is_empty() and a.enemies.all(func(e): return e.charging <= 0.0 and e.action_phase != "windup"), "every hostile family loses pursuit and cancels committed attacks")
	a._sync_villain(); _check(not a.villain.visible, "the disguise replaces the scientist's visible silhouette")
	a.consumables.tick(a,0.1,true)
	_check(a.P.disguise_t == 0.0, "firing breaks the disguise")
	a.ebul.clear(); var swat = a.make_enemy("swat",1050,550); swat.shoot_cd = 0; swat.tick(0.01)
	_check(not a.ebul.is_empty(), "enemies reacquire the villain after disguise ends")
	# Throw a grenade with the real consumable control, then verify its blast.
	_start(); run.selected_consumable = "grenade"; run.consumable_charges.grenade = 1
	var near = a.make_enemy("riot",1020,550); near.hp = 1000
	var far = a.make_enemy("riot",1200,550); far.hp = 1000
	await process_frame
	Input.action_press("consume"); a.consumables.tick(a,0.01,false); Input.action_release("consume")
	_check(a.consumables.grenades.size() == 1 and run.consumable_charges.grenade == 0, "Y / Q throws one paid grenade")
	for frame in 60: a.consumables.tick(a,1.0/60.0,false)
	_check(near.hp < 1000 and far.hp == 1000 and a.consumables.grenades.is_empty(), "grenade explodes after its fuse and only damages foes in the blast")
	# Teleport Pads are a B action now (not a supply): two placements, one traversal either way, then a long cooldown.
	_check(not run.CONSUMABLE_IDS.has("teleport") and not run.ITEM.has("kit_teleport"), "teleport pads are no longer a supply")
	_check(run.ITEM.has("teleport") and run.ITEM.teleport.get("action", "") == "teleport", "teleport pads are a B-button action")
	for reverse in [false,true]:
		_start(); run.build.items.append("teleport"); run.recompute()
		_check(run.equipped_action() == "teleport", "buying the pads puts them on B")
		_check(a.BossAbilities.start_action(a, "teleport") and a.consumables.pads.size() == 1, "B places the first pad")
		a.consumables.use_cd = 0
		_check(not a.BossAbilities.start_action(a, "teleport") and a.consumables.pads.size() == 1, "second pad cannot overlap the first")
		a.P.x = 1100; _check(a.BossAbilities.start_action(a, "teleport") and a.consumables.pads.size() == 2, "B again places the partner pad")
		a.consumables.tick(a,0.01,false)
		_check(a.P.x == 1100 and not a.consumables.pads_armed and a.action_cooldown == 0.0, "placing a pad does not teleport or start the cooldown")
		a.P.y = 650; a.consumables.tick(a,0.4,false)
		a.P.y = 550; a.P.x = 1100 if reverse else 800; a.consumables.tick(a,0.01,false)
		_check(a.P.x == (800 if reverse else 1100) and a.consumables.pads.is_empty(), "either pad teleports to its partner once, then both disappear")
		_check(a.action_cooldown >= 13.9, "the trip starts a long cooldown")
		a.consumables.use_cd = 0
		_check(not a.BossAbilities.start_action(a, "teleport") and a.consumables.pads.is_empty(), "no new pads until the cooldown ends")
	_start(); run.scrap = 0; run.consumables_owned = {"disguise":true}
	_check(not run.buy_consumable("disguise") and run.consumable_charges.disguise == 0, "insufficient scrap never grants free supplies")
	_check(not a.consumables.activate(a), "Y with no supplies is harmless")
	_start(); run.build.items.append("teleport"); run.recompute()
	a.BossAbilities.start_action(a, "teleport"); a.end_wave(); a.start_wave()
	_check(a.consumables.pads.is_empty() and a.action_cooldown == 0.0, "unused pads are cleared at wave end without costing the cooldown")
	_start(); run.consumable_charges.disguise = 1; run.consumable_charges.grenade = 1
	run.spend_consumable()
	_check(run.selected_consumable == "grenade", "using the final charge selects the next carried supply")
	_start(); run.consumable_charges.disguise = 1; a.consumables.activate(a)
	run.build.off = {"kind":"gun","ammo":0,"frame":0,"items":[]}; run.recompute()
	Input.action_press("fire_off"); a._update_play(0.01); Input.action_release("fire_off")
	_check(a.P.disguise_t <= 0.0, "rear-gun fire also breaks disguise")
	if OS.get_cmdline_user_args().has("--screenshots"): await _screenshots()
	print("REINFORCEMENT / CONSUMABLE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _screenshots() -> void:
	_start(16); run.theme_order = ["street"]; a.start_wave()
	a.set_process(false); a.banner_t = 0; a.siren_t = 0; a.wave_t = 45; a.P.inv = 0
	a.P.x = 800; a.P.y = 550; a.P.aim = -0.3
	run.consumable_charges = {"disguise":2,"grenade":3}
	for fixture in [["undercover",635,410],["undercover",700,715],["swat_shield",965,480],["swat",1010,525],["guard",1060,430],["robodog",615,625],["interceptor",510,510],["tank",1100,680]]:
		var e = a.make_enemy(fixture[0],fixture[1],fixture[2]); e.shoot_cd = 1
		if e.type in ["tank","interceptor","robodog"]:
			e.action_phase = "windup"; e.action_t = 0.7; e.action_target = Vector2(a.P.x,a.P.y); e.action_dir = (e.action_target-Vector2(e.x,e.y)).normalized()
			e.aim_dir = e.action_dir
		e.sync()
	a._sync(0); scene._show("play"); await _shot("reinforcements-combat")
	for e in a.enemies:
		if e.ranged:
			e.shoot_cd = 0.0; e.tick(0.01); e.sync()
	await _shot("reinforcements-muzzle-flashes")
	run.selected_consumable = "disguise"; a.consumables.activate(a); a._sync(0); await _shot("consumable-disguise")
	a.P.disguise_t = 0; a.consumables.use_cd = 0; a.action_cooldown = 0.0; a.consumables.place_pad(a)
	a.P.x = 1030; a.P.y = 600; a.consumables.use_cd = 0; a.consumables.place_pad(a); a._sync(0); await _shot("consumable-teleports")
	run.wave = 5; run.scrap = 120; run.gen_offers(); scene.shop_s.refresh(); scene._show("shop"); await _shot("consumable-shop")

func _shot(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/"+name+".png")

extends SceneTree
var scene
var a
var run
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func use(id: String) -> void:
	run.selected_consumable = id; run.consumable_charges[id] = 3; a.consumables.use_cd = 0.0
	check(a.consumables.activate(a),id+" activates")
func enemy(type: String, dx: float, dy := 0.0):
	var e = a.make_enemy(type,a.P.x+dx,a.P.y+dy); e.hp = 5000.0; e.max_hp = 5000.0
	return e
func _run() -> void:
	seed(20261123); run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	run.new_run(); run.scrap = 10000; scene._start_wave()
	a.walls = []; a.spawn_t = 10000; a.civ_t = 10000; a.crate_t = 10000
	a.P.x = 800.0; a.P.y = 550.0; a.P.inv = 0.0; run.S.crit = 0.0
	for id in ["shrink_pill","enlarge_pill","tesla_coil"]:
		var kit: Dictionary = run.ITEM["kit_"+id]
		run.offers = [{"it":kit,"price":int(kit.c),"sold":false}]
		check(run.buy(0) and run.owns_consumable(id) and run.consumable_charges[id]==3,id+" kit unlocks three charges")
		run.consumable_charges[id] = 2
		check(run.buy_consumable(id) and run.consumable_charges[id]==3,id+" can be refilled")
	use("shrink_pill")
	check(is_equal_approx(a.P.r,6.05) and is_equal_approx(a.P.size_scale,0.55),"shrinking changes actual collision radius")
	check(a.villain.scale.is_equal_approx(Vector2.ONE*0.55),"body and weapons shrink together")
	check(absf(a.villain.feet_global().y-a.P.y)<0.51,"shrinking keeps the feet on the collision/sorting plane within the renderer's pixel snap")
	check(a.villain.muzzle_global().distance_to(a.villain.rig.anchor_global("gun.muzzle"))<0.001,"scaled shot origin remains on the actual muzzle")
	var hp: float = a.P.hp
	a.ebul.append({"x":a.P.x+8.0,"y":a.P.y,"vx":0.0,"vy":0.0,"r":1.0,"dmg":1.0,"t":1.0})
	a._update_play(0.01)
	check(a.P.hp==hp,"bullet outside shrunken hitbox misses")
	a.ebul.clear(); a.consumables.tick(a,11.0,false)
	check(a.P.size_scale==1.0 and a.P.r==11.0 and a.P.size_t==0.0,"shrinking fully expires")
	use("enlarge_pill")
	check(is_equal_approx(a.P.r,17.6) and is_equal_approx(a.P.size_scale,1.6),"enlargement grows collision and sprite together")
	use("shrink_pill")
	check(a.P.size_scale<1.0 and a.P.size_t==10.0,"opposite pill replaces the active effect")
	use("enlarge_pill"); use("enlarge_pill")
	check(is_equal_approx(a.P.size_scale,1.6),"repeated pills refresh without multiplying size")
	a.P.moving = true
	var small = enemy("cop",0); var heavy = enemy("riot",0); var flyer = enemy("drone",0)
	var vehicle = enemy("interceptor",0); var boss = enemy("boss",0); var civilian = enemy("civ",0)
	a._update_stomps()
	check(small.size_class=="small" and small.hp<5000,"enlarged walking stomps small ground enemies")
	check(heavy.hp==5000 and vehicle.hp==5000 and boss.hp==5000,"medium/large enemies cannot be stomped by enlargement")
	check(flyer.hp==5000 and civilian.hp==5000,"flying enemies and civilians are excluded")
	var after: float = small.hp; a._update_stomps()
	check(small.hp==after,"stomp cooldown prevents repeated contact damage every frame")
	a.consumables.tick(a,11.0,false); small.stomp_cd = 0.0; a._update_stomps()
	check(small.hp==after,"enlargement stomp eligibility ends when the pill wears off")
	for e in a.enemies: e.dead = true
	a._sync(0.0)
	use("tesla_coil")
	var coil: Dictionary = a.consumables.coils[0]
	var position: Vector2 = coil.position
	a.P.x += 200.0; a._sync_villain()
	var between = enemy("cop",-100); var outside = enemy("cop",-100,100)
	a.consumables.pulse_coil(a,coil)
	check(coil.position==position and coil.arc_t>0.0,"coil stays planted while its electrical link follows the player")
	check(between.hp<5000 and outside.hp==5000,"lightning damages enemies along the connection only")
	var ranged_before: float = between.hp
	a.P.x = position.x+241; a.consumables.tick(a,0.01,false); a.consumables.pulse_coil(a,coil)
	check(coil.arc_t==0.0 and between.hp==ranged_before,"leaving the close-proximity radius immediately stops the link")
	check(coil.life<15.0,"out-of-range coils still consume their lifetime")
	a.P.x = position.x+200; a.consumables.pulse_coil(a,coil)
	check(coil.arc_t>0.0 and between.hp<ranged_before,"returning within range reconnects the active coil")
	a.walls = [{"rect":Rect2(position+Vector2(130,-35),Vector2(30,70)),"open":false}]
	var before: float = between.hp; coil.arc_t = 0.0; a.consumables.pulse_coil(a,coil)
	check(between.hp==before and coil.arc_t==0.0,"solid walls block damage and arc pulses")
	a.walls = []; coil.pulse = 0.0; a.consumables.tick(a,0.01,false)
	check(coil.pulse>=0.25 and coil.pulse<=0.65,"coil schedules irregular pulse intervals")
	a.consumables.tick(a,16.0,false)
	check(a.consumables.coils.is_empty(),"Tesla coil expires after 15 seconds")
	use("enlarge_pill"); use("tesla_coil"); a.start_wave()
	check(a.P.size_scale==1.0 and a.P.r==11.0 and a.consumables.coils.is_empty(),"new arena resets temporary effects and deployed coils")
	scene.shop_s.refresh()
	check(scene.shop_s.consumables_box.get_child_count()==3,"all owned new supplies appear in the wrapping refill list")
	print("SIZE AND COIL TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

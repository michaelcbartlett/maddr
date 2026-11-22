extends SceneTree
## Purchases, paced damage, independent laser channels, sustained ticks and live charge artwork.
const Art = preload("res://character/art_renderer.gd")
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items: Array = ["capacitor"], ammo := 0, off = null) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.build.ammo = ammo; run.build.off = off
	scene._start_wave(); a.walls = []; a.gun_cd.fill(0.0); a.P.off_cd = 0.0
	a.spawn_t = 1000; a.civ_t = 1000; run.S.crit = 0.0
	a.P.aim = 0.0; a._sync(0.0)

func _fire(held_time := 0.01, rear := false) -> Array:
	a.projs.clear(); a._fire_weapons(held_time,not rear,rear)
	return a.projs.duplicate()

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	_start([])
	_check(run.item_available(run.ITEM.capacitor), "starting laser can buy the capacitor without a blueprint or arm")
	run.scrap = 100; run.offers = [{"it":run.ITEM.capacitor,"price":32,"sold":false}]
	_check(run.buy(0) and run.scrap==68, "capacitor can be purchased for its base price")
	_check(not run.item_available(run.ITEM.capacitor), "capacitor is a single purchase")
	_start([],1)
	_check(not run.item_available(run.ITEM.capacitor), "non-laser loadouts do not roll the capacitor")
	run.build.items = ["gLaser"]; run.recompute()
	_check(run.item_available(run.ITEM.capacitor), "an extra laser barrel enables the offer")
	_start(["capacitor"])
	_check(is_equal_approx(_fire()[0].dmg,8.0), "uncharged laser retains base damage")
	a._fire_weapons(1.5,false,false)
	_check(is_equal_approx(a.laser_charge_ratio(),1.0), "released fire reaches full charge")
	var charged := _fire()
	_check(is_equal_approx(charged[0].dmg,20.0), "paced shot deals 2.5 times normal damage")
	_check(charged[0].color != Color("#ff4a4a"), "charged laser has a hotter shot colour")
	_check(a.laser_charge_ratio()==0.0, "firing spends the stored charge")
	_check(is_equal_approx(_fire(1.5)[0].dmg,8.0), "holding fire through a long cooldown never recharges")
	a._fire_weapons(0.75,false,false)
	_check(is_equal_approx(_fire()[0].dmg,14.0), "partial charge gives a proportional bonus")
	_start(["capacitor","split"])
	a._fire_weapons(2.0,false,false); var split := _fire()
	_check(split.size()==run.D.shots and split.all(func(p): return is_equal_approx(p.dmg,run.D.dmg*2.5)), "all split nozzles share one charged volley")
	_check(_fire(1.5).all(func(p): return is_equal_approx(p.dmg,run.D.dmg)), "split volley spends charge only once")
	_start(["capacitor"],1)
	a._fire_weapons(2.0,false,false)
	_check(is_equal_approx(_fire()[0].dmg,run.D.dmg), "bullets gain no capacitor damage")
	_start(["capacitor"],0,{"ammo":0,"frame":0,"items":[]})
	a._fire_weapons(1.5,false,false); _fire()
	_check(a.laser_charge_ratio(a.OFF_HAND)==1.0, "main laser cannot drain the rear laser's charge")
	_check(is_equal_approx(_fire(0.01,true)[0].dmg,run.D.dmg*0.7*2.5), "rear laser gets the bonus after its normal damage scaling")
	_start(["capacitor","lens"])
	var muzzle: Vector2 = a.villain.muzzle_global()
	var target = a.make_enemy("riot",muzzle.x+90,muzzle.y); target.hp = 10000; target.max_hp = 10000
	a._fire_weapons(1.5,false,false); _fire()
	_check(is_equal_approx(10000-target.hp,run.D.dmg*2.5), "charged piercing beam applies bonus damage to actual enemies")
	_start(["capacitor","lens","sustain"])
	muzzle = a.villain.muzzle_global()
	target = a.make_enemy("riot",muzzle.x+90,muzzle.y); target.hp = 10000; target.max_hp = 10000
	a._fire_weapons(1.5,false,false); _fire()
	var tick_damage: float = run.D.dmg*(0.1/run.D.cd)*1.15
	_check(is_equal_approx(10000-target.hp,tick_damage*2.5), "sustained laser spends charge on its opening damage tick")
	var hp: float = target.hp
	a._fire_weapons(0.01,true,false)
	_check(target.hp==hp and a.laser_charge_ratio()==0.0, "beam visual refresh adds no damage or charge")
	a._fire_weapons(0.1,true,false)
	_check(is_equal_approx(hp-target.hp,tick_damage), "subsequent held beam ticks use normal damage")
	_start(); a._fire_weapons(1.5,false,false); a._sync(0.0)
	_check(a.villain.rig.capacitor_charge==1.0, "rig receives the current charge for its amber windows")
	var art = Art.new(); art.configure(["capacitor"],"laser","pistol")
	_check(art.weapon_frame(0).anims.any(func(effect): return effect.k=="capacitor"), "purchased module includes animated charge windows")
	var effect: Dictionary = art.weapon_frame(0).anims.filter(func(fx): return fx.k=="capacitor")[0]
	var empty = Pixels.new(230,96); var full = Pixels.new(230,96)
	art.draw_effect(Pen.new(empty,35,59),effect,{"capacitor_charge":0.0},0.0)
	art.draw_effect(Pen.new(full,35,59),effect,{"capacitor_charge":1.0},0.0)
	_check(empty.image.get_data()!=full.image.get_data(), "charge windows visibly brighten as the capacitor fills")
	if OS.get_cmdline_user_args().has("--screenshots"):
		a.banner_t = 0; a.siren_t = 0; scene._show("play"); a.cam.reset_smoothing()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/capacitor-ready.png")
		run.scrap = 100; run.offers = [{"it":run.ITEM.capacitor,"price":32,"sold":false}]
		run.build.items = []; run.recompute(); scene.shop_s.refresh(); scene._show("shop")
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/capacitor-shop.png")
	_start()
	_check(a.laser_charge.is_empty(), "new waves clear stored charge")
	a._fire_weapons(1.5,false,false); run.build.items = []; run.recompute(); a._fire_weapons(0.01,false,false)
	_check(a.laser_charge.is_empty() and a.laser_charge_ratio()==0.0, "selling removes the charge and its bonus")
	scene.queue_free(); await process_frame; await process_frame
	print("CAPACITOR TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

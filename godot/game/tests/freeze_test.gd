extends SceneTree
## Freeze Ray arm turret: auto-fires effect-only ice bolts (no damage), build-up to frozen solid, kicking a frozen
## cop, the sliding ice block shattering into a cop, bosses and vehicles.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items := ["bionic_arm", "freeze_ray"]) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.build.off = null; run._rebuild_off(); run.recompute()
	scene._start_wave(); a.walls = []; a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; run.S.crit = 0.0
	for e in a.enemies: e.dead = true
	a.P.x = 800; a.P.y = 550; a.P.inv = 1000
	a.villain.set_items(); a._sync_villain()

func _cop(type := "cop", dx := 200.0, dy := 0.0):
	var e = a.make_enemy(type, a.P.x + dx, a.P.y + dy); e.hp = 5000; e.max_hp = 5000
	return e

func _slide(seconds: float) -> void:
	for i in int(seconds * 60.0): a._update_ice(1.0 / 60.0)

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)

	_check(not run.AMMO.any(func(d): return d.id == "freeze"), "the Freeze Ray is not a main-gun ammo")
	_check(run.ITEM.has("freeze_ray") and run.ITEM.freeze_ray.get("arm", "") == "freeze_ray", "the Freeze Ray is an arm-slot item")
	_start([])
	_check(not run.item_available(run.ITEM.freeze_ray), "it needs the Bionic Arm")

	# ---- the turret fires on its own, effect only ----
	_start()
	var e = _cop("cop", 200.0)
	a.projs.clear(); run.arm_cooldowns.freeze_ray = 0.0
	a._update_utility(0.01)
	_check(a.projs.size() == 1 and a.projs[0].type == "freeze" and a.projs[0].dmg == 0.0, "the arm auto-fires a no-damage ice bolt")
	for i in 40: a._update_projs(1.0 / 60.0)
	_check(e.hp == 5000 and e.chill > 0.0, "the bolt chills without doing damage")

	# ---- build-up ----
	_start()
	e = _cop()
	a._freeze_hit(e); a._freeze_hit(e)
	_check(e.frozen_t == 0.0, "two hits don't freeze a cop yet")
	a._freeze_hit(e)
	_check(e.frozen_t > 3.0, "the third hit freezes it solid")

	# ---- kick into another cop ----
	_start()
	var block = _cop("cop", 20.0)
	var victim = _cop("cop", 220.0)
	block.frozen_t = 3.0
	_slide(0.02)
	_check(block.slide.x > 400.0, "walking into a frozen cop kicks it away from you")
	_slide(1.0)
	_check(victim.hp < 5000 - 15.0, "the ice block smashes into the next cop")
	_check(block.hp < 5000 - 15.0 and block.frozen_t == 0.0 and block.slide == Vector2.ZERO, "the block shatters on impact")
	_check(victim.chill > 0.0, "the shatter chills the cop it hit")

	# ---- runs out of steam with nothing to hit ----
	_start()
	block = _cop("cop", 20.0)
	block.frozen_t = 3.0
	_slide(2.0)
	_check(block.slide == Vector2.ZERO and block.x > a.P.x + 100, "a lone block slides away and stops")

	# ---- unfrozen cops can't be kicked; bosses and vehicles ----
	_start()
	e = _cop("cop", 20.0)
	_slide(0.05)
	_check(e.slide == Vector2.ZERO, "only frozen cops can be kicked")
	var boss = _cop("boss", 300.0)
	for i in 3: a._freeze_hit(boss)
	_check(boss.frozen_t == 0.0, "bosses resist three hits")
	for i in 9: a._freeze_hit(boss)
	_check(boss.frozen_t > 0.0 and boss.frozen_t <= 0.8, "bosses only freeze briefly")
	boss.x = a.P.x + 20; boss.y = a.P.y
	_slide(0.05)
	_check(boss.slide == Vector2.ZERO, "bosses can't be kicked")
	var car = _cop("interceptor", -300.0)
	for i in 6: a._freeze_hit(car)
	_check(car.frozen_t == 0.0, "vehicles can't be frozen")

	print("FREEZE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

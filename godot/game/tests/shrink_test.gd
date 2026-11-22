extends SceneTree
## Shrink Ray arm turret: auto-fires effect-only bolts (no damage), build-up to the shrunk state (size, speed,
## damage), stomping, bosses and vehicles.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items := ["bionic_arm", "shrink_ray"]) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.build.off = null; run._rebuild_off(); run.recompute()
	scene._start_wave(); a.walls = []; a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; run.S.crit = 0.0
	for e in a.enemies: e.dead = true
	a.P.x = 800; a.P.y = 550; a.P.inv = 1000
	a.villain.set_items(); a._sync_villain()

func _cop(type := "cop", dx := 200.0):
	var e = a.make_enemy(type, a.P.x + dx, a.P.y); e.hp = 5000; e.max_hp = 5000
	return e

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)

	_check(not run.AMMO.any(func(d): return d.id == "shrink"), "the Shrink Ray is not a main-gun ammo")
	_check(run.ITEM.has("shrink_ray") and run.ITEM.shrink_ray.get("arm", "") == "shrink_ray", "the Shrink Ray is an arm-slot item")
	_start([])
	_check(not run.item_available(run.ITEM.shrink_ray), "it needs the Bionic Arm")
	_start(["bionic_arm"])
	_check(run.item_available(run.ITEM.shrink_ray), "it's offered once the arm is owned")

	# ---- the turret fires on its own, effect only ----
	_start()
	_check(run.build.off.kind == "shrink_ray", "it mounts in the arm slot")
	var e = _cop("cop", 200.0)
	a.projs.clear(); run.arm_cooldowns.shrink_ray = 0.0
	a._update_utility(0.01)
	_check(a.projs.size() == 1 and a.projs[0].type == "shrink" and a.projs[0].dmg == 0.0, "the arm auto-fires a no-damage shrink bolt at a cop in range")
	_check(run.arm_cooldowns.shrink_ray > 0.5, "then waits out its cooldown")
	a._update_utility(0.01)
	_check(a.projs.size() == 1, "no second bolt during the cooldown")
	for i in 40: a._update_projs(1.0 / 60.0)
	_check(e.hp == 5000 and e.shrink_meter > 0.0, "the bolt builds shrink without doing damage")
	_start()
	e = _cop("cop", 900.0)
	a.projs.clear(); run.arm_cooldowns.shrink_ray = 0.0; a._update_utility(0.01)
	_check(a.projs.is_empty(), "nothing in range, nothing fired")

	# ---- build-up and the shrunk state ----
	_start()
	e = _cop()
	var r0: float = e.r; var dmg0: float = e.dmg
	a._shrink_hit(e); a._shrink_hit(e)
	_check(e.shrunk_t == 0.0, "two hits don't shrink a cop yet")
	a._shrink_hit(e)
	_check(e.shrunk_t > 3.0, "the third hit shrinks it for about 4 s")
	_check(e.r < r0 and is_equal_approx(e.dmg, dmg0 * 0.3), "a shrunk cop has a smaller hitbox and does 30% damage")
	e.tick(4.5)
	_check(e.shrunk_t == 0.0 and is_equal_approx(e.r, r0) and is_equal_approx(e.dmg, dmg0), "it grows back to full size and damage")

	# ---- stomping ----
	_start()
	e = _cop("cop", 0.0)
	a._update_stomps()
	_check(e.hp == 5000, "full-size cops can't be stomped")
	e.shrink(4.0)
	a._update_stomps()
	var after_one: float = e.hp
	_check(after_one < 5000 - 15.0, "walking over a shrunk cop stomps it hard")
	a._update_stomps()
	_check(e.hp == after_one, "stomps have a short cooldown per cop")
	e.stomp_cd = 0.0; e.x = a.P.x + 120
	a._update_stomps()
	_check(e.hp == after_one, "you have to actually step on it")

	# ---- bosses and vehicles ----
	_start()
	var boss = _cop("boss")
	for i in 3: a._shrink_hit(boss)
	_check(boss.shrunk_t == 0.0, "bosses resist three hits")
	for i in 9: a._shrink_hit(boss)
	_check(boss.shrunk_t > 0.0 and boss.shrunk_t <= 1.5, "bosses shrink only briefly after a long build-up")
	var car = _cop("interceptor", -300.0)
	for i in 6: a._shrink_hit(car)
	_check(car.shrunk_t == 0.0, "vehicles can't be shrunk")

	print("SHRINK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
## Fire / poison spread between cops, and the close-range rules that stop K9s being unkillable:
## point-blank body hits, chasers stopping at the villain's edge, bite knockback, and the chaser speed cap.
const MAIN = "res://game/main.tscn"
var failures := 0
var checks := 0
var run: Node
var scene
var a

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", what)

func _setup(items: Array, wave := 1, diff := 1) -> void:
	run.unlocks.highest_difficulty = 5 # combat fixtures exercise each tier
	run.new_run(); run.set_difficulty(diff); run.wave = wave; run.build.items = items.duplicate(); run.recompute()
	scene._start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.P.inv = 1000.0
	for e in a.enemies: e.queue_free()
	a.enemies.clear()

func _cop(type: String, x: float, y: float, hp := 10000.0):
	var e = a.make_enemy(type, x, y); e.hp = hp; e.max_hp = hp
	return e

func _tick(e, seconds: float) -> void:
	for f in int(seconds * 60.0): e.tick(1.0 / 60.0)

func _run() -> void:
	seed(5150)
	run = root.get_node("Run")
	scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	a = scene.arena; a.set_process(false)
	# ---- shop gating ----
	_setup([])
	_check(not run.item_available(run.ITEM.napalm) and not run.item_available(run.ITEM.spores), "spread modules need their effect first")
	_setup(["thermite", "poison"])
	_check(run.item_available(run.ITEM.napalm) and run.item_available(run.ITEM.spores), "spread modules are offered with Thermite / Toxin")
	_check(run.S.burnSpread == 0.0 and run.S.poisonSpread == 0.0, "no spreading without the modules")
	# ---- no spread without the stat ----
	var src = _cop("riot", a.P.x + 300, a.P.y); var nb = _cop("riot", a.P.x + 340, a.P.y)
	src.burn_t = 100.0; src.burn_dps = 2.0; src.poison_s = 6; src.poison_t = 100.0
	_tick(src, 3.0)
	_check(nb.burn_t <= 0.0 and nb.poison_t <= 0.0, "without spread stats nothing jumps to a neighbour")
	# ---- fire spread ----
	_setup(["thermite", "napalm", "napalm", "napalm"])
	_check(is_equal_approx(run.S.burnSpread, 1.2), "Napalm Gel stacks the fire-spread chance")
	src = _cop("riot", a.P.x + 300, a.P.y); nb = _cop("riot", a.P.x + 340, a.P.y)
	var far = _cop("riot", a.P.x + 300 + 200, a.P.y)
	src.burn_t = 100.0; src.burn_dps = 4.0; src.burn_gen = 0
	_tick(src, 4.0)
	_check(nb.burn_t > 0.0 and nb.burn_gen == 1 and is_equal_approx(nb.burn_dps, 3.0), "a burning cop ignites a neighbour (gen 1, 75% dps)")
	_check(far.burn_t <= 0.0, "fire doesn't jump past the spread radius")
	# generation cap: gen 2 can't pass it on
	var g2 = _cop("riot", a.P.x - 300, a.P.y); var g3 = _cop("riot", a.P.x - 330, a.P.y)
	g2.burn_t = 100.0; g2.burn_dps = 2.0; g2.burn_gen = 2
	_tick(g2, 4.0)
	_check(g3.burn_t <= 0.0, "fire stops after two hops")
	# ---- poison spread ----
	_setup(["poison", "spores", "spores", "spores"])
	src = _cop("riot", a.P.x + 300, a.P.y); nb = _cop("riot", a.P.x + 340, a.P.y)
	src.poison_s = 6; src.poison_t = 100.0
	src._spread(1.0, run.S) # 120%/s: guaranteed catch while both enemies are still in range
	_tick(src, 4.0)
	_check(nb.poison_t > 0.0 and nb.poison_s == 3 and nb.poison_gen == 1, "poison infects a neighbour with half the stacks")
	var dmg_before: float = nb.hp
	_tick(nb, 1.0)
	_check(nb.hp < dmg_before, "caught poison deals damage")
	# a direct hit resets the generation (fresh source)
	nb.poison_gen = 2; a.hit(nb, 1.0, {"proc": true})
	_check(nb.poison_gen == 0, "a direct poison hit makes a fresh source")
	# ---- K9 speed cap ----
	_setup([], 20, 5)
	var fastest := 0.0
	for k in 200:
		var d = a.make_enemy("k9", a.P.x + 500, a.P.y); fastest = maxf(fastest, d.spd); d.queue_free()
	a.enemies.clear()
	var cap: float = run.base_stats().speed * float(run.RULES.enemies.chaser_speed_cap)
	_check(fastest <= cap + 0.001 and cap < run.base_stats().speed, "K9s never outrun the villain's base speed (%.0f <= %.0f)" % [fastest, cap])
	var dr = a.make_enemy("drone", a.P.x + 500, a.P.y)
	_check(dr.fly, "drones (flying) keep their own speed")
	# ---- chasers stop at the villain's edge, bite knockback ----
	_setup([])
	var dog = _cop("k9", a.P.x + 60, a.P.y)
	var closest := 1.0e9
	for f in 120:
		dog.tick(1.0 / 60.0)
		closest = minf(closest, Vector2(dog.x - a.P.x, dog.y - a.P.y).length())
	_check(closest >= (dog.r + a.P.r) * 0.85 - 27.0 and closest > 3.0, "a K9 never stacks on the villain's centre (closest %.1f)" % closest)
	a.P.inv = 0.0; dog.atk_cd = 0.0; dog.x = a.P.x + 15; dog.y = a.P.y
	var hp: float = a.P.hp
	dog.tick(1.0 / 60.0)
	_check(a.P.hp < hp and dog.x - a.P.x > 30.0, "a bite knocks the dog back")
	a.P.inv = 1000.0
	# ---- point-blank: a K9 pressed against or inside the body is always hit ----
	for spot in [Vector2(0, 0), Vector2(6, 8), Vector2(-4, 10), Vector2(12, -6)]:
		for lens in [false, true]:
			_setup(["lens"] if lens else [])
			var k = _cop("k9", a.P.x + spot.x, a.P.y + spot.y, 4.0)
			var ang: float = 0.0 if spot.length() < 0.5 else spot.angle()
			a.P.aim = ang; a._sync(0.0)
			var m = a.villain.muzzle_global(); var sh = a.villain.shoulder_global()
			a.fire_gun("laser", ang, 1.0, m.x, m.y, null, sh.x, sh.y, 0)
			_check(k.dead or k.hp <= 0.0, "a K9 at %s on the body dies to one %s" % [str(spot), "beam" if lens else "bolt"])
	# but a cop right behind you isn't hit by a shot fired forwards
	_setup([])
	var behind = _cop("k9", a.P.x - 16, a.P.y, 4.0)
	a.P.aim = 0.0; a._sync(0.0)
	var m2 = a.villain.muzzle_global(); var sh2 = a.villain.shoulder_global()
	a.fire_gun("laser", 0.0, 1.0, m2.x, m2.y, null, sh2.x, sh2.y, 0)
	_check(not behind.dead and behind.hp > 0.0, "a shot fired forwards doesn't hit a cop behind your back")
	_test_melee_windup()
	_test_drone_resistances()
	_test_ironclad()
	for e in a.enemies: e.queue_free()
	a.enemies.clear()
	print("COMBAT RULE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Baton cops and riot police wind up before the blow, so a villain who steps away makes them whiff.
func _test_melee_windup() -> void:
	for type in ["cop", "riot"]:
		_setup([])
		a.P.inv = 0.0
		var e = _cop(type, a.P.x + 20, a.P.y); e.atk_cd = 0.0
		var hp: float = a.P.hp
		e.tick(1.0 / 60.0)
		_check(e.action_phase == "swing" and a.P.hp == hp, "a %s winds up instead of hitting instantly" % type)
		_tick(e, 0.5)
		_check(a.P.hp < hp and e.action_phase == "", "a %s's blow lands when the villain stays in reach" % type)
		_setup([])
		a.P.inv = 0.0
		e = _cop(type, a.P.x + 20, a.P.y); e.atk_cd = 0.0
		hp = a.P.hp
		e.tick(1.0 / 60.0)
		a.P.x -= 140.0   # the villain sidesteps out of reach during the wind-up
		_tick(e, 0.5)
		_check(a.P.hp == hp, "a %s whiffs when the villain steps away" % type)
	a.P.inv = 1000.0

func _test_drone_resistances() -> void:
	_setup(["poison"], 7)
	run.S.crit = 0.0
	var drone = _cop("drone", a.P.x + 120, a.P.y)
	var cop = _cop("cop", a.P.x + 200, a.P.y)
	a.hit(drone, 10, {"proc":true})
	_check(drone.hp == 9990 and drone.poison_s == 0 and drone.poison_t == 0, "a poisoned weapon still deals its normal impact, without poisoning a drone")
	a.hit(drone, 10, {"element":"lightning"}); a.hit(cop, 10, {"element":"lightning"})
	_check(drone.hp == 9970 and cop.hp == 9990, "drones take double lightning damage; humans take normal damage")
	a.hit(drone, 100, {"element":"poison"})
	_check(drone.hp == 9970, "pure poison damage cannot hurt a drone")
	drone.poison_s = 8; drone.poison_t = 10
	_tick(drone, 1.0)
	_check(drone.hp == 9970 and drone.poison_t == 0 and drone.poison_s == 0, "drones clear poison without taking any poison tick damage")
	_setup(["poison", "spores"], 7); run.S.poisonSpread = 100.0
	var source = _cop("cop", a.P.x + 200, a.P.y)
	drone = _cop("drone", source.x + 30, source.y)
	source.poison_s = 6; source.poison_t = 10; source._spread(0.1, run.S)
	_check(drone.poison_s == 0 and drone.poison_t == 0, "spreading poison cannot infect drones")
	cop = _cop("cop", source.x + 40, source.y); source._spread(0.1, run.S)
	_check(cop.poison_s > 0, "an immune drone does not consume the poison spread to a human")
	_setup(["tesla"], 7)
	source = _cop("cop", a.P.x + 200, a.P.y); drone = _cop("drone", source.x + 40, source.y)
	a.chain_from(source, 10)
	_check(drone.hp == 9980, "chain-lightning jumps use the drone weakness")
	_setup(["tesla_helmet"], 7)
	drone = _cop("drone", a.P.x + 45, a.P.y); a.P.helmet_cd = 0; a._update_helmet(0.01)
	_check(drone.hp == 9994, "the helmet deals 6 lightning damage to drones")
	_setup([], 7); run.S.crit = 0.0
	drone = _cop("drone", a.P.x + 200, a.P.y)
	a.grapple._shock(a, Vector2(a.P.x + 100, a.P.y), Vector2(a.P.x + 300, a.P.y), run.D)
	_check(is_equal_approx(10000.0 - drone.hp, a.grapple.shock_damage(run.D) * 2), "the live grapple chain also uses the lightning weakness")

func _test_ironclad() -> void:
	_setup([], 5)
	var iron = a.make_enemy("boss", a.P.x - 250, a.P.y)
	_check(iron.hero == "ironclad" and iron.max_hp > 550, "Ironclad can withstand more than the old opening burst")
	var start: float = iron.x
	iron.charge_t = 10; iron.slam_cd = 10
	iron._boss_ai(1.0, 250, 0, 250, iron.spd)
	var normal_stride: float = iron.x - start
	_check(normal_stride > 125, "Ironclad closes more than 125 pixels in a second, above his old maximum")
	iron.x = start; iron.hp = iron.max_hp * 0.49
	iron._boss_ai(1.0, 250, 0, 250, iron.spd)
	_check(iron.x - start > normal_stride * 1.15, "Ironclad visibly speeds up below half health")
	iron.hp = iron.max_hp; iron.x = start; iron.charge_t = -0.001; iron.charging = 0
	for frame in 12: iron._boss_ai(0.05, 250, 0, 250, iron.spd)
	_check(iron.charging > 0 and iron.charge_t < 3 and Vector2(iron.cvx, iron.cvy).length() > iron.spd * 3, "Ironclad launches a fast charge within 0.6 seconds, with a shorter recovery")
	iron.charging = 0; iron.charge_t = 10; iron.slam_cd = 0; iron.x = start
	iron._boss_ai(0.01, 250, 0, 250, iron.spd)
	_check(iron.slam != null and iron.slam.T <= 0.8 and iron.slam.radius == 115 and iron.slam_cd <= 4, "Ironclad's normal slam has a shorter leap and recovery")
	iron._boss_ai(0.81, 250, 0, 250, iron.spd)
	_check(iron.slam == null and a.booms.back().r == 115, "the normal slam lands with the telegraphed radius")
	iron.hp = iron.max_hp * 0.49; iron.slam_cd = 0; iron.charge_t = 10; iron.x = start
	iron._boss_ai(0.01, 250, 0, 250, iron.spd)
	_check(iron.slam != null and iron.slam.T <= 0.65 and iron.slam.radius == 130 and iron.slam_cd <= 3.2, "enraged Ironclad slams faster, wider and more often")

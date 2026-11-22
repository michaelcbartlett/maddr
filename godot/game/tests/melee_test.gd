extends SceneTree
## Bionic-arm melee weapons (knife, whip, katana), melee stat upgrades, and damage-type amplifiers incl. radiation.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items: Array) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.build.off = null
	run._rebuild_off(); run.recompute()
	scene._start_wave(); a.walls = []; a.spawn_t = 1000; a.civ_t = 1000; run.S.crit = 0.0
	for e in a.enemies: e.dead = true
	a.P.melee_cd = 0.0; a.P.melee_t = 0.0; a.utility_fields.clear()
	a.villain.set_items()
	a._sync(0.0)

func _cop(dx: float, dy := 0.0):
	var o = a.villain.off_shoulder_global()
	var e = a.make_enemy("cop", o.x + dx, o.y + dy); e.hp = 5000; e.max_hp = 5000
	return e

## Runs the arm until one swing has landed.
func _swing() -> void:
	for i in 60:
		a._update_melee(1.0 / 60.0)
		if a.P.melee_hit and a.P.melee_t <= 0.0: return

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)

	_start([])
	for id in ["knife", "whip", "katana", "servos", "extender", "knuckles", "berserker"]:
		_check(not run.item_available(run.ITEM[id]), "%s needs the bionic arm" % id)
	_start(["bionic_arm"])
	for id in ["knife", "whip", "katana", "servos", "extender", "knuckles"]:
		_check(run.item_available(run.ITEM[id]), "%s is offered once the arm is owned" % id)
	_check(run.melee_spec().reach == 58.0, "bare arm keeps the fist")

	# per-weapon cooldowns
	for kind in ["knife", "whip", "katana"]:
		_start(["bionic_arm", kind])
		_check(run.build.off.kind == kind, "%s mounts in the arm slot" % kind)
		var e = _cop(30)
		_swing()
		_check(e.hp < 5000, "%s auto-swings at a nearby cop" % kind)
		_check(is_equal_approx(a.P.melee_cd + a.P.melee_swing, float(run.ITEM[kind].melee.cd)) or a.P.melee_cd > 0.0, "%s starts its own cooldown" % kind)
		_check(a.utility_fields.any(func(f): return f.kind == "slash"), "%s leaves a swing trail" % kind)

	# knife: one target, fast
	_start(["bionic_arm", "knife"])
	var k1 = _cop(30, -4); var k2 = _cop(34, 6)
	_swing()
	_check((k1.hp < 5000) != (k2.hp < 5000), "knife stabs a single target")
	_check(run.melee_spec().cd < run.ITEM.katana.melee.cd, "knife cooldown is shorter than the katana")

	# whip: long reach, hits the line, stuns
	_start(["bionic_arm", "whip"])
	var far = _cop(130); var near = _cop(60)
	_swing()
	_check(far.hp < 5000 and near.hp < 5000, "whip lashes everything along its 150px line")
	_check(far.time_lock > 0.0, "whip stuns")
	_start(["bionic_arm", "knife"])
	var out_of_reach = _cop(130)
	_swing()
	_check(out_of_reach.hp == 5000, "knife can't reach a whip-distance cop")

	# katana: wide arc
	_start(["bionic_arm", "katana"])
	var front = _cop(50); var side = _cop(20, 45); var behind = _cop(-60)
	_swing()
	_check(front.hp < 5000 and side.hp < 5000, "katana slash hits a wide arc")
	_check(behind.hp == 5000, "katana misses foes behind the swing")

	# civilians are never auto-attacked
	_start(["bionic_arm", "knife"])
	var o = a.villain.off_shoulder_global()
	var civ = a.make_enemy("civ", o.x + 25, o.y)
	if civ != null:
		civ.civ = true; civ.hp = 100
		for i in 30: a._update_melee(1.0 / 60.0)
		_check(civ.hp == 100 and a.P.melee_t == 0.0, "melee ignores civilians")

	# melee upgrades
	_start(["bionic_arm", "katana"])
	var base: Dictionary = run.melee_spec()
	_start(["bionic_arm", "katana", "servos", "extender", "knuckles"])
	var up: Dictionary = run.melee_spec()
	_check(up.cd < base.cd and up.swing < base.swing, "servos speed up melee")
	_check(is_equal_approx(up.reach, base.reach * 1.2), "telescoping forearm adds 20% reach")
	_check(is_equal_approx(up.dmg, base.dmg * 1.25), "brass knuckles add 25% melee damage")
	_start(["bionic_arm", "servos"])
	_check(run.melee_spec().cd < 0.72, "melee upgrades also apply to the bare fist")

	# damage-type amplifiers gate on their effect and scale it
	_start([])
	for id in ["bellows", "venom", "geiger", "payraise", "windings"]:
		_check(not run.item_available(run.ITEM[id]), "%s waits for its effect" % id)
	_start(["thermite", "poison", "uranium", "hypno", "tesla"])
	for id in ["bellows", "venom", "geiger", "payraise", "windings"]:
		_check(run.item_available(run.ITEM[id]), "%s offered with its effect" % id)
	_start(["thermite", "bellows"])
	var burner = _cop(200); a.hit(burner, 1.0, {"proc": true})
	_check(is_equal_approx(burner.burn_dps, run.S.burn * 1.3 * (1.0 + run.S.dmgPct * 0.5)), "bellows boosts burn damage")
	_start(["tesla_helmet"])
	var z1 = _cop(200); a.hit(z1, 10.0, {"element": "lightning"})
	_start(["tesla_helmet", "windings"])
	var z2 = _cop(200); a.hit(z2, 10.0, {"element": "lightning"})
	_check(is_equal_approx(5000.0 - z2.hp, (5000.0 - z1.hp) * 1.25), "copper windings boost lightning")

	# radiation
	_start(["uranium"])
	var hot = _cop(200)
	a.hit(hot, 1.0, {"proc": true})
	_check(hot.rad_s == 1 and hot.rad_t > 0.0, "uranium slugs irradiate on hit")
	var neighbour = _cop(230)
	hot.rad_s = a.RAD_MAX - 1
	var before: float = hot.hp
	a.hit(hot, 1.0, {"proc": true})
	_check(hot.rad_s == 0 and hot.hp < before - 15.0, "full dose melts down for burst damage")
	_check(neighbour.rad_s > 0, "meltdown irradiates neighbours")

	print("MELEE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

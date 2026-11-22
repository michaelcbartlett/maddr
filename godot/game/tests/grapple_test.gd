extends SceneTree
## Shock Grapple ("hook" ammo, game/grapple.gd): launch, anchoring, the tight chain's shocks, the tether,
## snapping on a wall, reeling in, and the shop/off-hand rules. Run headless:
##   Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/grapple_test.gd [-- --screenshots]
const Grapple = preload("res://game/grapple.gd")
var scene
var arena
var run
var checks := 0
var failures := 0
var capture := false

func _initialize() -> void: call_deferred("_run")

func _wall(x: float, y: float, w: float, h: float) -> Dictionary: return {"rect": Rect2(x, y, w, h), "open": false}

func _step(firing: bool, frames := 1) -> void:
	for i in frames:
		arena._sync_villain()
		arena.grapple.update(arena, 1.0 / 60.0, firing, arena.villain.muzzle_global(0), arena.P.aim, run.D)

func _run() -> void:
	seed(77); capture = OS.get_cmdline_user_args().has("--screenshots")
	run = root.get_node("Run"); run.new_run()
	var hook: int = run.AMMO.find_custom(func(a): return a.id == "hook")
	_check(hook >= 0, "the Shock Grapple is an ammo part")
	_check(not run.part_def("ammo", hook).is_empty(), "the shop can offer the Shock Grapple as an ammo swap")
	_check(run.unlocks.requirement("ammo", "hook") == "Reach wave 12", "the grapple unlocks as a starting pick at wave 12")
	run.build.ammo = hook; run.recompute()
	_check(run.has_hook() and run.S.guns[0] == "hook", "the main gun fires the grapple")
	_check(not run.item_available(run.ITEM.split), "Split Shot isn't offered with the grapple (one hook)")
	_check(run.AMMO[run.off_ammo()].id != "hook", "the rear gun never gets grapple ammo")
	run.build.ammo = 2; _check(run.AMMO[run.off_ammo()].id == "laser", "the rear gun skips the grapple when wrapping around")
	run.build.ammo = hook; run.recompute()

	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false)
	scene._enter_lab(); scene._open_difficulty(); scene.difficulty_s.buttons[0].pressed.emit()
	run.build.ammo = hook; run.recompute()   # the Lab starts a fresh run, so put the grapple back on
	_check(run.has_hook() and arena.villain.rig.ammo == "hook", "the villain's gun is rebuilt as the grapple")
	arena.P.inv = 1000.0
	for e in arena.enemies: e.dead = true
	arena.markers.clear(); arena._sync(0.0)
	var level_walls = arena.walls
	var length: float = Grapple.chain_length(run.D)

	# ---- launch and bite into a wall ----
	arena.walls = [_wall(500, 300, 20, 400)]
	arena.P.x = 300; arena.P.y = 500; arena.P.aim = 0.0
	_step(false, 2)
	_check(not arena.grapple.is_out(), "nothing happens until fire is held")
	_step(true)
	_check(arena.grapple.state == "fly", "holding fire launches the hook")
	_step(true, 30)
	_check(arena.grapple.anchored() and absf(arena.grapple.head.x - 500.0) < 1.0, "the hook bites into the first wall it reaches (%.1f)" % arena.grapple.head.x)
	_check(arena.villain.rig.hook_out, "the claw leaves the gun while the hook is out")

	# ---- the live chain shocks cops that touch it ----
	var muzzle: Vector2 = arena.villain.muzzle_global(0)
	var cop = arena.make_enemy("cop", (muzzle.x + 500.0) / 2.0, muzzle.y + 4.0)
	cop.max_hp = 1000.0; cop.hp = 1000.0
	var far = arena.make_enemy("cop", 420, 380); far.max_hp = 1000.0; far.hp = 1000.0
	_step(true)
	_check(cop.hp < 1000.0, "a cop touching the chain is shocked")
	_check(far.hp == 1000.0, "a cop away from the chain is not")
	var after: float = cop.hp
	_step(true)
	_check(cop.hp == after, "shocks wait for the frame's fire-rate interval")
	_step(true, int(ceil(Grapple.shock_interval(run.D) * 60.0)) + 1)
	_check(cop.hp < after, "the chain keeps shocking while it is held")
	cop.dead = true; far.dead = true; arena._sync(0.0)

	# ---- the tether: the villain can move, but not past the chain's length ----
	arena.P.x = 500.0 - length - 150.0
	_step(true)
	_check(Vector2(arena.P.x, arena.P.y).distance_to(arena.grapple.head) <= length + 0.5, "the chain stops the villain at its full length")
	_check(arena.grapple.anchored(), "walking to the limit doesn't drop the hook")
	arena.P.x = 380; arena.P.y = 560
	_step(true)
	_check(arena.grapple.anchored(), "the villain moves freely inside the chain's reach")

	# ---- a wall between the gun and the anchor snaps the chain ----
	arena.walls = [_wall(500, 300, 20, 400), _wall(440, 300, 8, 400)]
	_step(true)
	_check(arena.grapple.state == "reel", "a wall coming between gun and anchor snaps the chain")
	_step(true, 40)
	_check(arena.grapple.state != "reel", "the hook reels back in")

	# ---- releasing fire reels it in; a miss reels in at full length ----
	arena.walls = [_wall(500, 300, 20, 400)]
	arena.grapple.reset(); arena.P.x = 300; arena.P.y = 500; arena.P.aim = 0.0
	_step(true, 30)
	_check(arena.grapple.anchored(), "re-anchors after a reel")
	_step(false)
	_check(arena.grapple.state == "reel", "letting go of fire reels the hook in")
	_step(false, 40)
	_check(not arena.grapple.is_out() and not arena.villain.rig.hook_out, "the claw is back on the gun")
	arena.walls = []
	arena.grapple.reset(); arena.P.x = 800; arena.P.y = 550; arena.P.aim = PI / 2.0
	_step(true, 60)
	_check(arena.grapple.state != "anchored", "a hook that reaches the chain's length without a wall reels in")
	arena.grapple.reset(); arena.P.x = 60; arena.P.aim = PI
	_step(true, 20)
	_check(arena.grapple.anchored() and arena.grapple.head.x <= 13.0, "the arena edge holds the hook too")

	# ---- the hook strikes cops it flies through ----
	arena.grapple.reset(); arena.P.x = 300; arena.P.y = 500; arena.P.aim = 0.0
	arena.walls = [_wall(700, 300, 20, 400)]
	_step(false); muzzle = arena.villain.muzzle_global(0)
	var target = arena.make_enemy("cop", muzzle.x + 120.0, muzzle.y); target.max_hp = 1000.0; target.hp = 1000.0
	_step(true, 12)
	_check(target.hp < 1000.0, "the flying hook hits a cop in its path")
	target.dead = true; arena._sync(0.0)

	# ---- through the real input path ----
	arena.walls = level_walls; arena.grapple.reset()
	arena.P.x = 200; arena.P.y = 550; arena.P.aim = PI
	Input.action_press("fire")
	for frame in 20: arena._process(1.0 / 60.0)
	_check(arena.grapple.is_out(), "RT / left mouse drives the grapple in play")
	_check(arena.projs.is_empty() and arena.beams.is_empty(), "the main gun fires no shots while it carries the grapple")
	if capture:
		for e in arena.enemies: e.dead = true
		arena._sync(0.0)
		for i in 4: arena.make_enemy("cop", lerpf(arena.villain.muzzle_global(0).x, arena.grapple.head.x, 0.25 + i * 0.18) , arena.P.y + randf_range(-6, 6))
		for frame in 3: arena._process(1.0 / 60.0)
		await process_frame; await process_frame
		root.get_texture().get_image().save_png("res://test-results/grapple.png")
	Input.action_release("fire")
	for frame in 40: arena._process(1.0 / 60.0)
	_check(not arena.grapple.is_out(), "releasing fire in play reels the hook in")
	arena.end_wave()
	_check(not arena.grapple.is_out(), "the hook is cleared when the wave ends")

	print("GRAPPLE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + what)

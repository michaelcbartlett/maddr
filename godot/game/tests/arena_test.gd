extends SceneTree
## Single-arena run: size, wave flow, themes, difficulty, pickups (scrap, cash, crates, magnet),
## bosses, the Bionic Arm and its slot weapons. Run headless:
##   Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/arena_test.gd [-- --screenshots]
var scene
var arena
var run
var checks := 0
var failures := 0
var capture := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	seed(3015); capture = OS.get_cmdline_user_args().has("--screenshots")
	run = root.get_node("Run"); run.new_run()
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false)
	# ---- flow: design -> difficulty -> wave 1 ----
	scene._enter_lab(); scene._open_difficulty()
	run.unlocks.highest_difficulty = 5; scene.difficulty_s.refresh() # unlocked profile for the tier balance checks
	_check(scene.state == "difficulty" and scene.difficulty_s.visible, "difficulty picker follows the design screen")
	scene.difficulty_s.buttons[2].pressed.emit()
	_check(run.difficulty == 3 and scene.state == "play" and arena.state == "play", "picking a difficulty starts wave 1")
	_check(Levels.AW == 1600 and Levels.AH == 1100 and arena.cam.limit_right == 1600 and arena.cam.limit_bottom == 1100, "one Brotato-sized 1600x1100 arena")
	_check(Vector2(arena.P.x, arena.P.y) == Levels.SPAWN, "the villain starts in the middle")
	_check(arena.wave_t == 30.0, "wave 1 lasts 30 s")
	_check(arena.level == "street" and arena.banner_txt.contains("CITY STREETS") and arena.siren_t > 0, "wave 1 is the street theme with a siren intro")
	_check(run.D.maxHp == 30 and arena.P.hp == 30, "starting health is 30")
	if capture: await _shot("arena-wave1")
	# ---- difficulty multipliers ----
	var hp := {}
	for level in [1, 5]:
		run.set_difficulty(level); var e = arena.make_enemy("cop", 300, 300); hp[level] = e.max_hp; e.dead = true
	_check(is_equal_approx(hp[5] / hp[1], 1.3 / 0.85), "Arch-Nemesis cops have 1.3x HP, Petty Crook 0.85x")
	_check(hp[5] < run.D.dmg, "the starting gun one-shots a wave-1 cop even on Arch-Nemesis")
	_check(run.payout_for(5) < run.payout_for(1) and is_equal_approx(run.payout_for(1), 1.0), "harder tiers pay less per cop (they spawn more)")
	_check(run.tier("spawn", 5) > run.tier("spawn", 3) and run.tier("spawn", 3) > run.tier("spawn", 1), "spawn rate climbs with the tier")
	run.set_difficulty(1)
	# ---- the wave runs: spawns, timer, no city ----
	arena.P.inv = 1000.0
	for frame in 240: arena._process(1.0 / 60.0)
	_check(arena.wave_t < 30.0 and (arena.enemies.size() > 0 or arena.markers.size() > 0), "the wave timer runs and cops spawn")
	_check(not ("city" in arena) and not ("active_shop" in arena), "no city or heist rooms remain")
	for e in arena.enemies:
		_check(e.x >= 20 and e.x <= 1580 and e.y >= 20 and e.y <= 1080 and not arena.in_wall(e.x, e.y), "cops stay inside the arena and out of props")
	# ---- pickups ----
	run.scrap = 0; run.scrap_f = 0.0; arena.pickups.clear()
	arena.pickups.append({"x": arena.P.x + 4, "y": arena.P.y, "v": 3.0, "vx": 0.0, "vy": 0.0, "mag": false})
	arena._process(1.0 / 60.0)
	_check(run.scrap == 3 and arena.pickups.is_empty(), "walking onto a scrap gear collects it in full")
	arena.pickups.append({"x": arena.P.x, "y": arena.P.y + 6, "v": 5.0, "vx": 0.0, "vy": 0.0, "cash": 1})
	arena._process(1.0 / 60.0)
	_check(run.scrap == 8, "cash piles are collected too")
	var far := {"x": arena.P.x + run.D.pickup - 10, "y": arena.P.y, "v": 2.0, "vx": 0.0, "vy": 0.0, "mag": false}
	arena.pickups.append(far)
	for frame in 60: arena._process(1.0 / 60.0)
	_check(run.scrap == 10, "the magnet pulls in scrap inside the pickup range")
	var outside := {"x": arena.P.x + run.D.pickup + 120, "y": arena.P.y, "v": 2.0, "vx": 0.0, "vy": 0.0, "mag": false}
	arena.pickups.append(outside); arena._process(1.0 / 60.0)
	_check(arena.pickups.has(outside), "scrap outside the range stays put")
	arena.pickups.clear()
	var civ = arena.make_enemy("civ", arena.P.x + 200, arena.P.y); arena.kill(civ)
	_check(arena.pickups.filter(func(p): return p.has("cash")).size() == 3, "civilians drop cash")
	arena.pickups.clear()
	arena.P.hp = 10; var before: int = run.scrap
	arena.crates.append({"x": arena.P.x + 10, "y": arena.P.y, "v": 6, "t": 0.0, "got": false})
	arena._process(1.0 / 60.0)
	_check(run.scrap == before + 6 and arena.P.hp > 10 and arena.crates.is_empty(), "plutonium crates pay scrap and heal")
	# ---- arm slot (carried over from the heist suite) ----
	_check(not arena.villain.rig.has_bionic, "the villain starts without the bionic arm")
	_check(not run.item_available(run.ITEM.time_freeze), "arm weapons require the purchased arm")
	run.scrap = 1000
	_buy("bionic_arm")
	_check(arena.villain.rig.has_bionic and run.CNT.bionic_arm == 1, "buying the bionic arm installs it")
	for other in arena.enemies: other.dead = true   # faster cops may have reached the villain during the warm-up frames
	var origin = arena.villain.off_shoulder_global()
	var enemy = arena.make_enemy("cop", origin.x + 56, origin.y); enemy.hp = 1000; enemy.max_hp = 1000
	arena._update_melee(0.01); arena._update_melee(0.12)
	_check(enemy.hp < 1000, "the arm punches nearby foes")
	_buy("offhand")
	arena.P.aim = 0; arena.P.off_cd = 0; arena.gun_cd.fill(0); arena._fire_weapons(1.0 / 60.0, true, true)
	_check(arena.projs.any(func(p): return p.source == -1 and p.vx < 0), "the arm gun fires opposite the main aim")
	_buy("time_freeze")
	arena.ebul = [{"x": arena.P.x + 30, "y": arena.P.y, "vx": 100.0, "vy": 0.0, "t": 2.0, "r": 3.0, "dmg": 1.0}]
	arena._update_utility(0.01)
	_check(enemy.time_lock > 0 and arena.ebul[0].time_lock > 0, "time freeze stops foes and hostile shots")
	_buy("proximity_bomb")
	var close = arena.make_enemy("cop", arena.P.x + 55, arena.P.y); close.hp = 1000; close.max_hp = 1000
	var distant = arena.make_enemy("cop", arena.P.x + 350, arena.P.y); distant.hp = 1000; distant.max_hp = 1000
	arena._update_utility(0.01)
	_check(close.hp < 1000 and distant.hp == 1000, "the proximity bomb hits a circle around the villain")
	# ---- wave end -> shop -> next wave with a new theme ----
	arena.wave_t = 0.01; arena._process(0.05)
	_check(arena.state == "clear", "the wave ends when the timer runs out")
	for frame in 40: arena._process(0.05)
	_check(scene.state == "shop" and run.wave == 2, "clearing a wave opens the shop")
	scene.shop_s.next_wave.emit()
	_check(scene.state == "play" and arena.wave_t == 35.0 and arena.level != "street", "wave 2 is 35 s in a new theme")
	_check(arena.banner_txt.begins_with("WAVE 2 · ") and arena.banner_txt.contains(arena.arena_level.theme.name), "the banner names the theme")
	if capture: await _shot("arena-wave2-" + arena.level)
	# every theme builds, keeps the centre clear and has solid props
	var seen := {}
	for w in range(1, 21):
		run.wave = w; arena.start_wave(); seen[arena.level] = true
		var spawn: Vector2 = arena.arena_level.spawn
		_check(not arena.in_wall(spawn.x, spawn.y, 40) and Vector2(arena.P.x, arena.P.y) == spawn, "spawn is clear in %s" % arena.level)
		# the train heist adds its car walls and couplings on top of one wall per prop
		var structural: int = 0 if arena.level != "train" else arena.walls.filter(func(wall): return not wall.has("prop_index")).size()
		_check(arena.walls.size() > 0 and arena.arena_level.props.size() == arena.walls.size() - structural, "%s has solid props" % arena.level)
		_check(arena.wave_t == minf(60.0, 25.0 + 5.0 * w), "wave %d length (30 s, +5 s a wave, 60 s cap)" % w)
		if run.boss_for(w) != null:
			arena.P.inv = 1000.0
			for frame in 120: arena._process(0.05)
			_check(arena.boss != null and arena.boss.hero == run.boss_for(w).id, "wave %d brings %s" % [w, run.boss_for(w).name])
		if capture and w <= 7:
			arena.P.x = 560; arena.P.y = 420; await _shot("arena-theme-" + arena.level)
	_check(seen.size() == 8 and seen.has("train"), "all seven themes and the train heist appear in a run")
	run.wave = 20; arena.state = "done"; scene._on_cleared()
	_check(scene.state == "over" and scene.over_title.text == "CITY CONQUERED!", "surviving wave 20 wins")
	print("ARENA TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _shot(name: String) -> void:
	arena.banner_t = 0; arena.siren_t = 0.0; arena.lights.begin(); arena._sync(0); arena.cam.force_update_scroll()
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/%s.png" % name)

func _buy(id: String) -> void:
	run.offers = [{"it": run.ITEM[id], "price": run.ITEM[id].c, "sold": false}]
	_check(run.buy(0), "can purchase " + id)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error("FAIL: " + label)

extends SceneTree
## Train heist stage (game/train_heist.gd, levels/train_level.gd): scheduling, the connected cars, boarding spawns,
## reaching the vault, failing on timeout, the five per-difficulty unlocks and their save, and the reward visuals.
## Uses its own save file under user://; the player's user://unlocks.json is never touched.
const UnlocksT = preload("res://game/unlocks.gd")
const TrainLevel = preload("res://levels/train_level.gd")
const Art = preload("res://character/art_renderer.gd")
const SAVE := "user://heist_selftest.json"
const REWARDS := ["bullion", "rail_spike", "steam_piston", "firebox", "headlamp"]
var checks := 0
var failures := 0
var run
var scene
var a

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", label)

## Start the run's heist wave on a difficulty through the real flow (main._start_wave -> arena.start_wave).
func _start_heist(level: int) -> void:
	run.new_run(); run.unlocks.highest_difficulty = 5
	_check(run.set_difficulty(level), "difficulty %d selectable for the test" % level)
	run.wave = run.heist_wave; scene._start_wave()
	a.civ_t = 1000; a.crate_t = 1000; a.P.inv = 1000

func _step(n := 1) -> void:
	for i in n: a._process(1.0 / 60.0)

func _run() -> void:
	seed(5150)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	run.unlocks.reset()

	# ---- scheduling: one heist wave per run, from rules.json heist.waves, never a boss wave ----
	var allowed: Array = run.RULES.heist.waves.map(func(w): return int(w))
	for i in 30:
		run.new_run()
		_check(allowed.has(run.heist_wave) and run.boss_for(run.heist_wave) == null, "heist wave %d is an allowed non-boss wave" % run.heist_wave)
		var trains := 0
		for w in range(1, 21):
			if run.theme_for_wave(w) == "train": trains += 1
		_check(trains == 1 and run.theme_for_wave(run.heist_wave) == "train", "exactly one train wave per run")
	_check(run.RULES.heist.rewards == REWARDS, "one reward per difficulty")
	for id in REWARDS:
		_check(run.ITEM.has(id) and run.unlocks.rule_for("item", id).need.has("heist"), "%s is a heist-locked item" % id)

	# ---- the stage: a long train of connected cars ----
	_start_heist(1)
	_check(a.level == "train" and a.heist.active and a.AW > Levels.AW * 2 and a.AW == int(TrainLevel.size().x), "the heist wave builds the long train arena")
	_check(a.cam.limit_right == a.AW and a.cam.limit_bottom == a.AH, "camera limits follow the train")
	_check(Vector2(a.P.x, a.P.y) == TrainLevel.spawn() and a.heist.car_at(a.P.x) == 0, "the villain boards at the caboose")
	_check(a.banner_txt.contains("TRAIN HEIST") and a.wave_t == run.wave_len(run.wave), "banner names the heist; the normal wave timer runs")
	var route: PackedVector2Array = a.nav.path(Vector2(a.P.x, a.P.y), a.heist.goal().get_center())
	_check(route.size() > 20, "every car connects to the next through its gangway door (path %d cells)" % route.size())
	for i in 60:
		var p: Vector2 = a._outside_spawn()
		var inside := false
		for c in TrainLevel.car_count(): inside = inside or TrainLevel.car_rect(c).has_point(p)
		_check(inside and not a.in_wall(p.x, p.y, 20) and p.distance_to(Vector2(a.P.x, a.P.y)) >= 200, "cops board inside a car near the villain")
	await process_frame   # HUD draws the heist bar without errors
	_check(scene.hud.visible, "HUD is up during the heist")
	_check(not run.item_available(run.ITEM.bullion), "the Petty Crook reward isn't sold before it's won")

	# ---- reaching the end: walk the cars along the navigation route ----
	a.spawn_t = 1000
	var last_car := 0; var cars_in_order := true
	for point in route:
		a.P.x = point.x; a.P.y = point.y
		_step()
		var car: int = a.heist.car_at(a.P.x)
		if car < last_car: cars_in_order = false
		last_car = car
		if a.state != "play": break
	_check(cars_in_order and last_car == TrainLevel.car_count() - 1, "the route runs car by car to the vault car")
	_check(a.heist.won and a.state == "clear" and a.banner_txt == "VAULT CRACKED!", "reaching the vault ends the wave as a heist win")
	_check(run.unlocks.is_unlocked("item", "bullion") and a.heist.unlocked and a.heist.reward == "bullion", "Petty Crook unlocks the Gold Bullion Ballast")
	_check(run.build.items.has("bullion") and run.S.armor >= 2.0, "the reward is installed for the rest of the run")
	_check(a.heist.message.contains("GOLD BULLION BALLAST UNLOCKED"), "HUD announces the unlock")
	for id in REWARDS.slice(1): _check(not run.unlocks.is_unlocked("item", id), "%s stays locked after a Petty Crook heist" % id)
	_check(run.item_available(run.ITEM.bullion), "the won reward joins the shop pool")
	scene._game_over(false)
	_check(scene.over_text.text.contains("Gold Bullion Ballast"), "game over lists the heist unlock")
	# the wave after the heist is a normal arena again
	run.wave = run.heist_wave + 1; a.start_wave()
	_check(a.level != "train" and a.AW == Levels.AW and not a.heist.active, "the next wave goes back to the normal arena")

	# ---- repeating a difficulty: no second unlock, but the loot is still installed ----
	_start_heist(1)
	var before: int = run.build.items.size()
	a.P.x = a.heist.goal().get_center().x; a.P.y = a.heist.goal().get_center().y; _step()
	_check(a.heist.won and not a.heist.unlocked and not run.unlocks.fresh.has("item:bullion"), "the same difficulty never unlocks twice")
	_check(run.build.items.size() == before + 1, "a repeat heist still installs the loot")

	# ---- failing on timeout ----
	_start_heist(2)
	a.spawn_t = 1000; a.P.x = a.heist.goal().position.x - 400; a.wave_t = 0.01
	_step()
	_check(a.heist.failed and not a.heist.won and a.state == "clear" and a.banner_txt == "THE TRAIN GOT AWAY!", "timer ends the heist as a getaway")
	_check(not run.unlocks.is_unlocked("item", "rail_spike") and not run.build.items.has("rail_spike"), "no reward when the timer runs out")
	a.P.x = a.heist.goal().get_center().x; a.P.y = a.heist.goal().get_center().y; _step(3)
	_check(not run.unlocks.is_unlocked("item", "rail_spike"), "reaching the vault after the timer is too late")

	# ---- each difficulty unlocks its own reward ----
	for level in range(2, 6):
		_start_heist(level)
		a.spawn_t = 1000
		a.P.x = a.heist.goal().get_center().x; a.P.y = a.heist.goal().get_center().y; _step()
		var id: String = REWARDS[level - 1]
		_check(a.heist.won and a.heist.reward == id and run.unlocks.is_unlocked("item", id), "%s unlocks %s" % [run.difficulty_name(level), id])
		_check(run.unlocks.fresh.filter(func(k): return REWARDS.has(k.substr(5))) == ["item:" + id], "only %s is new on %s" % [id, run.difficulty_name(level)])
		for later in REWARDS.slice(level): _check(not run.unlocks.is_unlocked("item", later), "%s still locked after %s" % [later, run.difficulty_name(level)])
	_check(run.unlocks.heists == [1, 2, 3, 4, 5], "all five difficulties recorded")

	# ---- persistence ----
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var u = UnlocksT.new(run.RULES.unlocks, true); u.path = SAVE; u.persist = true; u.difficulty_names = run.DIFFICULTY
	_check(u.requirement("item", "steam_piston") == "Reach the vault car in the train heist on MENACE", "requirement text names the difficulty")
	_check(u.note_heist(3) == ["item:steam_piston"], "Menace heist unlocks the Steam Piston Rings")
	_check(u.note_heist(3).is_empty(), "and only once")
	var v = UnlocksT.new(run.RULES.unlocks, true); v.path = SAVE; v.persist = true; v.load_save()
	_check(v.is_unlocked("item", "steam_piston") and v.heists == [3] and not v.is_unlocked("item", "firebox"), "heist unlocks load back from the save")
	_check(v.note_heist(3).is_empty(), "a reloaded profile doesn't re-award the heist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	# ---- every reward visibly changes the gun ----
	var plain = Art.new(); plain.configure([], "laser", "pistol")
	var base: Image = plain.weapon_frame(1).cv
	for id in REWARDS:
		var art = Art.new(); art.configure([id], "laser", "pistol")
		var img: Image = art.weapon_frame(1).cv
		_check(img.get_size() != base.get_size() or img.get_data() != base.get_data(), "%s is drawn on the weapon" % id)

	run.unlocks.reset()
	print("HEIST TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

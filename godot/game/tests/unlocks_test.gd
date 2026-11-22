extends SceneTree
## Meta-progression: persistent starting-part unlocks (game/unlocks.gd) and the design screen's locked/unlocked cards.
## Uses its own save file under user://; the player's user://unlocks.json is never touched.
const MAIN = "res://game/main.tscn"
const UnlocksT = preload("res://game/unlocks.gd")
const TEST_SAVE := "user://unlocks_selftest.json"
var failures := 0
var checks := 0
var run: Node

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", what)

func _run() -> void:
	seed(4242)
	run = root.get_node("Run")
	var rules: Array = run.RULES.unlocks
	# ---- the game's own instance never persists in a test process ----
	_check(run.is_test_process() and not run.unlocks.persist, "test runs keep unlock progress in memory only")
	_check(run.unlocks.path == UnlocksT.SAVE_PATH, "real save path is user://unlocks.json")
	# ---- rules ----
	var ids: Array = rules.map(func(r): return r.part + ":" + r.id)
	var start_rules := rules.filter(func(r): return r.part != "item").size()
	_check(start_rules == run.AMMO.size() + run.FRAMES.size() - 2, "every starting part except Laser / Ray Pistol has an unlock rule")
	for k in ["ammo:bullet", "ammo:razor", "frame:blunder", "frame:rifle", "frame:repeater", "item:lens"]:
		_check(ids.has(k), "unlock rule exists for " + k)
	_check(not ids.has("ammo:laser") and not ids.has("frame:pistol"), "Laser and Ray Pistol are always available")
	# ---- save / load round trip ----
	if FileAccess.file_exists(TEST_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	var u = UnlocksT.new(rules, true); u.path = TEST_SAVE; u.persist = true
	_check(u.is_unlocked("ammo", "laser") and not u.is_unlocked("ammo", "bullet"), "fresh profile: only the defaults")
	_check(u.requirement("ammo", "bullet") == "Reach wave 4" and u.requirement("frame", "blunder") == "Defeat the wave-5 boss", "requirement text")
	_check(u.note_wave(3).is_empty(), "wave 3 unlocks nothing")
	_check(u.note_wave(4) == ["ammo:bullet"], "reaching wave 4 unlocks Bullets")
	_check(u.note_wave(4).is_empty() and u.note_wave(2).is_empty(), "the same wave never unlocks twice")
	_check(u.note_boss(5) == ["frame:blunder"], "beating the wave-5 boss unlocks the Blunderbuss")
	_check(FileAccess.file_exists(TEST_SAVE), "progress is written to the save file")
	var v = UnlocksT.new(rules, true); v.path = TEST_SAVE; v.persist = true; v.load_save()
	_check(v.best_wave == 4 and v.bosses == [5], "best wave and bosses load back")
	_check(v.is_unlocked("ammo", "bullet") and v.is_unlocked("frame", "blunder") and not v.is_unlocked("frame", "rifle"), "unlocks load back")
	var later: Array = v.note_wave(8)
	_check(later.has("frame:rifle") and later.has("item:lens") and v.note_boss(10) == ["ammo:razor"] and v.note_boss(15) == ["frame:repeater"], "later unlocks")
	_check(v.fresh.has("frame:rifle") and v.fresh.has("item:lens") and v.fresh.has("frame:repeater"), "unlocks earned this run are listed for the game-over screen")
	v.begin_run(); _check(v.fresh.is_empty(), "a new run clears the fresh list")
	# corrupt and missing files are survivable
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE); f.store_string("{not json"); f.close()
	var w = UnlocksT.new(rules, true); w.path = TEST_SAVE; w.persist = true; w.load_save()
	_check(w.best_wave == 0 and w.unlocked.is_empty(), "an unreadable save starts a fresh profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	w.load_save(); _check(w.unlocked.is_empty(), "a missing save starts a fresh profile")
	# ---- design screen + starting loadout ----
	var scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	run.unlocks.reset()
	scene._enter_lab(); await process_frame
	_check(run.build.ammo == 0 and run.build.frame == 0 and run.ammo_id() == "laser" and run.FRAMES[run.build.frame].id == "pistol", "every run starts with a Laser Ray Pistol")
	var locked := _locked_cards(scene.design_s)
	_check(locked == start_rules, "design screen shows every locked starting part (%d)" % locked)
	run.build.items = []; run.recompute()
	_check(not run.item_available(run.ITEM.lens), "Focusing Lens isn't sold before it's unlocked")
	_check(not run.set_start("ammo", 1) and run.build.ammo == 0, "a locked starting ammo can't be picked")
	# card presses on a locked part do nothing
	(scene.design_s.ammo_box.get_child(1) as Button).pressed.emit()
	_check(run.build.ammo == 0, "pressing a locked card changes nothing")
	# earn unlocks through the real hooks: starting wave 4 and killing the wave-5 boss
	run.new_run(); run.wave = 4; scene._start_wave()
	run.wave = 5; scene._start_wave()
	var a = scene.arena; var b = a.make_enemy("boss", a.P.x + 200, a.P.y); a.boss = b
	a.hit(b, 1.0e9, {})
	for i in 3: a._process(1.0 / 60.0)
	_check(run.unlocks.is_unlocked("frame", "blunder"), "killing the wave-5 boss unlocks the Blunderbuss")
	_check(run.unlocks.is_unlocked("ammo", "bullet"), "starting wave 4 unlocks Bullets")
	scene._game_over(false)
	_check(scene.over_text.text.contains("Bullets") and scene.over_text.text.contains("Blunderbuss"), "game over lists new unlocks")
	scene._enter_lab(); await process_frame
	_check(run.ammo_id() == "laser" and run.build.frame == 0, "unlocks don't change the default start")
	_check(_locked_cards(scene.design_s) == start_rules - 2, "two fewer locked parts after unlocking two")
	_check(run.unlocks.is_unlocked("item", "lens") and run.item_available(run.ITEM.lens), "reaching wave 5 puts the Focusing Lens in the shop pool")
	var bullet_card: Button = scene.design_s.ammo_box.get_child(1)
	_check(not bullet_card.disabled, "unlocked card is selectable")
	bullet_card.pressed.emit()
	(scene.design_s.frame_box.get_child(1) as Button).pressed.emit()
	_check(run.ammo_id() == "bullet" and run.FRAMES[run.build.frame].id == "blunder", "unlocked parts can be picked as the starting loadout")
	_check(run.build.start.ammo == 1 and run.build.start.frame == 1 and not run.build.swapped.ammo, "starting parts are recorded as the run's start")
	_check(scene.design_s.name_edit.text == "The Diabolical Slug Blunderbuss", "auto name follows the picked parts")
	scene.design_s._on_begin()
	_check(scene.state == "difficulty" and run.build.name == "The Diabolical Slug Blunderbuss", "begin keeps the name and moves on")
	run.new_run()
	_check(run.ammo_id() == "laser" and run.build.frame == 0, "the next run starts with a Laser Ray Pistol again")
	run.unlocks.reset()
	print("UNLOCK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _locked_cards(ds) -> int:
	var n := 0
	for box in [ds.ammo_box, ds.frame_box]:
		for c in box.get_children():
			if c.is_queued_for_deletion(): continue
			if c.has_meta("locked") and c.disabled: n += 1
	return n

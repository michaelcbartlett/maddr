extends SceneTree
## Villain Intel (game/intel.gd): dossier drops and pickup, persistent points, free reassignment, offer-roll
## weighting, and the RIG THE DEPOT screen driven by real controller button events.
## Uses its own save file under user://; the player's user://intel.json is never touched.
const MAIN = "res://game/main.tscn"
const IntelT = preload("res://game/intel.gd")
const TEST_SAVE := "user://intel_selftest.json"
var failures := 0
var checks := 0
var run: Node

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", what)

func _tap(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new(); event.device = 0; event.button_index = button; event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	seed(9090)
	run = root.get_node("Run")
	var rules: Dictionary = run.RULES.intel
	var cap := int(rules.max_points_per_item)
	_check(run.is_test_process() and not run.intel.persist, "test runs keep Intel in memory only")
	_check(run.intel.path == IntelT.SAVE_PATH, "real save path is user://intel.json")
	_check(float(rules.drop_chance) > 0.0 and float(rules.weight_per_point) > 0.0 and cap > 0, "rules.json has tunable Intel rules")

	# ---- points: collect, assign, move, caps, refusals ----
	if FileAccess.file_exists(TEST_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	var u = IntelT.new(rules, true); u.path = TEST_SAVE; u.persist = true
	_check(u.unspent == 0 and u.total() == 0 and u.weight("lens") == 1.0, "fresh profile: no Intel, neutral weights")
	_check(not u.assign("lens", 1), "can't assign without free points")
	u.collect(cap + 3)
	_check(u.unspent == cap + 3 and u.earned_run == cap + 3, "collected dossiers bank as free points")
	_check(u.assign("lens", 2) and u.points("lens") == 2 and u.unspent == cap + 1, "assigning moves points out of the free pool")
	_check(is_equal_approx(u.weight("lens"), 1.0 + 2.0 * float(rules.weight_per_point)), "weight = 1 + points * weight_per_point")
	_check(u.assign("lens", 99) and u.points("lens") == cap and not u.assign("lens", 1), "points per module are capped")
	_check(u.unspent == 3 and u.total() == cap + 3, "the cap never eats points")
	_check(u.assign("lens", -1) and u.assign("magnet", 1) and u.points("lens") == cap - 1 and u.points("magnet") == 1, "points move freely between modules")
	_check(not u.assign("frost", -1), "can't remove points a module doesn't have")
	_check(FileAccess.file_exists(TEST_SAVE), "Intel is written to the save file")
	var v = IntelT.new(rules, true); v.path = TEST_SAVE; v.persist = true; v.load_save()
	_check(v.unspent == u.unspent and v.points("lens") == cap - 1 and v.points("magnet") == 1 and v.total() == cap + 3, "balance and allocations load back")
	_check(v.clear("lens") and v.points("lens") == 0 and not v.alloc.has("lens") and v.unspent == cap + 2, "clearing a module refunds its points")
	_check(v.clear_all() and v.alloc.is_empty() and v.unspent == cap + 3, "refund all returns every point")
	# over-cap saves (rules tightened) refund the excess; corrupt/missing saves start fresh
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE); f.store_string(JSON.stringify({"version":1, "unspent":1, "alloc":{"lens":cap + 4}})); f.close()
	v.load_save(); _check(v.points("lens") == cap and v.unspent == 5, "over-cap allocation is clamped and the excess refunded")
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE); f.store_string("{not json"); f.close()
	v.load_save(); _check(v.unspent == 0 and v.alloc.is_empty(), "an unreadable save starts fresh")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	v.load_save(); _check(v.unspent == 0 and v.alloc.is_empty(), "a missing save starts fresh")

	# ---- drop rule ----
	_check(run.intel_drops(true, 0.99, 5) == int(rules.boss_drop), "bosses drop boss_drop dossiers")
	_check(run.intel_drops(false, float(rules.drop_chance) * 0.5, 5) == 1 and run.intel_drops(false, float(rules.drop_chance) + 0.001, 5) == 0, "cops drop a dossier with drop_chance")

	# ---- offer weighting ----
	run.new_run(); run.intel.reset()
	var pool: Array = run.ITEMS.filter(func(it): return int(it.t) == 1 and run.item_available(it))
	_check(pool.size() >= 4, "enough common modules to test weighting")
	var target: Dictionary = pool[0]
	_check(is_equal_approx(run.pick_share(pool, target.id), 1.0 / pool.size()), "unrigged modules have a uniform share")
	var base_hits := _hits(pool, target.id, 6000)
	run.intel.unspent = cap; run.intel.assign(target.id, cap)
	var share: float = run.pick_share(pool, target.id)
	var expect := (1.0 + cap * float(rules.weight_per_point)) / (pool.size() + cap * float(rules.weight_per_point))
	_check(is_equal_approx(share, expect), "rigged share = weight / total weight")
	var rigged_hits := _hits(pool, target.id, 6000)
	_check(absf(rigged_hits / 6000.0 - expect) < 0.03, "weighted_pick matches the rigged share (%.3f vs %.3f)" % [rigged_hits / 6000.0, expect])
	_check(rigged_hits > base_hits * 2, "rigging raises the pick rate (%d -> %d of 6000)" % [base_hits, rigged_hits])
	# whole shop rolls: the rigged common shows up in noticeably more shops
	run.intel.clear_all()
	var plain_shops := _shops_with(target.id, 1500)
	run.intel.assign(target.id, cap)
	var rigged_shops := _shops_with(target.id, 1500)
	_check(rigged_shops > plain_shops * 1.5, "rigged module appears in more shop offer sets (%d -> %d of 1500)" % [plain_shops, rigged_shops])
	print("Intel odds for %s (%d points): pool picks %d -> %d of 6000, shops containing it %d -> %d of 1500" % [target.id, cap, base_hits, rigged_hits, plain_shops, rigged_shops])
	run.intel.reset()

	# ---- arena: kill drops, pickup banks points, wave-end vacuum ----
	var scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	scene._enter_lab(); await process_frame
	run.new_run(); run.wave = 3; scene._start_wave()
	var a = scene.arena
	var boss = a.make_enemy("boss", a.P.x + 300, a.P.y); a.boss = boss
	a.hit(boss, 1.0e9, {})
	var dossiers: Array = a.pickups.filter(func(p): return p.has("intel"))
	_check(dossiers.size() == int(rules.boss_drop), "a boss kill drops %d Intel dossiers" % int(rules.boss_drop))
	for p in dossiers: p.x = a.P.x; p.y = a.P.y
	a._process(1.0 / 60.0)
	_check(run.intel.unspent == int(rules.boss_drop) and a.pickups.filter(func(p): return p.has("intel")).is_empty(), "walking over dossiers banks them")
	a.drop_intel(Vector2(a.P.x + 400, a.P.y + 300))
	a.state = "clear"; a.clear_t = 0.01
	a._process(1.0 / 60.0)
	_check(run.intel.unspent == int(rules.boss_drop) + 1, "dossiers left at wave end are vacuumed up, never seized")

	# ---- RIG THE DEPOT from the Lab ----
	scene._enter_lab(); await process_frame
	scene.design_s.intel_btn.grab_focus(); await process_frame
	await _tap(JOY_BUTTON_A)
	var ov = scene.design_s.intel_s
	_check(ov != null and ov.visible and not scene.design_s._panel.visible, "A on the Lab's Intel button opens RIG THE DEPOT")
	await process_frame
	await _tap(JOY_BUTTON_B)
	_check(not ov.visible and scene.state == "design" and scene.design_s._panel.visible, "B closes the overlay without leaving the Lab")

	# ---- RIG THE DEPOT from the shop, controller only ----
	run.new_run(); run.intel.reset(); run.intel.collect(3)
	run.wave = 1; scene._start_wave(); scene._on_cleared(); await process_frame
	_check(scene.state == "shop", "shop open")
	await _tap(JOY_BUTTON_BACK); await process_frame
	ov = scene.shop_s.intel_s
	_check(ov != null and ov.visible and not scene.shop_s._panel.visible, "Select/Back opens RIG THE DEPOT from the shop")
	var focus := root.gui_get_focus_owner()
	_check(focus is Button and ov.list.is_ancestor_of(focus), "the first module row is highlighted")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	var row: Button = root.gui_get_focus_owner()
	var id: String = ""
	for k in ov._rows:
		if ov._rows[k] == row: id = k
	_check(id != "" and row != focus, "D-pad down highlights the next module")
	await _tap(JOY_BUTTON_DPAD_RIGHT); await _tap(JOY_BUTTON_A)
	_check(run.intel.points(id) == 2 and run.intel.unspent == 1 and root.gui_get_focus_owner() == row, "right and A each add a point and keep the highlight")
	_check(row.text.contains("◆◆") and ov.free_l.text.contains("1 free"), "the row and balance show the new allocation")
	await _tap(JOY_BUTTON_DPAD_LEFT)
	_check(run.intel.points(id) == 1 and run.intel.unspent == 2, "left removes a point")
	await _tap(JOY_BUTTON_DPAD_UP); await _tap(JOY_BUTTON_A); await _tap(JOY_BUTTON_A)
	var first_id: String = ov.rig_ids()[0]
	_check(run.intel.points(first_id) == 2 and run.intel.unspent == 0, "points move to another module")
	await _tap(JOY_BUTTON_A)
	_check(run.intel.points(first_id) == 2 and ov.odds_l.text.contains("No free Intel"), "with no free points, adding explains why")
	await _tap(JOY_BUTTON_X)
	_check(run.intel.points(first_id) == 1 and run.intel.unspent == 1, "X removes a point")
	await _tap(JOY_BUTTON_Y)
	var rerolls: int = run.reroll_cost
	_check(run.intel.points(first_id) == 0 and run.intel.unspent == 2 and run.reroll_cost == rerolls and scene.state == "shop", "Y clears the module (and never rerolls the shop underneath)")
	await _tap(JOY_BUTTON_START)
	_check(not ov.visible and scene.state == "shop" and scene.shop_s._panel.visible, "Start closes the overlay instead of starting the wave")
	await process_frame
	_check(root.gui_get_focus_owner() == scene.shop_s.intel_btn and scene.shop_s.intel_btn.text.contains("2"), "focus returns to the Intel button showing the free balance")
	await _tap(JOY_BUTTON_START)
	_check(scene.state == "play", "Start begins the next wave again once the overlay is closed")
	run.intel.reset()
	print("INTEL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _hits(pool: Array, id: String, n: int) -> int:
	var hits := 0
	for i in n:
		if run.weighted_pick(pool).id == id: hits += 1
	return hits

func _shops_with(id: String, n: int) -> int:
	var hits := 0
	run.wave = 2
	for i in n:
		run.gen_offers()
		if run.offers.any(func(o): return o.it.get("id", "") == id): hits += 1
	return hits

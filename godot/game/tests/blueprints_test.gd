extends SceneTree
## Real combat/collection, persistent unlocks, difficulty gates, new helmet and road lamps.
const UnlocksT = preload("res://game/unlocks.gd")
const Art = preload("res://character/art_renderer.gd")
const SAVE := "user://blueprints_selftest.json"
var checks := 0
var failures := 0
var run
var scene
var a

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", label)

func _start(wave := 5, theme := "museum") -> void:
	run.new_run(); run.wave = wave; run.theme_order = [theme]; a.start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.wave_t = 1000; a.P.inv = 1000

func _run() -> void:
	seed(871)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	run.unlocks.reset()
	# Numeric pierce includes zero, without changing projectile collision rules.
	_check(run.stats_rows().any(func(row): return row[0] == "Pierce" and row[1] == "0"), "base Pierce is shown as 0")
	_check(not str(run.stats_rows()).contains("stops at"), "stats omit the first-cop wording")
	for n in [1, 2, 3]:
		run.S.pierce = n
		_check(run.stats_rows().any(func(row): return row[0] == "Pierce" and row[1] == str(n)), "numeric Pierce %d" % n)
	run.S.beam = 1
	_check(run.stats_rows().any(func(row): return row[0] == "Pierce" and row[1] == "∞"), "unlimited beam pierce is explicit")
	# Difficulty selection is gated in both UI and the actual setter.
	scene.difficulty_s.refresh()
	_check(not scene.difficulty_s.buttons[0].disabled and scene.difficulty_s.buttons[1].disabled, "only Petty Crook starts available")
	scene.difficulty_s.buttons[4].pressed.emit()
	_check(run.difficulty == 1 and not run.set_difficulty(2), "locked tiers cannot be selected even via emitted signals")
	_check(not run.unlocks.note_difficulty_wave(1, 19) and not run.unlocks.note_difficulty_wave(2, 20), "wave 19 and an unearned tier do not unlock anything")
	run.wave = 20; run.note_wave_reached(20)
	_check(run.unlocks.highest_difficulty == 2, "actually reaching wave 20 opens the next tier before the boss dies")
	scene._game_over(false)
	_check(scene.over_text.text.contains("🔓 NUISANCE"), "game over announces the earned difficulty even when the final boss wins")
	_check(not run.unlocks.note_difficulty_wave(1, 20), "repeating a lower tier cannot skip tiers")
	for tier in range(2, 5):
		_check(run.set_difficulty(tier), "earned difficulty %d is selectable" % tier)
		run.note_wave_reached(20)
		_check(run.unlocks.highest_difficulty == tier + 1, "wave 20 unlocks difficulty %d" % (tier + 1))
	run.unlocks.reset()
	# Ironclad drops a blueprint, not an automatic unlock or a free equipped item.
	_start(5, "street")
	_check(not run.item_available(run.ITEM.boots), "Rocket Boots aren't in the fresh shop pool")
	var boss = a.make_enemy("boss", a.P.x + 220, a.P.y); a.kill(boss)
	var blueprints: Array = a.pickups.filter(func(p): return p.get("blueprint", "") == "boots")
	_check(blueprints.size() == 1 and blueprints[0].blueprint == "boots", "Captain Ironclad drops the boots blueprint")
	_check(not run.unlocks.is_unlocked("item", "boots"), "the kill itself does not unlock the boots")
	a.end_wave()
	for frame in 36: a._process(0.05)
	_check(not run.unlocks.is_unlocked("item", "boots") and a.pickups.any(func(p): return p.has("blueprint")), "wave-clear vacuum never collects a blueprint")
	a.start_wave(); a.P.inv = 1000; a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000
	var p: Dictionary = a.pickups.filter(func(pickup): return pickup.has("blueprint"))[0]
	a.P.x = p.x; a.P.y = p.y; a._update_play(0.01)
	_check(run.unlocks.is_unlocked("item", "boots") and run.item_available(run.ITEM.boots), "walking onto the pickup unlocks future shops")
	_check(not run.CNT.has("boots"), "unlocking does not equip a free pair")
	a.pickups.clear(); a.kill(a.make_enemy("boss", a.P.x + 200, a.P.y))
	_check(not a.pickups.any(func(pickup): return pickup.get("blueprint", "") == "boots"), "unlocked boots do not drop duplicate blueprints")
	run.new_run()
	_check(not run.item_available(run.ITEM.boots), "future runs still wait until wave 5 for the boots shop pool")
	run.wave = 5
	_check(run.item_available(run.ITEM.boots), "permanent unlock becomes eligible again at wave 5")
	# Reinforced cases absorb real projectiles and beams, then lose collision and release actual pickups.
	_start()
	var c: Dictionary = a.arena_level.props[0]
	var origin: Vector2 = c.rect.get_center() - Vector2(100, 0)
	a.fire_gun("laser", 0, 1, origin.x, origin.y, null, origin.x, origin.y)
	for frame in 3: a._update_projs(0.05)
	_check(c.hp == 232 and not c.broken, "a real laser bolt chips only 8 out of 240 case HP")
	run.S.beam = 1
	a.fire_gun("laser", 0, 1, origin.x, origin.y, null, origin.x, origin.y)
	_check(c.hp == 224, "beam fire also damages the case")
	var obstructed: bool = a.in_wall(c.rect.get_center().x, c.rect.get_center().y)
	_check(obstructed, "an intact case blocks movement")
	a.damage_case(c, 224)
	_check(c.broken and not a.in_wall(c.rect.get_center().x, c.rect.get_center().y), "shattering removes wall and navigation obstruction")
	_check(a.nav.clear_segment(origin, c.rect.get_center() + Vector2(70, 0), 0), "navigation sees the opened route immediately")
	_check(a.pickups.filter(func(pickup): return pickup.has("gem")).size() == 3, "contents spill as three collectible gems")
	a.damage_case(c, 10000)
	_check(a.pickups.size() == 3, "a case pays only once")
	var special: Dictionary = a.arena_level.props[1]
	a.explode(special.rect.get_center().x, special.rect.get_center().y, 240, 65, Color.CYAN)
	var research: Array = a.pickups.filter(func(pickup): return pickup.has("blueprint"))
	_check(special.broken and research.size() == 1, "explosions can shatter a research case and reveal one blueprint")
	var item: String = research[0].blueprint
	_check(not run.item_available(run.ITEM[item]), "revealing the blueprint alone does not unlock it")
	a.P.x = research[0].x; a.P.y = research[0].y; a._update_play(0.01)
	_check(run.unlocks.is_unlocked("item", item) and run.item_available(run.ITEM[item]), "physically collecting the research blueprint opens that item")
	# Durable save round-trip includes blueprints and difficulty progression.
	var u = UnlocksT.new(run.RULES.unlocks, true); u.path = SAVE; u.persist = true
	u.collect_blueprint("boots"); u.collect_blueprint(item); u.note_difficulty_wave(1, 20)
	var restored = UnlocksT.new(run.RULES.unlocks, true); restored.path = SAVE; restored.load_save()
	_check(restored.is_unlocked("item", "boots") and restored.is_unlocked("item", item) and restored.highest_difficulty == 2, "blueprints and earned difficulties survive save/reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	# All offers, including the fallback pool, respect the new item gates.
	run.unlocks.reset(); run.new_run(); run.wave = 20
	for roll in 50:
		run.gen_offers()
		_check(run.offers.all(func(o): return run.item_available(o.it)), "shop offers respect unlock restrictions, roll %d" % roll)
	# Helmet: light, capped chains inside proximity, no procs through walls or allies/civilians.
	_start(1, "street")
	run.build.items = ["tesla_helmet"]; run.recompute(); a.villain.set_items(); a._sync_villain()
	var targets: Array = []
	for x in [40, 65, 95, 180]:
		var e = a.make_enemy("cop", a.P.x + x, a.P.y); e.hp = 100; targets.append(e)
	var civ = a.make_enemy("civ", a.P.x + 15, a.P.y); civ.hp = 100
	a.P.helmet_cd = 0; a._update_helmet(0.01)
	_check(targets[0].hp == 97 and targets[1].hp == 97 and targets[2].hp == 97 and targets[3].hp == 100, "helmet chains 3 light hits inside 110 proximity only")
	_check(civ.hp == 100 and a.arcs.size() == 3, "helmet ignores civilians and draws a chain from the helmet")
	a._update_helmet(0.1)
	_check(targets[0].hp == 97, "helmet obeys its 1.5 second cooldown")
	a.walls = [{"rect":Rect2(a.P.x + 20, a.P.y - 30, 10, 60), "open":false}]; a.nav.configure(a.walls, Vector2(Levels.AW, Levels.AH))
	a.P.helmet_cd = 0; a._update_helmet(0.01)
	_check(targets[0].hp == 97, "helmet cannot zap through a solid obstacle")
	_check(not run.item_available(run.ITEM.tesla_helmet), "helmet is a single installed upgrade")
	var art = Art.new(); art.configure(["tesla_helmet"], "laser", "pistol")
	_check(art.body_frame(0, false).anims.size() >= 3, "helmet art includes animated electrode glows")
	# Every visible street lamp base sits wholly on the rendered concrete sidewalks.
	_start(1, "street")
	_check(a.arena_level.lamps.size() == 8, "street keeps eight sidewalk lamps")
	for pos in a.arena_level.lamps:
		var base := Rect2(pos - Vector2(5,5), Vector2(10,6))
		_check(a.arena_level.STREET_SIDEWALKS.any(func(side): return Rect2(side).encloses(base)), "lamp %s has its whole base on concrete" % pos)
		_check(a.arena_level.prop_nodes.any(func(n): return n.kind == "lamp_post" and n.position == pos + Vector2(0, 1)), "sidewalk lamp %s has a visible post" % pos)
	if OS.get_cmdline_user_args().has("--screenshots"):
		await _screenshots()
	scene.queue_free(); await process_frame; await process_frame
	print("BLUEPRINT / DIFFICULTY / HELMET TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _screenshots() -> void:
	_start(5, "museum")
	run.build.items = ["tesla_helmet"]; run.recompute(); a.villain.set_items()
	a.P.x = 1170; a.P.y = 355; a.cam.position = Vector2(1100, 325)
	a.banner_t = 0; a.siren_t = 0; a.P.inv = 0; a.wave_t = 43
	a.damage_case(a.arena_level.props[1], 150); a.damage_case(a.arena_level.props[4], 240)
	a.drop_blueprint("boots", Vector2(1060, 345))
	for i in 3:
		var e = a.make_enemy("cop", 1160 - i * 28, 405); e.hp = 100
	a._sync_villain(); a.P.helmet_cd = 0; a._update_helmet(0.01); a._sync(0)
	for e in a.enemies: e.flash = 0; e.sync()
	scene._show("play")
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/blueprints-helmet.png")
	run.unlocks.reset(); scene._open_difficulty()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/difficulty-locks.png")
	scene._enter_lab()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/blueprints-lab.png")
	_start(1, "street"); a.banner_t = 0; a.siren_t = 0; a.P.inv = 0; a.wave_t = 30; a._sync(0); scene._show("play")
	var combat_zoom: Vector2 = a.cam.zoom
	var capture_size: Vector2 = a.get_viewport_rect().size
	a.cam.zoom = Vector2.ONE * minf(capture_size.x / float(Levels.AW), capture_size.y / float(Levels.AH)) * 0.96
	a.cam.position = Vector2(Levels.AW, Levels.AH) * 0.5; a.cam.reset_smoothing()
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/road-lamps.png")
	a.cam.zoom = combat_zoom
	run.wave = 6; run.gen_offers(); scene.shop_s.refresh(); scene._show("shop")
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/concise-shop.png")

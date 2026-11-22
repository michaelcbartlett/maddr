extends SceneTree
## Exercise actual shot paths, material reactions, fuse timing and opened navigation.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", label)

func _start(theme := "street") -> Dictionary:
	run.new_run(); run.theme_order = [theme]
	a.start_wave(); a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.wave_t = 1000
	return a.arena_level.props[0]

func _shoot(p: Dictionary, kind: String) -> void:
	var pos: Vector2 = p.rect.get_center() - Vector2(p.rect.size.x * 0.5 + 30, 0)
	a.fire_gun(kind, 0, 1, pos.x, pos.y, null, pos.x, pos.y)
	for projectile in a.projs: projectile.vy = 0
	for i in 4: a._update_projs(0.05)

func _tick(seconds: float, fps := 20) -> void:
	for i in ceili(seconds * fps): a.SceneryDamage.tick(a, 1.0 / fps)

func _run() -> void:
	seed(891)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	var p := _start()
	_shoot(p, "bullet")
	_check(p.hp < p.max_hp and p.marks.size() == 1 and p.marks[0].kind == "bullet", "real bullets damage a car and leave one bullet hole")
	_check(p.fuse < 0 and p.burn_t == 0, "ordinary bullets do not spontaneously ignite a healthy car")
	_check(a.projs.is_empty(), "car body stops a bullet")
	_shoot(p, "laser")
	_check(p.marks.back().kind == "bolt", "laser bolts leave heat scars rather than bullet holes")
	_shoot(p, "razor")
	_check(p.marks.any(func(mark): return mark.kind == "razor"), "razors leave cuts on a prop and ricochet")
	a.projs.clear()
	# A long barrel is still blocked by the first prop, and sustained visuals cannot deal damage.
	p = _start(); run.S.beam = 1
	var origin: Vector2 = p.rect.get_center() - Vector2(90, 0)
	a.fire_gun("laser", 0, 1, origin.x, origin.y, null, origin.x, origin.y)
	_check(p.hp == 152 and p.marks[0].kind == "laser", "beam ticks reach the scenery surface")
	var hp: float = p.hp
	a.fire_gun("laser", 0, 1, origin.x, origin.y, {"tick":false}, origin.x, origin.y)
	_check(p.hp == hp, "visual-only sustained beam refreshes never damage scenery")
	a.fire_gun("bullet", 0, 1, origin.x + 180, origin.y, null, origin.x, origin.y)
	_check(p.hp < hp and a.projs.is_empty(), "barrels extending across a car damage its near side without firing through it")
	# Even tiny burn damage guarantees a fuse; additional hits cannot postpone it.
	for fps in [20, 60]:
		p = _start(); run.S.burn = 0.1; _shoot(p, "bullet")
		_check(p.fuse > 2.0 and p.burn_t > 0, "a fire-equipped shot ignites the car at %d FPS" % fps)
		_tick(1.0, fps); var fuse: float = p.fuse
		a.SceneryDamage.damage(a, p, 1, "bullet", p.rect.get_center(), 0.1)
		_check(p.fuse <= fuse, "repeated fire hits cannot reset the countdown")
		_check(not p.broken, "burning gives a warning before the explosion")
		_tick(1.25, fps)
		_check(p.broken and a.booms.size() == 1, "the fuse detonates exactly once at %d FPS" % fps)
		_check(not a.in_wall(p.rect.get_center().x, p.rect.get_center().y), "the wreck no longer blocks movement")
		_check(a.nav.clear_segment(origin, p.rect.get_center() + Vector2(90, 0), 0), "navigation immediately sees the destroyed car as open")
		_tick(4, fps)
		_check(p.wreck_t == 0 and a.booms.size() == 1, "wreck fire expires and a destroyed car cannot detonate again")
	# Blasts reach the actual footprint, with a shorter fuse and no effect from cosmetic blasts.
	p = _start(); var center: Vector2 = p.rect.get_center()
	a.explode(center.x, center.y, 0, 180, Color.WHITE)
	_check(p.hp == p.max_hp and p.fuse < 0, "zero-damage celebrations never ignite scenery")
	a.booms.clear()
	a.explode(center.x - 80, center.y, 1, 21, Color.ORANGE)
	_check(p.fuse > 0 and p.fuse <= 0.8, "explosion overlap uses the footprint edge and arms a short fuse")
	# Relocate a second real car to verify delayed chain reactions and environmental damage.
	var other: Dictionary = a.arena_level.props[1]
	other.rect = Rect2(center + Vector2(130, 0) - other.rect.size * 0.5, other.rect.size)
	a.arena_level.walls[1].rect = other.rect; a.walls = a.arena_level.walls
	a.nav.configure(a.walls, Vector2(Levels.AW, Levels.AH))
	a.P.x = center.x; a.P.y = center.y + 80; a.P.inv = 0
	var enemy = a.make_enemy("cop", center.x - 90, center.y + 70); enemy.hp = 100
	_tick(0.81)
	_check(p.broken and not other.broken and other.fuse > 0, "a car blast ignites a neighbouring car without instant chain recursion")
	_check(enemy.hp == 64 and a.P.hp == run.D.maxHp - 12, "car explosions hurt nearby cops and the player")
	_tick(0.85)
	_check(other.broken and a.booms.size() == 3, "the neighbouring car explodes after its own warning")
	# All solid theme props react to hits, preserve cases' loot, and release their routes.
	for theme in ["bank", "rooftop", "police", "museum", "harbour", "spyhq"]:
		p = _start(theme); run.S.burn = 4; _shoot(p, "bullet")
		_check(p.hp < p.max_hp and p.marks.size() == 1, "%s props take damage and retain impact marks" % theme)
		_check((p.burn_t > 0) == p.flammable, "%s respects its material's flammability" % theme)
		a.SceneryDamage.damage(a, p, 10000, "explosion", p.rect.get_center())
		_check(p.broken and a.arena_level.walls[0].open, "%s destruction clears collision" % theme)
		_check(a.arena_level.prop_nodes[0].glows().all(func(g): return g.col == Color("#ff882d")), "%s destruction disables original lights" % theme)
		if theme == "museum": _check(a.pickups.filter(func(pickup): return pickup.has("gem")).size() == 3, "museum shattering still pays exactly three gems")
	# Enemy gunfire and rocket blasts also hit scenery; player upgrades never attach to them.
	p = _start(); run.S.burn = 99; center = p.rect.get_center()
	var start := center - Vector2(80, 0)
	a.ebul.append({"x":start.x,"y":start.y,"vx":620.0,"vy":0.0,"t":1.0,"r":3.0,"dmg":5.0})
	a._update_play(0.05)
	_check(p.hp == 155 and p.marks.back().kind == "bullet" and p.fuse < 0, "enemy bullets leave holes without inheriting the player's burn")
	a.ebul.append({"x":start.x,"y":start.y,"vx":620.0,"vy":0.0,"t":1.0,"r":3.0,"dmg":5.0,"blast":60.0})
	a._update_play(0.05)
	_check(p.fuse > 0 and p.hp == 150, "enemy rockets ignite cars on collision")
	p = _start(); p.hp = 100000
	for i in 80: a.SceneryDamage.damage(a, p, 1, "bullet", p.rect.get_center() + Vector2(i % 15, i % 17))
	_check(p.marks.size() == a.SceneryDamage.MAX_MARKS, "persistent damage marks stay bounded under sustained fire")
	_start()
	_check(a.arena_level.props.all(func(prop): return not prop.broken and prop.marks.is_empty() and prop.fuse < 0), "a new wave rebuilds intact scenery without stale damage")
	if OS.get_cmdline_user_args().has("--screenshots"): await _screenshots()
	scene.queue_free(); await process_frame; await process_frame
	print("SCENERY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _screenshots() -> void:
	# Capture real arena props with several impacts and an actively burning car.
	var p := _start(); a.P.x = 450; a.P.y = 330; a.P.inv = 0; a.banner_t = 0; a.siren_t = 0
	for i in 12:
		a.SceneryDamage.damage(a, p, 1, "bullet", p.rect.position + Vector2(8 + (i * 23) % 105, 6 + (i * 17) % 45))
	a.SceneryDamage.damage(a, p, 1, "burn", p.rect.get_center(), 3)
	a.SceneryDamage.tick(a, 0.1)
	a._sync(0); scene._show("play")
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/scenery-burning.png")
	a.SceneryDamage.destroy(a, p); a._sync(0)
	for i in 8: a._update_fx(0.05); a.SceneryDamage.tick(a, 0.05)
	a.P.inv = 0; a._sync(0)
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/scenery-wreck.png")
	await _gallery(["car", "car_v", "case", "pillar"], "scenery-gallery-cars")
	await _gallery(["desk", "ac_unit", "server", "container"], "scenery-gallery-props")

func _gallery(kinds: Array, filename: String) -> void:
	var layer := CanvasLayer.new(); layer.layer = 10; root.add_child(layer)
	var background := ColorRect.new(); background.color = Color("#252d33"); background.size = Vector2(960, 540); background.z_index = -2; layer.add_child(background)
	var gallery := Node2D.new(); layer.add_child(gallery)
	for column in kinds.size():
		for row in 3:
			var kind: String = "car" if kinds[column] == "car_v" else kinds[column]
			var size: Vector2 = a.ArenaLevel.PROP_SIZE[kind]
			if kinds[column] == "car_v": size = Vector2(size.y, size.x)
			var center := Vector2(120 + column * 240, 140 + row * 170)
			var rule: Dictionary = a.ArenaLevel.PROP_DAMAGE[kind]
			var p := {"rect":Rect2(center - size * 0.5, size), "kind":kind, "color":Color("#376cb4"), "h":a.ArenaLevel.PROP_H[kind], "variant":column,
				"hp":rule.hp, "max_hp":rule.hp, "material":rule.material, "flammable":rule.flammable, "broken":false, "marks":[], "burn_t":0.0, "fuse":-1.0, "char":0.0}
			var view = a.ArenaLevel.PropView.new(); view.setup(p, a.arena_level.theme); gallery.add_child(view)
			view.scale = Vector2.ONE * 0.9; view.position = Vector2(center.x, 165 + row * 170)
			if row == 1:
				p.hp *= 0.5; p.char = 0.2
				for i in 9:
					p.marks.append({"pos":Vector2(-size.x * 0.35 + (i * 17) % int(size.x * 0.7), -p.h - size.y * 0.2 - (i * 13) % int(size.y * 0.6)), "kind":["bullet", "bullet", "laser", "razor"][i % 4], "angle":i * 1.3})
				if rule.flammable: p.burn_t = 2.0
			if row == 2: p.broken = true; p.hp = 0; p.char = 0.6
			var label := Label.new(); label.position = Vector2(column * 240 + 15, row * 170 + 4)
			label.text = "%s / %s" % [kinds[column], ["intact", "damaged", "destroyed"][row]]; layer.add_child(label)
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/%s.png" % filename)
	layer.queue_free(); await process_frame

extends SceneTree
## Enemy art checks: every sprite key bakes every state, frames are non-empty and sized like the scientist,
## normal maps match the albedo, the disk cache round-trips, and a live combat exercises state picking,
## the detective muzzle flash, boss powers, tints and death corpses.
## `-- --screenshots` also saves combat captures to test-results/enemies-*.png (needs a display/GPU).
const Painter = preload("res://enemies/enemy_painter.gd")
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Corpse = preload("res://enemies/enemy_corpse.gd")
var failures := 0
var checks := 0
var capture := false

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _run() -> void:
	seed(4242)
	capture = OS.get_cmdline_user_args().has("--screenshots")
	var t0 := Time.get_ticks_msec()
	EnemyArt.build()
	print("enemy sheets ready in %d ms" % (Time.get_ticks_msec() - t0))
	_test_sheets()
	_test_cache()
	await _test_combat()
	print("ENEMY ART TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _bounds(img: Image, r: Rect2) -> Rect2i:
	var used := img.get_region(Rect2i(r)).get_used_rect()
	return used

func _test_sheets() -> void:
	for kind in Painter.KINDS:
		var s := EnemyArt.sheet(kind)
		var states: Dictionary = Painter.states(kind)
		for st in ["idle", "walk", "hurt", "death", "frozen", "stunned"]:
			_check(s.frames.has(st), "%s has state %s" % [kind, st])
		for st in states:
			_check(s.frames[st].size() == int(states[st]), "%s/%s frame count" % [kind, st])
			var distinct := {}
			for i in s.frames[st].size():
				var r: Rect2 = s.frames[st][i]
				var region: Image = s.albedo.get_region(Rect2i(r))
				var used := region.get_used_rect()
				_check(used.size.x > 4 and used.size.y > 4, "%s/%s/%d is painted" % [kind, st, i])
				distinct[region.get_data().hex_encode().sha256_text()] = true
				# every opaque albedo pixel has a unit-ish, outward-facing normal
				var nrm: Image = s.normal.get_region(Rect2i(r))
				var bad := 0
				for y in range(0, region.get_height(), 2):
					for x in range(0, region.get_width(), 2):
						if region.get_pixel(x, y).a <= 0.0: continue
						var n := nrm.get_pixel(x, y)
						if n.a <= 0.0 or n.b < 0.5: bad += 1
				_check(bad == 0, "%s/%s/%d normals cover the sprite (%d bad)" % [kind, st, i, bad])
			if int(states[st]) > 1 and st != "idle":
				_check(distinct.size() > 1, "%s/%s animates" % [kind, st])
		# outline: the outermost pixels are dark selective outline, not raw fill
		var idle: Rect2 = s.frames.idle[0]
		var used2: Rect2i = _bounds(s.albedo, idle)
		_check(used2.size.y >= {"human": 48, "hero": 66, "dog": 22, "drone": 14, "vehicle":40}[s.family], "%s is drawn at the scientist's scale (%d px tall)" % [kind, used2.size.y])
		var region2: Image = s.albedo.get_region(Rect2i(idle))
		var outlined := 0; var tops := 0
		for x in region2.get_width():
			for y in region2.get_height() - 1:
				var top_pixel := region2.get_pixel(x, y)
				if top_pixel.a < 0.95: continue   # skip translucent capes / shields / rotor blur
				var below := region2.get_pixel(x, y + 1)
				tops += 1
				if below.a <= 0.0 or top_pixel.get_luminance() <= below.get_luminance(): outlined += 1
				break
		_check(outlined >= tops * 0.8, "%s has a darker selective outline on top (%d/%d)" % [kind, outlined, tops])
		# silhouette is white where the albedo is opaque
		var sil: Image = s.sil.get_image()
		var p := Vector2i(idle.position) + used2.position + used2.size / 2
		_check(s.albedo.get_pixelv(p).a == sil.get_pixelv(p).a and (sil.get_pixelv(p).a == 0.0 or sil.get_pixelv(p).r == 1.0), "%s silhouette matches" % kind)
		# the normal map is attached for 2D lighting
		_check(s.tex is CanvasTexture and s.tex.normal_texture != null, "%s has a normal map" % kind)
	_check(EnemyArt.CIVPALS.keys().all(func(k): return EnemyArt.SPR.has("civ_" + k)), "every civilian kind has a sheet")
	# Omega Paragon's eyes sit near the arena's eye-laser origin (y - 34) while hovering.
	var par := EnemyArt.sheet("hero_paragon")
	var eye := Sheets.anchor(par, "laser", 1, "eye")
	var eye_y: float = par.foot - 6.0 + eye.y
	_check(absf(eye_y - (-34.0)) < 8.0, "Paragon eyes line up with the laser origin (%.1f)" % eye_y)

func _test_cache() -> void:
	var dir := "user://enemy_sheets/test_roundtrip"
	var built := Sheets.build("dog")
	Sheets._save(dir, built)
	var loaded := Sheets._load(dir, "dog")
	_check(not loaded.is_empty(), "cache loads")
	_check(loaded.frames.walk.size() == built.frames.walk.size() and loaded.frames.walk[3] == built.frames.walk[3], "cache keeps frame rects")
	_check(loaded.albedo.get_data() == built.albedo.get_data(), "cache keeps albedo pixels")
	_check(loaded.normal.get_data() == built.normal.get_data(), "cache keeps normal pixels")

func _test_combat() -> void:
	var scene: Node = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	var run: Node = root.get_node("Run")
	scene.arena.set_process(false)
	scene._enter_lab()
	var a = scene.arena
	run.new_run(); run.wave = 10; scene._start_wave()
	a.P.inv = 100000.0
	var spawned := []
	var types := ["cop", "k9", "det", "riot", "drone", "swat", "civ", "civ", "civ", "civ"]
	for i in types.size():
		var ang := i * TAU / types.size()
		spawned.append(a.make_enemy(types[i], a.P.x + cos(ang) * 150.0, a.P.y + sin(ang) * 110.0))
	var civ_kinds := ["suit", "tourist", "granny", "jogger"]
	var ci := 0
	for e in spawned:
		if e.civ: e.civ_kind = civ_kinds[ci]; e.spr = "civ_" + civ_kinds[ci]; ci += 1
	var bosses := []
	for w in [5, 10, 15, 20]:
		run.wave = w
		var b = a.make_enemy("boss", a.P.x - 300 + bosses.size() * 200, a.P.y - 190)
		bosses.append(b)
	run.wave = 10
	_check(bosses.map(func(b): return b.hero) == ["ironclad", "surge", "glacia", "paragon"], "one boss per hero: %s" % str(bosses.map(func(b): return b.hero)))
	var det = spawned[2]
	var flashes := 0
	var seen := {}
	for frame in 240:
		a._process(1.0 / 60.0)
		for e in a.enemies:
			if e.gfx.has("state"): seen[e.spr + "/" + e.gfx.state] = true
		if det.gfx.has("flash") and det.gfx.flash.life > 0.0: flashes += 1
		if frame == 60: det.shoot_cd = 0.0   # force a shot
	_check(det.gfx.has("flash"), "detectives own a muzzle flash")
	_check(flashes > 0, "detective shots light the muzzle flash")
	_check(seen.keys().any(func(k): return k.ends_with("/walk")), "enemies walk")
	if capture:
		await _shot("enemies-combat")
	# statuses: frozen, mind-controlled, sick, time-locked, hit flash
	var alive: Array = a.enemies.filter(func(e): return not e.dead and not e.boss)
	if alive.size() >= 5:
		alive[0].frozen_t = 5.0; alive[1].ally = true; alive[1].ally_t = 5.0; alive[2].sick_t = 5.0
		alive[3].time_lock = 5.0; alive[4].flash = 5.0
		a._sync(0.0)
		_check(alive[0].gfx.state == "frozen" and alive[0].gfx.tint.a > 0.0, "frozen state + tint")
		_check(alive[1].gfx.tint.is_equal_approx(preload("res://enemies/enemy_view.gd").TINT_ALLY), "mind-control tint")
		_check(alive[2].gfx.tint.a > 0.0, "sickness tint")
		_check(alive[3].gfx.state == "stunned", "time lock shows the stunned pose")
		_check(alive[4].gfx.state == "hurt" and alive[4].gfx.tint.a > 0.8, "hit flash")
		if capture: await _shot("enemies-status")
	# boss powers
	var iron = bosses[0]; var surge = bosses[1]; var glacia = bosses[2]; var par = bosses[3]
	iron.slam = {"sx": iron.x, "sy": iron.y, "x": iron.x, "y": iron.y, "t": 1.0, "T": 1.1}; iron.air = 0.0
	glacia.nova_cd = 0.2; surge.blink_cd = 0.1
	par.laser = {"phase": "fire", "t": 0.5, "a": 0.0, "dir": 1.0}
	for e in bosses: e.flash = 0.0; e.frozen_t = 0.0; e.time_lock = 0.0
	a._sync(0.0)
	_check(iron.gfx.state == "windup", "Ironclad slam windup (%s)" % iron.gfx.state)
	_check(glacia.gfx.state == "nova", "Glacia nova cast")
	_check(surge.gfx.state == "blink", "Static Surge blink")
	_check(par.gfx.state == "laser", "Omega Paragon laser eyes")
	if capture: await _shot("enemies-bosses")
	# deaths leave a corpse that plays the death animation, then cleans up
	var before := Corpse.live
	var victims: Array = a.enemies.filter(func(e): return not e.dead and not e.boss).slice(0, 3)
	for v in victims: v.hp = 0.0; a.kill(v)
	a._sync(0.0)
	await process_frame; await process_frame
	_check(Corpse.live >= before + victims.size(), "killed enemies leave corpses (%d -> %d)" % [before, Corpse.live])
	scene.queue_free()
	await process_frame; await process_frame

func _shot(name: String) -> void:
	for k in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/" + name + ".png")
	print("saved test-results/%s.png" % name)

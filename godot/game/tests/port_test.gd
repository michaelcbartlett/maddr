extends SceneTree
## Gameplay/flow integration checks against the frozen browser design.
const MAIN = "res://game/main.tscn"
var failures := 0
var checks := 0
var scene: Node
var run: Node
var capture := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	seed(947)
	capture = OS.get_cmdline_user_args().has("--screenshots")
	run = root.get_node("Run")
	_test_stats()
	scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	await _capture("title")
	_inside(scene.title_s.get_meta("focus"),"title button is on screen")
	_check(not scene.hud.visible and not scene.arena.fx_layer.visible,"title hides gameplay HUD and effects")
	scene._enter_lab()
	await _capture("design")
	_inside(scene.design_s.begin_btn,"begin button is on screen")
	_check(scene.design_s.size==scene.fit.size,"design screen fills the viewport")
	var a = scene.arena
	# All ordinary enemy families and each boss execute their native AI.
	for wave in [1,5,10,15,20]:
		run.new_run(); run.wave = wave; scene._start_wave()
		_check(a.level == run.theme_for_wave(wave) and a.arena_level.theme_id == a.level,"correct arena theme for wave %d" % wave)
		for type in ["cop","k9","det","riot","drone","swat","civ"]:
			a.make_enemy(type,a.P.x+randf_range(-300,300),a.P.y+randf_range(-220,220))
		if wave>1: a.boss = a.make_enemy("boss",a.P.x-230,a.P.y+100)
		Input.action_press("move_right"); Input.action_press("fire"); a.P.inv = 1000.0
		for frame in 420: a._process(1.0/60.0)
		Input.action_release("move_right"); Input.action_release("fire")
		_check(a.P.walk>0,"native movement advances the walk clock")
		_check(a.villain.rig.pose>=11,"gameplay passes a working walk phase")
		if wave==10:
			a.ebul.append({"x":a.P.x,"y":a.P.y,"vx":0.0,"vy":0.0,"r":5.0,"dmg":1.0,"t":1.0,"zap":true})
			a._process(1.0/60.0)
			_check(a.P.zap_t>0 and a.villain.rig.zap,"Static Surge lightning triggers x-ray state")
		a._sync(0.0)
		await _capture("wave-%d" % wave)
		_check(scene.hud.size==scene.fit.size,"HUD fills the viewport")
	# Status effects and all three weapon families.
	run.new_run(); run.build.items = ["thermite","acid","poison","bleed","cryo","tesla","remote","moon","orb","lens","sustain"]
	scene._start_wave(); a.P.inv = 1000.0
	var target = a.make_enemy("riot",a.P.x+70,a.P.y-16); target.hp = 10000; target.max_hp = 10000
	a.hit(target,1,{"proc":true})
	_check(target.burn_t>0 and target.acid_t>0 and target.poison_s>0 and target.bleed_s>0 and target.slow_t>0,"purchased status modules affect combat")
	for ammo in ["laser","bullet","razor"]:
		a.fire_gun(ammo,0.0,1.0,a.P.x+50,a.P.y-16,null,a.P.x,a.P.y-16)
	_check(a.beams.size()>0 and a.projs.size()>0,"native beam and projectile families spawn")
	# Clear -> shop -> purchase -> next wave, plus reroll and off-hand acquisition.
	run.wave = 1; a.end_wave()
	for frame in 102: a._process(1.0/60.0)
	_check(scene.state=="shop" and run.wave==2,"clearing a wave opens the next-wave shop")
	run.build.items.append("bionic_arm"); run.recompute()
	run.scrap = 10000; run.offers = [{"it":run.ITEM.offhand,"price":52,"sold":false}]
	_check(run.buy(0) and run.build.off!=null,"off-hand rig can be bought")
	_check(a.villain.rig.armed,"purchase updates the native rig")
	run.reroll_cost = 3; var before = run.scrap
	_check(run.reroll() and run.scrap==before-3,"reroll charges scrap and produces offers")
	# Stress the shop with a late-game inventory and many effect stats.
	run.build.items = run.ITEM.keys(); run.recompute(); run.wave = 19; run.gen_offers(); scene.shop_s.refresh(); scene._show("shop")
	await _capture("shop")
	_inside(scene.shop_s.next_btn,"shop next-wave button is on screen")
	_inside(scene.shop_s.reroll_btn,"shop reroll button is on screen")
	_inside(scene.shop_s.stats_box.get_parent(),"shop stats stay in a scrollable panel")
	_inside(scene.shop_s.owned_box.get_parent(),"inventory stays in a scrollable panel")
	scene._start_wave(); a.P.inv = 1000.0
	Input.action_press("fire"); Input.action_press("fire_off")
	for frame in 90: a._process(1.0/60.0)
	Input.action_release("fire"); Input.action_release("fire_off")
	_check(a.villain.rig.armed and a.villain.rig.off_gun.visible,"both equipped weapons remain visible")
	await _capture("upgraded")
	scene._show("paused"); _check(paused,"pause freezes the game"); scene._resume(); _check(not paused,"resume restores the game")
	run.wave = 20; scene._on_cleared()
	_check(scene.state=="over" and scene.over_title.text=="CITY CONQUERED!","wave 20 reaches the win screen")
	await _capture("win")
	scene._game_over(false)
	_check(scene.over_title.text in ["BUSTED!","FOILED AGAIN!","CURSES!","MEDDLING COPPERS!"],"player death reaches the loss screen")
	print("GAMEPLAY TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## Balance values tuned after the browser prototype was frozen (README "Tuning notes"). The stat check is about
## the build formulas, so it runs with the prototype's numbers swapped back in, then restores the tuned ones.
## Values the native game deliberately retuned away from the browser prototype: [id, section, key, browser value].
## A null browser value means the prototype has no such key. Ammo, frames and items are all looked up by id.
const BROWSER_VALUES := [["laser", "add", "dmg", 7], ["laser", "add", "atkSpd", null], ["razor", "add", "dmg", 7], ["razor", "add", "atkSpd", null], ["razor", "add", "bleed", 0.6], ["bullet", "add", "dmg", 10], ["rifle", "set", "dmgMul", 1.8],
	["pistol", "set", "cd", 0.6], ["blunder", "set", "dmgMul", 0.8], ["rifle", "add", "pierce", null],
	["storm", "add", "chainMul", 0.4], ["clock", "add", "bomb", 0.15], ["virus", "add", "sick", 0.25], ["hive", "mul", "minionMul", 2]]

func _tuned_def(id: String) -> Dictionary:
	for table in [run.AMMO, run.FRAMES]:
		for d in table:
			if d.id == id: return d
	return run.ITEM[id]

## Swap each tuned value for its browser value; returns what to put back.
func _swap_values(values: Array) -> Array:
	var previous: Array = []
	for v in values:
		var section: Dictionary = _tuned_def(v[0]).get(v[1], {})
		if not _tuned_def(v[0]).has(v[1]): _tuned_def(v[0])[v[1]] = section
		previous.append([v[0], v[1], v[2], section.get(v[2])])
		if v[3] == null: section.erase(v[2])
		else: section[v[2]] = v[3]
	return previous
const BROWSER_SPEED := 150.0

func _test_stats() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://character/tests/reference/cases.json"))
	var tuned := _swap_values(BROWSER_VALUES)
	var speed_k: float = run.base_stats().speed / BROWSER_SPEED
	for config in manifest.cases:
		run.build = {"ammo":int(config.ammo),"frame":int(config.frame),"items":config.items,"name":"","off":null}
		run.recompute()
		var stats = run.S.duplicate(); stats.maxHp += 30.0; stats.speed = stats.speed / speed_k
		# The prototype adds this flag lazily; native code keeps an explicit zero default.
		if not config.stats.S.has("aimGuide") and stats.aimGuide==0: stats.erase("aimGuide")
		# Native-only stats (laser beam vs bolt, loot drop modifier); the prototype has no such keys.
		# ...plus melee and damage-type amplifier stats, compared at their neutral defaults.
		var native := {"beam":0.0,"dropPct":0.0,"burnSpread":0.0,"poisonSpread":0.0,"meleeSpd":0.0,"meleeReach":0.0,"meleeDmg":0.0,
			"burnMul":1.0,"poisonMul":1.0,"lightningMul":1.0,"rad":0.0,"radMul":1.0}
		for key in native:
			if not config.stats.S.has(key) and float(stats[key])==native[key]: stats.erase(key)
		_check(_same(stats,config.stats.S),config.name+": base stats match browser")
		var expected = config.stats.D.duplicate(); expected.maxHp = maxi(10,roundi(config.stats.S.maxHp-30.0)); expected.speed *= speed_k
		_check(_same(run.D,expected),config.name+": derived stats match browser")
		_check(_same(run.CNT,config.stats.CNT),config.name+": stack counts match browser")
	tuned.reverse(); _swap_values(tuned)
	run.new_run()

func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	return a==b

func _inside(control: Control, label: String) -> void:
	var rect = control.get_global_rect()
	_check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(rect),label+" "+str(rect))

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error("FAIL: "+label)

func _capture(name: String) -> void:
	for frame in 4: await process_frame
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/"+name+".png")

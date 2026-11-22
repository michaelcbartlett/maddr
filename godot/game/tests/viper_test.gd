extends SceneTree
const Viper = preload("res://game/viper_boss.gd")
const Abilities = preload("res://game/boss_abilities.gd")
const UnlocksT = preload("res://game/unlocks.gd")
var checks := 0
var failures := 0
var run
var scene
var a

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ",label)

func _start(wave := 12) -> void:
	run.new_run(); run.wave = wave; run.theme_order = ["street"]; a.start_wave()
	a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.wave_t = 1000; a.P.inv = 1000
	a.walls = []; a.nav.configure([],Vector2(a.AW,a.AH)); a.P.x = 800; a.P.y = 550; a.P.aim = 0

func _missile(x := 920.0, y := 550.0) -> Dictionary:
	var owner = a.make_enemy("boss",1300,800); owner.frozen_t = 1000
	var b := {"x":x,"y":y,"vx":-265.0,"vy":0.0,"r":9.0,"dmg":5.0,"t":24.0,"seeker":true,"owner":owner,"col":Viper.COLOR,"trail":PackedVector2Array()}
	a.ebul.append(b); return b

func _run() -> void:
	seed(9921); run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	_start()
	_check(run.boss_for(12).id == "viper" and run.boss_for(15).id == "glacia", "Viper has a real encounter and preserves the existing bosses")
	var boss = a.make_enemy("boss",1100,550)
	_check(boss.hero == "viper" and EnemyArt.sheet(boss.spr).frames.has("charge"),"Viper has her own painted, animated sprite")
	boss.missile_cd = 0; boss.tick(0.01)
	_check(a.ebul.size() == 2 and a.ebul.all(func(b): return b.seeker and b.t > 20),"opening salvo fires long-lived seekers")
	for salvo in 8: boss.missile_cd = 0; boss.tick(0.01)
	_check(a.ebul.size() == 6,"active seekers are capped at six")
	boss.action_cd = 0; boss.action_phase = ""; boss.tick(0.01)
	_check(boss.action_phase == "windup" and boss.zig_points.size() == 3,"zigzag warns before its three committed legs")
	var path: PackedVector2Array = boss.zig_points.duplicate()
	a.P.y += 200; boss.tick(0.6)
	_check(boss.action_phase == "zigzag" and boss.zig_points == path,"zigzag locks its warning path instead of tracking during the dash")
	for frame in 100: boss.tick(0.016)
	_check(boss.action_phase == "recover" or boss.action_phase == "", "zigzag ends with a punishable recovery")
	_start(); var b := _missile(150,120); a.P.x = 1300; a.P.y = 850
	b.vx = 265.0
	for frame in 70: Viper.update_missile(a,b,0.05)
	_check(b.t > 0 and b.x > 700 and b.y > 400,"seeker follows a distant player across the map")
	_start(); b = _missile(920,450); Viper.update_missile(a,b,0.05)
	_check(b.vy > 0,"seeker turns towards the player's new position")
	b.time_lock = 1.0; var frozen := Vector2(b.x,b.y); Viper.update_missile(a,b,0.1)
	_check(Vector2(b.x,b.y) == frozen,"time freeze also pauses homing missiles")
	b.time_lock = 0.0; a.P.x = b.x - 5; a.P.y = b.y; a.P.inv = 0; var hp: float = a.P.hp
	Viper.update_missile(a,b,0.01)
	_check(b.t <= 0 and a.P.hp < hp,"a live seeker damages the player on swept contact")
	for ammo in ["laser","bullet","razor"]:
		_start(); b = _missile()
		a.fire_gun(ammo,0,1,820,550,null,800,550)
		a._update_projs(0.35 if ammo == "razor" else 0.2)
		_check(b.t <= 0,"%s shoots seekers down using swept collision" % ammo)
	_start(); b = _missile(); run.S.beam = 1
	a.fire_gun("laser",0,1,820,550,null,800,550)
	_check(b.t <= 0,"piercing laser beams intercept seekers")
	_start(); b = _missile(); a.walls = [{"rect":Rect2(870,400,20,300),"open":false}]
	run.S.beam = 1; a.fire_gun("laser",0,1,820,550,null,800,550)
	_check(b.t > 0,"beam interception cannot shoot through props")
	_start(); b = _missile(); a.explode(b.x,b.y,10,30,Color.WHITE)
	_check(b.t <= 0,"player explosions destroy seekers without hurting the player")
	_start(); b = _missile(); a.kill(b.owner)
	_check(b.t <= 0,"defeating Viper clears her remaining seekers")
	# Blueprints: normal and rare drops, physical pickup, persistent shop gates.
	run.unlocks.reset(); _start()
	Abilities.drop_rewards(a,"viper",Vector2(900,550),0.9)
	_check(a.pickups.size() == 1 and a.pickups[0].blueprint == "seeker_rack","normal Viper reward is the triple launcher blueprint")
	Abilities.drop_rewards(a,"viper",Vector2(900,550),0.0)
	_check(a.pickups.size() == 2 and a.pickups[1].blueprint == "zigzag","rare Viper roll adds zigzag without duplicate launcher blueprints")
	_check(not run.item_available(run.ITEM.seeker_rack),"uncollected blueprint never enters the shop")
	for p in a.pickups: a._collect_blueprint(p)
	run.build.items = ["bionic_arm"]; run.recompute()
	_check(run.item_available(run.ITEM.seeker_rack) and run.ITEM.zigzag.t > run.ITEM.seeker_rack.t,"collected launcher opens the shop; zigzag remains a rarer shop tier")
	run.scrap = 10000; run.offers = [{"it":run.ITEM.seeker_rack,"price":48,"sold":false}]
	_check(run.buy(0) and run.build.off.kind == "seeker_rack","launcher buys into the secondary arm slot")
	run.build.items.append("zigzag"); run.recompute()
	_check(run.equipped_action() == "zigzag" and run.build.off.kind == "seeker_rack","B action coexists with the secondary rockets")
	Abilities.drop_rewards(a,"ironclad",Vector2(1000,550),0.0)
	_check(a.pickups.any(func(p): return p.blueprint == "iron_slam"),"rare Ironclad roll drops leap-and-slam blueprint")
	run.unlocks.collect_blueprint("iron_slam")
	var saved = UnlocksT.new(run.RULES.unlocks,true); saved.path = "user://viper-selftest.json"; saved.unlocked = run.unlocks.unlocked.duplicate(); saved.persist = true; saved.save()
	var loaded = UnlocksT.new(run.RULES.unlocks,true); loaded.path = saved.path; loaded.load_save()
	_check(["seeker_rack","zigzag","iron_slam"].all(func(id): return loaded.is_unlocked("item",id)),"all boss rewards survive save/reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path))
	# Triple rockets select nearby hostile enemies, reacquire, and stop at walls.
	_start(); run.build.items = ["bionic_arm","seeker_rack"]; run.build.off = {"kind":"seeker_rack"}; run.recompute()
	var foes := []
	for at in [Vector2(1000,550),Vector2(1040,620),Vector2(1020,470)]:
		var e = a.make_enemy("riot",at.x,at.y); e.hp = 1000; foes.append(e)
	a.make_enemy("civ",840,550); var ally = a.make_enemy("cop",850,550); ally.ally = true
	a._update_utility(0.01)
	_check(a.projs.size() == 3 and a.projs.all(func(p): return foes.has(p.target)),"secondary fires exactly three rockets, ignoring nearby civilians and allies")
	_check(a.projs[0].target != a.projs[1].target and a.projs[1].target != a.projs[2].target,"salvo distributes rockets across the three closest foes")
	a._update_utility(0.01); _check(a.projs.size() == 3,"launcher obeys its five-second cooldown")
	a.projs[0].target.dead = true; a._update_projs(0.01)
	_check(is_instance_valid(a.projs[0].target) and not a.projs[0].target.dead,"rocket reacquires if its original target dies")
	for frame in 120: a._update_projs(0.016)
	_check(foes.any(func(e): return e.hp < 1000) and a.projs.is_empty(),"homing rockets reach and explode on nearby foes")
	_start(); a.make_enemy("cop",1500,550)
	_check(not Abilities.launch_rockets(a),"no rockets or cooldown are wasted when there are no nearby foes")
	# B input, committed dash hits, cooldown and independent secondary equipment.
	_start(); run.build.items = ["zigzag"]; run.recompute()
	var controls = root.get_node("Controls")
	_check(InputMap.action_get_events("boss_action").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B),"B is bound to the boss action")
	var victim = a.make_enemy("riot",900,615); victim.hp = 1000
	await process_frame
	Input.action_press("boss_action"); a._update_play(0.01); Input.action_release("boss_action")
	_check(not a.boss_move.is_empty() and a.boss_move.kind == "zigzag","B starts the equipped zigzag action")
	for frame in 80: Abilities.update_action(a,0.016)
	print("ZIG DEBUG ", a.boss_move, " pos ", Vector2(a.P.x,a.P.y), " hp ",victim.hp)
	_check(a.boss_move.is_empty() and a.P.x > 1090 and victim.hp < 1000,"zigzag completes three damaging dashes")
	_check(not Abilities.start_action(a,"zigzag"),"B action cannot restart during cooldown")
	_start(); a.walls = [{"rect":Rect2(900,400,30,350),"open":false}]
	Abilities.start_action(a,"zigzag")
	for frame in 80: Abilities.update_action(a,0.016)
	_check(a.P.x < 900 - a.P.r and a.boss_move.is_empty(),"zigzag stops before solid props")
	_start(); victim = a.make_enemy("riot",1050,550); victim.hp = 1000
	_check(Abilities.start_action(a,"iron_slam"),"Ironclad action launches a leap")
	for frame in 50: Abilities.update_action(a,0.016)
	_check(a.boss_move.is_empty() and a.P.x > 1040 and victim.hp < 1000,"leap lands in a damaging ground slam")
	run.build.items = ["zigzag","iron_slam"]; run.recompute()
	_check(run.equipped_action() == "iron_slam","latest purchased action equips B")
	run.sell("iron_slam"); _check(run.equipped_action() == "zigzag","selling an action restores the previous B ability")
	if OS.get_cmdline_user_args().has("--screenshots"): await _capture()
	print("VIPER / BOSS REWARD TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)

func _capture() -> void:
	_start(); a.banner_t = 0; a.siren_t = 0; a.wave_t = 45; a.P.inv = 0
	run.build.items = ["bionic_arm","seeker_rack","zigzag"]; run.build.off = {"kind":"seeker_rack"}; run.recompute(); a.villain.set_items()
	var boss = a.make_enemy("boss",1060,510); a.boss = boss
	boss.action_phase = "windup"; boss.action_t = 0.35; boss.zig_points = Viper.zigzag(Vector2(boss.x,boss.y),Vector2.LEFT)
	for at in [Vector2(950,420),Vector2(660,650),Vector2(1010,680)]:
		var b := _missile(at.x,at.y); b.trail = PackedVector2Array([at+Vector2(35,-20),at+Vector2(15,-8),at])
	# Fixture helpers create owners; hide those off-camera and keep one visible boss bar.
	a._sync(0); scene._show("play")
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/velvet-viper.png")

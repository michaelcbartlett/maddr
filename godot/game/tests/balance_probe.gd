extends SceneTree
## Balance probe (not a pass/fail suite). Plays real waves headless with a kiting bot and prints, per
## difficulty and wave: kills, damage taken (vs max HP), scrap earned, peak cops alive, and what the bot
## could afford in the shop. The bot never dies: HP is topped up after each hit and the would-be deaths
## are counted instead, so later waves are still measured.
##   Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/balance_probe.gd -- [--waves 10] [--diff 1,3,5] [--ammo 0] [--frame 0]
##     [--seed 77] [--no-parts]   --no-parts keeps the starting ammo/frame (no shop part swaps) for fair loadout comparisons
var scene
var arena
var run

func _initialize() -> void: call_deferred("_run")

func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args(); var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def

func _run() -> void:
	seed(int(_arg("--seed", "77")))
	run = root.get_node("Run")
	run.unlocks.highest_difficulty = 5
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false); scene.set_process(false)
	var waves := int(_arg("--waves", "10"))
	var ammo := int(_arg("--ammo", "0")); var frame := int(_arg("--frame", "0"))
	print("== one-shot check (wave-1 cop HP vs starting gun damage) ==")
	for d in range(1, 6):
		run.new_run(); run.build.ammo = ammo; run.build.frame = frame; run.recompute(); run.set_difficulty(d)
		var e = arena.make_enemy("cop", 300, 300); var hp: float = e.max_hp; e.dead = true
		print("  %-13s cop hp %5.1f  gun dmg %4.1f  hits %d  cop spd %.0f  villain spd %.0f" % [run.difficulty_name(), hp, run.D.dmg, ceili(hp / run.D.dmg), e.spd, run.D.speed])
	print("== boss HP / contact damage ==")
	for d in [1, 3, 5]:
		for w in [5, 10, 15, 20]:
			run.new_run(); run.set_difficulty(d); run.wave = w
			var b = arena.make_enemy("boss", 300, 300); b.dead = true
			print("  %-13s w%-2d %-17s hp %6.0f  dmg %5.1f" % [run.difficulty_name(), w, b.hero_name, b.max_hp, b.dmg])
	if OS.get_cmdline_user_args().has("--item-probe"):
		_item_probe(int(_arg("--at", "8"))); quit(); return
	for d in Array(_arg("--diff", "1,3,5").split(",")).map(func(s): return int(s)):
		_play(d, waves, ammo, frame)
	quit()

func _play(diff: int, waves: int, ammo: int, frame: int) -> void:
	run.new_run(); run.build.ammo = ammo; run.build.frame = frame; run.recompute(); run.set_difficulty(diff)
	print("== %s (%s %s) ==" % [run.difficulty_name(), run.AMMO[ammo].id, run.FRAMES[frame].id])
	print("  wave  len  kills  dmgTaken/maxHp  deaths  scrap  peakAlive  bank  gunDPS  boss  bought")
	var dt := 1.0 / 30.0
	var tot_kills := 0; var tot_deaths := 0; var tot_taken := 0.0; var boss_times: Array = []
	for w in range(1, waves + 1):
		arena.start_wave(); scene.state = "play"
		var k0: int = run.kills; var s0: int = run.total_scrap; var taken := 0.0; var deaths := 0; var peak := 0
		var hp_prev: float = arena.P.hp; var t := 0.0; var boss_t0 := -1.0; var boss_ttk := "-"
		while arena.state == "play" and t < 200.0:
			_bot()
			arena._process(dt); t += dt
			if arena.state == "over": arena.state = "play"
			if arena.P.hp < hp_prev:
				taken += hp_prev - arena.P.hp
				if arena.P.hp <= 0.0: deaths += 1; arena.P.hp = run.D.maxHp
			hp_prev = arena.P.hp
			peak = maxi(peak, arena.live_foes().size())
			if arena.boss != null and boss_t0 < 0.0: boss_t0 = t
			if boss_t0 >= 0.0 and boss_ttk == "-" and arena.boss == null: boss_ttk = "%.0fs" % (t - boss_t0)
		if boss_t0 >= 0.0 and boss_ttk == "-": boss_ttk = "alive"
		tot_kills += run.kills - k0; tot_deaths += deaths; tot_taken += taken
		if boss_ttk != "-": boss_times.append(boss_ttk)
		while arena.state == "clear": arena._process(dt)
		var earned: int = run.total_scrap - s0
		var dps_hp := [run.D.dmg * run.D.shots * run.S.guns.size() / run.D.cd, run.D.maxHp]   # build as played this wave
		var bought := []
		if w < waves:
			# main._on_cleared already opened the shop for the next wave (Run.wave + 1, fresh offers)
			# buy cheapest-first until broke (a rough stand-in for a player's shopping)
			for r in 4:   # buy cheapest-first; reroll while there's clearly money left over
				var idx := range(run.offers.size()); idx.sort_custom(func(a, b): return run.offers[a].price < run.offers[b].price)
				for i in idx:
					if OS.get_cmdline_user_args().has("--no-parts") and run.offers[i].it.has("swap"): continue
					if run.buy(i): bought.append("%s(%d)" % [run.offers[i].it.id, run.offers[i].price])
				if run.scrap < run.reroll_cost * 4 or not run.reroll(): break
				bought.append("R")
		print("  %4d  %3.0f  %5d  %5.1f/%-3d       %3d   %5d  %9d  %4d  %6.1f  %5s  %s" % [w, run.wave_len(w), run.kills - k0, taken, dps_hp[1], deaths, earned, peak, run.scrap, dps_hp[0], boss_ttk, " ".join(bought)])
		Input.action_release("fire")
	print("SUMMARY %s %s diff%d: kills %d  deaths %d  taken %.0f  boss %s" % [run.AMMO[ammo].id, run.FRAMES[frame].id, diff, tot_kills, tot_deaths, tot_taken, ",".join(boss_times)])

func _bot() -> void:
	var P = arena.P; var pos := Vector2(P.x, P.y)
	var push := Vector2.ZERO
	for e in arena.live_foes():
		var d := pos - Vector2(e.x, e.y); var l := d.length()
		if l < 260.0 and l > 0.01: push += d / l * (260.0 - l) / 260.0
	for b in arena.ebul:
		var d := pos - Vector2(b.x, b.y); var l := d.length()
		if l < 90.0 and l > 0.01: push += d / l * 0.8
	push += (Vector2(800, 550) - pos) / 900.0          # drift back toward the middle
	var tang := Vector2(-push.y, push.x) * 0.35    # strafe so the bot doesn't pin itself to a wall
	var mv := (push + tang).limit_length(1.0)
	for a in ["move_right", "move_left", "move_down", "move_up"]: Input.action_release(a)
	if mv.x > 0.05: Input.action_press("move_right", mv.x)
	if mv.x < -0.05: Input.action_press("move_left", -mv.x)
	if mv.y > 0.05: Input.action_press("move_down", mv.y)
	if mv.y < -0.05: Input.action_press("move_up", -mv.y)
	var e = arena.nearest_foe(P.x, P.y)
	root.get_node("Controls").aim_src = "pad"
	if e:
		P.aim = atan2(e.y - P.y, e.x - P.x)
		if Vector2(e.x - P.x, e.y - P.y).length() < run.D.range + 40: Input.action_press("fire")
		else: Input.action_release("fire")
	else: Input.action_release("fire")

## --item-probe [--at 8]: one 60 s wave (Nuisance) per module, baseline build + 2 copies of that module (1 if unique).
## Prints kills, damage taken and a score vs the baseline, sorted, so outliers stand out.
func _item_probe(wave: int) -> void:
	var base := ["cell", "fins", "coat", "scope"]
	var rows := []
	var ids := [""]
	for it in run.ITEMS: ids.append(it.id)
	var ref := []
	for id in ids:
		var kills := 0.0; var taken := 0.0
		for sd in 2:
			seed(1000 + sd)
			run.new_run(); run.set_difficulty(2); run.wave = wave
			run.build.items = base.duplicate()
			if id != "":
				var it: Dictionary = run.ITEM[id]
				var uniq: bool = id in ["bionic_arm", "offhand", "telescope", "time_freeze", "proximity_bomb"] or it.has("arm")
				if id == "offhand" or it.has("arm"): run.build.items.append("bionic_arm")
				for c in (1 if uniq else 2): run.build.items.append(id)
				if id == "offhand": run.build.off = {"kind": "gun", "ammo": 1, "frame": 0, "items": []}
				elif it.has("arm"): run.build.off = {"kind": it.arm}
			run.recompute()
			arena.start_wave(); scene.state = "play"
			var k0: int = run.kills; var hp_prev: float = arena.P.hp; var t := 0.0
			while arena.state == "play" and t < 70.0:
				_bot(); arena._process(1.0 / 30.0); t += 1.0 / 30.0
				if arena.state == "over": arena.state = "play"
				if arena.P.hp < hp_prev:
					taken += hp_prev - arena.P.hp
					if arena.P.hp <= 0.0: arena.P.hp = run.D.maxHp
				hp_prev = arena.P.hp
			kills += run.kills - k0
			arena.end_wave(); while arena.state == "clear": arena._process(1.0 / 30.0)
			scene.state = "play"
		if id == "": ref = [kills, taken]
		var cost: int = 0 if id == "" else int(run.ITEM[id].c)
		rows.append([id if id != "" else "(baseline)", kills / 2.0, taken / 2.0, cost])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("== item impact: wave %d Nuisance, base %s + 2x item ==" % [wave, ",".join(base)])
	print("  item              cost  kills   x base   dmgTaken")
	for r in rows: print("  %-16s %5d  %5.0f   %5.2f   %6.1f" % [r[0], r[3], r[1], r[1] / maxf(1.0, ref[0] / 2.0), r[2]])

extends SceneTree
## Boss duel probe (not a pass/fail suite). Spawns one boss alone (no cops/civilians) at its wave with a
## representative build and plays it out with two bots, attributing every hit on the villain to the boss attack
## that caused it. Hits never kill: HP is tracked as "damage taken / max HP" instead.
##   Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/boss_duel_probe.gd -- [--wave 5] [--diff 1,2,3,4,5] [--seeds 12] [--hp 30] [--items cell,fins]
##   --bot kite|dodge|both   kite = balance_probe's naive kiter; dodge also sidesteps charges and runs out of slam circles
var scene
var arena
var run

func _initialize() -> void: call_deferred("_run")

func _arg(name: String, def: String) -> String:
	var a := OS.get_cmdline_user_args(); var i := a.find(name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def

func _run() -> void:
	run = root.get_node("Run")
	run.unlocks.highest_difficulty = 5
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	arena = scene.arena; arena.set_process(false); scene.set_process(false)
	var wave := int(_arg("--wave", "5")); var seeds := int(_arg("--seeds", "12"))
	var items: Array = Array(_arg("--items", "cell,fins").split(",")).filter(func(s): return s != "")
	var bots: Array = ["kite", "dodge"] if _arg("--bot", "both") == "both" else [_arg("--bot", "both")]
	print("== boss duel: wave %d, items %s ==" % [wave, ",".join(items)])
	print("  diff           bot    bossHP  dmg  kill%  ttk   taken/maxHp  hits  contact charge  slam  other  enrSpd")
	for d in Array(_arg("--diff", "1,2,3,4,5").split(",")).map(func(s): return int(s)):
		for bot in bots:
			var agg := {"kills": 0, "ttk": 0.0, "taken": 0.0, "hits": 0, "contact": 0, "charge": 0, "slam": 0, "other": 0, "spd": 0.0}
			var bhp := 0.0; var bdmg := 0.0; var mhp := 0
			for sd in seeds:
				seed(500 + sd)
				var r := _duel(d, wave, items, bot)
				bhp = r.bhp; bdmg = r.bdmg; mhp = r.mhp
				for k in ["taken", "hits", "contact", "charge", "slam", "other", "spd"]: agg[k] += r[k]
				if r.killed: agg.kills += 1; agg.ttk += r.t
			print("  %-13s  %-5s  %5.0f  %4.1f  %4.0f%%  %4.0fs  %5.1f/%-3d    %4.1f   %4.1f    %4.1f   %4.1f  %4.1f   %3.0f" % [
				run.difficulty_name(), bot, bhp, bdmg, 100.0 * agg.kills / seeds, agg.ttk / maxf(1, agg.kills),
				agg.taken / seeds, mhp, float(agg.hits) / seeds, float(agg.contact) / seeds, float(agg.charge) / seeds,
				float(agg.slam) / seeds, float(agg.other) / seeds, agg.spd / seeds])
	quit()

func _duel(diff: int, wave: int, items: Array, bot: String) -> Dictionary:
	run.new_run(); run.set_difficulty(diff); run.wave = wave
	run.build.items = items.duplicate(); run.recompute()
	arena.start_wave(); scene.state = "play"
	arena.P.boss_spawned = true
	for e in arena.enemies: e.queue_free()
	arena.enemies.clear(); arena.markers.clear()
	var b = arena.make_enemy("boss", arena.P.x + 450.0, arena.P.y); arena.boss = b
	var out := {"bhp": b.max_hp, "bdmg": b.dmg, "mhp": run.D.maxHp, "taken": 0.0, "hits": 0, "contact": 0, "charge": 0, "slam": 0, "other": 0, "killed": false, "t": 0.0, "spd": 0.0}
	var dt := 1.0 / 30.0; var t := 0.0; var hp_prev: float = arena.P.hp
	while t < 45.0 and not b.dead:
		arena.spawn_t = 999.0; arena.civ_t = 999.0; arena.wave_t = 999.0
		var was_charging: bool = b.charging > 0.0; var was_slam: bool = b.slam != null
		if bot == "dodge": _dodge_bot(b)
		else: _kite_bot()
		arena._process(dt); t += dt
		if arena.state == "over": arena.state = "play"
		if arena.P.hp < hp_prev:
			out.taken += hp_prev - arena.P.hp; out.hits += 1
			if was_slam and b.slam == null: out.slam += 1
			elif was_charging or b.charging > 0.0: out.charge += 1
			elif Vector2(b.x - arena.P.x, b.y - arena.P.y).length() < b.r + arena.P.r + 8: out.contact += 1
			else: out.other += 1
			if arena.P.hp <= 0.0: arena.P.hp = run.D.maxHp
		hp_prev = arena.P.hp
	out.killed = b.dead; out.t = t
	out.spd = b.spd
	for a in ["move_right", "move_left", "move_down", "move_up", "fire"]: Input.action_release(a)
	arena.end_wave(); while arena.state == "clear": arena._process(dt)
	return out

func _press(mv: Vector2) -> void:
	for a in ["move_right", "move_left", "move_down", "move_up"]: Input.action_release(a)
	if mv.x > 0.05: Input.action_press("move_right", mv.x)
	if mv.x < -0.05: Input.action_press("move_left", -mv.x)
	if mv.y > 0.05: Input.action_press("move_down", mv.y)
	if mv.y < -0.05: Input.action_press("move_up", -mv.y)

func _aim_fire() -> void:
	var P = arena.P; var e = arena.nearest_foe(P.x, P.y)
	root.get_node("Controls").aim_src = "pad"
	if e:
		P.aim = atan2(e.y - P.y, e.x - P.x)
		if Vector2(e.x - P.x, e.y - P.y).length() < run.D.range + 40: Input.action_press("fire")
		else: Input.action_release("fire")
	else: Input.action_release("fire")

func _wall_push(pos: Vector2) -> Vector2:
	var m := 120.0; var p := Vector2.ZERO
	if pos.x < m: p.x += (m - pos.x) / m
	if pos.x > arena.AW - m: p.x -= (pos.x - (arena.AW - m)) / m
	if pos.y < m: p.y += (m - pos.y) / m
	if pos.y > arena.AH - m: p.y -= (pos.y - (arena.AH - m)) / m
	return p * 1.5

## Same steering as balance_probe's bot.
func _kite_bot() -> void:
	var P = arena.P; var pos := Vector2(P.x, P.y); var push := Vector2.ZERO
	for e in arena.live_foes():
		var d := pos - Vector2(e.x, e.y); var l := d.length()
		if l < 260.0 and l > 0.01: push += d / l * (260.0 - l) / 260.0
	for bl in arena.ebul:
		var d := pos - Vector2(bl.x, bl.y); var l := d.length()
		if l < 90.0 and l > 0.01: push += d / l * 0.8
	push += (Vector2(arena.AW / 2.0, arena.AH / 2.0) - pos) / 900.0
	var tang := Vector2(-push.y, push.x) * 0.35
	_press((push + tang).limit_length(1.0)); _aim_fire()

## A competent player: keep ~300 px, circle-strafe, sidestep perpendicular on the charge telegraph,
## and sprint straight out of a slam's landing circle.
var _side := 1.0
func _dodge_bot(b) -> void:
	var P = arena.P; var pos := Vector2(P.x, P.y); var bp := Vector2(b.x, b.y)
	var to_me := pos - bp; var l := maxf(0.01, to_me.length()); var n := to_me / l
	var perp := Vector2(-n.y, n.x) * _side
	var mv := Vector2.ZERO
	if b.slam != null:
		var c := Vector2(b.slam.x, b.slam.y); var away := pos - c
		mv = away.normalized() if away.length() > 1.0 else perp
	elif b.charging > 0.0 or b.charge_t < 0.0:
		mv = perp   # sidestep the charge line
	else:
		var radial := 1.0 if l < 300.0 else (-0.6 if l > 380.0 else 0.0)
		mv = n * radial + perp * 0.8
	mv += _wall_push(pos)
	if pos.x < 160 or pos.x > arena.AW - 160 or pos.y < 160 or pos.y > arena.AH - 160:
		if randf() < 0.02: _side = -_side
	_press(mv.limit_length(1.0)); _aim_fire()

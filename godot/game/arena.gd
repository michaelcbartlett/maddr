extends Node2D
class_name Arena
## One wave of play in the single Brotato-sized arena (levels/arena_level.gd), re-themed each wave.
## Port of index.html startWave/update/fireGun/hit/kill/... with Godot lights on top.
## Emits cleared() after the wave-clear vacuum, died() when the villain is busted.

signal cleared
signal died

## World size of the current wave's level (the arena, or the longer train heist); set by _setup_level.
var AW: int = Levels.AW
var AH: int = Levels.AH
const VIEW_H := 540.0        # world units visible vertically (index.html shows about 880x580 at its min zoom)
const BlasterFx = preload("res://fx/blaster_fx.gd")
const ShotGeometry = preload("res://game/shot_geometry.gd")
const OFF_HAND = -1
const UNBOUND_SHOT = -2
const ArenaLevel = preload("res://levels/arena_level.gd")
const TrainHeist = preload("res://game/train_heist.gd")
var heist = TrainHeist.new()    # train heist wave: goal, progress and boarding spawns
const BankVault = preload("res://game/bank_vault.gd")
var bank_vault = BankVault.new()   # bank lobby robbery: a customer's vault key opens the vault
const WallIndex = preload("res://levels/wall_index.gd")
const BeamView = preload("res://fx/laser_beam.gd")
const Grapple = preload("res://game/grapple.gd")
const Consumables = preload("res://game/consumables.gd")
const Viper = preload("res://game/viper_boss.gd")
const BossAbilities = preload("res://game/boss_abilities.gd")
var boss_move: Dictionary = {}
var action_cooldown := 0.0

const SceneryDamage = preload("res://game/scenery_damage.gd")

class PlayerState:
	var x := 800.0
	var y := 550.0
	var r := 11.0
	var hp := 30.0
	var inv := 0.0
	var aim := 0.0
	var moving := false
	var walk := 0.0
	var idle_t := 0.0
	var recoil := 0.0
	var flash_t := 0.0
	var firing_t := 0.0
	var zap_t := 0.0
	var slow_t := 0.0
	var recoil2 := 0.0
	var flash_t2 := 0.0
	var off_cd := 0.4
	var firing2_t := 0.0
	var boss_spawned := false
	var melee_cd := 0.0
	var melee_t := 0.0
	var melee_aim := 0.0
	var melee_hit := false
	var melee_swing := 0.26   # duration of the current swing (weapon specific)
	var melee_arc := 0.0      # angular sweep of the current swing, for the pose
	var helmet_cd := 0.4
	var disguise_t := 0.0

var P := PlayerState.new()
var state := "done"           # play | clear | done | over
var time := 0.0
var wave_t := 0.0
var wave_dur := 60.0
var spawn_t := 0.8
var crate_t := 10.0
var clear_t := 0.0
var civ_t := 4.0
var banner_t := 0.0
var banner_txt := ""
var shake := 0.0
var orb_a := 0.0
var moon_t := 3.0
var mine_t := 0.0
var heal_budget := 0.0
var gun_cd: Array = []
var beam_tick: Array = []
var gun_flashes: Array = []
var blaster_fx = BlasterFx.new()
var _main_trigger_held := false
const CAPACITOR_TIME := 1.5
const CAPACITOR_BONUS := 1.5
var laser_charge: Dictionary = {}   # independent charge for each gun; releasing its trigger charges it
var grapple = Grapple.new()   # Shock Grapple state (main gun with "hook" ammo)
var consumables = Consumables.new()
var boss: Enemy = null
var level := "street"       # current theme id (cosmetic only)
var _wall_index = WallIndex.new()
var walls: Array = []:
	set(value):
		walls = value
		_wall_index.rebuild(value)
var arena_level             # ArenaLevel: floor, props, lamps, navigation
var nav                     # navigation shared with enemies (A.nav.waypoint)
var siren_t := 0.0          # wave-intro siren flash

var enemies: Array[Enemy] = []
var beams: Array = []
var arcs: Array = []
var projs: Array = []
var ebul: Array = []
var pickups: Array = []
var _pickup_run_serial := -1
var parts: Array = []
var nums: Array = []
var markers: Array = []
var crates: Array = []
var strikes: Array = []
var booms: Array = []
var mines: Array = []
var novas: Array = []
var utility_fields: Array = []

# nodes
var bg: Sprite2D
var ground: Node2D
var actors: Node2D
var villain: VillainView
var fx_layer: CanvasLayer
var fx_add: Node2D
var ambient_fx: ArenaAmbient
var decals: Array = []      # scorch marks left by explosions ({x, y, r, t})
var fx_top: Node2D
var beam_layer: Node2D
var _beam_views: Array[Node2D] = []
var lights: LightPool
var ambient: CanvasModulate
var cam: Camera2D
var font: Font

func _ready() -> void:
	EnemyArt.build()
	font = UiKit.mono()
	ambient = CanvasModulate.new(); add_child(ambient)
	bg = Sprite2D.new(); bg.centered = false; add_child(bg)
	arena_level = ArenaLevel.new(); add_child(arena_level); nav = arena_level.navigation
	ground = Node2D.new(); ground.draw.connect(_draw_ground.bind(ground)); add_child(ground)
	actors = Node2D.new(); actors.y_sort_enabled = true; add_child(actors)
	villain = VillainView.new(); actors.add_child(villain)
	arena_level.prop_parent = actors
	lights = LightPool.new(); add_child(lights)
	# emissive FX: its own canvas layer (follows the camera) so the CanvasModulate darkness doesn't dim it
	fx_layer = CanvasLayer.new(); fx_layer.follow_viewport_enabled = true; fx_layer.layer = 1; add_child(fx_layer)
	ambient_fx = ArenaAmbient.new(); fx_layer.add_child(ambient_fx)
	fx_add = Node2D.new(); var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; fx_add.material = m
	fx_add.draw.connect(_draw_fx_add.bind(fx_add)); fx_layer.add_child(fx_add)
	beam_layer = Node2D.new(); fx_layer.add_child(beam_layer)
	fx_top = Node2D.new(); fx_top.draw.connect(_draw_fx_top.bind(fx_top)); fx_layer.add_child(fx_top)
	cam = Camera2D.new(); cam.limit_left = 0; cam.limit_top = 0; cam.limit_right = AW; cam.limit_bottom = AH
	add_child(cam)

func _apply_zoom() -> void:
	var vs := get_viewport_rect().size
	var z := vs.y / VIEW_H
	cam.zoom = Vector2(z, z)

# =============== FLOW ===============
func start_wave() -> void:
	Run.recompute()
	# Uncollected blueprints survive wave changes, but never carry into a different run.
	var carried := pickups.filter(func(p): return p.has("blueprint") and _pickup_run_serial == Run.run_serial)
	_pickup_run_serial = Run.run_serial
	var D := Run.D; var S := Run.S
	P = PlayerState.new(); P.x = Levels.SPAWN.x; P.y = Levels.SPAWN.y; P.hp = D.maxHp
	consumables.reset(); boss_move = {}; action_cooldown = 0.0
	for e in enemies: e.queue_free()
	enemies.clear(); beams.clear(); arcs.clear(); projs.clear(); ebul.clear(); pickups.clear(); parts.clear(); nums.clear()
	for p in carried:
		p.x = P.x + 90 + pickups.size() * 30; p.y = P.y + 40; pickups.append(p)
	markers.clear(); crates.clear(); strikes.clear(); booms.clear(); mines.clear(); novas.clear(); utility_fields.clear(); beam_tick = []
	blaster_fx.clear(); gun_cd = []; gun_flashes = []; _main_trigger_held = false; grapple.reset()
	laser_charge.clear()
	for i in (S.guns as Array).size(): gun_cd.append(0.3 + i * 0.13); beam_tick.append(0.0); gun_flashes.append(0.0)
	boss = null; wave_dur = Run.wave_len(Run.wave); wave_t = wave_dur; spawn_t = 0.8; crate_t = randf_range(8, 14); moon_t = 3.0; mine_t = 0.0
	civ_t = randf_range(3, 6); heal_budget = 0.0
	_setup_level()
	P.x = arena_level.spawn.x; P.y = arena_level.spawn.y
	heist.reset(self)
	bank_vault.reset(self)
	var B = Run.boss_for(Run.wave)
	banner_txt = "WAVE %d · %s" % [Run.wave, arena_level.theme.name]
	if B != null: banner_txt += " · %s INCOMING" % B.name
	banner_t = 2.4; siren_t = 1.2; Sfx.play("siren")
	state = "play"
	_apply_zoom()
	cam.position = Vector2(P.x, P.y); cam.reset_smoothing()
	villain.set_items()
	villain.prepare_for_play()
	_sync_villain()

func _setup_level() -> void:
	level = Run.theme_for_wave(Run.wave)
	arena_level.build(level)
	bg.visible = false
	ambient.color = arena_level.theme.ambient
	ambient_fx.reset(self, arena_level); decals.clear()
	walls = arena_level.walls
	AW = int(arena_level.size.x); AH = int(arena_level.size.y)
	cam.limit_right = AW; cam.limit_bottom = AH
	ground.queue_redraw()

func make_enemy(type: String, x: float, y: float) -> Enemy:
	var e := Enemy.new(); e.setup(self, type, x, y)
	enemies.append(e); actors.add_child(e)
	return e

func end_wave() -> void:
	# An unused teleport kit is returned before this wave's arena dressing is replaced.
	if not consumables.pads.is_empty():
		Run.consumable_charges.teleport = mini(3, int(Run.consumable_charges.teleport) + 1)
		consumables.pads.clear(); consumables.pads_armed = false
	state = "clear"; clear_t = 1.6; banner_txt = "WAVE CLEARED!"; banner_t = 1.6
	for e in enemies:
		if not e.dead: poof(e.x, e.y, Color("#88aabb"), 10); e.dead = true
	ebul.clear(); markers.clear(); projs.clear(); mines.clear(); novas.clear(); boss = null; grapple.reset(); boss_move = {}
	Sfx.play("clear1"); get_tree().create_timer(0.11).timeout.connect(Sfx.play.bind("clear2"))

func is_playing() -> bool: return state in ["play","clear"]

# =============== HELPERS ===============
func snd(n: String) -> void: Sfx.play(n)

func add_num(x: float, y: float, v, col: Color, big: bool) -> void:
	if nums.size() > 90: nums.pop_front()
	nums.append({"x": x + randf_range(-6, 6), "y": y, "t": 0.7, "txt": str(v), "col": col, "big": big})

func part(x: float, y: float, vx: float, vy: float, t: float, col: Color, s: float) -> void:
	parts.append({"x": x, "y": y, "vx": vx, "vy": vy, "t": t, "m": t, "col": col, "s": s})

func poof(x: float, y: float, col: Color, n := 8, sp := 120.0, sz := 4.0) -> void:
	for i in n:
		var a := randf() * TAU; var s := randf_range(sp * 0.3, sp)
		parts.append({"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s, "t": randf_range(0.3, 0.7), "m": 0.7, "col": col, "s": sz})
	if parts.size() > 900: parts = parts.slice(parts.size() - 900)

func gain_scrap(v: float) -> int: return Run.gain_scrap(v)

func hurt_player(a: float) -> void:
	if P.inv > 0 or state != "play": return
	var d := maxi(1, roundi(a * 15.0 / (15.0 + maxf(0.0, Run.S.armor))))
	P.hp -= d; P.inv = 0.4; shake = maxf(shake, 6); Controls.rumble(0.3, 0.7, 160)
	add_num(P.x, P.y - 24, "-" + str(d), Color("#ff4a4a"), true); snd("hurt")
	if P.hp <= 0: P.hp = 0; state = "over"; died.emit()

func live_foes() -> Array:
	return enemies.filter(func(e): return not e.dead and not e.ally)

func nearest_foe(x: float, y: float, max_d := 1e9) -> Enemy:
	var best: Enemy = null; var bd := max_d * max_d
	for e in enemies:
		if e.dead or e.ally: continue
		var d := (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)
		if d < bd: bd = d; best = e
	return best

func in_wall(x: float, y: float, pad := 0.0) -> bool:
	for w in _wall_index.query(Rect2(Vector2(x-pad,y-pad),Vector2.ONE*(pad*2+1))):
		if w.open: continue
		var r: Rect2 = w.rect
		if x > r.position.x - pad and x < r.end.x + pad and y > r.position.y - pad and y < r.end.y + pad: return true
	return false

func collide_walls(o, r: float, prev := Vector2.INF) -> void:
	# a body that crossed a whole wall in one step is put back on the side it started from
	if prev!=Vector2.INF and not _wall_index.query(Rect2(prev,Vector2.ZERO).expand(Vector2(o.x,o.y)).grow(r)).is_empty():
		var step := Vector2(o.x,o.y)-prev
		if step.length()>1.0 and nav!=null and not nav.clear_segment(prev,Vector2(o.x,o.y),0.0): o.x = prev.x; o.y = prev.y
	for w in _wall_index.query(Rect2(Vector2(o.x,o.y)-Vector2.ONE*(r+32),Vector2.ONE*(r+32)*2)):
		if w.open: continue
		var R: Rect2 = w.rect
		var cx := clampf(o.x, R.position.x, R.end.x); var cy := clampf(o.y, R.position.y, R.end.y)
		var dx: float = o.x - cx; var dy: float = o.y - cy; var d2 := dx * dx + dy * dy
		if d2 >= r * r: continue
		if d2 > 0:
			var d := sqrt(d2); var p := r - d; o.x += dx / d * p; o.y += dy / d * p
		else:
			var l: float = o.x - R.position.x; var rr: float = R.end.x - o.x; var t: float = o.y - R.position.y; var b: float = R.end.y - o.y
			var m := minf(minf(l, rr), minf(t, b))
			if prev!=Vector2.INF and not R.has_point(prev):   # exit through the side we entered from
				if prev.x<R.position.x: m = l
				elif prev.x>R.end.x: m = rr
				elif prev.y<R.position.y: m = t
				else: m = b
			if m == l: o.x = R.position.x - r
			elif m == rr: o.x = R.end.x + r
			elif m == t: o.y = R.position.y - r
			else: o.y = R.end.y + r

func ray_len(x: float, y: float, cx: float, sy: float, length: float) -> float:
	if walls.is_empty(): return length
	var start = Vector2(x,y); var finish = start+Vector2(cx,sy)*length
	var fraction = 1.0
	for wall in _wall_index.query(Rect2(start,Vector2.ZERO).expand(finish)):
		if wall.open: continue
		var contact = ShotGeometry.rect_entry(start,finish,wall.rect)
		if not contact.is_empty(): fraction = minf(fraction,contact.fraction)
	return length*fraction

# =============== COMBAT ===============
func hit(e: Enemy, amt: float, o := {}) -> void:
	if e.dead or e.ally: return
	amt *= e.damage_taken(o.get("element", "physical"))
	amt *= Enemy.Tactics.shield_multiplier(e, o)
	if amt <= 0.0: return
	var S := Run.S; var D := Run.D
	if e.frozen_t > 0: amt *= S.frozenMul
	if e.acid_t > 0: amt *= 1.2
	if o.get("element", "") == "lightning": amt *= S.lightningMul
	var proc: bool = o.get("proc", false)
	var crit := false
	if proc and randf() < S.crit: amt *= 2.0; crit = true
	e.hp -= amt; e.flash = 0.07
	if not o.get("silent", false): add_num(e.x, e.y - e.r - 6, roundi(amt), Color("#ffe14a") if crit else o.get("col", Color.WHITE), crit)
	if S.lifesuck > 0 and heal_budget > 0:
		var hg := minf(heal_budget, amt * S.lifesuck); heal_budget -= hg; P.hp = minf(D.maxHp, P.hp + hg)
	if proc:
		var pf: float = D.pf * o.get("pfm", 1.0)
		if o.has("kx") and not e.heavy: e.kx += o.kx * 70; e.ky += o.ky * 70
		if S.burn: e.burn_t = 3.0; e.burn_dps = maxf(e.burn_dps, S.burn * S.burnMul * (1.0 + S.dmgPct * 0.5)); e.burn_gen = 0
		if S.acid: e.acid_t = 3.0
		if S.poison and e.damage_taken("poison") > 0.0: e.poison_s = mini(8, e.poison_s + 1); e.poison_t = 5.0; e.poison_gen = 0
		if S.bleed: e.bleed_s = mini(10, e.bleed_s + 1); e.bleed_t = 4.0
		if S.rad and e.damage_taken("radiation") > 0.0: irradiate(e, 1)
		if S.sick and randf() < S.sick * pf * 2.0: e.sick_t = 6.0
		if S.freeze:
			e.chill += S.freeze * pf * (0.3 if e.boss else 1.0); e.slow_t = 2.0
			if e.chill >= 1.0:
				e.chill = 0.0; e.frozen_t = 0.5 if e.boss else 1.6; poof(e.x, e.y, Color("#bff4ff"), 8, 90); snd("frz")
		if S.explode and randf() < S.explode * pf: explode(e.x, e.y, (14.0 + D.dmg * 0.8) * S.boomMul, 55.0 * sqrt(S.boomMul), Color("#ffa030"))
		if S.bomb and e.bomb_t <= 0 and not e.boss and randf() < S.bomb * pf: e.bomb_t = 2.5; e.bomb_dmg = D.dmg * 3.0 * S.boomMul
		if S.remote and mines.size() < 8 and randf() < S.remote * pf:
			mines.append({"x": e.x + randf_range(-10, 10), "y": e.y + randf_range(-10, 10), "t": 0.0})
			if mines.size() >= 8: detonate()
		if S.execute and not e.boss and e.hp > 0 and e.hp < e.max_hp * S.execute: e.hp = 0; e.disint = true
		if S.mind and not e.boss and not e.civ and e.hp > 0 and randf() < S.mind * pf: make_minion(e); return
		if S.chain and o.get("chainable", true): chain_from(e, D.dmg * 0.6 * S.chainMul * o.get("mul", 1.0))
	if e.hp <= 0: kill(e)

const RAD_MAX := 12
## Uranium Slugs: each hit adds radiation dose. A full dose melts down: a burst on the cop, and its neighbours catch a third of the dose.
func irradiate(e: Enemy, dose: int) -> void:
	if e.dead or e.ally: return
	e.rad_s = mini(RAD_MAX, e.rad_s + dose); e.rad_t = 6.0
	if e.rad_s < RAD_MAX: return
	e.rad_s = 0; e.rad_t = 0.0
	poof(e.x, e.y, Color("#b6ff3a"), 14, 110); snd("zap")
	for o in live_foes():
		if o != e and not o.civ and Vector2(o.x - e.x, o.y - e.y).length_squared() < 70.0 * 70.0: irradiate(o, RAD_MAX / 3)
	hit(e, (20.0 + Run.D.dmg * 2.0) * Run.S.radMul, {"col": Color("#b6ff3a"), "element": "radiation"})

func chain_from(src: Enemy, dmg: float) -> void:
	var cur := src; var done := {src: true}
	for i in int(Run.S.chain):
		var best: Enemy = null; var bd := 150.0 * 150.0
		for e in enemies:
			if e.dead or e.ally or done.has(e): continue
			var d := (e.x - cur.x) * (e.x - cur.x) + (e.y - cur.y) * (e.y - cur.y)
			if d < bd: bd = d; best = e
		if best == null: break
		done[best] = true; arcs.append({"x1": cur.x, "y1": cur.y, "x2": best.x, "y2": best.y, "t": 0.15})
		hit(best, dmg, {"col": Color("#fff36b"), "element":"lightning"}); cur = best
	if done.size() > 1: snd("zap")

func explode(x: float, y: float, dmg: float, rad: float, col: Color) -> void:
	booms.append({"x": x, "y": y, "r": rad, "t": 0.3, "col": col})
	if rad > 20.0:
		decals.append({"x": x, "y": y, "r": minf(rad * 0.6, 70.0), "t": 22.0, "a": randf() * TAU})
		if decals.size() > 40: decals.pop_front()
	poof(x, y, col, 14, rad * 3, 5); shake = maxf(shake, 3); snd("boom")
	Controls.rumble(0.2, 0.3, 90)
	SceneryDamage.blast(self, Vector2(x, y), dmg, rad)
	if dmg > 0.0:
		for b in ebul:
			if b.get("seeker",false) and Vector2(x,y).distance_to(Vector2(b.x,b.y)) < rad + b.r: Viper.destroy(self,b)
	for e in enemies.duplicate():
		if e.dead or e.ally: continue
		if (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y) < (rad + e.r) * (rad + e.r): hit(e, dmg, {"col": Color("#ffa030")})

func detonate() -> void:
	if mines.is_empty(): return
	var S := Run.S
	var ms := mines.duplicate(); mines.clear()
	for m in ms: explode(m.x, m.y, (Run.D.dmg * 2.5 + 10) * S.boomMul, 70.0 * sqrt(S.boomMul), Color("#ff5030"))

func make_minion(e: Enemy) -> void:
	e.ally = true; e.ally_t = Run.S.mindDur; e.frozen_t = 0; e.burn_t = 0; e.chill = 0; e.poison_s = 0; e.bleed_s = 0; e.sick_t = 0; e.acid_t = 0; e.bomb_t = 0; e.rad_s = 0; e.rad_t = 0.0
	e.hp = maxf(e.hp, e.max_hp * 0.6); e.atk_cd = 0
	add_num(e.x, e.y - 26, "MINION!", Color("#d07bff"), true); poof(e.x, e.y, Color("#d07bff"), 10, 80); snd("mind")

func kill(e: Enemy) -> void:
	if e.dead: return
	e.dead = true; Run.kills += 1
	var S := Run.S
	if e.bomb_t > 0: explode(e.x, e.y, e.bomb_dmg, 65.0 * sqrt(S.boomMul), Color("#ff5030"))
	if e.disint:
		poof(e.x, e.y, Color("#ff4a2a"), 16, 120, 4); poof(e.x, e.y, Color("#555555"), 12, 60, 5); add_num(e.x, e.y - 20, "VAPORIZED", Color("#ff6a4a"), false)
	elif e.frozen_t > 0: poof(e.x, e.y, Color("#bff4ff"), 14, 140, 4)
	else: poof(e.x, e.y, Color("#9acd32") if e.sick_t > 0 else Color("#cc3333"), 8, 100, 3)
	if e.sick_t > 0:
		for o in enemies:
			if not o.dead and not o.ally and o != e and (o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y) < 70 * 70: o.sick_t = maxf(o.sick_t, 4)
		poof(e.x, e.y, Color("#b0e040"), 10, 80, 5)
	if e.civ:
		var cash := (5.0 + Run.wave * 1.0) * e.rich
		for i in 3: pickups.append({"x": e.x, "y": e.y, "v": cash / 3.0, "vx": randf_range(-90, 90), "vy": randf_range(-90, 90), "cash": 1})
		add_num(e.x, e.y - 24, "$$$", Color("#5aff7a"), true)

	elif e.boss or randf() < Run.drop_chance():   # Brotato-style loot roll (Run.drop_chance); bosses always drop
		var v: float = 40.0 + Run.wave * 5.0 if e.boss else e.scrap * Run.kill_scrap_mult() * Run.drop_value_mult()
		var n := 24 if e.boss else clampi(int(e.scrap), 1, 4)
		for i in n: pickups.append({"x": e.x + randf_range(-8, 8), "y": e.y + randf_range(-8, 8), "v": v / n, "vx": randf_range(-60, 60), "vy": randf_range(-60, 60), "mag": false})
	if e.boss:
		if e.hero == "vex": preload("res://game/rival_scientist.gd").cleanup(e)
		BossAbilities.drop_rewards(self, e.hero, Vector2(e.x,e.y), randf())
		if e.hero == "viper":
			for b in ebul:
				if b.get("seeker", false): Viper.destroy(self,b)
		boss = null; shake = 14; explode(e.x, e.y, 0, 120, Color("#ffd23c")); banner_txt = e.hero_name + " DEFEATED!"; banner_t = 1.8
		Controls.rumble(0.8, 1.0, 500)
		var got: Array = Run.note_boss_defeated(Run.wave)   # meta unlocks (game/unlocks.gd)
		if not got.is_empty(): banner_txt += "  ·  🔓 UNLOCKED: " + ", ".join(got.map(Run.part_name))
	snd("bosskill" if e.boss else "kill")

func drop_blueprint(id: String, pos: Vector2) -> void:
	if Run.unlocks.is_unlocked("item", id) or pickups.any(func(p): return p.get("blueprint", "") == id): return
	pickups.append({"x":pos.x, "y":pos.y, "v":0.0, "vx":0.0, "vy":0.0, "age":0.0, "blueprint":id})

func _collect_blueprint(p: Dictionary) -> void:
	if Run.unlocks.collect_blueprint(p.blueprint):
		banner_txt = "%s UNLOCKED!" % Run.ITEM[p.blueprint].name.to_upper()
		banner_t = 2.0; snd("crate"); p.collected = true
	elif Run.unlocks.is_unlocked("item", p.blueprint): p.collected = true

func damage_case(p: Dictionary, amount: float) -> void:
	if amount <= 0 or p.get("broken", false): return
	p.hp = maxf(0, p.hp - amount)
	var center: Vector2 = p.rect.get_center()
	if p.hp > 0: return
	arena_level.shatter_case(p)
	poof(center.x, center.y, Color("#a7efff"), 26, 150, 3); snd("break")
	add_num(center.x, center.y - 35, "SHATTERED!", Color("#a7efff"), true)
	for i in 3:
		pickups.append({"x":center.x + (i - 1) * 12, "y":p.rect.end.y + 18, "v":4.0, "vx":randf_range(-25, 25), "vy":20.0, "gem":true})
	# One hidden research cache per museum; subsequent museums can reveal the other designs.
	if int(p.variant) == 1:
		var candidates: Array = ["disint", "zero", "moon"].filter(func(id): return not Run.unlocks.is_unlocked("item", id) and not pickups.any(func(pickup): return pickup.get("blueprint", "") == id))
		if not candidates.is_empty(): drop_blueprint(candidates.pick_random(), Vector2(center.x, p.rect.end.y + 40))

func _damage_prop_ray(start: Vector2, finish: Vector2, amount: float, kind: String, pfm := 1.0, player_shot := true) -> void:
	var closest := 2.0; var target: Dictionary = {}; var point := finish
	for wall in _wall_index.query(Rect2(start, Vector2.ZERO).expand(finish).grow(1)):
		if wall.open: continue
		var contact := ShotGeometry.rect_entry(start, finish, wall.rect)
		if not contact.is_empty() and contact.fraction < closest:
			closest = contact.fraction; target = wall; point = start.lerp(finish, closest)
	SceneryDamage.weapon_hit(self, target, amount, kind, point, pfm, player_shot)

# =============== FIRING ===============
## (bx, by) = shoulder end: hits are measured from there so point-blank enemies can't hide inside the barrel.
func fire_gun(type: String, ang: float, mul: float, ox: float, oy: float, sus, bx: float, by: float, source: int = UNBOUND_SHOT) -> void:
	var S := Run.S; var D := Run.D
	var n: int = D.shots
	var spr := minf(1.2, (S.spread if S.spread else 0.14) * (n - 1) / 2.0 + 0.1 * (n - 1)) if n > 1 else 0.0
	var dmg: float = D.dmg * mul
	var charge := 0.0
	if type == "laser" and Run.CNT.get("capacitor",0)>0 and (sus == null or sus.tick):
		charge = laser_charge_ratio(source)
		laser_charge[source] = 0.0   # spend once per volley, so all split nozzles get the same bonus
		dmg *= 1.0 + CAPACITOR_BONUS * charge
	if sus != null: dmg *= (0.1 / D.cd) * (1.15 + 0.15 * (S.sustain - 1))   # per 0.1 s tick
	for i in n:
		if source!=UNBOUND_SHOT:
			var muzzle = _shot_muzzle(source,i); ox = muzzle.x; oy = muzzle.y
		var a := ang + ((-spr / 2.0 + spr * i / (n - 1)) if n > 1 else 0.0) + (randf_range(-0.03, 0.03) if type != "laser" else 0.0)
		var cx := cos(a); var sy := sin(a)
		var color = Color("#ff4a4a") if type=="laser" else (Color("#ffd76a") if type=="bullet" else Color("#dfe6ec"))
		if charge>0.0: color = color.lerp(Color("#fff0b0"), charge * 0.8)
		# A long barrel may visually extend beyond a vault wall. It must not spawn
		# a shot on the far side of that wall or sweep point-blank damage through it.
		var barrel = Vector2(ox-bx,oy-by)
		if not walls.is_empty() and barrel.length_squared()>0.0001:
			var direction = barrel.normalized()
			var clear_length = ray_len(bx,by,direction.x,direction.y,barrel.length())
			if clear_length<barrel.length()-0.001:
				if sus==null or sus.tick: blaster_fx.impact(Vector2(bx,by)+direction*clear_length,-direction,color,sus!=null)
				if sus==null or sus.tick: _damage_prop_ray(Vector2(bx,by), Vector2(ox,oy), dmg, type, 0.1 / D.cd if sus != null else 1.0)
				continue
		if sus==null or sus.tick: blaster_fx.muzzle(Vector2(ox,oy),Vector2(cx,sy),color,sus!=null)
		# Lasers fire bolts (stop at the first cop) until a Focusing Lens (S.beam) makes them piercing beams.
		# Sustained beams only exist with the lens (the shop requires it).
		if type == "laser" and (S.beam or sus != null):
			var length := ray_len(ox, oy, cx, sy, D.range); var x2 := ox + cx * length; var y2 := oy + sy * length
			var w: float = D.width * ((0.85 + 0.15 * sin(time * 40)) if sus != null else 1.0)
			var lifetime = 0.05 if sus!=null else 0.12
			var beam = {"x1":ox,"y1":oy,"x2":x2,"y2":y2,"w":w,"t":lifetime,"m":lifetime,"col":color,"sus":sus!=null,"source":source,"shot":i,"angle_offset":a-ang,"range":float(D.range),"fresh":true}
			var existing = -1
			if sus!=null and source!=UNBOUND_SHOT:
				existing = beams.find_custom(func(b): return b.sus and b.source==source and b.shot==i)
			if existing>=0: beams[existing] = beam
			else: beams.append(beam)
			if sus != null and not sus.tick: continue
			_damage_prop_ray(Vector2(ox, oy), Vector2(ox, oy) + Vector2(cx, sy) * D.range, dmg, "laser", 0.1 / D.cd if sus != null else 1.0)
			Viper.intercept(self, Vector2(ox,oy), Vector2(x2,y2), w * 0.5)
			var impact_distance: float = length if length<D.range else INF
			var back := Vector2(ox - bx, oy - by).length()
			for e in enemies.duplicate():
				if e.dead or e.ally: continue
				var px: float = e.x - bx; var py: float = e.y - by; var proj: float = px * cx + py * sy
				var touching := touching_body(e, cx, sy)
				if not touching and (proj < -e.r or proj > back + length + e.r): continue
				var perp := absf(px * sy - py * cx)
				if touching or perp <= w / 2.0 + e.r:
					impact_distance = minf(impact_distance,maxf(0.0,Vector2(e.x-ox,e.y-oy).dot(Vector2(cx,sy))-e.r))
					if sus != null: hit(e, dmg, {"proc": true, "mul": mul, "pfm": 0.1 / D.cd, "silent": randf() < 0.6, "col": Color("#ff9a9a")})
					else: hit(e, dmg, {"proc": true, "kx": cx * 0.3, "ky": sy * 0.3, "mul": mul})
			if is_finite(impact_distance): blaster_fx.impact(Vector2(ox,oy)+Vector2(cx,sy)*impact_distance,-Vector2(cx,sy),color,sus!=null)
			if sus != null and randf() < 0.5:
				var k := randf() * length
				part(x2 - cx * k, y2 - sy * k, randf_range(-30, 30), randf_range(-30, 30), 0.2, Color("#ff8a8a"), 2)
		else:
			var ptype := "bolt" if type == "laser" else type   # laser bolt: fastest projectile, red, no ricochet
			var sp := 620.0 if type == "bullet" else (900.0 if ptype == "bolt" else 380.0)
			var r: float = maxf(3.0, D.width / 3.5) if type != "razor" else maxf(6.0, D.width / 2.2)
			var pr := {"type": ptype, "x": ox, "y": oy, "vx": cx * sp, "vy": sy * sp, "r": r, "dmg": dmg, "mul": mul, "pierce": int(S.pierce),
				"life": D.range / sp * (1.6 if type == "razor" else 1.0), "hit": {}, "spin": 0.0, "bounces": 2 if type == "razor" else 0,
				"trail":PackedVector2Array([Vector2(ox,oy)]),"color":color,"source":source,"shot":i}
			# point-blank sweep: shoulder -> muzzle
			var back := Vector2(ox - bx, oy - by).length()
			var near := enemies.filter(func(e):
				if e.dead or e.ally: return false
				var px: float = e.x - bx; var py: float = e.y - by; var proj := px * cx + py * sy
				return touching_body(e, cx, sy) or (proj > -e.r and proj < back + e.r and absf(px * sy - py * cx) <= r + e.r))
			near.sort_custom(func(p, q): return (p.x - bx) * cx + (p.y - by) * sy < (q.x - bx) * cx + (q.y - by) * sy)
			for e in near:
				pr.hit[e] = true; hit(e, dmg, {"proc": true, "kx": cx * 0.4, "ky": sy * 0.4, "mul": mul})
				blaster_fx.impact(Vector2(e.x,e.y),-Vector2(cx,sy),color)
				if type == "razor": poof(e.x, e.y, Color("#c01828"), 3, 60, 2)
				pr.pierce -= 1
				if pr.pierce < 0: pr.life = 0.0; break
			if pr.life > 0: projs.append(pr)
	if sus != null:
		if sus.tick: snd("hum")
	elif type == "laser": snd("las")
	elif type == "bullet": snd("bul")
	else: snd("raz")

## Point-blank rule: a foe pressed against the villain's body on the side the shot goes is always hit, even
## when it sits behind the shoulder/barrel line (small fast K9s used to hide there and chew through you).
const BODY_HIT_PAD := 8.0
func touching_body(e: Enemy, cx: float, sy: float) -> bool:
	var dx: float = e.x - P.x; var dy: float = e.y - P.y
	var reach: float = P.r + e.r + BODY_HIT_PAD
	var d2 := dx * dx + dy * dy
	if d2 > reach * reach: return false
	return dx * cx + dy * sy >= -0.35 * sqrt(d2)   # in front of / beside the body, not behind it

func _shot_muzzle(source: int, shot_index: int = -1) -> Vector2:
	return villain.off_muzzle_global(shot_index) if source==OFF_HAND else villain.muzzle_global(source,shot_index)

func _refresh_beams() -> void:
	# Beam visuals stay on the rendered muzzle through walk bob, recoil, turns and hurt poses.
	# Only fire_gun applies damage; refreshing a fading pulse never applies another hit.
	for beam in beams:
		if beam.source==UNBOUND_SHOT: continue
		var origin = _shot_muzzle(beam.source,beam.shot)
		var angle = (villain.off_aim if beam.source==OFF_HAND else villain.aim)+beam.angle_offset
		var direction = Vector2.from_angle(angle)
		var length = ray_len(origin.x,origin.y,direction.x,direction.y,beam.range)
		beam.x1 = origin.x; beam.y1 = origin.y
		beam.x2 = origin.x+direction.x*length; beam.y2 = origin.y+direction.y*length

func _sync_beam_views() -> void:
	var count = mini(beams.size(),128)
	while _beam_views.size()<count:
		var visual = BeamView.new(); beam_layer.add_child(visual); _beam_views.append(visual)
	for i in _beam_views.size():
		if i>=count: _beam_views[i].visible = false; continue
		var beam: Dictionary = beams[i]
		_beam_views[i].configure(Vector2(beam.x1,beam.y1),Vector2(beam.x2,beam.y2),beam.w,beam.col,beam.t/beam.m,time,Run.S)

func laser_charge_ratio(source: int = 0) -> float:
	if Run.CNT.get("capacitor",0)==0: return 0.0
	return clampf(float(laser_charge.get(source,0.0)) / CAPACITOR_TIME,0.0,1.0)

func laser_charge_display(off := false) -> float:
	if off: return laser_charge_ratio(OFF_HAND)
	var charge := 0.0
	for i in Run.S.guns.size():
		if Run.S.guns[i]=="laser": charge = maxf(charge,laser_charge_ratio(i))
	return charge

func _fire_weapons(dt: float, firing: bool, firing_off: bool) -> void:
	var events: Array = []
	var guns: Array = Run.S.guns
	if Run.CNT.get("capacitor",0)>0:
		for i in guns.size():
			if guns[i]=="laser" and not firing: laser_charge[i] = minf(CAPACITOR_TIME,float(laser_charge.get(i,0.0))+dt)
		if Run.build.off!=null and Run.build.off.get("kind","gun")=="gun" and Run.ammo_id(Run.build.off.ammo)=="laser" and not firing_off:
			laser_charge[OFF_HAND] = minf(CAPACITOR_TIME,float(laser_charge.get(OFF_HAND,0.0))+dt)
	else: laser_charge.clear()
	for i in guns.size():
		gun_cd[i] -= dt; gun_flashes[i] = maxf(0.0,gun_flashes[i]-dt)
		if guns[i]=="hook": continue   # the grapple is driven by game/grapple.gd below
		if Run.S.sustain and guns[i]=="laser":
			if firing:
				var tick = not _main_trigger_held
				if tick: beam_tick[i] = 0.1
				else:
					beam_tick[i] -= dt
					tick = beam_tick[i]<=0.000001
					if tick: beam_tick[i] += 0.1
				events.append({"source":i,"type":"laser","mul":1.0 if i==0 else 0.7,"sustain":{"tick":tick}})
				gun_flashes[i] = 0.05
				if i==0: P.flash_t = 0.05; P.recoil = maxf(P.recoil,0.35)
				if tick: Controls.rumble(0.08,0.0,100)
		elif firing and gun_cd[i]<=0.0:
			gun_cd[i] = Run.D.cd*(1.0 if i==0 else 1.08); gun_flashes[i] = 0.06
			events.append({"source":i,"type":guns[i],"mul":1.0 if i==0 else 0.7,"sustain":null})
			if i==0: P.recoil = 1.0; P.flash_t = 0.06
			Controls.rumble(0.0,0.18,40)
	if Run.build.off!=null and Run.build.off.get("kind","gun")=="gun":
		P.off_cd -= dt
		if firing_off and P.off_cd<=0.0:
			P.off_cd = Run.D.cd*1.15; P.recoil2 = 1.0; P.flash_t2 = 0.06
			events.append({"source":OFF_HAND,"type":Run.ammo_id(Run.build.off.ammo),"mul":0.7,"sustain":null})
			Controls.rumble(0.12,0.0,40)
	# Set every recoil first, then sample the exact pose that will be rendered.
	_sync_villain()
	if Run.has_hook():
		var hook_event: String = grapple.update(self,dt,firing,villain.muzzle_global(0),P.aim,Run.D)
		if hook_event=="launch": P.recoil = 1.0; P.flash_t = 0.06; gun_flashes[0] = 0.06; Controls.rumble(0.0,0.25,50)
		elif hook_event=="bite": Controls.rumble(0.25,0.35,90)
	elif grapple.is_out(): grapple.reset()
	for event in events:
		var origin = _shot_muzzle(event.source)
		var back = villain.off_shoulder_global() if event.source==OFF_HAND else villain.gun_back_global(event.source)
		fire_gun(event.type,P.aim+PI if event.source==OFF_HAND else P.aim,event.mul,origin.x,origin.y,event.sustain,back.x,back.y,event.source)
	_main_trigger_held = firing

func _melee_progress() -> float:
	return clampf(1.0-P.melee_t/P.melee_swing,0.0,1.0) if P.melee_t>0.0 else 0.0

func _melee_extension() -> float:
	return sin(_melee_progress()*PI) if P.melee_t>0.0 else 0.0

## Arm angle shown on the villain: arc weapons sweep across their arc during the swing.
func _melee_pose_aim() -> float:
	return P.melee_aim + (_melee_progress()-0.5)*P.melee_arc

const MELEE_COLORS := {"knife":"#e8eef4","katana":"#ff5ad0","whip":"#7df9ff"}

## The bionic arm swings on its own whenever a foe is inside the mounted weapon's reach,
## then waits out that weapon's cooldown. Bare fist by default; knife/whip/katana from the shop.
func _update_melee(dt: float) -> void:
	P.melee_cd = maxf(0.0,P.melee_cd-dt)
	var spec: Dictionary = Run.melee_spec()
	if spec.is_empty(): P.melee_t = 0.0; return
	var origin = villain.off_shoulder_global()
	if P.melee_t>0.0:
		P.melee_t = maxf(0.0,P.melee_t-dt)
		if not P.melee_hit and P.melee_t<=P.melee_swing*0.6:
			P.melee_hit = true
			_melee_strike(spec,origin)
	elif P.melee_cd<=0.0:
		var target = _melee_target(origin,float(spec.reach)+14.0)
		if target!=null:
			P.melee_aim = (Vector2(target.x,target.y)-origin).angle()
			P.melee_swing = float(spec.swing); P.melee_arc = float(spec.arc) if float(spec.arc)>1.0 else 0.0
			P.melee_t = P.melee_swing; P.melee_cd = float(spec.cd); P.melee_hit = false

func _melee_target(origin: Vector2, max_d: float) -> Enemy:
	var best: Enemy = null; var best_d := max_d*max_d
	for e in enemies:
		if e.dead or e.ally or e.civ: continue
		var d := origin.distance_squared_to(Vector2(e.x,e.y))
		if d<best_d: best_d = d; best = e
	return best

func _melee_strike(spec: Dictionary, origin: Vector2) -> void:
	var direction = Vector2.from_angle(P.melee_aim)
	var reach: float = spec.reach; var color := Color(MELEE_COLORS.get(spec.get("kind",""),"#7defff"))
	var victims: Array = []
	for enemy in live_foes():
		if enemy.civ: continue
		var delta = Vector2(enemy.x,enemy.y)-origin; var distance: float = delta.length()
		if distance>reach+enemy.r: continue
		var tolerance = float(spec.arc)*0.5 + asin(minf(1.0,enemy.r/maxf(distance,1.0)))
		if absf(wrapf(delta.angle()-P.melee_aim,-PI,PI))>tolerance: continue
		if ray_len(origin.x,origin.y,delta.normalized().x,delta.normalized().y,distance)<distance-0.01: continue
		victims.append([distance,enemy])
	victims.sort_custom(func(a,b): return a[0]<b[0])
	var damage: float = float(spec.dmg)+Run.D.dmg*float(spec.scale)
	for pair in victims.slice(0,int(spec.targets)):
		var enemy: Enemy = pair[1]
		var point = Vector2(enemy.x,enemy.y)
		hit(enemy,damage,{"col":color,"proc":spec.get("proc",false)})
		if not enemy.heavy and float(spec.knock)>0.0:
			var push = (point-origin).normalized()*float(spec.knock); enemy.kx += push.x; enemy.ky += push.y
		if spec.has("stun") and not enemy.boss and not enemy.dead: enemy.time_lock = maxf(enemy.time_lock,float(spec.stun))
		blaster_fx.impact(point,-direction,color)
	if spec.get("kind","")!="":
		utility_fields.append({"kind":"slash","weapon":spec.kind,"position":origin,"radius":reach,"aim":P.melee_aim,"arc":maxf(float(spec.arc),0.12),"time":0.18,"life":0.18,"col":color})
	if not victims.is_empty(): snd("pick"); Controls.rumble(0.2,0.1,50)

## Swing trail: a crescent for blades, a crackling line for the whip.
func _draw_slash(g: Node2D, field: Dictionary, fade: float) -> void:
	var color: Color = field.col; var center: Vector2 = field.position; var reach: float = field.radius
	if field.weapon == "whip":
		var direction := Vector2.from_angle(field.aim); var side := direction.orthogonal()
		var points := PackedVector2Array()
		for i in 13:
			var u := i/12.0
			points.append(center+direction*reach*u+side*sin(u*TAU*1.5+time*40.0)*6.0*u)
		g.draw_polyline(points,Color(color,0.85*fade),3.0)
		g.draw_circle(points[points.size()-1],5.0*fade+1.0,Color(1,1,1,fade))
		return
	var half: float = field.arc*0.5
	for band in 3:
		var radius := reach-band*5.0
		g.draw_arc(center,radius,field.aim-half,field.aim+half,24,Color(color,(0.75-band*0.22)*fade),4.0-band)

func _update_helmet(dt: float) -> void:
	if Run.CNT.get("tesla_helmet", 0) == 0: return
	P.helmet_cd = maxf(0, P.helmet_cd - dt)
	if P.helmet_cd > 0: return
	var candidates := enemies.filter(func(e): return not e.dead and not e.ally and not e.civ and Vector2(e.x - P.x, e.y - P.y).length_squared() <= 110.0 * 110.0)
	var origin := Vector2(P.x, P.y)
	var source := villain.anchor("helmet")
	var used := false
	for jump in 3:
		var target: Enemy = null; var distance := INF
		for e in candidates:
			var point := Vector2(e.x, e.y); var d := origin.distance_to(point)
			if d < distance and (jump == 0 or d <= 80) and nav.clear_segment(origin, point, 0): target = e; distance = d
		if target == null: break
		candidates.erase(target)
		arcs.append({"x1":source.x, "y1":source.y, "x2":target.x, "y2":target.y - 10, "t":0.18, "col":Color("#90dfff")})
		hit(target, 3.0, {"col":Color("#9cdeff"), "element":"lightning"})
		origin = Vector2(target.x, target.y); source = origin - Vector2(0, 10); used = true
	if used: P.helmet_cd = 1.5; snd("zap")

func _update_utility(dt: float) -> void:
	for kind in Run.arm_cooldowns: Run.arm_cooldowns[kind] = maxf(0.0,Run.arm_cooldowns[kind]-dt)
	if Run.build.off==null: return
	var kind: String = Run.build.off.get("kind","gun")
	if kind=="gun" or Run.arm_cooldowns.get(kind,1.0)>0.0: return
	if kind=="seeker_rack":
		if BossAbilities.launch_rockets(self): Run.arm_cooldowns[kind] = 5.0
		return
	var center = Vector2(P.x,P.y)
	var radius = 240.0 if kind=="time_freeze" else 140.0*sqrt(Run.S.boomMul)
	if nearest_foe(P.x,P.y,radius)==null and not Controls.firing_off(): return
	if kind=="time_freeze":
		Run.arm_cooldowns[kind] = 15.0
		for enemy in live_foes():
			if center.distance_to(Vector2(enemy.x,enemy.y))<=radius+enemy.r: enemy.time_lock = maxf(enemy.time_lock,1.0 if enemy.boss else 2.8)
		for bullet in ebul:
			if center.distance_to(Vector2(bullet.x,bullet.y))<=radius: bullet.time_lock = 2.8
		utility_fields.append({"kind":kind,"position":center,"radius":radius,"time":2.8,"life":2.8})
		snd("frz")
	else:
		Run.arm_cooldowns[kind] = 12.0
		explode(P.x,P.y,(24.0+Run.D.dmg)*Run.S.boomMul,radius,Color("#ff8060"))
		utility_fields.append({"kind":kind,"position":center,"radius":radius,"time":0.45,"life":0.45})
	Controls.rumble(0.35,0.45,180)


# =============== SPAWNING ===============
func pick_type() -> String:
	var w := Run.wave; var tbl := []; var tot := 0.0
	for row in Run.SPAWN_TABLE:
		var wt: float = (row[1] + row[3] * w) if w + int(Run.tier("unlock")) >= row[2] else 0.0
		var themes: Array = Run.ET[row[0]].get("themes", [])
		if not themes.is_empty() and not themes.has(level): wt = 0.0
		var limit := int(Run.ET[row[0]].get("max_alive", 9999))
		var present := enemies.filter(func(e): return not e.dead and e.type == row[0]).size() + markers.filter(func(m): return m.type == row[0]).size()
		if present >= limit: wt = 0.0
		tbl.append([row[0], wt]); tot += wt
	var r := randf() * tot
	for t in tbl:
		r -= t[1]
		if t[1] > 0.0 and r <= 0: return t[0]
	return "cop"

## A free spot in the arena at least `radius_min` from the villain (index.html spawnGroup).
func _outside_spawn(radius_min: float = 260.0) -> Vector2:
	if heist.active: return heist.spawn_point(self, radius_min)
	var point := Vector2(P.x, P.y)
	for attempt in 40:
		point = Vector2(randf_range(60, AW - 60), randf_range(60, AH - 60))
		if point.distance_squared_to(Vector2(P.x, P.y)) >= radius_min * radius_min and not in_wall(point.x, point.y, 28): return point
	return point

func spawn_group() -> void:
	var cap := 30 + Run.wave * 5
	if enemies.filter(func(enemy): return not enemy.dead).size() >= cap: return
	var point := _outside_spawn()
	var count := randi_range(1, 3) + floori(Run.wave / 4.0)
	var type := pick_type()
	count = mini(count, int(Run.ET[type].get("group_size", 99)))
	count = mini(count, cap - enemies.filter(func(e): return not e.dead).size() - markers.size())
	for i in count:
		var unit_type := type
		if type == "swat_shield" and i > 0: unit_type = "swat"
		var radius := float(Run.ET[unit_type].r)
		var pos := point
		var valid := false
		for tr in 40:
			pos = (point + Vector2(randf_range(-65, 65), randf_range(-65, 65))).clamp(Vector2.ONE * (radius + 5), Vector2(AW - radius - 5, AH - radius - 5))
			if not in_wall(pos.x, pos.y, radius + 3) and pos.distance_to(Vector2(P.x, P.y)) > 230:
				valid = true; break
		if valid: markers.append({"x": pos.x, "y": pos.y, "t": 1.3 if radius > 25 else 0.9, "type": unit_type})

# =============== UPDATE ===============
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if state == "over": return
	time += dt
	if banner_t > 0: banner_t -= dt
	lights.begin()
	if state == "clear":
		clear_t -= dt
		for p in pickups:
			p.age = p.get("age", 0.0) + dt
			if p.has("blueprint"):
				if Vector2(P.x - p.x, P.y - p.y).length() < 24: _collect_blueprint(p)
				continue
			var dv := Vector2(P.x - p.x, P.y - p.y); var d := maxf(0.001, dv.length())
			p.x += dv.x / d * 700 * dt; p.y += dv.y / d * 700 * dt
			if d < 16: gain_scrap(p.v); p.v = 0.0
		pickups = pickups.filter(func(p): return not p.get("collected", false) and (p.has("blueprint") or p.v > 0))
		_update_fx(dt); _sync(dt)
		if clear_t <= 0:
			for p in pickups:
				if not p.has("blueprint"): gain_scrap(p.v)
			for c in crates: gain_scrap(c.v)
			pickups = pickups.filter(func(p): return p.has("blueprint")); crates.clear(); state = "done"; cleared.emit()
		return
	if state != "play": return
	_update_play(dt)
	if state == "play" or state == "clear": _update_fx(dt)
	_sync(dt)

func _update_play(dt: float) -> void:
	var S := Run.S; var D := Run.D
	wave_t -= dt
	if siren_t > 0: siren_t -= dt
	if wave_t <= 0: wave_t = 0; end_wave(); heist.timeout(self); return
	if heist.update(self, dt): return
	bank_vault.update(self, dt)
	SceneryDamage.tick(self, dt)
	if state != "play": return
	heal_budget = minf(6.0, heal_budget + dt * 4.0)
	# ---- movement: left stick or WASD ----
	var mv := Controls.move_vec()
	var ml := minf(1.0, mv.length()); P.moving = ml > 0.0
	var action := Run.equipped_action()
	if action != "" and Input.is_action_just_pressed("boss_action"): BossAbilities.start_action(self,action)
	var acting := not boss_move.is_empty()
	BossAbilities.update_action(self,dt)
	if ml > 0.0 and not acting:
		var k := ml * (0.55 if P.slow_t > 0 else 1.0)
		P.x += mv.normalized().x * k * D.speed * dt; P.y += mv.normalized().y * k * D.speed * dt
		P.walk += dt * 10.0 * k * (D.speed / 150.0); P.idle_t = 0.0
	else: P.idle_t += dt
	P.x = clampf(P.x, 28, AW - 28); P.y = clampf(P.y, 28, AH - 28)
	if not walls.is_empty(): collide_walls(P, P.r)
	if P.inv > 0: P.inv -= dt
	if P.slow_t > 0: P.slow_t -= dt
	P.hp = minf(D.maxHp, P.hp + S.regen * dt)
	# ---- aim: right stick ONLY on a controller (idle stick keeps the last aim), else the mouse ----
	var ang := P.aim
	var rs := Controls.aim_stick()
	if rs != Vector2.ZERO: ang = rs.angle()
	elif Controls.aim_src == "mouse":
		var s0 := villain.shoulder_global(); var mp := get_global_mouse_position()
		ang = atan2(mp.y - s0.y, mp.x - s0.x)
	var firing := Controls.firing()
	var rear_firing: bool = Controls.firing_off() and Run.build.off != null and Run.build.off.get("kind","gun") == "gun"
	consumables.tick(self, dt, firing or rear_firing)
	P.firing_t = 0.2 if firing else P.firing_t - dt
	var da := wrapf(ang - P.aim, -PI, PI); P.aim += da * minf(1.0, dt * 20.0)
	P.recoil = maxf(0.0, P.recoil - dt * 9.0); P.flash_t -= dt
	if P.zap_t > 0: P.zap_t -= dt
	P.recoil2 = maxf(0.0,P.recoil2-dt*9.0); P.flash_t2 -= dt
	var firing2 = Run.build.off!=null and Run.build.off.get("kind","gun")=="gun" and (Controls.firing_off() or firing)
	P.firing2_t = 0.2 if firing2 else P.firing2_t-dt
	_fire_weapons(dt,firing,firing2)
	if P.disguise_t <= 0.0: _update_melee(dt)
	if P.disguise_t <= 0.0: _update_utility(dt)
	if P.disguise_t <= 0.0: _update_helmet(dt)
	# ---- orbs ----
	orb_a += dt * 3.0
	if S.orbs:
		for i in int(S.orbs):
			var a: float = orb_a + i * TAU / S.orbs; var ox := P.x + cos(a) * 62; var oy := P.y + sin(a) * 62
			for e in enemies.duplicate():
				if e.dead or e.ally or e.orb_cd > 0: continue
				if (e.x - ox) * (e.x - ox) + (e.y - oy) * (e.y - oy) < (12 + e.r) * (12 + e.r):
					e.orb_cd = 0.45; hit(e, 6.0 + D.dmg * 0.45, {"col": Color("#b4ff3c")})
	# ---- moon laser ----
	if S.moon:
		moon_t -= dt
		if moon_t <= 0:
			moon_t = 3.0 / S.moon; var fs := live_foes()
			if fs.size() > 0:
				var e: Enemy = fs.pick_random(); strikes.append({"x": e.x, "y": e.y, "t": 0.55, "done": false, "fade": 0.0})
	for s in strikes:
		s.t -= dt
		if s.t <= 0 and not s.done:
			s.done = true; s.fade = 0.3; shake = maxf(shake, 5); snd("moon"); Controls.rumble(0.3, 0.5, 150)
			for e in enemies.duplicate():
				if not e.dead and not e.ally and (e.x - s.x) * (e.x - s.x) + (e.y - s.y) * (e.y - s.y) < (55 + e.r) * (55 + e.r): hit(e, 30.0 + D.dmg * 4.0, {"col": Color("#fff6a0")})
		if s.done: s.fade -= dt
	strikes = strikes.filter(func(s): return not s.done or s.fade > 0)
	# ---- mines ----
	if mines.size() > 0: mine_t += dt
	else: mine_t = 0.0
	if Input.is_action_just_pressed("detonate") and mines.size() > 0: detonate()
	# ---- spawning ----
	spawn_t -= dt
	if spawn_t <= 0:
		spawn_t = maxf(0.5, 1.7 - Run.wave * 0.06) * randf_range(0.7, 1.3) / Run.spawn_mult()
		spawn_group()
	if Run.boss_for(Run.wave) != null and boss == null and wave_t < wave_dur - 3 and not enemies.any(func(e): return e.boss) and not P.boss_spawned:
		P.boss_spawned = true
		markers.append({"x": AW - 150.0 if P.x < AW / 2.0 else 150.0, "y": AH / 2.0, "t": 1.4, "type": "boss"})
	# ---- civilians wander in, panic, drop cash when hit and escape at the edges ----
	if true:
		civ_t -= dt
		if civ_t <= 0:
			civ_t = randf_range(4, 8)
			if enemies.filter(func(e): return e.civ and not e.dead).size() < 6:
				var n := randi_range(1, 2); var x := 0.0; var y := 0.0; var tr := 0
				while true:
					var point = _outside_spawn(300); x = point.x; y = point.y; tr += 1
					if Vector2(x - P.x, y - P.y).length() >= 300 or tr >= 20: break
				for i in n: make_enemy("civ", x + randf_range(-30, 30), y + randf_range(-30, 30))
	for nv in novas:
		nv.r += 320 * dt
		if not nv.hit and absf(Vector2(P.x - nv.x, P.y - nv.y).length() - nv.r) < 16:
			nv.hit = true; hurt_player(nv.dmg); P.slow_t = 2.5; add_num(P.x, P.y - 36, "FROZEN!", Color("#9ef0ff"), true)
	novas = novas.filter(func(nv): return nv.r < nv.max)
	for m in markers:
		m.t -= dt
		if m.t <= 0:
			var e := make_enemy(m.type, m.x, m.y)
			if e.boss: boss = e; Controls.rumble(0.5, 0.8, 300)
			poof(m.x, m.y, Color("#4a6ad8"), 6, 60)
	markers = markers.filter(func(m): return m.t > 0)
	# ---- plutonium crates ----
	crate_t -= dt
	if crate_t <= 0:
		crate_t = randf_range(10, 16); var x := 0.0; var y := 0.0; var tr := 0
		while true:
			var point = _outside_spawn(120); x = point.x; y = point.y; tr += 1
			if not in_wall(x,y,24) or tr >= 30: break
		crates.append({"x": x, "y": y, "v": 4 + Run.wave, "t": 0.0, "got": false})
	for c in crates:
		c.t += dt
		if (c.x - P.x) * (c.x - P.x) + (c.y - P.y) * (c.y - P.y) < 30 * 30:
			c.got = true; gain_scrap(c.v); P.hp = minf(D.maxHp, P.hp + D.maxHp * 0.15)
			add_num(c.x, c.y - 20, "+%d ⚙  +HP" % c.v, Color("#b4ff3c"), true); snd("crate"); Controls.rumble(0.2, 0.2, 80)
	crates = crates.filter(func(c): return not c.got)
	_update_enemies(dt)
	if state != "play": return
	_update_projs(dt)
	# ---- enemy bullets ----
	for b in ebul:
		if b.t <= 0.0: continue
		if b.get("seeker",false): Viper.update_missile(self,b,dt); continue
		if b.get("time_lock",0.0)>0.0: b.time_lock = maxf(0.0,b.time_lock-dt); continue
		var old := Vector2(b.x, b.y)
		b.x += b.vx * dt; b.y += b.vy * dt; b.t -= dt
		var motion := Vector2(b.x, b.y) - old
		var wall_distance := ray_len(old.x, old.y, motion.normalized().x, motion.normalized().y, motion.length())
		if wall_distance < motion.length() - 0.001:
			var impact := old + motion.normalized() * wall_distance
			if not b.has("blast"):
				_damage_prop_ray(old, Vector2(b.x, b.y), b.dmg, "laser" if b.get("zap", false) else "bullet", 1.0, false)
				blaster_fx.impact(impact, -motion.normalized(), b.get("col", Color("#ffd76a")))
			b.x = impact.x; b.y = impact.y; b.t = 0.0
		if b.t > 0.0 and (b.x - P.x) * (b.x - P.x) + (b.y - P.y) * (b.y - P.y) < (b.r + P.r) * (b.r + P.r):
			b.t = 0.0
			if not b.has("blast"): hurt_player(b.dmg)
			if b.get("slow", false): P.slow_t = 1.5
			if b.get("zap", false): P.zap_t = 0.6
		if b.t <= 0.0 and b.has("blast"):
			SceneryDamage.blast(self, Vector2(b.x, b.y), b.dmg, b.blast)
			booms.append({"x":b.x, "y":b.y, "r":b.blast, "t":0.3, "col":Color("#ffbd68")})
			poof(b.x, b.y, Color("#ffb35c"), 18, 180); snd("boom"); shake = maxf(shake, 4.0)
			var delta := Vector2(P.x - b.x, P.y - b.y)
			if delta.length() < b.blast + P.r and nav.clear_segment(Vector2(b.x,b.y), Vector2(P.x,P.y),0): hurt_player(b.dmg)
	ebul = ebul.filter(func(b): return b.t > 0 and b.x > 0 and b.y > 0 and b.x < AW and b.y < AH)
	# ---- pickups ----
	for p in pickups:
		if p.has("blueprint"):
			p.age = p.get("age", 0.0) + dt
			if Vector2(P.x - p.x, P.y - p.y).length() < 24: _collect_blueprint(p)
			continue
		p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.9; p.vy *= 0.9; p.age = p.get("age", 0.0) + dt
		var dx: float = P.x - p.x; var dy: float = P.y - p.y; var d := maxf(0.001, sqrt(dx * dx + dy * dy))
		if d < D.pickup: p.mag = true
		if p.get("mag", false):
			var sp: float = 420.0 + (D.pickup - d) * 2.0; p.x += dx / d * sp * dt; p.y += dy / d * sp * dt
		if d < 16:
			gain_scrap(p.v); p.v = 0.0; snd("cash" if p.has("cash") else "pick")
	pickups = pickups.filter(func(p): return not p.get("collected", false) and (p.has("blueprint") or p.v>0))

func _update_enemies(dt: float) -> void:
	for e in enemies.duplicate():
		if e.dead: continue
		e.px = e.x; e.py = e.y
		if not e.boss and not e.ally and Vector2(e.x-P.x,e.y-P.y).length_squared()>1800.0*1800.0:
			e.dead = true; continue
		e.tick(dt)
		if state != "play": return
	# separation
	var list := enemies
	for i in list.size():
		var a := list[i]
		if a.dead: continue
		for j in range(i + 1, list.size()):
			var b := list[j]
			if b.dead: continue
			var dx := b.x - a.x; var dy := b.y - a.y; var rr := a.r + b.r
			if absf(dx) > rr or absf(dy) > rr: continue
			var d2 := dx * dx + dy * dy
			if d2 >= rr * rr or d2 == 0: continue
			var d := sqrt(d2); var push := minf((rr - d) / 2.0, 4.0); var nx := dx / d; var ny := dy / d
			var wa := 0.0 if a.time_lock>0.0 else (0.1 if a.boss else 1.0); var wb := 0.0 if b.time_lock>0.0 else (0.1 if b.boss else 1.0)
			a.x -= nx * push * wa; a.y -= ny * push * wa; b.x += nx * push * wb; b.y += ny * push * wb
	for e in list:
		e.x = clampf(e.x, 20, AW - 20); e.y = clampf(e.y, 20, AH - 20)
		if not walls.is_empty() and not e.fly: collide_walls(e, e.r, Vector2(e.px, e.py))

func _update_projs(dt: float) -> void:
	for projectile in projs:
		if projectile.type == "rocket": BossAbilities.update_rocket(self,projectile,dt); continue
		projectile.life -= dt; projectile.spin += dt*25.0
		if projectile.life<=0.0: continue
		projectile.trail = PackedVector2Array([Vector2(projectile.x,projectile.y)])
		var remaining = dt
		# At most two ricochets plus the final segment in a frame.
		for segment in 3:
			var start = Vector2(projectile.x,projectile.y)
			var velocity = Vector2(projectile.vx,projectile.vy)
			var finish = start+velocity*remaining
			var wall = _projectile_wall_hit(start,finish,projectile.r)
			if not wall.is_empty(): finish = start.lerp(finish,wall.fraction)
			var contacts: Array = []
			for enemy in enemies:
				if enemy.dead or enemy.ally or projectile.hit.has(enemy): continue
				var fraction = ShotGeometry.circle_fraction(start,finish,Vector2(enemy.x,enemy.y),enemy.r+projectile.r)
				if fraction>=0.0: contacts.append({"enemy":enemy,"fraction":fraction})
			for b in ebul:
				if not b.get("seeker",false) or b.t <= 0.0: continue
				var fraction := ShotGeometry.circle_fraction(start,finish,Vector2(b.x,b.y),b.r+projectile.r)
				if fraction >= 0.0: contacts.append({"missile":b,"fraction":fraction})
			contacts.sort_custom(func(a,b): return a.fraction<b.fraction)
			for contact in contacts:
				if contact.has("missile"):
					if contact.missile.t <= 0.0: continue
					Viper.destroy(self,contact.missile); projectile.pierce -= 1
					if projectile.pierce < 0:
						projectile.life = 0.0; finish = start.lerp(finish,contact.fraction); break
					continue
				var enemy: Enemy = contact.enemy
				if enemy.dead or enemy.ally: continue
				var point = start.lerp(finish,contact.fraction)
				projectile.hit[enemy] = true
				var direction = velocity.normalized()
				hit(enemy,projectile.dmg,{"proc":true,"kx":direction.x*0.4,"ky":direction.y*0.4,"mul":projectile.mul})
				blaster_fx.impact(point,-direction,projectile.color)
				projectile.pierce -= 1
				if projectile.pierce<0:
					projectile.life = 0.0; finish = point; break
			projectile.x = finish.x; projectile.y = finish.y; projectile.trail.append(finish)
			if projectile.life<=0.0 or wall.is_empty(): break
			SceneryDamage.weapon_hit(self, wall.get("wall", {}), projectile.dmg, projectile.type, finish)
			blaster_fx.impact(finish,wall.normal,projectile.color)
			if projectile.type!="razor" or projectile.bounces<=0:
				projectile.life = 0.0; break
			velocity = velocity.bounce(wall.normal)
			projectile.vx = velocity.x; projectile.vy = velocity.y; projectile.bounces -= 1
			projectile.x += wall.normal.x*0.5; projectile.y += wall.normal.y*0.5
			remaining *= 1.0-wall.fraction
			if remaining<0.00001: break
	projs = projs.filter(func(p): return p.life>0.0)

func _projectile_wall_hit(start: Vector2, finish: Vector2, radius: float) -> Dictionary:
	var closest: Dictionary = {}
	var delta = finish-start
	# The arena edge is a surface too; clamp ricochets at the surface before reflecting.
	for axis in 2:
		var low = 20.0+radius; var high = (AW if axis==0 else AH)-20.0-radius
		var normal = Vector2.ZERO; var fraction = INF
		if finish[axis]<low:
			normal[axis] = 1.0; fraction = (low-start[axis])/delta[axis] if absf(delta[axis])>0.00001 else 0.0
		elif finish[axis]>high:
			normal[axis] = -1.0; fraction = (high-start[axis])/delta[axis] if absf(delta[axis])>0.00001 else 0.0
		if is_finite(fraction):
			fraction = clampf(fraction,0.0,1.0)
			if closest.is_empty() or fraction<closest.fraction: closest = {"fraction":fraction,"normal":normal}
	for wall in _wall_index.query(Rect2(start,Vector2.ZERO).expand(finish).grow(radius)):
		if wall.open: continue
		var contact = ShotGeometry.rect_entry(start,finish,(wall.rect as Rect2).grow(radius))
		if not contact.is_empty(): contact.wall = wall
		if not contact.is_empty() and (closest.is_empty() or contact.fraction<closest.fraction): closest = contact
	return closest

func _update_fx(dt: float) -> void:
	blaster_fx.update(dt)
	for field in utility_fields: field.time -= dt
	utility_fields = utility_fields.filter(func(field): return field.time>0.0)
	for p in parts: p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.92; p.vy *= 0.92; p.t -= dt
	parts = parts.filter(func(p): return p.t > 0)
	for n in nums: n.t -= dt; n.y -= 40 * dt
	nums = nums.filter(func(n): return n.t > 0)
	for b in beams:
		# A shot emitted this simulation step must survive its first rendered frame,
		# including at 20 FPS where dt equals a sustained beam's fade duration.
		if b.fresh: b.fresh = false
		else: b.t -= dt
	beams = beams.filter(func(b): return b.t > 0)
	for a in arcs: a.t -= dt
	arcs = arcs.filter(func(a): return a.t > 0)
	for d in decals: d.t -= dt
	decals = decals.filter(func(d): return d.t > 0.0)
	for b in booms: b.t -= dt
	booms = booms.filter(func(b): return b.t > 0)
	if shake > 0: shake = maxf(0.0, shake - dt * 30.0)

# =============== SYNC NODES + LIGHTS ===============
func _sync(dt: float) -> void:
	# remove dead enemies
	var alive: Array[Enemy] = []
	for e in enemies:
		if e.dead: e.queue_free()
		else: alive.append(e); e.sync()
	enemies = alive
	_sync_villain()
	_refresh_beams()
	_sync_beam_views()
	# camera
	cam.position = Vector2(P.x, P.y)
	cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	_add_lights()
	ambient_fx.update(dt, cam.get_screen_center_position(), get_viewport_rect().size / cam.zoom / 2.0)
	ground.queue_redraw(); fx_add.queue_redraw(); fx_top.queue_redraw()

func _sync_villain() -> void:
	var lift := sin(clampf(float(boss_move.get("time",0.0)) / 0.65,0.0,1.0) * PI) * 65.0 if boss_move.get("kind","") == "iron_slam" else 0.0
	villain.position = Vector2(roundf(P.x), roundf(P.y - lift))
	villain.visible = P.disguise_t <= 0.0
	villain.set_state({"aim": P.aim, "off_aim": P.aim+PI, "moving": P.moving, "walk_phase": fposmod(P.walk / 8.0, 1.0), "recoil": P.recoil, "flash": P.flash_t,
		"recoil2": P.recoil2, "flash2": P.flash_t2, "firing": P.firing_t > 0, "firing2": P.firing2_t > 0,
		"white": P.inv > 0.3, "zap": P.zap_t > 0,"gun_flashes":gun_flashes,"time":time,"melee_extension":_melee_extension(),"melee_aim":_melee_pose_aim(),"hook_out":grapple.is_out(),
		"capacitor_charge":laser_charge_display(),"capacitor_charge_off":laser_charge_display(true)})
	villain.modulate.a = 0.5 if P.inv > 0 and P.inv < 0.28 and sin(time * 50) > 0 else 1.0

func _add_lights() -> void:
	var S := Run.S
	# Keep the player readable even when many projectiles request lights.
	lights.add(Vector2(P.x-40,P.y-60),Color("#fff2dc"),0.55,140,60)
	for field in utility_fields:
		if field.kind=="time_freeze": lights.add(field.position,Color("#62dfff"),0.45*field.time/field.life,field.radius,80)
	# theme lamps (only the ones near the camera)
	for lamp in arena_level.lamps:
		if lamp.distance_squared_to(Vector2(P.x,P.y)) < 900.0 * 900.0:
			if arena_level.theme.floor in ["street", "planks"]: lights.add(lamp + Vector2(18, 4), arena_level.theme.lamp, 1.15, 240, 60)
			else: lights.add(lamp, arena_level.theme.lamp, 0.75, 230, 50)
	# prop emissives: police light bar, headlights, monitors, server racks, museum gems
	for n in arena_level.prop_nodes:
		if is_instance_valid(n) and n.global_position.distance_squared_to(Vector2(P.x, P.y)) < 800.0 * 800.0:
			for e in n.glows():
				if e.r > 0.0: lights.add(e.pos, e.col, e.e, e.r, 30)
	# wave-intro siren: red / blue sweep around the villain
	if siren_t > 0:
		var red := fmod(siren_t, 0.4) > 0.2
		lights.add(Vector2(P.x + (-160 if red else 160), P.y - 80), Color("#ff2a2a") if red else Color("#2a5aff"), 0.9 * minf(1.0, siren_t * 2), 360, 60)
	for i in gun_flashes.size():
		if gun_flashes[i]>0.0:
			var index = Run.AMMO.find_custom(func(ammo): return ammo.id==S.guns[i])
			lights.add(villain.muzzle_global(i),Color(Run.AMMO[index].col),2.1,70,18)
	if P.flash_t2 > 0 and Run.build.off != null and Run.build.off.get("kind","gun")=="gun": lights.add(villain.off_muzzle_global(), Color(Run.AMMO[Run.build.off.ammo].col), 1.8, 70, 18)
	blaster_fx.add_lights(lights)
	if grapple.anchored():
		var origin = villain.muzzle_global(0); var steps := clampi(int(origin.distance_to(grapple.head)/110.0),1,4)
		for k in steps+1: lights.add(origin.lerp(grapple.head,float(k)/steps),Grapple.COLOR,0.8+randf()*0.4,50,14)
	# laser beams: a few lights along each beam
	var nb := 0
	for b in beams:
		if nb >= 6: break
		var a := Vector2(b.x1, b.y1); var c := Vector2(b.x2, b.y2); var f: float = b.t / b.m
		var steps := clampi(int(a.distance_to(c) / 120.0), 1, 3)
		for k in steps + 1:
			var color: Color = b.col
			if S.burn>0: color = color.lerp(Color("#ff6028"),0.65)
			if S.chain>0 and k%2==1: color = color.lerp(Color("#fff36b"),0.65)
			lights.add(a.lerp(c,float(k)/steps),color,(1.15 if S.burn>0 else 0.9)*minf(1.0,f),45+b.w*2,14)
		nb += 1
	for b in booms: lights.add(Vector2(b.x, b.y), b.col, 2.6 * (b.t / 0.3), b.r * 2.4, 30)
	for s in strikes:
		if s.done: lights.add(Vector2(s.x, s.y), Color("#fff6a0"), 3.0 * s.fade / 0.3, 180, 40)
		else: lights.add(Vector2(s.x, s.y), Color("#fff6a0"), 0.5, 70, 30)
	if S.orbs:
		for i in int(S.orbs):
			var a: float = orb_a + i * TAU / S.orbs
			lights.add(Vector2(P.x + cos(a) * 62, P.y + sin(a) * 62), Color("#b4ff3c"), 1.3, 70, 16)
	for a in arcs: lights.add(Vector2(a.x2, a.y2), a.get("col", Color("#fff36b")), 0.7 if a.has("col") else 1.4, 60, 16)
	for c in crates: lights.add(Vector2(c.x, c.y), Color("#7dff3a"), 0.9 + sin(c.t * 4) * 0.2, 70, 20)
	for m in mines: lights.add(Vector2(m.x, m.y), Color("#ff3030"), 0.6 if sin(time * 10) > 0 else 0.15, 30, 10)
	for p in projs:
		if lights.count() > 80: break
		lights.add(Vector2(p.x, p.y), Color("#ffd76a") if p.type == "bullet" else (Color("#ff4a4a") if p.type == "bolt" else Color("#dfe6ec")), 0.6, 34, 12)
	for b in ebul:
		if lights.count() > 86: break
		lights.add(Vector2(b.x, b.y), b.get("col", Color("#ff4040")), 0.5, 28, 10)
	for e in enemies:
		if e.boss and e.laser != null and e.laser.phase == "fire":
			var o := Vector2(e.x, e.y - 34); var dv := Vector2(cos(e.laser.a), sin(e.laser.a)); var length := ray_len(o.x, o.y, dv.x, dv.y, 760)
			for k in 5: lights.add(o + dv * length * k / 4.0, Color("#ff8a20"), 1.4, 90, 20)
		if e.burn_t > 0 and lights.count() < 90: lights.add(Vector2(e.x, e.y - e.r), Color("#ff7a2a"), 0.7, 34, 12)
	# worn glows: isotope pack, reactor
	var core := Run.worn_core()
	if core == "isotope": lights.add(villain.anchor("backpack"), Color("#7dff3a"), 0.8 + sin(time * 3) * 0.2, 46, 20)
	if Run.CNT.has("reactor"): lights.add(villain.anchor("chest"), Color("#7dff3a"), 0.9 + sin(time * 5) * 0.25, 40, 20)
# =============== DRAW ===============
func _draw_ground(g: Node2D) -> void:
	var t := time
	consumables.draw_ground(self, g)
	bank_vault.draw_door(self, g)
	for d in decals:   # scorch marks
		var al: float = minf(1.0, d.t / 6.0)
		g.draw_circle(Vector2(d.x, d.y), d.r, Color(0.04, 0.03, 0.03, 0.22 * al))
		g.draw_circle(Vector2(d.x, d.y), d.r * 0.7, Color(0.04, 0.03, 0.03, 0.25 * al))
		g.draw_circle(Vector2(d.x, d.y), d.r * 0.4, Color(0.02, 0.02, 0.02, 0.35 * al))
		for k in 7:
			var dir := Vector2.from_angle(d.a + k * TAU / 7.0)
			g.draw_line(Vector2(d.x, d.y) + dir * d.r * 0.5, Vector2(d.x, d.y) + dir * d.r * (1.05 + 0.25 * sin(k * 3.7)), Color(0.03, 0.02, 0.02, 0.3 * al), 3.0)
	for m in mines:
		g.draw_rect(Rect2(m.x - 6, m.y - 3, 12, 6), Color("#333333"))
		g.draw_rect(Rect2(m.x - 2, m.y - 5, 4, 3), Color("#ff3030") if sin(t * 10) > 0 else Color("#550000"))
	for c in crates: _crate_icon(g, c)
	for p in pickups:
		if p.has("blueprint"): continue # bright blueprint markers are drawn above the ambient darkness
		elif p.has("gem"):
			var center := Vector2(p.x, p.y - pickup_hop(p))
			g.draw_colored_polygon(PackedVector2Array([center + Vector2(-6, -3), center + Vector2(0, -8), center + Vector2(6, -3), center + Vector2(0, 6)]), Color("#6eeaff"))
			g.draw_line(center + Vector2(0, -7), center + Vector2(4, -3), Color.WHITE, 2)
		elif p.has("cash"): _cash_icon(g, p.x, p.y, p.cash, p)
		else: _gear_icon(g, p.x, p.y, p.v, p)
	for m in markers:
		if sin(m.t * 30) > 0:
			var col := Color("#ffd700") if m.type == "boss" else Color("#ff3030"); var s := 20 if m.type == "boss" else 7
			for i in range(-s, s + 1, 2):
				g.draw_rect(Rect2(m.x + i - 1, m.y + i - 1, 3, 3), col); g.draw_rect(Rect2(m.x + i - 1, m.y - i - 1, 3, 3), col)
	for nv in novas:
		g.draw_arc(Vector2(nv.x, nv.y), nv.r, 0, TAU, 64, Color(0.7, 0.94, 1, 0.85), 6)
		g.draw_arc(Vector2(nv.x, nv.y), nv.r - 5, 0, TAU, 64, Color(1, 1, 1, 0.6), 2)
	for e in enemies:
		if e.dead or not e.boss: continue
		if e.slam != null:
			var s: Dictionary = e.slam; var f: float = 1.0 - s.t / s.T
			var radius: float = s.get("radius", 105.0)
			g.draw_circle(Vector2(s.x, s.y), radius, Color(1, 0.24, 0.16, 0.15 + 0.25 * f))
			g.draw_arc(Vector2(s.x, s.y), maxf(1.0, radius * f), 0, TAU, 48, Color("#ff4030"), 2)
		if e.charge_t < 0 and e.charging <= 0 and e.hero != "paragon":
			g.draw_line(Vector2(e.x, e.y), Vector2(P.x, P.y), Color(1, 0.24, 0.16, 0.6), 3)
	for s in strikes:
		if not s.done: g.draw_arc(Vector2(s.x, s.y), 55 * (s.t / 0.55) + 4, 0, TAU, 40, Color("#fff6a0"), 2)
	# player shadow + pickup radius
	g.draw_rect(Rect2(P.x - 15, P.y + 15 - 18, 30, 5), Color(0, 0, 0, 0.35))
	if Run.S.pickupPct > 0.3: g.draw_arc(Vector2(P.x, P.y), Run.D.pickup, 0, TAU, 64, Color(1, 0.82, 0.24, 0.07), 1)

## Little hop when a pickup is dropped (world px above the floor).
func pickup_hop(p: Dictionary) -> float:
	var age: float = p.get("age", 1.0)
	if age < 0.45: return sin(age / 0.45 * PI) * 12.0
	if age < 0.65: return sin((age - 0.45) / 0.2 * PI) * 3.0
	return 0.0

func _cash_icon(g: Node2D, x: float, y: float, _k: int, p := {}) -> void:
	var hop := pickup_hop(p)
	g.draw_circle(Vector2(x, y + 3), 6.0 - hop * 0.2, Color(0, 0, 0, 0.3))
	var flut := sin(time * 5.0 + x * 0.3)
	g.draw_set_transform(Vector2(x, y - 2 - hop - absf(flut) * 1.5), 0.18 * flut, Vector2(1.0, 0.85 + 0.15 * cos(time * 4.0 + y)))
	g.draw_rect(Rect2(-10, -6, 20, 12), Color("#1a4a1a")); g.draw_rect(Rect2(-9, -5, 18, 10), Color("#5ac85a"))
	g.draw_rect(Rect2(-9, -5, 18, 1), Color("#b8f0b8")); g.draw_rect(Rect2(-7, -3, 14, 6), Color("#48b048"), false, 1.0)
	g.draw_circle(Vector2.ZERO, 3.0, Color("#2a8a2a"))
	g.draw_rect(Rect2(-1, -3, 2, 6), Color("#d8ffd8")); g.draw_rect(Rect2(-2, -2, 4, 1), Color("#d8ffd8")); g.draw_rect(Rect2(-2, 1, 4, 1), Color("#d8ffd8"))
	g.draw_set_transform(Vector2.ZERO)

func _gear_icon(g: Node2D, x: float, y: float, v: float, p := {}) -> void:
	var s := 8.0 if v >= 3 else (6.5 if v >= 1.5 else 5.0)
	var hop := pickup_hop(p)
	g.draw_circle(Vector2(x, y + s * 0.6), s * 0.9, Color(0, 0, 0, 0.28 - hop * 0.01))
	var c := Vector2(x, y - hop - 1.0 - sin(time * 3.0 + x) * 1.0)
	var rot := time * 1.6 + x * 0.05
	var pts := PackedVector2Array(); var outline := PackedVector2Array()
	for i in 32:
		var r := s * (1.32 if (i / 2) % 2 == 0 else 1.0)
		var dir := Vector2.from_angle(rot + i * TAU / 32.0)
		pts.append(c + dir * r); outline.append(c + dir * (r + 1.2))
	g.draw_colored_polygon(outline, Color("#5a4808"))
	g.draw_colored_polygon(pts, Color("#ffd23c"))
	g.draw_circle(c + Vector2(-s * 0.15, -s * 0.15), s * 0.7, Color("#ffe680"))
	g.draw_circle(c, s * 0.55, Color("#d8a820"))
	g.draw_circle(c, s * 0.32, Color("#3a2c06"))
	g.draw_arc(c, s * 0.85, PI * 1.05, PI * 1.6, 8, Color(1, 1, 0.85, 0.9), 1.2)

func _crate_icon(g: Node2D, c: Dictionary) -> void:
	var x: float = c.x; var y: float = c.y
	var land := minf(1.0, c.t / 0.35)
	var b := sin(c.t * 4) * 1.5 - (1.0 - land) * 80.0   # drops in from above, then bobs
	g.draw_circle(Vector2(x, y + 2), 13.0 * (0.5 + 0.5 * land), Color(0, 0, 0, 0.35))
	g.draw_circle(Vector2(x, y + 2), 22, Color(0.5, 1, 0.2, 0.10 + 0.06 * sin(c.t * 4)))
	var top := y - 30 + b
	# barrel body: shaded yellow with dark hoops
	var n := 8
	for i in n:
		var u := (i + 0.5) / n
		var lit := clampf(0.55 + 0.6 * cos((u - 0.3) * PI), 0.35, 1.15)
		g.draw_rect(Rect2(x - 11 + 22.0 * i / n, top + 4, 22.0 / n + 0.4, 24), Color(1.0 * lit, 0.82 * lit, 0.24 * lit))
	for hy in [top + 8, top + 22]: g.draw_rect(Rect2(x - 11, hy, 22, 2), Color("#3a3010"))
	# radiation trefoil
	var tc := Vector2(x, top + 15.5)
	g.draw_circle(tc, 5.5, Color("#1a1a10"))
	for k in 3:
		var a0 := -PI / 2 + k * TAU / 3.0
		g.draw_colored_polygon(PackedVector2Array([tc, tc + Vector2.from_angle(a0 - 0.5) * 5.0, tc + Vector2.from_angle(a0 + 0.5) * 5.0]), Color("#ffd23c"))
	g.draw_circle(tc, 1.4, Color("#1a1a10"))
	# lid with glowing ooze
	g.draw_set_transform(Vector2(x, top + 4), 0.0, Vector2(1.0, 0.45))
	g.draw_circle(Vector2.ZERO, 11, Color("#8a7a20")); g.draw_circle(Vector2.ZERO, 8, Color("#7dff3a"))
	g.draw_circle(Vector2(-2, -2), 4, Color("#e0ffb0"))
	g.draw_set_transform(Vector2.ZERO)
	g.draw_rect(Rect2(x - 9, top + 4, 2, 23), Color(1, 1, 0.8, 0.45))

func _draw_fx_add(g: Node2D) -> void:
	var S := Run.S
	blaster_fx.draw_glow(g)
	grapple.draw_glow(g,villain.muzzle_global(0),time)
	if boss_move.get("kind","") == "iron_slam":
		var landing: Vector2 = boss_move.points[0]
		g.draw_arc(landing,115.0 * sqrt(S.boomMul),0,TAU,48,Color("#ffd890",0.6),2.0)
	for field in utility_fields:
		var fade: float = field.time/field.life
		if field.kind=="time_freeze":
			g.draw_circle(field.position,field.radius,Color(0.2,0.65,1.0,0.055*fade))
			g.draw_arc(field.position,field.radius,0,TAU,80,Color(0.35,0.8,1.0,0.5*fade),2)
			for i in 12:
				var direction = Vector2.from_angle(i*TAU/12.0)
				g.draw_line(field.position+direction*(field.radius-10),field.position+direction*field.radius,Color(0.6,0.95,1,fade),2)
			g.draw_line(field.position,field.position+Vector2.from_angle(-PI/2+time*0.5)*26,Color(0.4,0.9,1,0.6*fade),2)
		elif field.kind=="slash":
			_draw_slash(g,field,fade)
		else:
			g.draw_arc(field.position,field.radius*(1.0-fade),0,TAU,80,Color(1.0,0.35,0.12,fade),5)
	if siren_t > 0:
		var red := fmod(siren_t, 0.4) > 0.2
		g.draw_rect(Rect2(0, 0, AW, AH), Color(1, 0.1, 0.1, 0.10 * minf(1.0, siren_t * 2)) if red else Color(0.1, 0.25, 1, 0.10 * minf(1.0, siren_t * 2)))
	# orbs (glow)
	if S.orbs:
		for i in int(S.orbs):
			var a: float = orb_a + i * TAU / S.orbs; var o := Vector2(P.x + cos(a) * 62, P.y + sin(a) * 62)
			g.draw_circle(o, 13, Color(0.7, 1, 0.24, 0.25))
	# arcs
	for ar in arcs:
		var pts := PackedVector2Array([Vector2(ar.x1, ar.y1)])
		for i in range(1, 6): pts.append(Vector2(ar.x1 + (ar.x2 - ar.x1) * i / 6.0 + randf_range(-8, 8), ar.y1 + (ar.y2 - ar.y1) * i / 6.0 + randf_range(-8, 8)))
		pts.append(Vector2(ar.x2, ar.y2))
		g.draw_polyline(pts, ar.get("col", Color("#fff36b")), 2)
	# booms
	for b in booms:
		var f: float = b.t / 0.3
		g.draw_circle(Vector2(b.x, b.y), b.r * (1.2 - f * 0.4), Color(b.col, 0.5 * f))
		g.draw_circle(Vector2(b.x, b.y), b.r * 0.5 * (1.2 - f * 0.4), Color(1, 1, 1, 0.6 * f))
	# moon strike beams
	for s in strikes:
		if s.done:
			var al: float = s.fade / 0.3
			g.draw_rect(Rect2(s.x - 22, s.y - 1000, 44, 1000), Color(1, 0.96, 0.63, al)); g.draw_rect(Rect2(s.x - 10, s.y - 1000, 20, 1000), Color(1, 1, 1, al))
			g.draw_circle(Vector2(s.x, s.y), 55, Color(1, 0.96, 0.63, 0.5 * al))
	# hero eye laser
	for e in enemies:
		if e.dead or e.laser == null: continue
		var L: Dictionary = e.laser; var o := Vector2(e.x + cos(L.a) * 6, e.y - 34 + (sin(e.hover * 3) * 3 if e.hover else 0.0) - 12)
		var dv := Vector2(cos(L.a), sin(L.a)); var length := ray_len(o.x, o.y, dv.x, dv.y, 760); var end := o + dv * length
		if L.phase == "aim": g.draw_line(o, end, Color(1, 0.31, 0.16, 0.7 if sin(time * 40) > 0 else 0.25), 1.5)
		else:
			g.draw_line(o, end, Color(1, 0.54, 0.13, 0.5), 22); g.draw_line(o, end, Color("#ffd0a0"), 8); g.draw_line(o, end, Color.WHITE, 3)
			if randf() < 0.6: poof(end.x, end.y, Color("#ff8a20"), 2, 120, 3)

func aim_marker_position() -> Vector2:
	if Run.aim_guide_level() >= 2:
		if Controls.aim_src == "mouse": return get_global_mouse_position()
		return villain.muzzle_global(0) + Vector2.from_angle(P.aim)*float(Run.D.range)
	return villain.shoulder_global() + Vector2.from_angle(P.aim)*minf(float(Run.D.range),170.0)

func _draw_fx_top(g: Node2D) -> void:
	consumables.draw_fx(self, g)
	bank_vault.draw_top(self, g)
	var S := Run.S
	for p in pickups:
		if not p.has("blueprint"): continue
		var pos := Vector2(p.x, p.y - 10 - sin(time * 3) * 3)
		g.draw_circle(Vector2(p.x, p.y), 22, Color(0.2, 0.8, 1, 0.16))
		g.draw_arc(Vector2(p.x, p.y), 20, time, time + TAU * 0.8, 24, Color("#70eaff"), 2)
		g.draw_rect(Rect2(pos - Vector2(9, 12), Vector2(18, 24)), Color("#1b5975"))
		g.draw_rect(Rect2(pos - Vector2(9, 12), Vector2(18, 24)), Color("#a7efff"), false, 2)
		for i in 3: g.draw_line(pos + Vector2(-5, -6 + i * 6), pos + Vector2(5, -6 + i * 6), Color("#a7efff"), 1)
		var label: String = Run.ITEM[p.blueprint].name.to_upper() + " BLUEPRINT"
		g.draw_string(font, pos + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, -21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#a7efff"))
	blaster_fx.draw_core(g)
	grapple.draw_chain(g,villain.muzzle_global(0))
	if S.orbs:
		for i in int(S.orbs):
			var a: float = orb_a + i * TAU / S.orbs; var o := Vector2(P.x + cos(a) * 62, P.y + sin(a) * 62)
			g.draw_rect(Rect2(o.x - 6, o.y - 6, 12, 12), Color("#b4ff3c")); g.draw_rect(Rect2(o.x - 3, o.y - 3, 6, 6), Color("#f0ffd0"))
	for p in projs:
		if p.type == "rocket": Viper.draw_missile(g,p,true)
		elif p.type == "bullet":
			if p.trail.size()>1: g.draw_polyline(p.trail,Color(1,0.84,0.42,0.7),maxf(1.0,p.r*0.7))
			g.draw_rect(Rect2(p.x - p.r / 2, p.y - p.r / 2, p.r, p.r), Color("#ffe9a0"))
		elif p.type == "bolt":
			# short red dash: glow streak behind a white-hot core
			var dir := Vector2(p.vx, p.vy).normalized(); var head := Vector2(p.x, p.y)
			g.draw_line(head - dir * 26.0, head, Color(1, 0.29, 0.29, 0.55), p.r * 1.6)
			g.draw_line(head - dir * 16.0, head, Color("#ffb0b0"), maxf(1.5, p.r * 0.7))
			g.draw_circle(head, p.r * 0.6, Color("#fff0f0"))
		else:
			var r: float = p.r
			g.draw_set_transform(Vector2(p.x, p.y), p.spin)
			g.draw_rect(Rect2(-r, -r * 0.35, r * 2, r * 0.7), Color("#dfe6ec")); g.draw_rect(Rect2(-r * 0.35, -r, r * 0.7, r * 2), Color("#dfe6ec"))
			g.draw_set_transform(Vector2(p.x, p.y), p.spin + 0.785)
			g.draw_rect(Rect2(-r * 0.8, -r * 0.3, r * 1.6, r * 0.6), Color("#aab4be")); g.draw_rect(Rect2(-r * 0.3, -r * 0.8, r * 0.6, r * 1.6), Color("#aab4be"))
			g.draw_rect(Rect2(-2, -2, 4, 4), Color("#333333"))
			g.draw_set_transform(Vector2.ZERO)
	for b in ebul:
		if b.get("seeker",false): Viper.draw_missile(g,b); continue
		if b.get("laser_bolt",false):
			var point := Vector2(b.x,b.y); var direction := Vector2(b.vx,b.vy).normalized()
			g.draw_line(point-direction*14,point,b.col,5.0)
			g.draw_line(point-direction*11,point,Color.WHITE,2.0)
			continue
		# hostile shot: dark outline for contrast on any floor, a trail showing its heading, white-hot core
		var bp := Vector2(b.x, b.y); var bc: Color = b.get("col", Color("#ff4040"))
		var bv := Vector2(b.vx, b.vy); var br: float = b.r
		if bv.length() > 1.0: g.draw_line(bp - bv.normalized() * br * 3.5, bp, Color(bc, 0.35), br * 1.3)
		g.draw_circle(bp, br + 1.5, Color(0.05, 0.02, 0.03, 0.75)); g.draw_circle(bp, br, bc)
		g.draw_circle(bp, maxf(1.0, br * 0.45), Color.WHITE)
	# enemy status bars, bombs
	for e in enemies:
		if e.dead: continue
		if e.bomb_t > 0:
			g.draw_rect(Rect2(e.x - 4, e.y - e.r - 18, 8, 8), Color("#222222"))
			g.draw_rect(Rect2(e.x - 2, e.y - e.r - 16, 4, 4), Color("#ff2020") if sin(time * (20 / maxf(0.3, e.bomb_t))) > 0 else Color("#660000"))
		if e.ally: g.draw_rect(Rect2(e.x - 10, e.y - e.r - 14, 20 * e.ally_t / S.mindDur, 3), Color("#d07bff"))
		elif e.hp < e.max_hp and not e.boss and not e.civ:
			g.draw_rect(Rect2(e.x - 10, e.y - e.r - 12, 20, 3), Color("#330000")); g.draw_rect(Rect2(e.x - 10, e.y - e.r - 12, 20 * maxf(0, e.hp / e.max_hp), 3), Color("#ee3333"))
		if e.chill > 0 and e.frozen_t <= 0: g.draw_rect(Rect2(e.x - 10, e.y - e.r - 8, 20 * minf(1, e.chill), 2), Color("#8ff0ff"))
	for p in parts:
		g.draw_rect(Rect2(p.x - p.s / 2, p.y - p.s / 2, p.s, p.s), Color(p.col, minf(1.0, p.t / (p.m * 0.5))))
	for n in nums:
		var sz := 16 if n.big else 12; var al := minf(1.0, n.t * 3)
		var w := font.get_string_size(n.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		g.draw_string(font, Vector2(n.x - w / 2 + 1, n.y + 1), n.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, al))
		g.draw_string(font, Vector2(n.x - w / 2, n.y), n.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(n.col, al))
	# aim guide: only with the Telescoping Monocle
	if S.aimGuide and state == "play":
		var c := aim_marker_position()
		var col := Color("#ff5a5a") if Controls.firing() else Color(0.7, 1, 0.24, 0.8)
		for ab in [[-8, -1], [5, -1], [-1, -8], [-1, 5]]:
			g.draw_rect(Rect2(c.x + ab[0], c.y + ab[1], 2 if ab[0] == -1 else 3, 3 if ab[0] == -1 else 2), col)
		if Run.aim_guide_level() >= 2:
			g.draw_circle(c,1.5,col)
			g.draw_arc(c,12,0,TAU,32,Color(col,0.45),1)

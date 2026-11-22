extends Node2D
class_name Enemy
## One cop / dog / drone / civilian / hero. Logic ported from index.html updateEnemies/civAI/bossAI/updateAlly.
## x, y are the gameplay position (synced to `position` every frame); A is the arena.

var A: Node  # Arena
var type := "cop"
var x := 0.0
var y := 0.0
var r := 11.0
var hp := 10.0
var max_hp := 10.0
var spd := 72.0
var dmg := 5.0
var scrap := 1.0
var spr := "cop"
var heavy := false
var boss := false
var ranged := false
var fly := false
var civ := false
var bank := false
var has_key := false      # Bank Lobby robbery: this customer carries the vault key (game/bank_vault.gd)
var civ_kind := ""
var rich := 1.0
var juke := 0.0
var life := 0.0
var panic := false
var w_t := 0.0
var w_a := 0.0

var px := 0.0   # position at the start of this frame (wall push-out side)
var py := 0.0
var kx := 0.0
var ky := 0.0
var flash := 0.0
var atk_cd := 0.0
var shoot_cd := 0.0
var face := 1
var walk := 0.0
var chill := 0.0
var slow_t := 0.0
var frozen_t := 0.0
var time_lock := 0.0
var burn_t := 0.0
var burn_dps := 0.0
var acid_t := 0.0
var poison_s := 0
var poison_t := 0.0
## Spread generation: 0 = applied by a shot, 1-2 = caught from a neighbour (see _spread). Caps chain reactions.
var burn_gen := 0
var poison_gen := 0
var bleed_s := 0
var bleed_t := 0.0
var sick_t := 0.0
var rad_s := 0
var rad_t := 0.0
var dot := 0.0
var bomb_t := 0.0
var bomb_dmg := 0.0
var ally := false
var ally_t := 0.0
var tgt: Enemy = null
var tgt_t := 0.0
var orb_cd := 0.0
var dead := false
var disint := false
# boss
var hero := ""
var hero_name := ""
var charge_t := 3.0
var charge_windup := 0.7
var charging := 0.0
var cvx := 0.0
var cvy := 0.0
var slam = null
var air := 0.0
var slam_cd := 4.0
var blink_cd := 2.0
var shard_cd := 1.5
var nova_cd := 4.0
var laser_cd := 3.0
var dive_cd := 5.0
var summon_cd := 6.0
var missile_cd := 1.8
var zig_points := PackedVector2Array()
var zig_cursor := 0
var laser = null
var hover := 0.0
var nav_path := PackedVector2Array()
var nav_cursor := 0
var nav_timer := 0.0
var nav_last := Vector2.ZERO   # position at the last re-plan (stuck detection)
var nav_side := 0.0            # seconds left in a sidestep
var nav_dir := Vector2.ZERO
const Tactics = preload("res://game/enemy_tactics.gd")
var behavior := ""
var vehicle := false
var aim_dir := Vector2.RIGHT
var action_dir := Vector2.RIGHT
var action_target := Vector2.ZERO
var action_phase := ""
var action_t := 0.0
var action_cd := 1.8
var burst_left := 0
var shield_flash := 0.0
var gadget_targets: Array[Vector2] = []
var attack_cycle := 0
var summoner_id := 0
## Per-enemy approach angle: chasers fan out around the villain instead of queueing behind each other.
var flank := 0.0
## Own generator for flank angles and cosmetic dust, so seeded gameplay rolls stay reproducible.
static var _feel_rng := RandomNumberGenerator.new()

func setup(arena: Node, t: String, px: float, py: float) -> void:
	A = arena; type = t; x = px; y = py; position = Vector2(x, y)
	var T: Dictionary = Run.ET[t]
	var w := Run.wave - 1
	var sc: Dictionary = Run.SCALING
	var hp_m: float = 1.0 + sc.hp_lin * w + sc.hp_quad * w * w
	hp = T.hp * hp_m
	if T.get("boss", 0): hp = T.hp * hp_m * (Run.wave / 5.0) * float((Run.boss_for(Run.wave) if Run.boss_for(Run.wave) != null else Run.BOSSES[20]).get("hp", 1.0))   # per-hero factor (bosses table)
	hp *= Run.tough_mult()
	max_hp = hp; r = T.r
	spd = T.spd * (1.0 + sc.spd * w) * Run.speed_mult() * randf_range(0.8, 1.2)   # wide jitter: a crowd of one type spreads out
	# ground melee chasers never outrun the villain's base speed, or a K9 that reaches you can never be shaken off
	if not T.get("boss", 0) and not T.get("civ", 0) and not T.get("fly", 0):
		spd = minf(spd, float(Run.base_stats().speed) * float(Run.RULES.get("enemies", {}).get("chaser_speed_cap", 1.0e9)))
	dmg = T.dmg * (1.0 + sc.dmg * w) * Run.damage_mult()
	if T.get("boss", 0): dmg = T.dmg * (1.0 + sc.get("boss_dmg", sc.dmg) * w) * Run.damage_mult()   # bosses ramp slower: one touch must not erase a fresh HP bar
	scrap = T.scrap; spr = T.spr
	heavy = T.get("heavy", 0) == 1; boss = T.get("boss", 0) == 1; ranged = T.get("ranged", 0) == 1; fly = T.get("fly", 0) == 1
	behavior = T.get("behavior", ""); vehicle = T.get("vehicle", 0) == 1
	aim_dir = Vector2(A.P.x - x, A.P.y - y).normalized(); action_dir = aim_dir
	action_cd = randf_range(1.3, 2.4)
	flank = _feel_rng.randf_range(-0.6, 0.6)
	if type == "undercover" and randf() < 0.5: spr = "undercover_hood"
	shoot_cd = randf_range(1, 2.5); walk = randf() * 10.0
	if T.get("civ", 0):
		civ = true; civ_kind = EnemyArt.CIVPALS.keys().pick_random(); spr = "civ_" + civ_kind
		rich = 1.6 if civ_kind == "suit" else 1.0; juke = randf() * TAU
	if boss:
		var B: Dictionary = Run.boss_for(Run.wave) if Run.boss_for(Run.wave) != null else Run.BOSSES[20]
		hero = B.id; spr = "hero_" + hero; hero_name = B.name
		if hero == "paragon": fly = true
		if hero == "surge": spd *= 1.3
		if hero == "vex": spd *= float(B.get("speed",1.0)); ranged = true; action_cd = 1.8
		if hero == "ironclad":
			spd *= float(B.get("speed", 1.0)); charge_t = 1.25; charge_windup = 0.5; slam_cd = 2.4

func damage_taken(element: String) -> float:
	return float(Run.ET[type].get("damage_taken", {}).get(element, 1.0))

# =============== UPDATE ===============
func tick(dt: float) -> void:
	if time_lock>0.0: time_lock = maxf(0.0,time_lock-dt); return
	var S: Dictionary = Run.S
	flash -= dt; shield_flash = maxf(0.0, shield_flash - dt); orb_cd -= dt; atk_cd -= dt; walk += dt * 8.0
	# DOTs
	var dps := 0.0; var dcol := Color.WHITE
	if burn_t > 0.0:
		burn_t -= dt; dps += burn_dps; dcol = Color("#ff8a30")
		if randf() < dt * 8.0: A.part(x + randf_range(-6, 6), y - r, 0, -50, 0.4, [Color("#ff7a2a"), Color("#ffd23c")].pick_random(), 3)
	if acid_t > 0.0:
		acid_t -= dt; dps += S.acid; dcol = Color("#e8f040")
		if randf() < dt * 4.0: A.part(x + randf_range(-6, 6), y, 0, 30, 0.4, Color("#e8f040"), 3)
	if damage_taken("poison") <= 0.0: poison_s = 0; poison_t = 0.0
	if poison_t > 0.0:
		poison_t -= dt; dps += S.poison * S.poisonMul * poison_s; dcol = Color("#5aff5a")
		if randf() < dt * 4.0: A.part(x + randf_range(-8, 8), y - r, 0, -25, 0.6, Color("#5aff5a"), 3)
	else: poison_s = 0
	if (burn_t > 0.0 and S.burnSpread > 0.0) or (poison_t > 0.0 and S.poisonSpread > 0.0): _spread(dt, S)
	if bleed_t > 0.0:
		bleed_t -= dt; dps += S.bleed * bleed_s; dcol = Color("#ff3040")
		if randf() < dt * 5.0: A.part(x + randf_range(-5, 5), y, 0, 40, 0.35, Color("#c01828"), 3)
	else: bleed_s = 0
	if rad_t > 0.0:
		rad_t -= dt; dps += S.rad * S.radMul * rad_s; dcol = Color("#b6ff3a")
		if randf() < dt * 3.0: A.part(x + randf_range(-7, 7), y - r, 0, -20, 0.5, Color("#b6ff3a"), 2)
	else: rad_s = 0
	if sick_t > 0.0:
		sick_t -= dt; dps += 3.0 * (1.0 + Run.wave * 0.1); dcol = Color("#b0e040")
		if randf() < dt * 0.8:
			for o in A.enemies:
				if not o.dead and not o.ally and o != self and o.sick_t <= 0.0 and _d2(o) < 60 * 60:
					o.sick_t = 5.0; break
	if dps > 0.0 and not ally:
		dot += dps * dt
		if dot >= maxf(1.0, dps * 0.5):
			var d := dot; dot = 0.0; A.hit(self, d, {"col": dcol})
			if dead: return
	if bomb_t > 0.0:
		bomb_t -= dt
		if bomb_t <= 0.0:
			bomb_t = 0.0; A.explode(x, y, bomb_dmg, 65.0 * sqrt(S.boomMul), Color("#ff5030"))
			if dead: return
	chill = maxf(0.0, chill - dt * 0.2)
	if slow_t > 0.0: slow_t -= dt
	# knockback
	x += kx * dt; y += ky * dt; kx *= 0.85; ky *= 0.85
	if ally: _ally_ai(dt); return
	if frozen_t > 0.0: frozen_t -= dt; return
	if civ: _civ_ai(dt); return
	if A.P.disguise_t > 0.0:
		# Search the last area without acquiring, firing at, or charging the disguised villain.
		Tactics.distracted(self, dt)
		return
	if behavior in ["vex_sentry","vex_mine"]:
		preload("res://game/rival_scientist.gd").gadget_tick(self,dt)
		return
	var sp := spd * (0.55 if slow_t > 0.0 else 1.0) * (0.7 if sick_t > 0.0 else 1.0)
	var P = A.P
	var tx: float = P.x; var ty: float = P.y; var tgt_ally: Enemy = null
	tgt_t -= dt
	if tgt_t <= 0.0:
		tgt_t = 0.4; tgt = null; var bd := 140.0 * 140.0
		for o in A.enemies:
			if o.ally and not o.dead:
				var d := _d2(o)
				if d < bd: bd = d; tgt = o
	if tgt != null and not tgt.dead and tgt.ally: tgt_ally = tgt; tx = tgt.x; ty = tgt.y
	# Reinforcements share status effects and targeting, then use their own combat patterns.
	if behavior != "" and tgt_ally == null:
		Tactics.tick(self, dt, sp)
		return
	var navigating = false
	if not fly:
		var waypoint = A.nav.waypoint(self,Vector2(tx,ty),dt)
		navigating = waypoint.distance_to(Vector2(tx,ty))>1.0
		tx = waypoint.x; ty = waypoint.y
	var dx := tx - x; var dy := ty - y; var d := maxf(0.0001, sqrt(dx * dx + dy * dy))
	var pd := Vector2(P.x - x, P.y - y).length()
	if boss: _boss_ai(dt, dx, dy, d, sp)
	elif ranged and tgt_ally == null and not navigating:
		if d > 240: _move(dx / d * sp * dt, dy / d * sp * dt)
		elif d < 180: _move(-dx / d * sp * 0.6 * dt, -dy / d * sp * 0.6 * dt)
		shoot_cd -= dt
		if shoot_cd <= 0.0 and d < 380:
			shoot_cd = randf_range(1.8, 2.6); var bs := 190.0
			face = 1 if dx >= 0.0 else -1
			var muzzle := EnemyView.muzzle_world(self)
			var shot := (Vector2(P.x,P.y)-muzzle).normalized()
			if A.nav.clear_segment(Vector2(x,y),muzzle,0.0) and A.nav.clear_segment(muzzle,Vector2(P.x,P.y),0.0):
				A.ebul.append({"x":muzzle.x,"y":muzzle.y,"vx":shot.x*bs,"vy":shot.y*bs,"r":4.0,"dmg":dmg,"t":3.0})
				gfx.shot_t = 0.0; EnemyView._fire_flash(self,gfx,shot)
			A.snd("ebul")
	elif tgt_ally != null or navigating or pd > r + P.r:
		# chase, but stop at the villain's edge instead of stacking on its centre
		var step := sp * dt * _gait(pd)
		if action_phase == "swing": step *= SWING_SLOW
		if tgt_ally == null and not navigating: step = minf(step, maxf(0.0, pd - (r + P.r) * 0.85))
		var heading := Vector2(dx / d, dy / d)
		if tgt_ally == null and not navigating:
			# fan out at range, close in straight; drones weave so they are harder to track
			heading = heading.rotated(flank * clampf((pd - 110.0) / 220.0, 0.0, 1.0))
			if type == "drone": heading = (heading + heading.orthogonal() * sin(walk * 0.55 + flank * 9.0) * 0.55).normalized()
		_move(heading.x * step, heading.y * step)
	face = 1 if dx >= 0 else -1
	if tgt_ally == null and not boss and SWING.has(type):
		_swing(dt, pd)
	elif tgt_ally == null and pd < r + P.r and atk_cd <= 0.0 and not boss:
		atk_cd = 1.0; A.hurt_player(dmg)
		# the bite knocks the biter back a step, so a contact attacker doesn't sit glued to you
		var kd := maxf(0.0001, pd); _move(-(P.x - x) / kd * BITE_KNOCKBACK, -(P.y - y) / kd * BITE_KNOCKBACK)

## Baton cops and riot police telegraph their hit: a short wind-up (raised baton / shield drawn back),
## then the blow lands only if the villain is still in reach. K9s and drones keep their instant bite.
## windup s, extra reach px, lunge px/s during the wind-up.
const SWING := {"cop": [0.26, 12.0, 0.0], "riot": [0.42, 16.0, 150.0]}
const SWING_SLOW := 0.35
## Called by EnemyView (dynamically, so the view never compiles this script ahead of the Run autoload).
func swings() -> bool: return SWING.has(type)
func _swing(dt: float, pd: float) -> void:
	var P = A.P
	var spec: Array = SWING[type]
	var reach: float = r + P.r + spec[1]
	if action_phase == "swing":
		action_t -= dt
		if spec[2] > 0.0 and pd > r + P.r * 0.8:   # riot shield charge: step into the bash
			var kd := maxf(0.0001, pd); _move((P.x - x) / kd * spec[2] * dt, (P.y - y) / kd * spec[2] * dt)
		if action_t <= 0.0:
			action_phase = ""; atk_cd = 1.0
			if Vector2(P.x - x, P.y - y).length() < reach + 4.0:
				A.hurt_player(dmg)
				var kd2 := maxf(0.0001, pd); _move(-(P.x - x) / kd2 * BITE_KNOCKBACK * 0.6, -(P.y - y) / kd2 * BITE_KNOCKBACK * 0.6)
				if type == "riot": A.shake = maxf(A.shake, 3.0)
	elif pd < reach and atk_cd <= 0.0:
		action_phase = "swing"; action_t = spec[0]
		if type == "riot": A.poof(x, y + 12, Color("#a89878"), 5, 60, 3)   # boots dig in for the shield charge

## K9s gallop: speed surges and eases with each bound (same average pace).
func _gait(pd: float) -> float:
	if type == "k9":
		if _feel_rng.randf() < 0.04 and pd > 60.0: A.part(x - face * 6, y + 8, -face * 25.0, -12.0, 0.3, Color("#a89878"), 2)   # paw dust
		return 0.94 + 0.12 * sin(walk * 0.75)   # peaks stay under the chaser speed cap
	if type == "drone" and pd < 170.0 and pd > 50.0: return 1.3   # swoop in for the hit
	return 1.0

## Fire and poison spread (like Sickness): each second, a burning / poisoned cop has a S.burnSpread /
## S.poisonSpread chance (stat, can exceed 1 = several catches a second) to pass it to one cop within SPREAD_R.
## A caught fire burns 2 s at 75% of the source's dps; caught poison carries half the stacks (min 1).
## Each catch is one generation further; generation SPREAD_HOPS can't pass it on, so a crowd can't burn forever.
const BITE_KNOCKBACK := 26.0
const SPREAD_R := 70.0
const SPREAD_HOPS := 2
func _spread(dt: float, S: Dictionary) -> void:
	if ally: return
	var fire: bool = burn_t > 0.0 and burn_gen < SPREAD_HOPS and randf() < float(S.burnSpread) * dt
	var tox: bool = poison_t > 0.0 and poison_gen < SPREAD_HOPS and randf() < float(S.poisonSpread) * dt
	if not fire and not tox: return
	for o in A.enemies:
		if o.dead or o.ally or o == self or o.civ or _d2(o) > SPREAD_R * SPREAD_R: continue
		if fire and o.burn_t <= 0.0:
			o.burn_t = 2.0; o.burn_dps = burn_dps * 0.75; o.burn_gen = burn_gen + 1; fire = false
			A.part(o.x, o.y - o.r, 0, -60, 0.5, Color("#ffb040"), 4)
		if tox and o.poison_t <= 0.0 and o.damage_taken("poison") > 0.0:
			o.poison_s = maxi(1, int(poison_s / 2.0)); o.poison_t = 4.0; o.poison_gen = poison_gen + 1; tox = false
			A.part(o.x, o.y - o.r, 0, -40, 0.6, Color("#7aff5a"), 4)
		if not fire and not tox: return

func _d2(o: Enemy) -> float: return (o.x - x) * (o.x - x) + (o.y - y) * (o.y - y)
func _move(mx: float, my: float) -> void: x += mx; y += my

func _civ_ai(dt: float) -> void:
	life += dt
	var P = A.P
	var dx: float = x - P.x; var dy: float = y - P.y; var d := maxf(0.0001, sqrt(dx * dx + dy * dy))
	var sp := spd * (0.55 if slow_t > 0.0 else 1.0) * (0.7 if sick_t > 0.0 else 1.0)
	var vx := 0.0; var vy := 0.0; var k := 1.0
	var AW: float = A.AW; var AH: float = A.AH
	if d < 340:
		panic = true; var j := sin(A.time * 5.0 + juke) * 1.1; var nx := dx / d; var ny := dy / d
		vx = nx - ny * j; vy = ny + nx * j
		if x < 60 or x > AW - 60: vx *= 0.2
		if y < 60 or y > AH - 60: vy *= 0.2
		if randf() < dt * 0.35: A.add_num(x, y - 26, ["AAAH!", "HELP!", "EEK!", "NOOO!", "MY WALLET!"].pick_random(), Color.WHITE, false)
	else:
		panic = false; w_t -= dt
		if w_t <= 0.0: w_t = randf_range(1, 2.5); w_a = randf() * TAU
		vx = cos(w_a); vy = sin(w_a); k = 0.3
	var l := maxf(0.0001, sqrt(vx * vx + vy * vy))
	x += vx / l * sp * k * dt; y += vy / l * sp * k * dt; face = 1 if vx >= 0 else -1
	if panic: walk += dt * 6.0
	# escape at the arena edges (never inside the bank: they're locked in)
	if not bank and panic and life > 3.0 and (x < 30 or x > AW - 30 or y < 30 or y > AH - 30):
		dead = true; A.add_num(x, y - 20, "ESCAPED", Color("#99aabb"), false); A.poof(x, y, Color("#99aabb"), 6)

func _ally_ai(dt: float) -> void:
	var S: Dictionary = Run.S
	ally_t -= dt; tgt_t -= dt
	if action_phase == "swing": action_phase = ""
	if tgt_t <= 0.0 or tgt == null or tgt.dead or tgt.ally: tgt_t = 0.3; tgt = A.nearest_foe(x, y)
	var t := tgt
	if t != null:
		var dx := t.x - x; var dy := t.y - y; var d := maxf(0.0001, sqrt(dx * dx + dy * dy)); face = 1 if dx >= 0 else -1
		if d > r+t.r:
			var waypoint = A.nav.waypoint(self,Vector2(t.x,t.y),dt) if not fly else Vector2(t.x,t.y)
			var direction = (waypoint-Vector2(x,y)).normalized()
			_move(direction.x*spd*1.25*dt,direction.y*spd*1.25*dt)
		elif atk_cd <= 0.0:
			atk_cd = 0.5; A.hit(t, (dmg * 2.0 + Run.D.dmg * 0.5) * S.minionMul, {"col": Color("#d07bff")})
			hp -= t.dmg * (1.0 if t.boss else 0.6)
	if ally_t <= 0.0 or hp <= 0.0:   # brain overload
		dead = true; A.explode(x, y, (10.0 + Run.D.dmg) * S.minionMul, 70, Color("#d07bff"))
		var n := maxi(1, int(scrap))
		for i in n: A.pickups.append({"x": x, "y": y, "v": scrap / n, "vx": randf_range(-60, 60), "vy": randf_range(-60, 60)})

func _boss_ai(dt: float, dx: float, dy: float, d: float, sp: float) -> void:
	var P = A.P
	var AW: float = A.AW; var AH: float = A.AH
	match hero:
		"vex":
			preload("res://game/rival_scientist.gd").tick(self,dt,sp)
		"ironclad":   # armored bruiser: charge + leaping ground slam
			var rage := hp < max_hp * 0.5
			charge_windup = 0.4 if rage else 0.5
			if rage: sp *= 1.18
			if slam != null:
				var s: Dictionary = slam; s.t -= dt; var k: float = 1.0 - maxf(0.0, s.t) / s.T
				x = s.sx + (s.x - s.sx) * k; y = s.sy + (s.y - s.sy) * k; air = sin(k * PI)
				if s.t <= 0.0:
					air = 0.0; var rr: float = s.get("radius", 115.0)
					A.booms.append({"x": x, "y": y, "r": rr, "t": 0.4, "col": Color("#d8c8a8")}); A.poof(x, y, Color("#a89878"), 26, 280, 5)
					A.shake = 12.0; Controls.rumble(0.6, 1.0, 300); A.snd("slam")
					if Vector2(P.x - x, P.y - y).length() < rr + P.r: A.hurt_player(dmg * 1.3)
					slam = null
				return
			if charging > 0.0:
				charging -= dt; x += cvx * dt; y += cvy * dt
				if randf() < 0.5: A.poof(x, y + 20, Color("#888888"), 1, 30)
			elif charge_t < 0.0:
				charge_t -= dt
				if charge_t < -charge_windup:
					charge_t = randf_range(1.35, 1.9) if rage else randf_range(2.0, 2.8)
					charging = 0.75 if rage else 0.65
					var direction := Vector2(P.x - x, P.y - y).normalized()
					var speed := sp * (3.8 if rage else 3.6)
					cvx = direction.x * speed; cvy = direction.y * speed; A.snd("charge")
			else:
				_move(dx / d * sp * dt, dy / d * sp * dt); charge_t -= dt
				if charge_t <= 0.0: charge_t = -0.001
				slam_cd -= dt
				if slam_cd <= 0.0 and Vector2(P.x - x, P.y - y).length() < 450:
					slam_cd = randf_range(2.5, 3.2) if rage else randf_range(3.2, 4.0)
					var duration := 0.65 if rage else 0.8
					slam = {"sx": x, "sy": y, "x": P.x, "y": P.y, "t": duration, "T": duration, "radius":130.0 if rage else 115.0}; A.snd("leap")
		"viper":
			preload("res://game/viper_boss.gd").tick(self, dt, sp)
		"surge":   # speedster: blink + lightning volleys
			blink_cd -= dt
			if blink_cd <= 0.0:
				var rage := hp < max_hp * 0.5; blink_cd = 2.1 if rage else 3.1
				var nx := 0.0; var ny := 0.0; var tr := 0
				while true:
					var a := randf() * TAU; var rr := randf_range(170, 260)
					nx = clampf(P.x + cos(a) * rr, 40, AW - 40); ny = clampf(P.y + sin(a) * rr, 40, AH - 40); tr += 1
					if not A.in_wall(nx, ny, 24) or tr >= 15: break
				A.poof(x, y, Color("#fff36b"), 14, 160); A.arcs.append({"x1": x, "y1": y, "x2": nx, "y2": ny, "t": 0.25})
				x = nx; y = ny; A.poof(x, y, Color("#fff36b"), 14, 160); A.snd("blink")
				var a0 := atan2(P.y - y, P.x - x)
				for i in range(-1, 2):
					var a := a0 + i * 0.18
					A.ebul.append({"x": x, "y": y - 10, "vx": cos(a) * 330, "vy": sin(a) * 330, "r": 5.0, "dmg": dmg * 0.6, "t": 3.0, "col": Color("#fff36b"), "zap": true})
				if rage:
					for i in 12:
						var a := i * 0.5236
						A.ebul.append({"x": x, "y": y, "vx": cos(a) * 200, "vy": sin(a) * 200, "r": 5.0, "dmg": dmg * 0.5, "t": 3.0, "col": Color("#fff36b"), "zap": true})
			else:
				var want := 1.0 if d > 230 else (-1.0 if d < 170 else 0.0)
				_move((dx / d * want - dy / d * 0.8) * sp * dt, (dy / d * want + dx / d * 0.8) * sp * dt)
			if randf() < dt * 6.0: A.part(x + randf_range(-14, 14), y + randf_range(-30, 10), 0, 0, 0.1, Color("#fff36b"), 2)
		"glacia":   # ice: shard fans + frost nova
			var want := 1.0 if d > 270 else (-1.0 if d < 200 else 0.0)
			_move((dx / d * want - dy / d * 0.5) * sp * dt, (dy / d * want + dx / d * 0.5) * sp * dt)
			shard_cd -= dt
			if shard_cd <= 0.0:
				shard_cd = 1.1 if hp < max_hp * 0.5 else 1.6; var a0 := atan2(dy, dx)
				for i in range(-2, 3):
					var a := a0 + i * 0.16
					A.ebul.append({"x": x, "y": y - 10, "vx": cos(a) * 240, "vy": sin(a) * 240, "r": 5.0, "dmg": dmg * 0.5, "t": 3.0, "col": Color("#9ef0ff"), "slow": true})
				A.snd("shard")
			nova_cd -= dt
			if nova_cd <= 0.0:
				nova_cd = 6.0; A.novas.append({"x": x, "y": y, "r": 10.0, "max": 360.0, "dmg": dmg * 0.7, "hit": false}); A.snd("nova")
			if randf() < dt * 5.0: A.part(x + randf_range(-20, 20), y - 30, randf_range(-10, 10), 30, 0.8, Color("#e8ffff"), 2)
		"paragon":   # flying powerhouse: eye lasers, dives, backup
			if laser != null:
				var L: Dictionary = laser; L.t -= dt
				if L.phase == "aim":
					L.a = atan2(P.y - (y - 34), P.x - x)
					if L.t <= 0.0:
						L.phase = "fire"; L.t = 0.9; L.dir = -1.0 if randf() < 0.5 else 1.0; A.snd("eyelaser"); Controls.rumble(0.4, 0.6, 800)
				else:
					L.a += L.dir * 0.7 * dt
					var ca := cos(L.a); var sa := sin(L.a); var px: float = P.x - x; var py: float = P.y - (y - 34)
					var proj := px * ca + py * sa; var perp := absf(px * sa - py * ca)
					if proj > 0 and proj < A.ray_len(x, y - 34, ca, sa, 760) and perp < 16: A.hurt_player(dmg * 0.7)
					if L.t <= 0.0: laser = null
				return
			if charging > 0.0: charging -= dt; x += cvx * dt; y += cvy * dt
			else:
				var f := 1.0 if d > 160 else 0.2
				_move(dx / d * sp * f * dt, dy / d * sp * f * dt)
				laser_cd -= dt
				if laser_cd <= 0.0: laser_cd = randf_range(4, 6); laser = {"phase": "aim", "t": 0.9, "a": 0.0, "dir": 1.0}
				dive_cd -= dt
				if dive_cd <= 0.0:
					dive_cd = randf_range(5, 7); charging = 0.7; var s3 := sp * 5.0; cvx = dx / d * s3; cvy = dy / d * s3; A.snd("charge")
				summon_cd -= dt
				if summon_cd <= 0.0:
					summon_cd = 7.0
					for i in 4: A.markers.append({"x": clampf(P.x + randf_range(-260, 260), 40, AW - 40), "y": clampf(P.y + randf_range(-260, 260), 40, AH - 40), "t": 0.9, "type": "swat"})
	if Vector2(P.x - x, P.y - y).length() < r + P.r and atk_cd <= 0.0 and air <= 0.0:
		atk_cd = 1.0; A.hurt_player(dmg)
		if hero == "surge": P.zap_t = 0.6

# =============== DRAW ===============
## Rendering only: sprite selection, FX and corpses live in res://enemies/enemy_view.gd.
var gfx := {}

func _ready() -> void:
	EnemyView.attach(self)

func sync() -> void:
	position = Vector2(roundf(x), roundf(y))
	EnemyView.update(self)
	queue_redraw()

func _draw() -> void:
	EnemyView.draw(self)

func _exit_tree() -> void:
	if dead: EnemyView.leave_corpse(self)

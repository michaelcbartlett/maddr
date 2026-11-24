extends RefCounted
## Street and military reinforcements. All movement still goes through arena wall collision.

static func distracted(e, dt: float) -> void:
	if e.hero == "vex": preload("res://game/rival_scientist.gd").cancel(e)
	if e.action_phase == "swing": e.action_phase = ""
	if e.action_phase in ["aim","flee","cornered"]: e.action_phase = ""
	if e.action_phase in ["windup","rush","zigzag"]: e.action_phase = "recover"; e.action_t = 1.0
	e.burst_left = 0; e.shoot_cd = maxf(e.shoot_cd, 0.8)
	e.charging = 0.0; e.slam = null; e.air = 0.0; e.laser = null
	e.charge_t = maxf(e.charge_t, 1.0); e.action_cd = maxf(e.action_cd, 1.0)
	e.tgt = null
	# Confused patrol, slow enough to make a gap without freezing enemies in place.
	e.w_t -= dt
	if e.w_t <= 0.0: e.w_t = randf_range(0.8, 1.4); e.w_a = randf() * TAU
	var velocity: Vector2 = Vector2.from_angle(e.w_a) * e.spd * (0.12 if e.vehicle else 0.22) * dt
	e._move(velocity.x, velocity.y)

static func tick(e, dt: float, speed: float) -> void:
	var target := Vector2(e.A.P.x, e.A.P.y)
	var delta := target - Vector2(e.x, e.y)
	var distance := delta.length()
	var dir := delta.normalized()
	e.aim_dir = Vector2.from_angle(rotate_toward(e.aim_dir.angle(), dir.angle(), dt * (1.7 if e.type == "swat_shield" else 3.2)))
	e.face = 1 if e.aim_dir.x >= 0.0 else -1
	match e.behavior:
		"rifle": _rifle(e, dt, speed, distance, dir)
		"ram": _rush(e, dt, speed, distance, dir, false)
		"pounce": _rush(e, dt, speed, distance, dir, true)
		"cannon": _cannon(e, dt, speed, distance, dir)
		"marksman":
			_marksman(e, dt, speed, distance, dir)
			return   # he runs from contact instead of hitting back
	if distance < e.r + e.A.P.r and e.atk_cd <= 0.0:
		e.atk_cd = 1.0
		e.A.hurt_player(e.dmg)
		if not e.vehicle:
			e._move(-dir.x * 26.0, -dir.y * 26.0)

static func _advance(e, target: Vector2, speed: float, dt: float) -> void:
	var waypoint: Vector2 = e.A.nav.waypoint(e, target, dt)
	var delta := waypoint - Vector2(e.x, e.y)
	var move := delta.normalized() * minf(speed * dt, delta.length())
	e._move(move.x, move.y)

static func _clear(e, dir: Vector2, distance: float) -> bool:
	return e.A.ray_len(e.x, e.y, dir.x, dir.y, distance) >= distance - 1.0

static func _rifle(e, dt: float, speed: float, distance: float, dir: Vector2) -> void:
	var spec: Dictionary = Run.ET[e.type]
	var reach := float(spec.get("range", 280))
	var clear := _clear(e, dir, distance)
	if not clear or distance > reach:
		_advance(e, Vector2(e.A.P.x, e.A.P.y), speed, dt)
	elif distance < reach * 0.60 and e.type != "swat_shield":
		e._move(-dir.x * speed * 0.45 * dt, -dir.y * speed * 0.45 * dt)
	elif e.type == "undercover":
		# Trainers, jeans and a lateral sidestep distinguish the plainclothes gunmen.
		var side := sin(e.walk * 0.35)
		e._move(-dir.y * speed * 0.4 * side * dt, dir.x * speed * 0.4 * side * dt)
	e.shoot_cd -= dt
	if not clear or distance > reach + 85.0:
		e.burst_left = 0
		return
	if e.shoot_cd > 0.0: return
	var muzzle := EnemyView.muzzle_world(e)
	var target := Vector2(e.A.P.x,e.A.P.y)
	if not e.A.nav.clear_segment(Vector2(e.x,e.y),muzzle,0.0) or not e.A.nav.clear_segment(muzzle,target,0.0): return
	if e.burst_left <= 0: e.burst_left = int(spec.get("burst", 3))
	var shot: Vector2 = (target-muzzle).normalized().rotated(randf_range(-0.045, 0.045))
	if shot.x * e.face < -0.05: return
	var shot_speed := float(spec.get("shot_speed", 260))
	e.A.ebul.append({"x":muzzle.x, "y":muzzle.y, "vx":shot.x * shot_speed, "vy":shot.y * shot_speed,
		"r":3.0, "dmg":e.dmg, "t":2.2, "col":Color("#ffb85c")})
	e.burst_left -= 1
	e.shoot_cd = 0.18 if e.burst_left > 0 else float(spec.get("cooldown", 2.6)) * randf_range(0.9, 1.1)
	e.gfx.shot_t = 0.0
	EnemyView._fire_flash(e, e.gfx, shot)
	e.A.snd("ebul")

## The detective: holds revolver range, steadies, fires, and runs when you close in.
const FLEE_IN := 115.0        # closer than this: run
const FLEE_OUT := 235.0       # far enough to stop running
const FLEE_MAX := 2.2         # he tires, so a chase always ends
const FLEE_REST := 1.1        # breath before he can run again
const FLEE_SPEED := 1.35
const PINNED := 0.55
const HOLD_NEAR := 185.0
const HOLD_FAR := 275.0
const STEADY := 0.38          # rooted aim before the shot (matches the sight line)

static func _marksman(e, dt: float, speed: float, distance: float, dir: Vector2) -> void:
	var clear := _clear(e, dir, distance)
	e.action_cd = maxf(0.0, e.action_cd - dt)
	if e.action_phase == "flee":
		e.action_t -= dt
		var stuck := _run_from(e, dt, speed * FLEE_SPEED, dir)
		if stuck:
			# Nowhere left to go: he spins round for one desperate shot.
			e.action_phase = "cornered"; e.action_t = 0.55
		elif distance > FLEE_OUT or e.action_t <= 0.0:
			e.action_phase = ""; e.action_cd = FLEE_REST; e.shoot_cd = maxf(e.shoot_cd, 0.7)
		return
	if e.action_phase == "cornered":
		e.action_t -= dt
		if e.action_t <= 0.0:
			if distance < 420.0: _revolver(e, true)
			e.action_phase = ""; e.action_cd = FLEE_REST; e.shoot_cd = randf_range(1.3, 1.8)
		return
	if distance < FLEE_IN and e.action_cd <= 0.0:
		e.action_phase = "flee"; e.action_t = FLEE_MAX; e.w_t = 0.0; e.juke = 0.0; e.gfx.erase("flee_at")
		return
	if e.action_phase == "aim":
		e.action_t -= dt; e.shoot_cd = maxf(0.0, e.action_t)
		if not clear: e.action_phase = ""; e.shoot_cd = 0.6
		elif e.action_t <= 0.0:
			_revolver(e, false)
			e.action_phase = ""; e.shoot_cd = randf_range(1.4, 2.0)
		return
	if not clear or distance > HOLD_FAR: _advance(e, Vector2(e.A.P.x, e.A.P.y), speed, dt)
	elif distance < HOLD_NEAR:
		e._move(-dir.x * speed * 0.6 * dt, -dir.y * speed * 0.6 * dt)
		e.x = clampf(e.x, 28.0, e.A.AW - 28.0); e.y = clampf(e.y, 28.0, e.A.AH - 28.0)
	# The last moment before a shot belongs to the rooted aim.
	e.shoot_cd = maxf(STEADY, e.shoot_cd - dt)
	if e.shoot_cd <= STEADY and clear and distance < 380.0:
		e.action_phase = "aim"; e.action_t = STEADY

static func _revolver(e, wild: bool) -> void:
	var muzzle := EnemyView.muzzle_world(e); var target := Vector2(e.A.P.x, e.A.P.y - 28.0)
	if not e.A.nav.clear_segment(Vector2(e.x, e.y), muzzle, 0.0) or not e.A.nav.clear_segment(muzzle, target, 0.0): return
	var shot := (target - muzzle).normalized().rotated(randf_range(-0.16, 0.16) if wild else 0.0)
	e.A.ebul.append({"x":muzzle.x, "y":muzzle.y, "vx":shot.x * 400.0, "vy":shot.y * 400.0, "r":4.0, "dmg":e.dmg, "t":3.0})
	e.gfx.shot_t = 0.0
	EnemyView._fire_flash(e, e.gfx, shot)
	e.A.snd("ebul")

## Runs along the most open heading away from the villain. True when he has been pinned for a moment.
static func _run_from(e, dt: float, speed: float, dir: Vector2) -> bool:
	e.w_t -= dt
	if e.w_t <= 0.0:
		e.w_t = 0.18
		var best := -INF
		for i in 16:
			var heading := Vector2.from_angle(TAU * i / 16.0)
			var room: float = minf(150.0, e.A.ray_len(e.x, e.y, heading.x, heading.y, 150.0))
			for axis in 2:
				# The arena edge is a wall too.
				var at: float = e.x if axis == 0 else e.y; var limit: float = e.A.AW if axis == 0 else e.A.AH
				if absf(heading[axis]) > 0.01: room = minf(room, maxf(0.0, ((limit - 30.0 - at) if heading[axis] > 0.0 else (30.0 - at)) / heading[axis]))
			var score := -heading.dot(dir) * 1.2 + room / 150.0 * 1.5 + heading.dot(Vector2.from_angle(e.w_a)) * 0.25
			if room < 24.0: score -= 4.0
			if heading.dot(dir) > 0.5: score -= 3.0   # never bolt into the villain's arms
			if score > best: best = score; e.w_a = heading.angle()
	# Pinned means going nowhere: jittering along a wall does not count as running.
	var from := Vector2(e.x, e.y)
	if not e.gfx.has("flee_at") or from.distance_to(e.gfx.flee_at) > speed * PINNED * 0.5: e.gfx.flee_at = from; e.juke = 0.0
	else: e.juke += dt
	var step := Vector2.from_angle(e.w_a) * speed * dt
	e._move(step.x, step.y)
	e.x = clampf(e.x, 28.0, e.A.AW - 28.0); e.y = clampf(e.y, 28.0, e.A.AH - 28.0)
	e.aim_dir = Vector2.from_angle(e.w_a); e.face = 1 if step.x >= 0.0 else -1
	return e.juke > PINNED

static func _rush(e, dt: float, speed: float, distance: float, dir: Vector2, dog: bool) -> void:
	if e.action_phase == "windup":
		e.action_t -= dt
		if e.action_t <= 0.0:
			e.action_phase = "rush"; e.action_t = 0.42 if dog else 0.95
			e.A.snd("charge")
	elif e.action_phase == "rush":
		e.action_t -= dt
		var velocity: Vector2 = e.action_dir * (340.0 if dog else 430.0) * (0.55 if e.slow_t > 0.0 else 1.0)
		var move: Vector2 = velocity * dt
		var ahead := Vector2(e.x, e.y) + move
		if e.A.in_wall(ahead.x, ahead.y, e.r) or ahead.x < e.r or ahead.y < e.r or ahead.x > e.A.AW - e.r or ahead.y > e.A.AH - e.r:
			e.action_t = 0.0
			if not dog: e.A.poof(e.x, e.y, Color("#ffc078"), 12, 90); e.A.snd("slam")
		else:
			e._move(move.x, move.y)
		if e.action_t <= 0.0:
			e.action_phase = "recover"; e.action_t = 0.65 if dog else 1.15
	elif e.action_phase == "recover":
		e.action_t -= dt
		if e.action_t <= 0.0: e.action_phase = ""; e.action_cd = 2.5 if dog else 3.1
	else:
		e.action_cd -= dt
		if distance > e.r + e.A.P.r + 2.0: _advance(e, Vector2(e.A.P.x, e.A.P.y), speed, dt)
		if e.action_cd <= 0.0 and distance < (285.0 if dog else 600.0) and distance > 65.0 and _clear(e, dir, distance):
			e.action_dir = dir; e.action_phase = "windup"; e.action_t = 0.55 if dog else 0.95
			e.action_target = Vector2(e.A.P.x, e.A.P.y)
	if e.action_phase == "windup" or e.action_phase == "rush":
		e.aim_dir = e.action_dir; e.face = 1 if e.action_dir.x >= 0.0 else -1

static func _cannon(e, dt: float, speed: float, distance: float, dir: Vector2) -> void:
	if e.action_phase == "windup":
		e.action_t -= dt
		if e.action_t <= 0.0:
			var muzzle: Vector2 = Vector2(e.x, e.y) + e.action_dir * float(Run.ET[e.type].get("muzzle",46.0)) - Vector2(0,59)
			var shot_dir: Vector2 = (e.action_target - muzzle).normalized()
			# Sweep the barrel as well: its longer muzzle must never create a shell beyond a prop.
			var barrel: Vector2 = muzzle - Vector2(e.x,e.y)
			var clear: float = e.A.ray_len(e.x,e.y,barrel.normalized().x,barrel.normalized().y,barrel.length())
			if clear < barrel.length(): muzzle = Vector2(e.x,e.y) + barrel.normalized()*maxf(0.0,clear-2.0)
			shot_dir = (e.action_target - muzzle).normalized()
			e.A.ebul.append({"x":muzzle.x, "y":muzzle.y, "vx":shot_dir.x * 240.0, "vy":shot_dir.y * 240.0,
				"r":7.0, "dmg":e.dmg, "t":muzzle.distance_to(e.action_target) / 240.0, "blast":72.0, "col":Color("#ffd574")})
			e.A.poof(muzzle.x,muzzle.y,Color("#ffda88"),7,85,3)
			e.action_phase = ""; e.action_cd = 4.4; e.A.snd("slam"); e.A.shake = maxf(e.A.shake, 3.0)
	else:
		e.action_cd -= dt
		if distance > 350.0 or not _clear(e, dir, distance): _advance(e, Vector2(e.A.P.x, e.A.P.y), speed, dt)
		if e.action_cd <= 0.0 and distance < 650.0 and distance > 230.0 and _clear(e, dir, distance):
			e.action_phase = "windup"; e.action_t = 1.1; e.action_dir = dir; e.action_target = Vector2(e.A.P.x, e.A.P.y)
	if e.action_phase == "windup": e.aim_dir = e.action_dir

## Only direct weapon hits are shielded. Explosions, lightning and status damage bypass the shield.
static func shield_multiplier(e, options: Dictionary) -> float:
	var block := float(Run.ET[e.type].get("shield", 0.0))
	if block <= 0.0 or not options.get("proc", false) or options.get("element", "physical") != "physical" or e.frozen_t > 0.0 or e.time_lock > 0.0: return 1.0
	var incoming := Vector2(e.A.P.x - e.x, e.A.P.y - e.y).normalized()
	if options.has("kx"): incoming = -Vector2(options.kx, options.get("ky", 0.0)).normalized()
	if incoming.dot(e.aim_dir) > 0.35:
		e.shield_flash = 0.14
		return 1.0 - block
	return 1.0

## Gunmen paint a thin laser sight on the villain just before they fire (detective shot, rifle burst).
const SIGHT_T := 0.45
static func _sight(e) -> void:
	if e.A == null or e.A.P == null or not e.ranged or e.vehicle: return
	var ready: bool
	if e.behavior == "rifle": ready = e.burst_left <= 0 and e.shoot_cd < SIGHT_T
	elif e.behavior == "marksman": ready = e.action_phase in ["aim","cornered"]
	else: ready = e.behavior == "" and e.shoot_cd < SIGHT_T
	if not ready: return
	var to := Vector2(e.A.P.x - e.x, e.A.P.y - e.y)
	var reach := float(Run.ET[e.type].get("range", 380)) + (85.0 if e.behavior == "rifle" else 0.0)
	if to.length() > reach or to.x * e.face < 0.0: return
	var k := clampf(1.0 - maxf(0.0, e.action_t if e.behavior == "marksman" else e.shoot_cd) / SIGHT_T, 0.0, 1.0)
	var from := EnemyView.muzzle_local(e)
	var end := to + Vector2(0, -14)
	var col := Color("#ff3a3a", 0.18 + 0.5 * k)
	e.draw_line(from, end, col, 1.0)
	e.draw_circle(end, 1.5 + 1.5 * k, col)

static func draw_warning(e) -> void:
	if e.ally or e.frozen_t > 0.0 or e.time_lock > 0.0: return
	if e.hero == "vex" or e.behavior in ["vex_sentry","vex_mine"]:
		preload("res://game/rival_scientist.gd").draw_warning(e)
		return
	if e.type == "swat_shield":
		var a: float = e.aim_dir.angle()
		e.draw_arc(Vector2.ZERO, e.r + 5.0, a - 1.1, a + 1.1, 16, Color("#c5f5ff") if e.shield_flash > 0.0 else Color("#60bcd1", 0.55), 2.0)
	if e.hero == "viper" and e.action_phase == "windup":
		var previous := Vector2.ZERO
		for point in e.zig_points:
			var end: Vector2 = point - Vector2(e.x,e.y)
			e.draw_line(previous,end,Color("#ff70b8",0.55),3.0)
			e.draw_circle(end,6.0,Color("#ffb2d8",0.65)); previous = end
		return
	_sight(e)
	if e.action_phase != "windup": return
	var col := Color("#ffb044", 0.65)
	var start := Vector2.ZERO
	var end: Vector2 = e.action_target - Vector2(e.x, e.y)
	if e.behavior == "cannon":
		e.draw_line(start, end, col, 2.0)
		e.draw_arc(end, 72.0, 0.0, TAU, 40, col, 2.0)
		e.draw_line(end - Vector2(12, 0), end + Vector2(12, 0), col, 2.0)
		e.draw_line(end - Vector2(0, 12), end + Vector2(0, 12), col, 2.0)
	else:
		var width: float = 12.0 if e.behavior == "pounce" else e.r
		end = e.action_dir * (145.0 if e.behavior == "pounce" else 410.0)
		var side: Vector2 = e.action_dir.orthogonal() * width
		e.draw_colored_polygon(PackedVector2Array([start-side, end-side, end+side, start+side]), Color(col, 0.10))
		e.draw_line(start-side, end-side, col, 1.0); e.draw_line(start+side, end+side, col, 1.0)
		e.draw_line(end-e.action_dir*14-side*0.4, end, col, 2.0); e.draw_line(end-e.action_dir*14+side*0.4, end, col, 2.0)

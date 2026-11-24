extends RefCounted
## LT / right mouse with an empty off hand: a palm shove in the direction he faces.
## It does no damage itself. Enemies driven into a wall, a car or each other are slammed: hurt and stunned.

const RANGE := 118.0           # reach from his centre, plus the enemy's radius
const HALF_ANGLE := 0.87       # about 50 degrees either side of the aim
const POINT_BLANK := 30.0      # bodies overlapping him count unless they are behind
const DISTANCE := 175.0        # push at point blank
const FAR_SHARE := 0.55        # share of it at full reach
const HEAVY_SHARE := 0.35
const TRAVEL := 0.26           # seconds an enemy slides
const COOLDOWN := 1.0
const SWING := 0.34            # arm animation
const CONTACT := 0.10          # the palm lands this long after the press
const BUFFER := 0.12
const SLAM_STUN := 0.9
const BUMP_STUN := 0.5

var cd := 0.0
var t := 0.0                   # time left in the arm animation
var aim := 0.0
var buffer_t := 0.0
var _landed := true
var sliding: Array = []        # {e, dir, left, total, hit}
var waves: Array = []

func reset() -> void:
	cd = 0.0; t = 0.0; buffer_t = 0.0; _landed = true; sliding.clear(); waves.clear()

func active() -> bool: return t > 0.0
func progress() -> float: return clampf(1.0 - t / SWING, 0.0, 1.0)
func press() -> void: buffer_t = BUFFER
static func available(run) -> bool: return run.build.off == null

## `pointing` is the raw right-stick (or mouse) direction; without it the current aim is used.
func update(a, dt: float, run, blocked: bool, pointing := NAN) -> void:
	aim = a.P.aim if is_nan(pointing) else pointing
	cd = maxf(0.0, cd - dt); buffer_t = maxf(0.0, buffer_t - dt)
	for w in waves: w.t -= dt
	waves = waves.filter(func(w): return w.t > 0.0)
	if buffer_t > 0.0 and cd <= 0.001 and t <= 0.0 and not blocked and available(run):
		t = SWING; cd = COOLDOWN; buffer_t = 0.0; _landed = false
		a.P.cackle_t = 0.0
	if t > 0.0:
		t = maxf(0.0, t - dt)
		if not _landed and SWING - t >= CONTACT - 0.0001: _landed = true; _strike(a)
	_slide(a, dt, run)

func _strike(a) -> void:
	# `aim` is live, so a turn during the wind-up still counts.
	var origin := Vector2(a.P.x, a.P.y); var forward := Vector2.from_angle(aim); var caught := 0
	for e in a.enemies:
		if e.dead or e.ally or e.boss or e.vehicle or e.behavior in ["vex_sentry", "vex_mine"]: continue
		var to := Vector2(e.x, e.y) - origin; var gap := to.length()
		if gap > RANGE + e.r: continue
		if gap > POINT_BLANK + e.r:
			if absf(forward.angle_to(to)) > HALF_ANGLE: continue
		elif forward.dot(to) < -4.0: continue
		if not a.nav.clear_segment(origin, Vector2(e.x, e.y), 0.0): continue
		var share := lerpf(1.0, FAR_SHARE, clampf(gap / RANGE, 0.0, 1.0)) * (HEAVY_SHARE if e.heavy else 1.0)
		# Mostly straight ahead with a little spread, so a crowd fans away from him.
		_send(e, (forward * 1.6 + to.normalized()).normalized(), DISTANCE * share, [])
		caught += 1
	waves.append({"at": origin, "aim": aim, "t": 0.22})
	a.snd("punch" if caught > 0 else "throw")
	if caught > 0:
		a.shake = maxf(a.shake, 3.0); a.get_node("/root/Controls").rumble(0.2, 0.45, 90)

func _send(e, dir: Vector2, distance: float, hit: Array) -> void:
	for s in sliding:
		if s.e == e:
			s.dir = dir; s.left = TRAVEL; s.total = distance; return
	sliding.append({"e": e, "dir": dir, "left": TRAVEL, "total": distance, "hit": hit})
	e.stun_t = maxf(e.stun_t, TRAVEL)
	if not e.heavy:
		# A shove breaks a wind-up.
		e.action_phase = ""; e.burst_left = 0; e.atk_cd = maxf(e.atk_cd, 0.45); e.shoot_cd = maxf(e.shoot_cd, 0.7)

func _slide(a, dt: float, run) -> void:
	for s in sliding.duplicate():
		if not is_instance_valid(s.e) or s.e.dead: sliding.erase(s); continue
		var e = s.e
		var step := minf(dt, s.left)
		var u0: float = 1.0 - s.left / TRAVEL; s.left -= step; var u1: float = 1.0 - s.left / TRAVEL
		# Ease out; the whole slide covers exactly `total` at any frame rate.
		var travel: float = ((1.0 - u0) * (1.0 - u0) - (1.0 - u1) * (1.0 - u1)) * s.total
		var from := Vector2(e.x, e.y); var to: Vector2 = from + s.dir * travel
		if not e.fly:
			var contact: Dictionary = a._projectile_wall_hit(from, to, e.r)
			if not contact.is_empty():
				to = from.lerp(to, maxf(0.0, contact.fraction - 0.01))
				e.x = to.x; e.y = to.y; sliding.erase(s)
				# Grazing along a wall is not a slam.
				if s.dir.dot(-contact.normal) > 0.35: _slam(a, e, run, 1.0, SLAM_STUN)
				continue
		e.x = to.x; e.y = to.y
		for o in a.enemies.duplicate():
			if o == e or o.dead or o.ally or o.civ or s.hit.has(o) or sliding.any(func(q): return q.e == o): continue
			if Vector2(o.x - e.x, o.y - e.y).length() > o.r + e.r: continue
			s.hit.append(o)
			_slam(a, e, run, 0.5, BUMP_STUN); _slam(a, o, run, 0.5, BUMP_STUN)
			if not o.dead and not o.boss and not o.vehicle: _send(o, s.dir, s.total * 0.4 * (HEAVY_SHARE if o.heavy else 1.0), [e])
			s.total *= 0.6
			if e.dead: break
		if s.left <= 0.0 or e.dead: sliding.erase(s)

func _slam(a, e, run, scale: float, stun: float) -> void:
	if not e.boss and not e.vehicle: e.stun_t = maxf(e.stun_t, stun)
	a.poof(e.x, e.y, Color("#e8d8b0"), int(10 * scale) + 3, 110, 2.5)
	a.shake = maxf(a.shake, 4.0 * scale); a.snd("thud")
	a.hit(e, (6.0 + run.D.dmg * 0.8) * scale, {"col": Color("#ffd890")})

## Thin ripples of air leaving the palm. The palm's place is read once, when its first ripple is drawn.
func draw(g: Node2D, a) -> void:
	for w in waves:
		if not w.has("palm"): w.palm = a.villain.rig.palm_global(); w.aim = aim
		var k: float = 1.0 - w.t / 0.22
		var reach: float = maxf(40.0, RANGE - Vector2(w.at).distance_to(w.palm) + 12.0)
		for ring in 3:
			var radius := lerpf(3.0, reach, clampf(k * 1.15 - ring * 0.13, 0.0, 1.0))
			g.draw_arc(w.palm, radius, w.aim - HALF_ANGLE, w.aim + HALF_ANGLE, 18, Color(0.75, 0.9, 1.0, 0.55 * (1.0 - k) * (1.0 - ring * 0.28)), 1.5 - ring * 0.35, true)

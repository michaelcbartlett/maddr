extends RefCounted
## Shock Grapple: the "hook" ammo on the main gun (RT / left mouse).
## Hold fire: the hook flies out along the aim and bites into the first wall (or the arena edge) it reaches.
## While fire is held, the chain stays tight between the muzzle and the anchor. The villain can keep moving, but no
## further than the chain's length from the anchor. Every cop touching the live chain is shocked on a timer.
## Release fire, miss, or let a wall come between you and the anchor, and the hook reels back in.
## Frame stats: range sets the chain length, width how thick (and so how easy to touch) it is, fire rate the shock rate.

const SPEED := 1250.0          # hook flight speed
const REEL := 1900.0           # reel-in speed
const LENGTH_MUL := 1.35       # chain length = range x this
const COLOR := Color("#7df9ff")

var state := "idle"            # idle | fly | anchored | reel
var head := Vector2.ZERO       # hook position (world)
var dir := Vector2.RIGHT       # flight direction
var travelled := 0.0
var cd := 0.0                  # short wait after reeling in before the next launch
var flown: Dictionary = {}     # enemies already struck by the hook in flight
var shock_cd: Dictionary = {}  # enemy -> seconds until it can be shocked again
var bite_t := 0.0              # anchor flash after the hook bites

func reset() -> void:
	state = "idle"; travelled = 0.0; cd = 0.0; flown = {}; shock_cd = {}; bite_t = 0.0

func is_out() -> bool: return state != "idle"
func anchored() -> bool: return state == "anchored"

static func chain_length(D: Dictionary) -> float: return float(D.range) * LENGTH_MUL
## Seconds between shocks on the same cop. Faster frames shock faster.
static func shock_interval(D: Dictionary) -> float: return clampf(float(D.cd) * 0.5, 0.12, 0.55)
static func shock_damage(D: Dictionary) -> float: return float(D.dmg) * 0.6
static func flight_damage(D: Dictionary) -> float: return float(D.dmg) * 1.2

## One play step. `muzzle` is the rendered muzzle, `aim` the gun angle, `D` the derived gun stats (Run.D).
## Returns "launch" or "bite" on the frame that happens (the arena adds recoil/rumble), otherwise "".
func update(A, dt: float, firing: bool, muzzle: Vector2, aim: float, D: Dictionary) -> String:
	cd = maxf(0.0, cd - dt); bite_t = maxf(0.0, bite_t - dt)
	for e in shock_cd.keys():
		shock_cd[e] -= dt
		if shock_cd[e] <= 0.0 or not is_instance_valid(e) or e.dead: shock_cd.erase(e)
	match state:
		"idle":
			if firing and cd <= 0.0:
				state = "fly"; head = muzzle; dir = Vector2.from_angle(aim); travelled = 0.0; flown = {}
				A.snd("raz"); A.blaster_fx.muzzle(muzzle, dir, COLOR)
				return "launch"
		"fly":
			if not firing: state = "reel"; return ""
			var step := minf(SPEED * dt, chain_length(D) - travelled)
			var length: float = A.ray_len(head.x, head.y, dir.x, dir.y, step)
			var finish := head + dir * length
			# the arena edge holds the hook too
			var edge := _edge_hit(A, head, finish)
			if edge >= 0.0: finish = head.lerp(finish, edge); length *= edge
			_strike_in_flight(A, head, finish, D)
			head = finish; travelled += length
			if length < step - 0.01 or edge >= 0.0: _bite(A); return "bite"
			elif travelled >= chain_length(D) - 0.01: state = "reel"
		"anchored":
			if not firing: state = "reel"; return ""
			_tether(A, D)
			var origin := muzzle
			var span := head - origin
			# a wall between the gun and the anchor snaps the chain
			if span.length() > 6.0:
				var n := span.normalized()
				if A.ray_len(origin.x, origin.y, n.x, n.y, span.length()) < span.length() - 6.0:
					A.blaster_fx.impact(head, -n, COLOR); A.poof(head.x, head.y, COLOR, 6, 120, 2); A.snd("hum")
					state = "reel"; return ""
			_shock(A, origin, head, D)
		"reel":
			var to := muzzle - head; var d := to.length()
			if d <= REEL * dt + 4.0: state = "idle"; cd = 0.18; head = muzzle
			else: head += to / d * REEL * dt
	return ""

func _bite(A) -> void:
	state = "anchored"; bite_t = 0.2
	A.blaster_fx.impact(head, -dir, COLOR); A.poof(head.x, head.y, Color("#dff8ff"), 8, 160, 2)
	A.shake = maxf(A.shake, 3.0); A.snd("bul")

## Fraction along start->finish where the hook meets the arena edge, or -1.
func _edge_hit(A, start: Vector2, finish: Vector2) -> float:
	var best := -1.0
	for axis in 2:
		var low := 12.0; var high: float = (A.AW if axis == 0 else A.AH) - 12.0
		var delta: float = finish[axis] - start[axis]
		if absf(delta) < 0.00001: continue
		var f := -1.0
		if finish[axis] < low: f = (low - start[axis]) / delta
		elif finish[axis] > high: f = (high - start[axis]) / delta
		if f >= 0.0 and (best < 0.0 or f < best): best = clampf(f, 0.0, 1.0)
	return best

func _strike_in_flight(A, start: Vector2, finish: Vector2, D: Dictionary) -> void:
	preload("res://game/viper_boss.gd").intercept(A,start,finish,5.0)
	for e in A.live_foes():
		if flown.has(e): continue
		if _seg_dist(Vector2(e.x, e.y), start, finish) > e.r + 5.0: continue
		flown[e] = true
		A.hit(e, flight_damage(D), {"proc": true, "kx": dir.x * 0.5, "ky": dir.y * 0.5, "col": COLOR})
		A.blaster_fx.impact(Vector2(e.x, e.y), -dir, COLOR)

## The chain doesn't stretch: the villain can't walk further than its length from the anchor.
func _tether(A, D: Dictionary) -> void:
	var P = A.P
	var off := Vector2(P.x, P.y) - head; var limit := chain_length(D)
	if off.length() > limit:
		var p := head + off.normalized() * limit
		P.x = p.x; P.y = p.y
		if not A.walls.is_empty(): A.collide_walls(P, P.r)

func _shock(A, origin: Vector2, anchor: Vector2, D: Dictionary) -> void:
	var reach := float(D.width) * 0.5 + 3.0
	var interval := shock_interval(D)
	preload("res://game/viper_boss.gd").intercept(A,origin,anchor,reach)
	for e in A.live_foes():
		if shock_cd.has(e): continue
		var pos := Vector2(e.x, e.y)
		var near := _closest(pos, origin, anchor)
		if near.distance_to(pos) > e.r + reach: continue
		shock_cd[e] = interval
		A.hit(e, shock_damage(D), {"proc": true, "pfm": interval / float(D.cd), "col": COLOR, "silent": randf() < 0.5, "element":"lightning"})
		A.arcs.append({"x1": near.x, "y1": near.y, "x2": e.x, "y2": e.y, "t": 0.12})
		if randf() < 0.4: A.snd("hum")

static func _closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a; var l2 := ab.length_squared()
	if l2 < 0.0001: return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float: return p.distance_to(_closest(p, a, b))

# =============== DRAWING (arena fx layers) ===============
## Additive layer: the chain's electric glow and crackle.
func draw_glow(g: Node2D, origin: Vector2, time: float) -> void:
	if not is_out(): return
	var live := anchored()
	g.draw_line(origin, head, Color(COLOR, 0.35 if live else 0.12), 7.0 if live else 4.0)
	if not live: return
	var span := head - origin; var n := span.length()
	if n < 2.0: return
	var side := Vector2(-span.y, span.x) / n
	var steps := clampi(int(n / 14.0), 3, 40)
	for strand in 2:
		var pts := PackedVector2Array([origin])
		for i in range(1, steps):
			pts.append(origin + span * (float(i) / steps) + side * randf_range(-5.0, 5.0))
		pts.append(head)
		g.draw_polyline(pts, Color("#fff36b") if strand == 0 else Color("#bff4ff"), 1.5)
	if bite_t > 0.0: g.draw_circle(head, 16.0 * bite_t / 0.2 + 6.0, Color(COLOR, 0.5))
	g.draw_circle(head, 7.0 + sin(time * 30.0) * 1.5, Color(COLOR, 0.35))

## Top layer: steel links and the claw.
func draw_chain(g: Node2D, origin: Vector2) -> void:
	if not is_out(): return
	var span := head - origin; var n := span.length()
	if n > 1.0:
		var u := span / n
		var link := 0.0; var k := 0
		while link < n:
			var c := origin + u * link
			var long := u * 3.0; var short := Vector2(-u.y, u.x) * (1.5 if k % 2 == 0 else 0.6)
			g.draw_line(c - long, c + long, Color("#2a3038"), 3.0)
			g.draw_line(c - long + short * 0.3, c + long + short * 0.3, Color("#aab8c6") if k % 2 == 0 else Color("#6c7884"), 1.5)
			link += 6.0; k += 1
	draw_claw(g, head, dir if state != "reel" else (origin - head).normalized() * -1.0, anchored())

static func draw_claw(g: Node2D, at: Vector2, facing: Vector2, live: bool) -> void:
	g.draw_set_transform(at, facing.angle())
	g.draw_rect(Rect2(-6, -2, 7, 4), Color("#2a3038"))
	g.draw_rect(Rect2(-5, -1, 6, 2), Color("#c8d2dc"))
	for s in [-1.0, 1.0]:
		var tip := Vector2(5, 6.0 * s) if live else Vector2(6, 4.0 * s)
		g.draw_line(Vector2(0, 1.5 * s), Vector2(3, 5.0 * s), Color("#2a3038"), 3.0)
		g.draw_line(Vector2(3, 5.0 * s), tip + Vector2(2, -2.0 * s), Color("#2a3038"), 3.0)
		g.draw_line(Vector2(0, 1.5 * s), Vector2(3, 5.0 * s), Color("#dfe6ec"), 1.5)
		g.draw_line(Vector2(3, 5.0 * s), tip + Vector2(2, -2.0 * s), Color("#dfe6ec"), 1.5)
	g.draw_rect(Rect2(-1, -1, 2, 2), COLOR)
	g.draw_set_transform(Vector2.ZERO)

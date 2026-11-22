extends RefCounted
## Velvet Viper's committed zigzag and interceptable, arena-wide seeker missiles.
const Geometry = preload("res://game/shot_geometry.gd")
const COLOR := Color("#ff70b8")
const MISSILE_CAP := 6

static func zigzag(origin: Vector2, direction: Vector2, stride := 135.0, width := 80.0) -> PackedVector2Array:
	var side := direction.orthogonal()
	return PackedVector2Array([origin + direction * stride + side * width,
		origin + direction * stride * 2.0 - side * width,
		origin + direction * stride * 3.0])

static func tick(e, dt: float, speed: float) -> void:
	var a = e.A
	var origin := Vector2(e.x, e.y)
	var target := Vector2(a.P.x, a.P.y)
	var direction := origin.direction_to(target)
	var rage: bool = e.hp < e.max_hp * 0.5
	e.missile_cd -= dt
	if e.missile_cd <= 0.0:
		e.missile_cd = 3.5 if rage else 4.5
		var available: int = MISSILE_CAP - a.ebul.filter(func(b): return b.get("seeker", false) and b.t > 0.0).size()
		for i in mini(3 if rage else 2, available):
			var launch := direction.rotated(-0.65 if i % 2 == 0 else 0.65)
			a.ebul.append({"x":e.x, "y":e.y - 18, "vx":launch.x * 265.0, "vy":launch.y * 265.0,
				"r":9.0, "dmg":e.dmg * 0.65, "t":24.0, "seeker":true, "owner":e, "col":COLOR, "trail":PackedVector2Array()})
		if available > 0: a.snd("charge")
	match e.action_phase:
		"windup":
			e.action_t -= dt
			if e.action_t <= 0.0: e.action_phase = "zigzag"; e.zig_cursor = 0; a.snd("charge")
		"zigzag":
			var goal: Vector2 = e.zig_points[e.zig_cursor]
			var step := origin.move_toward(goal, (680.0 if rage else 590.0) * dt)
			# End a rush on a prop; never slide through it or keep attacking against it.
			if not a.nav.clear_segment(origin, step, e.r):
				e.action_phase = "recover"; e.action_t = 0.85
			else:
				e.x = step.x; e.y = step.y
				if e.atk_cd <= 0.0 and Geometry.circle_fraction(origin, step, target, e.r + a.P.r) >= 0.0:
					a.hurt_player(e.dmg); e.atk_cd = 1.0
				a.part(e.x, e.y - 10, 0, 0, 0.16, COLOR, 5)
				if step.distance_to(goal) < 1.0:
					e.zig_cursor += 1
					if e.zig_cursor >= e.zig_points.size(): e.action_phase = "recover"; e.action_t = 0.85
		"recover":
			e.action_t -= dt
			if e.action_t <= 0.0: e.action_phase = ""; e.action_cd = 2.0 if rage else 3.0
		_:
			e.action_cd -= dt
			var distance := origin.distance_to(target)
			var approach := 1.0 if distance > 310.0 else (-0.6 if distance < 190.0 else 0.0)
			var move := (direction * approach + direction.orthogonal() * 0.7) * speed * dt
			e._move(move.x, move.y)
			if e.action_cd <= 0.0:
				e.zig_points = zigzag(Vector2(e.x, e.y), direction)
				for i in e.zig_points.size(): e.zig_points[i] = e.zig_points[i].clamp(Vector2.ONE * 35.0, Vector2(a.AW - 35, a.AH - 35))
				e.action_phase = "windup"; e.action_t = 0.55
				e.action_dir = direction; e.action_target = target
	e.face = 1 if direction.x >= 0.0 else -1

static func destroy(a, missile: Dictionary) -> void:
	if missile.t <= 0.0: return
	missile.t = 0.0
	a.poof(missile.x, missile.y, COLOR, 9, 100, 3)
	a.booms.append({"x":missile.x, "y":missile.y, "r":22.0, "t":0.2, "col":COLOR})
	a.snd("break")

static func intercept(a, start: Vector2, finish: Vector2, width: float) -> void:
	for b in a.ebul:
		if b.get("seeker", false) and b.t > 0.0 and Geometry.circle_fraction(start, finish, Vector2(b.x,b.y), b.r + width) >= 0.0: destroy(a, b)

static func update_missile(a, b: Dictionary, dt: float) -> void:
	if b.t <= 0.0: return
	if not is_instance_valid(b.owner) or b.owner.dead: destroy(a, b); return
	if b.get("time_lock", 0.0) > 0.0: b.time_lock = maxf(0.0, b.time_lock - dt); return
	var old := Vector2(b.x, b.y)
	var velocity := Vector2(b.vx, b.vy)
	# Disguise breaks new targeting; already-launched missiles remain dangerous.
	if a.P.disguise_t <= 0.0:
		velocity = Vector2.from_angle(rotate_toward(velocity.angle(), old.angle_to_point(Vector2(a.P.x,a.P.y)), 2.6 * dt)) * 265.0
	var finish := old + velocity * dt
	# Seekers fly over props, with finite fuel and an active cap to bound pressure.
	if finish.x < 12.0 or finish.x > a.AW - 12.0: velocity.x = -velocity.x
	if finish.y < 12.0 or finish.y > a.AH - 12.0: velocity.y = -velocity.y
	finish = (old + velocity * dt).clamp(Vector2.ONE * 12.0, Vector2(a.AW - 12, a.AH - 12))
	b.vx = velocity.x; b.vy = velocity.y; b.x = finish.x; b.y = finish.y; b.t -= dt
	b.trail.append(finish)
	if b.trail.size() > 16: b.trail.remove_at(0)
	if Geometry.circle_fraction(old, finish, Vector2(a.P.x,a.P.y), b.r + a.P.r) >= 0.0:
		a.hurt_player(b.dmg); destroy(a, b)

static func draw_missile(g: Node2D, b: Dictionary, friendly := false) -> void:
	if b.get("t", b.get("life", 0.0)) <= 0.0: return
	var col := Color("#83f4d0") if friendly else COLOR
	if b.trail.size() > 1: g.draw_polyline(b.trail, Color(col, 0.5), 4.0)
	g.draw_set_transform(Vector2(b.x,b.y), Vector2(b.vx,b.vy).angle())
	g.draw_line(Vector2(-11,0), Vector2(-21,0), Color("#ffbd68"), 5.0)
	g.draw_colored_polygon(PackedVector2Array([Vector2(-10,-4),Vector2(5,-4),Vector2(12,0),Vector2(5,4),Vector2(-10,4)]), Color("#e1e7f0"))
	g.draw_line(Vector2(-7,-7), Vector2(-7,7), col, 3.0)
	g.draw_circle(Vector2(6,0), 2.5, col)
	g.draw_set_transform(Vector2.ZERO)

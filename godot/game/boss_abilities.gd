extends RefCounted
## Boss blueprint rewards: a secondary seeker rack and B-button movement attacks.
const Viper = preload("res://game/viper_boss.gd")
const Geometry = preload("res://game/shot_geometry.gd")
const RARE_DROP_CHANCE := 0.2

static func drop_rewards(a, hero: String, at: Vector2, rare_roll: float) -> void:
	if hero == "viper":
		a.drop_blueprint("seeker_rack", at)
		if rare_roll < RARE_DROP_CHANCE: a.drop_blueprint("zigzag", at + Vector2(38,0))
	elif hero == "ironclad":
		a.drop_blueprint("boots", at)
		if rare_roll < RARE_DROP_CHANCE: a.drop_blueprint("iron_slam", at + Vector2(38,0))

static func targets(a, center: Vector2, radius: float) -> Array:
	var foes: Array = a.enemies.filter(func(e): return not e.dead and not e.ally and not e.civ and center.distance_to(Vector2(e.x,e.y)) <= radius)
	foes.sort_custom(func(e,f): return center.distance_squared_to(Vector2(e.x,e.y)) < center.distance_squared_to(Vector2(f.x,f.y)))
	return foes

static func launch_rockets(a) -> bool:
	var run = a.get_node("/root/Run")
	var origin := Vector2(a.P.x,a.P.y - 12)
	var foes := targets(a, origin, 500.0)
	if foes.is_empty(): return false
	for i in 3:
		var target = foes[i % foes.size()]
		var direction := Vector2.from_angle(a.P.aim + (i - 1) * 0.55)
		a.projs.append({"type":"rocket", "x":origin.x, "y":origin.y, "vx":direction.x * 370.0, "vy":direction.y * 370.0,
			"r":7.0, "dmg":run.D.dmg * 1.4 + 6.0, "life":6.0, "target":target, "trail":PackedVector2Array([origin])})
	a.P.recoil2 = 1.0; a.P.flash_t2 = 0.12; a.snd("charge")
	return true

static func update_rocket(a, p: Dictionary, dt: float) -> void:
	var run = a.get_node("/root/Run")
	p.life -= dt
	if p.life <= 0.0: return
	var old := Vector2(p.x,p.y)
	if not is_instance_valid(p.target) or p.target.dead or p.target.ally or p.target.civ:
		var foes := targets(a, old, 700.0)
		p.target = null if foes.is_empty() else foes[0]
	var velocity := Vector2(p.vx,p.vy)
	if p.target != null:
		velocity = Vector2.from_angle(rotate_toward(velocity.angle(), old.angle_to_point(Vector2(p.target.x,p.target.y)), 5.0 * dt)) * 370.0
	var finish := old + velocity * dt
	var wall: Dictionary = a._projectile_wall_hit(old, finish, p.r)
	if not wall.is_empty(): finish = old.lerp(finish, wall.fraction)
	var first := 2.0
	for e in a.enemies:
		if e.dead or e.ally or e.civ: continue
		var f := Geometry.circle_fraction(old, finish, Vector2(e.x,e.y), p.r + e.r)
		if f >= 0.0: first = minf(first, f)
	Viper.intercept(a, old, old.lerp(finish,minf(first,1.0)), p.r)
	if first <= 1.0: finish = old.lerp(finish, first)
	p.x = finish.x; p.y = finish.y; p.vx = velocity.x; p.vy = velocity.y; p.trail.append(finish)
	if p.trail.size() > 16: p.trail.remove_at(0)
	if first <= 1.0 or not wall.is_empty():
		p.life = 0.0; a.explode(p.x,p.y,p.dmg,48.0 * sqrt(run.S.boomMul),Color("#83f4d0"))

static func start_action(a, kind: String) -> bool:
	if not a.boss_move.is_empty() or a.action_cooldown > 0.0: return false
	var origin := Vector2(a.P.x,a.P.y)
	var direction: Vector2 = a.get_node("/root/Controls").move_vec()
	if direction.length() < 0.2: direction = Vector2.from_angle(a.P.aim)
	direction = direction.normalized()
	var points := Viper.zigzag(origin, direction, 100.0, 65.0) if kind == "zigzag" else PackedVector2Array([origin + direction * 245.0])
	var previous := origin
	for i in points.size():
		points[i] = points[i].clamp(Vector2.ONE * 28.0, Vector2(a.AW - 28,a.AH - 28))
		var contact: Dictionary = a._projectile_wall_hit(previous, points[i], a.P.r)
		if not contact.is_empty():
			points[i] = previous.lerp(points[i],maxf(0.0,contact.fraction - 0.02))
			points.resize(i + 1); break
		previous = points[i]
	if origin.distance_to(points[0]) < 5.0: return false
	a.P.disguise_t = 0.0; a.grapple.reset()
	a.boss_move = {"kind":kind, "points":points, "cursor":0, "hit":{}, "time":0.0, "origin":origin}
	a.action_cooldown = 7.0 if kind == "zigzag" else 10.0
	a.snd("charge" if kind == "zigzag" else "leap")
	return true

static func update_action(a, dt: float) -> void:
	var run = a.get_node("/root/Run")
	a.action_cooldown = maxf(0.0,a.action_cooldown-dt)
	if a.boss_move.is_empty(): return
	var m: Dictionary = a.boss_move
	var old := Vector2(a.P.x,a.P.y)
	var goal: Vector2 = m.points[m.cursor]
	m.time += dt
	var finish := old.move_toward(goal, 760.0 * dt)
	if m.kind == "iron_slam": finish = m.origin.lerp(goal,minf(1.0,m.time / 0.65))
	# Keep the stored path valid even if scenery changed after activation.
	var contact: Dictionary = a._projectile_wall_hit(old,finish,a.P.r)
	if not contact.is_empty(): finish = old.lerp(finish,maxf(0.0,contact.fraction - 0.01))
	a.P.x = finish.x; a.P.y = finish.y; a.P.moving = true
	a.P.inv = maxf(a.P.inv,0.12)
	if m.kind == "zigzag":
		for e in a.enemies.duplicate():
			if e.dead or e.ally or e.civ or m.hit.has(e): continue
			if Geometry.circle_fraction(old,finish,Vector2(e.x,e.y),e.r + a.P.r + 10.0) >= 0.0:
				m.hit[e] = true; a.hit(e,run.D.dmg * 1.8 + 10.0,{"col":Viper.COLOR})
		a.part(finish.x,finish.y - 8,0,0,0.18,Viper.COLOR,6)
	if finish.distance_to(goal) < 1.0 or not contact.is_empty():
		m.cursor += 1
		if m.cursor >= m.points.size():
			if m.kind == "iron_slam":
				a.explode(finish.x,finish.y,run.D.dmg * 3.0 + 20.0,115.0 * sqrt(run.S.boomMul),Color("#ffd890"))
				a.shake = 10.0; a.snd("slam")
			a.boss_move = {}

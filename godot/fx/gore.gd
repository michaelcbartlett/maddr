extends Node2D
## Blood and gore: directional spray, gibs, growing pools, floor stains and bloody footprints. Visual only.
## This node draws floor marks under pickups and actors; `air` draws flying drops and gibs over the actors.
## Stains are baked in small batches so only the newest batch is rebuilt. Has its own RNG: never touches gameplay rolls.
const MAX_DROPS := 320
const MAX_GIBS := 70
const MAX_POOLS := 45
const BATCH := 48
const MAX_BATCHES := 16        # about 770 marks before the oldest are dropped
const PX := 2.0
const GRAVITY := 620.0
const FLESH := [Color("#8f0d12"), Color("#b3151a"), Color("#6b070c"), Color("#d0252a")]
const OIL := [Color("#15171a"), Color("#26292e"), Color("#0c0d0f"), Color("#3b4048")]
const MEAT := [Color("#a51a20"), Color("#7a0e14"), Color("#5a090e"), Color("#b8937f")]
const METAL := [Color("#596069"), Color("#343a42"), Color("#8b949e"), Color("#22262b")]
const MACHINES := ["drone", "robodog", "vex_sentry", "vex_mine"]
const GIB_OVERKILL := 0.4      # damage past zero, as a share of max health, that tears a body apart
const STEP := 24.0
var arena
var air: Node2D
var drops: Array = []
var gibs: Array = []
var pools: Array = []
var batches: Array = []
var rng := RandomNumberGenerator.new()
var _pool_layer: Node2D
var _steps := 0
var _last_step := Vector2.INF
var _foot := 1.0

class StainBatch extends Node2D:
	var marks: Array = []      # [Rect2, Color]
	var count := 0
	func _draw() -> void:
		for m in marks: draw_rect(m[0], m[1])

func setup(owner_arena) -> void:
	arena = owner_arena; rng.randomize()
	_pool_layer = Node2D.new(); _pool_layer.draw.connect(_draw_pools); add_child(_pool_layer)
	air = Node2D.new(); air.draw.connect(_draw_air)

func reset() -> void:
	drops.clear(); gibs.clear(); pools.clear()
	for b in batches: b.queue_free()
	batches.clear(); _steps = 0; _last_step = Vector2.INF
	_pool_layer.queue_redraw(); air.queue_redraw()

static func is_machine(e) -> bool: return e.vehicle or e.type in MACHINES
static func floor_y(e) -> float: return e.y + e.r

## A wound. `o` is the hit options from Arena.hit; its knockback gives the spray direction.
func wound(e, amount: float, o: Dictionary, crit: bool) -> void:
	if e.frozen_t > 0.0 or e.max_hp <= 0.0: return
	var silent: bool = o.get("silent", false)
	if silent and rng.randf() > 0.35: return
	var n := 2 if silent else clampi(2 + int(12.0 * amount / e.max_hp), 2, 12)
	if crit: n += 6
	spray(Vector2(e.x, floor_y(e)), e.r * 1.4, _away(e, o), n, 190.0, OIL if is_machine(e) else FLESH)
	if e.hp < e.max_hp * 0.5 and not is_machine(e): stain(Vector2(e.x, floor_y(e)) + _scatter(e.r), 2, FLESH)

## Death. Returns true when the body is torn apart and should leave no corpse.
func death(e, o: Dictionary) -> bool:
	if e.disint or e.frozen_t > 0.0 or e.vehicle: return false
	var machine := is_machine(e)
	var colors: Array = OIL if machine else FLESH
	var at := Vector2(e.x, floor_y(e))
	var dir := _away(e, o)
	var size: float = clampf(e.r / 12.0, 0.7, 2.2)
	var torn: bool = e.hp < -e.max_hp * GIB_OVERKILL or (e.boss and not machine)
	spray(at, e.r * 1.5, dir, int(16 * size), 260.0, colors)
	for i in int(6 * size): stain(at + _scatter(e.r * 1.8), rng.randi_range(2, 5), colors)
	if not machine: pool(at, e.r * rng.randf_range(2.2, 3.0))
	if torn:
		spray(at, e.r * 1.5, Vector2.ZERO, int(28 * size), 300.0, colors)
		burst(at, e.r, dir, int(9 * size), METAL if machine else MEAT, colors)
	return bool(o.get("gib", false)) and torn and not machine and not e.boss

func _away(e, o: Dictionary) -> Vector2:
	var dir := Vector2(float(o.get("kx", 0.0)), float(o.get("ky", 0.0)))
	if dir.length_squared() < 0.0001: dir = Vector2(e.x - arena.P.x, e.y - arena.P.y)
	return dir.normalized()

## dir ZERO sprays all round.
func spray(at: Vector2, height: float, dir: Vector2, n: int, speed: float, colors: Array) -> void:
	for i in n:
		var a := rng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + rng.randfn(0.0, 0.42)
		var v := Vector2.from_angle(a) * speed * rng.randf_range(0.25, 1.0)
		drops.append({"p": at, "v": Vector2(v.x, v.y * 0.75), "z": height * rng.randf_range(0.6, 1.2),
			"vz": rng.randf_range(20.0, 190.0), "s": rng.randi_range(1, 3), "c": colors, "col": colors[rng.randi() % colors.size()]})
	if drops.size() > MAX_DROPS: drops = drops.slice(drops.size() - MAX_DROPS)

func burst(at: Vector2, r: float, dir: Vector2, n: int, chunks: Array, colors: Array) -> void:
	for i in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, 210.0) + dir * 70.0
		gibs.append({"p": at + _scatter(r * 0.5), "v": Vector2(v.x, v.y * 0.75), "z": r * rng.randf_range(0.5, 1.6), "vz": rng.randf_range(110.0, 270.0),
			"w": rng.randi_range(2, 5), "h": rng.randi_range(2, 3), "col": chunks[rng.randi() % chunks.size()], "c": colors, "t": 9.0, "trail": 0.0, "rest": false})
	if gibs.size() > MAX_GIBS: gibs = gibs.slice(gibs.size() - MAX_GIBS)

func pool(at: Vector2, radius: float) -> void:
	pools.append({"p": at, "r": radius, "g": 0.1, "seed": rng.randf() * TAU})
	if pools.size() > MAX_POOLS: pools.pop_front()

func stain(at: Vector2, cells: int, colors: Array) -> void:
	if arena.in_wall(at.x, at.y): return
	var col: Color = colors[rng.randi() % colors.size()]; col.a = 0.72
	var marks: Array = []
	for i in cells:
		var size := Vector2(rng.randi_range(1, 3), rng.randi_range(1, 2)) * PX
		marks.append([Rect2(_snap(at + _scatter(cells * 1.4) if i > 0 else at), size), col])
	_bake(marks)

func _bake(marks: Array) -> void:
	if batches.is_empty() or batches.back().count >= BATCH:
		var fresh := StainBatch.new(); add_child(fresh); batches.append(fresh)
		if batches.size() > MAX_BATCHES: batches.pop_front().queue_free()
	var batch: StainBatch = batches.back()
	batch.marks.append_array(marks); batch.count += 1; batch.queue_redraw()

func player_hurt(damage: float, fatal: bool) -> void:
	var at: Vector2 = arena.villain.ground_global()
	spray(at, 34.0, Vector2.ZERO, 60 if fatal else clampi(5 + int(damage), 6, 22), 230.0 if fatal else 150.0, FLESH)
	if fatal: pool(at, 30.0); burst(at, 14.0, Vector2.ZERO, 5, MEAT, FLESH)

func update(dt: float) -> void:
	var live: Array = []
	for d in drops:
		d.p += d.v * dt; d.vz -= GRAVITY * dt; d.z += d.vz * dt
		if d.z <= 0.0: stain(d.p, d.s, d.c)
		elif not arena.in_wall(d.p.x, d.p.y): live.append(d)
	drops = live
	for g in gibs:
		g.t -= dt
		if g.rest: continue
		var next: Vector2 = g.p + g.v * dt
		if arena.in_wall(next.x, next.y): g.v *= -0.35
		else: g.p = next
		g.vz -= GRAVITY * dt; g.z += g.vz * dt; g.trail += dt
		if g.trail > 0.07: g.trail = 0.0; stain(g.p, 1, g.c)
		if g.z <= 0.0:
			g.z = 0.0; stain(g.p, 3, g.c); g.v *= 0.45
			if g.vz > -90.0: g.rest = true
			else: g.vz *= -0.38
	gibs = gibs.filter(func(g): return g.t > 0.0)
	var growing := false
	for p in pools:
		if p.g < 1.0: p.g = minf(1.0, p.g + dt * 0.55); growing = true
	if growing: _pool_layer.queue_redraw()
	_footprints()
	air.queue_redraw()

func _footprints() -> void:
	var at: Vector2 = arena.villain.ground_global()
	for p in pools:
		var d: Vector2 = at - p.p
		if Vector2(d.x, d.y * 1.8).length() < p.r * p.g: _steps = 14; break
	if _steps <= 0: return
	if _last_step == Vector2.INF: _last_step = at
	var moved := at - _last_step
	if moved.length() < STEP: return
	if moved.length() < STEP * 3.0:   # not after a dash or teleport
		_foot = -_foot
		var print_at: Vector2 = at + moved.normalized().orthogonal() * 4.0 * _foot
		var col: Color = FLESH[2]; col.a = 0.65 * _steps / 14.0
		_bake([[Rect2(_snap(print_at - Vector2(3, 2)), Vector2(6, 4)), col]])
		_steps -= 1
	_last_step = at

func _scatter(r: float) -> Vector2:
	var v := Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
	return Vector2(v.x, v.y * 0.6)

func _snap(v: Vector2) -> Vector2: return (v / PX).round() * PX

## Rows of snapped pixels: ragged edge, darker rim, wet highlight.
func _draw_pools() -> void:
	for p in pools:
		var r: float = p.r * sqrt(p.g)
		var ry := r * 0.55
		var y := -ry
		while y <= ry:
			var half := sqrt(maxf(0.0, 1.0 - (y / ry) * (y / ry))) * r + sin(y * 1.3 + p.seed) * 3.0
			if half > PX:
				_pool_layer.draw_rect(Rect2(_snap(p.p + Vector2(-half, y)), Vector2(roundf(half) * 2.0, PX)), Color(0.28, 0.015, 0.025, 0.85))
				if half > 7.0: _pool_layer.draw_rect(Rect2(_snap(p.p + Vector2(-half + 4.0, y)), Vector2(roundf(half) * 2.0 - 8.0, PX)), Color(0.46, 0.03, 0.045, 0.8))
			y += PX
		if r > 9.0: _pool_layer.draw_rect(Rect2(_snap(p.p + Vector2(-r * 0.4, -ry * 0.4)), Vector2(roundf(r * 0.35), PX)), Color(0.9, 0.35, 0.35, 0.5))

func _draw_air() -> void:
	for d in drops: air.draw_rect(Rect2(_snap(d.p - Vector2(0, d.z)), Vector2.ONE * PX * (2.0 if d.s == 3 else 1.0)), d.col)
	for g in gibs:
		var al: float = minf(1.0, g.t)
		var at := _snap(g.p - Vector2(0, g.z))
		var size := Vector2(g.w, g.h) * PX
		if g.z > 1.0: air.draw_rect(Rect2(_snap(g.p), Vector2(size.x, PX)), Color(0, 0, 0, 0.3))
		var col: Color = g.col; col.a = al
		air.draw_rect(Rect2(at + Vector2(-PX, PX), size), Color(0.14, 0.01, 0.02, al))
		air.draw_rect(Rect2(at, size), col)
		air.draw_rect(Rect2(at + Vector2(PX, -PX), Vector2(size.x - PX, PX)), col.lightened(0.18))

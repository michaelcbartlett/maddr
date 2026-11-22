extends Node2D
class_name ArenaAmbient
## Ambient life for the arena, drawn on the FX canvas layer (outside the CanvasModulate darkness):
##  - per-theme weather/atmosphere: rain + splashes and drain steam (street), wind streaks (rooftop), dust motes in
##    lamp light (bank, police, museum), harbour mist and gulls, rising holo motes (spy HQ)
##  - additive glows: lamp cones, prop emissives (police bar, headlights, monitors, gems, LEDs), pickup glints,
##    plutonium crate auras and sky beams
## The arena calls update() every frame with the camera centre; particles live in world space near the view.

var glow: Node2D            # additive child
var time := 0.0
var theme := "street"
var floor_kind := "street"
var lamp_col := Color.WHITE
var view := Rect2()
var parts: Array = []      # {p, v, t, m, k}
var gulls: Array = []
var _level
var _arena
var _spawn_acc := 0.0

func _ready() -> void:
	glow = Node2D.new()
	var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; glow.material = m
	glow.draw.connect(_draw_glow); add_child(glow)

func reset(arena, level) -> void:
	_arena = arena; _level = level
	theme = level.theme_id; floor_kind = level.theme.floor; lamp_col = level.theme.lamp
	parts.clear(); gulls.clear()

func update(dt: float, centre: Vector2, half: Vector2) -> void:
	time += dt
	view = Rect2(centre - half - Vector2(60, 60), half * 2 + Vector2(120, 120))
	for p in parts:
		p.t -= dt; p.p += p.v * dt
		match p.k:
			"steam": p.v.x += sin(time * 2.0 + p.m * 9.0) * 6.0 * dt; p.v *= 0.995
			"mote": p.v += Vector2(sin(time * 0.7 + p.m * 20.0), cos(time * 0.5 + p.m * 13.0)) * 3.0 * dt
			"bubble": p.v.x = sin(time * 6.0 + p.m * 10.0) * 10.0
	parts = parts.filter(func(p): return p.t > 0.0)
	_spawn(dt)
	queue_redraw(); glow.queue_redraw()

func _rand_in_view() -> Vector2:
	return Vector2(randf_range(view.position.x, view.end.x), randf_range(view.position.y, view.end.y))

func _add(k: String, p: Vector2, v: Vector2, t: float) -> void:
	if parts.size() < 700: parts.append({"k": k, "p": p, "v": v, "t": t, "m": randf()})

func _spawn(dt: float) -> void:
	match floor_kind:
		"street":
			_spawn_acc += dt * 260.0
			while _spawn_acc > 1.0:
				_spawn_acc -= 1.0
				var land := _rand_in_view()
				_add("rain", land - Vector2(-40, 260) * 0.35, Vector2(-40, 260) * 2.0, 0.175)   # lands on `land`
			for d in _level.decor:
				if d.kind == "grate" and view.has_point(d.pos) and randf() < dt * 5.0:
					_add("steam", d.pos + Vector2(randf_range(-9, 9), randf_range(-6, 6)), Vector2(randf_range(-5, 5), randf_range(-26, -16)), randf_range(1.6, 2.6))
		"gravel":
			if randf() < dt * 14.0: _add("wind", Vector2(view.position.x, randf_range(view.position.y, view.end.y)), Vector2(randf_range(380, 520), randf_range(-20, 20)), 3.0)
			if randf() < dt * 3.0: _add("leaf", Vector2(view.position.x, randf_range(view.position.y, view.end.y)), Vector2(randf_range(120, 200), randf_range(-30, 30)), 8.0)
		"train":   # the countryside streams past the moving train (west, away from the engine)
			if randf() < dt * 30.0: _add("wind", Vector2(view.end.x, randf_range(view.position.y, view.end.y)), Vector2(randf_range(-900, -700), 0), 2.0)
		"planks":
			if randf() < dt * 4.0: _add("mist", Vector2(randf_range(view.position.x, view.end.x), randf_range(Levels.AH - 90, Levels.AH - 30)), Vector2(randf_range(8, 20), 0), randf_range(5, 8))
			if gulls.size() < 3 and randf() < dt * 0.15:
				var y := randf_range(view.position.y + 40, view.end.y - 40)
				gulls.append({"p": Vector2(view.position.x - 40, y), "v": Vector2(randf_range(90, 130), randf_range(-15, 15)), "ph": randf() * TAU})
		"grid":
			if randf() < dt * 22.0: _add("holo", _rand_in_view(), Vector2(0, randf_range(-30, -12)), randf_range(1.5, 3.0))
	if floor_kind in ["marble", "tile", "parquet"]:
		if randf() < dt * 18.0:
			var lamp: Vector2 = _level.lamps[randi() % _level.lamps.size()]
			_add("mote", lamp + Vector2(randf_range(-110, 110), randf_range(-110, 110)), Vector2(randf_range(-4, 4), randf_range(-6, 2)), randf_range(4, 8))
	for g in gulls: g.p += g.v * dt
	gulls = gulls.filter(func(g): return g.p.x < view.end.x + 80)
	# plutonium crates bubble
	if _arena:
		for c in _arena.crates:
			if randf() < dt * 6.0: _add("bubble", Vector2(c.x + randf_range(-5, 5), c.y - 16), Vector2(0, randf_range(-30, -18)), randf_range(0.6, 1.1))

# ---------------- normal-blend layer: weather and atmosphere ----------------
func _draw() -> void:
	for p in parts:
		var f: float = p.t
		match p.k:
			"rain":
				draw_line(p.p, p.p - p.v.normalized() * 14.0, Color(0.7, 0.8, 0.95, 0.28), 1.0)
				if p.t < 0.02: draw_arc(p.p + p.v * p.t, 3.0, PI, TAU, 6, Color(0.75, 0.85, 1, 0.4), 1.0)
			"steam":
				var age := 1.0 - f / 2.6
				var al := 0.05 * minf(1.0, f) * minf(1.0, age * 6.0)
				draw_circle(p.p, 5.0 + age * 20.0, Color(0.82, 0.86, 0.9, al)); draw_circle(p.p, 2.0 + age * 12.0, Color(0.85, 0.88, 0.92, al))
			"wind": draw_line(p.p, p.p - Vector2(46, 0), Color(0.8, 0.85, 1.0, 0.09), 1.0)
			"leaf":
				draw_set_transform(p.p, time * 6.0 + p.m * 10.0, Vector2(1.0, absf(sin(time * 5.0 + p.m * 7.0)) + 0.2))
				draw_rect(Rect2(-3, -1.5, 6, 3), Color(0.55, 0.45, 0.25, 0.8)); draw_set_transform(Vector2.ZERO)
			"mist": draw_circle(p.p, 40.0, Color(0.85, 0.9, 0.95, 0.05 * minf(1.0, f) * minf(1.0, (8.0 - f))))
	for g in gulls:
		var flap := sin(time * 9.0 + g.ph) * 5.0
		draw_circle(g.p + Vector2(28, 60), 4, Color(0, 0, 0, 0.18))   # shadow far below
		draw_polyline(PackedVector2Array([g.p + Vector2(-8, flap), g.p + Vector2(-3, -1), g.p, g.p + Vector2(3, -1), g.p + Vector2(8, flap)]), Color(0.95, 0.95, 0.92), 2.0)

# ---------------- additive layer ----------------
func _draw_glow() -> void:
	if _level == null: return
	var g := glow
	# lamps: outdoor cones from the lamp head, indoor soft pools with a faint shaft
	for l in _level.lamps:
		if not view.grow(200).has_point(l): continue
		var flick := 1.0
		if theme == "street" and l == _level.lamps[2]: flick = 0.25 if fmod(time, 5.3) < 0.2 or (fmod(time, 5.3) > 0.3 and fmod(time, 5.3) < 0.36) else 1.0
		if floor_kind in ["street", "planks"]:
			var head: Vector2 = l + Vector2(18, -63)
			g.draw_polygon(PackedVector2Array([head + Vector2(-5, 0), head + Vector2(5, 0), l + Vector2(70, 10), l + Vector2(-34, 10)]),
				PackedColorArray([Color(lamp_col, 0.16 * flick), Color(lamp_col, 0.16 * flick), Color(lamp_col, 0.0), Color(lamp_col, 0.0)]))
			_blob(g, head, 14, Color(lamp_col, 0.55 * flick)); _blob(g, l + Vector2(18, 4), 70, Color(lamp_col, 0.07 * flick))
		elif floor_kind not in ["grid", "gravel"]:
			g.draw_polygon(PackedVector2Array([l + Vector2(-30, -260), l + Vector2(30, -260), l + Vector2(90, 30), l + Vector2(-90, 30)]),
				PackedColorArray([Color(lamp_col, 0.035), Color(lamp_col, 0.035), Color(lamp_col, 0.0), Color(lamp_col, 0.0)]))
	# prop emissives
	for n in _level.prop_nodes:
		if not is_instance_valid(n) or not view.grow(120).has_point(n.global_position): continue
		for e in n.glows():
			if e.glow > 0.0: _blob(g, e.pos, e.glow * (0.6 + 0.4 * e.e), Color(e.col, 0.35 * minf(1.0, e.e + 0.2)))
			if e.has("sparkle") and e.sparkle > 0.85: _star(g, e.pos + Vector2(4, 4), 9.0 * (e.sparkle - 0.85) / 0.15, Color(1, 1, 1, 0.9))
	# atmosphere glows
	for p in parts:
		match p.k:
			"mote":
				var a: float = minf(1.0, p.t) * minf(1.0, 8.0 - p.t) * 0.5
				var near := 0.0
				for l in _level.lamps: near = maxf(near, 1.0 - (p.p as Vector2).distance_to(l) / 160.0)
				if near > 0.0: g.draw_rect(Rect2(p.p, Vector2(1.5, 1.5)), Color(lamp_col, a * near))
			"holo": g.draw_rect(Rect2(p.p, Vector2(2, 2)), Color(0.3, 0.9, 1.0, 0.6 * minf(1.0, p.t)))
			"bubble": g.draw_circle(p.p, 2.0, Color(0.5, 1.0, 0.2, 0.6 * minf(1.0, p.t * 2.0)))
	if _arena == null: return
	# pickups: soft glow, periodic glint, magnet streak
	for p in _arena.pickups:
		var pos := Vector2(p.x, p.y - _arena.pickup_hop(p))
		var cash: bool = p.has("cash")
		var c := Color(0.35, 1.0, 0.45) if cash else Color(1.0, 0.8, 0.25)
		_blob(g, pos, 10.0, Color(c, 0.22))
		var ph := fmod(time * 0.7 + p.x * 0.013 + p.y * 0.007, 1.0)
		if ph < 0.08: _star(g, pos + Vector2(-3, -3), 7.0 * sin(ph / 0.08 * PI), Color(1, 1, 0.9, 0.9))
		if p.get("mag", false):
			var to := Vector2(_arena.P.x, _arena.P.y) - pos
			g.draw_line(pos, pos - to.normalized() * 12.0, Color(c, 0.45), 2.0)
	for c in _arena.crates:
		var pul := 0.5 + 0.5 * sin(c.t * 4.0)
		_blob(g, Vector2(c.x, c.y - 6), 26.0 + pul * 6.0, Color(0.5, 1.0, 0.2, 0.22 + 0.1 * pul))
		g.draw_arc(Vector2(c.x, c.y), 22.0 + fmod(c.t * 20.0, 14.0), 0, TAU, 32, Color(0.5, 1.0, 0.25, 0.4 * (1.0 - fmod(c.t * 20.0, 14.0) / 14.0)), 1.5)
		if c.t < 0.9:   # drop beam from the sky
			var a: float = 1.0 - c.t / 0.9
			g.draw_rect(Rect2(c.x - 10 * a, c.y - 600, 20 * a, 600), Color(0.6, 1.0, 0.3, 0.35 * a))
			_blob(g, Vector2(c.x, c.y), 40.0 * a + 10.0, Color(0.7, 1.0, 0.4, 0.5 * a))

func _blob(g: Node2D, p: Vector2, r: float, c: Color) -> void:
	# cheap radial falloff: stacked translucent discs
	for i in 4:
		var k := 1.0 - i * 0.24
		g.draw_circle(p, r * k, Color(c.r, c.g, c.b, c.a * 0.32))

func _star(g: Node2D, p: Vector2, r: float, c: Color) -> void:
	g.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), c, 1.0); g.draw_line(p - Vector2(0, r), p + Vector2(0, r), c, 1.0)
	g.draw_line(p - Vector2(r, r) * 0.4, p + Vector2(r, r) * 0.4, Color(c, c.a * 0.6), 1.0); g.draw_line(p - Vector2(r, -r) * 0.4, p + Vector2(r, -r) * 0.4, Color(c, c.a * 0.6), 1.0)

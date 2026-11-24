extends Node2D
## One arena prop drawn in 3/4 view: a top face lifted `h` px above its footprint plus a visible front face.
## The origin is the bottom-centre of the footprint (the collision rect), so the actors' y-sort draws the
## villain and cops behind a prop when they stand north of it and in front of it when they stand south.
## Emissive bits (headlights, police bar, LEDs, gems, monitors) are listed by glows() for the arena's lights
## and additive ambient layer, so they still read under the CanvasModulate darkness.

var kind := "car"
var col := Color.WHITE
var size := Vector2(64, 32)    # footprint (collision rect) size
var h := 16.0                  # visual height above the floor
var flip := false
var police := false
var variant := 0
var lamp := Color.WHITE
var time := 0.0
var _sb := StyleBoxFlat.new()
var record: Dictionary = {}

func setup(p: Dictionary, theme: Dictionary) -> void:
	record = p
	var r: Rect2 = p.rect
	kind = p.kind; col = p.color; size = r.size; h = p.get("h", 16.0); flip = p.get("flip", false)
	police = p.get("police", false); variant = p.get("variant", 0); lamp = theme.lamp
	position = Vector2(r.get_center().x, r.end.y)
	time = float(variant) * 1.37
	_sb.anti_aliasing = true; _sb.anti_aliasing_size = 0.7

func _process(dt: float) -> void:
	time += dt
	z_index = -1 if record.get("broken", false) else 0
	var wear := 1.0 - float(record.get("hp", 1.0)) / maxf(1.0, float(record.get("max_hp", 1.0)))
	self_modulate = Color.WHITE.lerp(Color("#68605a"), wear * 0.25 + float(record.get("char", 0.0)) * 0.5)
	if record.get("flash", 0.0) > 0.0: self_modulate = self_modulate.lightened(0.35)
	queue_redraw()

# ---------------- small drawing helpers ----------------
func _rr(r: Rect2, c: Color, rad: float) -> void:
	_sb.bg_color = c; _sb.set_corner_radius_all(int(rad)); _sb.draw(get_canvas_item(), r)

func _grad(r: Rect2, c0: Color, c1: Color, horizontal := false) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cs := PackedColorArray([c0, c1, c1, c0] if horizontal else [c0, c0, c1, c1])
	draw_polygon(pts, cs)

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col0: Color, col1 := Color(0, 0, 0, -1)) -> void:
	if col1.a < 0: draw_colored_polygon(PackedVector2Array([a, b, c, d]), col0)
	else: draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([col0, col0, col1, col1]))

## A plain box: top face + front face with a lit top edge. x0..x1, front edge on the floor at gy.
func _box(x0: float, x1: float, gy: float, depth: float, height: float, top: Color, front: Color) -> void:
	var w := x1 - x0
	_grad(Rect2(x0, gy - depth - height, w, depth), top.lightened(0.08), top)
	_grad(Rect2(x0, gy - height, w, height), front, front.darkened(0.3))
	draw_rect(Rect2(x0, gy - depth - height, w, 1), top.lightened(0.35))
	draw_rect(Rect2(x0, gy - height, w, 1), top.lightened(0.18))

## Top face of a side-on car, read as a profile: one smooth line rises from a low boot, runs flat over the
## cabin, then eases down to a low bonnet (no hard steps). `inset` shrinks it for inner fills.
## Returns the far (north) edge first, then 4 near-edge points.
const CAR_DECK := 0.25         # boot / bonnet ends sit this fraction of the depth below the roofline
func _car_top(hw: float, top: float, d: float, inset := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var y0 := top + inset; var y1 := top + d - inset; var x := hw - inset
	var deck := top + d * CAR_DECK + inset * 0.5
	for i in 33:
		var px := lerpf(-x, x, i / 32.0)
		# 0 at the bumpers, 1 over the cabin: a long gentle rear slope, a shorter windscreen slope at the front
		var lift := smoothstep(-hw * 0.82, -hw * 0.32, px) * (1.0 - smoothstep(hw * 0.17, hw * 0.62, px))
		pts.append(Vector2(px, lerpf(deck, y0, lift)))
	pts.append(Vector2(x, y1 - 3)); pts.append(Vector2(x - 3, y1)); pts.append(Vector2(-x + 3, y1)); pts.append(Vector2(-x, y1 - 3))
	return pts

func _fill_v(pts: PackedVector2Array, c0: Color, c1: Color) -> void:
	var lo := INF; var hi := -INF
	for v in pts: lo = minf(lo, v.y); hi = maxf(hi, v.y)
	var cs := PackedColorArray()
	for v in pts: cs.append(c0.lerp(c1, (v.y - lo) / maxf(hi - lo, 1.0)))
	draw_polygon(pts, cs)

func _star(p: Vector2, r: float, c: Color) -> void:
	draw_line(p - Vector2(r, 0), p + Vector2(r, 0), c, 1.0); draw_line(p - Vector2(0, r), p + Vector2(0, r), c, 1.0)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), c)

func _draw() -> void:
	if record.get("broken", false) and kind != "case":
		_draw_wreck(); _draw_fire()
		return
	match kind:
		"car": _draw_car_h() if size.x > size.y else _draw_car_v()
		"pillar": _draw_pillar()
		"ac_unit": _draw_ac()
		"desk": _draw_desk()
		"case": _draw_case()
		"container": _draw_container()
		"server": _draw_server()
		"lamp_post": _draw_lamp_post()
	if not record.get("broken", false): _draw_damage()
	_draw_fire()

func _draw_damage() -> void:
	for mark in record.get("marks", []):
		var p: Vector2 = mark.pos
		match mark.kind:
			"bullet":
				draw_circle(p, 2.0, Color("#737b80"))
				draw_circle(p + Vector2(0, 0.4), 1.2, Color("#101318"))
				draw_line(p + Vector2(-1, -1.5), p + Vector2(0, -1.5), Color("#b7bcc0"), 1.0)
			"razor":
				var cut := Vector2.from_angle(mark.angle) * 5.0
				draw_line(p - cut, p + cut, Color("#15181c"), 2.0)
				draw_line(p - cut - Vector2(0, 1), p + cut - Vector2(0, 1), Color("#b4b9bd"), 1.0)
			_:
				draw_circle(p, 5.0 if mark.kind == "explosion" else 3.5, Color(0.06, 0.05, 0.04, 0.7))
				if mark.kind in ["laser", "bolt"]: draw_circle(p, 1.3, Color("#e98a44"))
	if kind == "car" and float(record.get("hp", 1.0)) < float(record.get("max_hp", 1.0)) * 0.65:
		var p := Vector2(size.x * 0.08, -size.y * 0.65 - h)
		for i in 5:
			var end := p + Vector2.from_angle(i * 2.4) * 9.0
			draw_line(p, end, Color("#9db5c3"), 1.0)

func _draw_wreck() -> void:
	var hw := size.x * 0.5; var d := size.y
	var base := Color("#34383b") if kind != "desk" else Color("#61432c")
	if kind == "pillar": base = Color("#999389")
	_draw_ellipse_shadow(Vector2(0, -d * 0.5), Vector2(hw + 8, d * 0.56))
	if kind == "car":
		# A flattened, torn shell and missing glass clearly signal a walkable wreck.
		var hull := PackedVector2Array([Vector2(-hw + 7, -d + 5), Vector2(-hw * 0.4, -d + 1), Vector2(-hw * 0.2, -d + 9), Vector2(hw - 7, -d + 4), Vector2(hw, -10), Vector2(hw * 0.4, -5), Vector2(0, -9), Vector2(-hw + 3, -3)])
		draw_colored_polygon(hull, base)
		draw_polyline(hull, Color("#666a6d"), 2.0)
		_rr(Rect2(-hw * 0.4, -d * 0.75, hw * 0.8, d * 0.5), Color("#12191d"), 3)
		for i in 3:
			var p := Vector2(-hw * 0.7 + i * hw * 0.7, -d * 0.3)
			draw_line(p, p + Vector2(11, -d * 0.4), Color("#565d60"), 3.0)
		for i in 2:
			var p := Vector2((-hw * 0.65 if i == 0 else hw * 0.65), -d * (0.3 if i == 0 else 0.7))
			draw_circle(p, 7, Color("#101215")); draw_circle(p, 3, Color("#52585d"))
	else:
		# Low piles retain enough of the material to read as debris rather than a hole.
		for i in 6:
			var p := Vector2((float(i % 3) - 1.0) * size.x * 0.27, -d * (0.28 + float(i / 3) * 0.4))
			var span := minf(22.0, size.x * 0.2)
			if kind == "pillar":
				var chunk := PackedVector2Array([p + Vector2(-span * 0.6, -6), p + Vector2(2, -11), p + Vector2(span * 0.7, -4), p + Vector2(span * 0.5, 5), p + Vector2(-span * 0.5, 6)])
				draw_colored_polygon(chunk, base.lightened(float(i % 3) * 0.08))
				draw_line(chunk[0], chunk[1], Color("#c6bfb1"), 2)
				draw_line(chunk[3], chunk[4], Color("#64605a"), 3)
			elif kind == "desk":
				draw_set_transform(p, sin(i * 2.7) * 0.8)
				draw_rect(Rect2(-span, -3, span * 2, 7), base.lightened(0.08 * (i % 3)))
				draw_line(Vector2(-span, -3), Vector2(span, -3), Color("#b28c57"), 1)
				draw_line(Vector2(-span + 3, 1), Vector2(span - 4, 1), Color("#382819"), 1)
				draw_set_transform(Vector2.ZERO)
			else:
				_quad(p + Vector2(-span, -7), p + Vector2(span - 3, -9), p + Vector2(span, 6), p + Vector2(-span + 4, 4), Color("#56616b"), Color("#343b42"))
				draw_line(p + Vector2(-span, -7), p + Vector2(span - 3, -9), Color("#9ba7af"), 1.5)
				for vent in 3: draw_line(p + Vector2(-span + 5, -3 + vent * 2), p + Vector2(span - 5, -3 + vent * 2), Color("#20272c"), 1)
	for i in 15:
		var p := Vector2(sin(i * 13.7 + variant) * (hw + 9), -d * 0.5 + cos(i * 7.3) * d * 0.57)
		var length := 5.0 + float(i % 4) * 2.0
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(length, -3), p + Vector2(3, 4 + i % 3)]), base.lightened(float(i % 3) * 0.12))
		if kind in ["car", "ac_unit", "server", "container"] and i % 3 == 0:
			draw_line(p, p + Vector2(length, -3), Color("#8b969b"), 1.0)

func _draw_ellipse_shadow(center: Vector2, radius: Vector2) -> void:
	draw_set_transform(center, 0, radius)
	draw_circle(Vector2.ZERO, 1, Color(0.04, 0.035, 0.03, 0.3))
	draw_set_transform(Vector2.ZERO)

func _draw_fire() -> void:
	var burning: bool = record.get("burn_t", 0.0) > 0.0 or record.get("fuse", -1.0) >= 0.0
	var wreck: bool = record.get("broken", false)
	if not burning and record.get("wreck_t", 0.0) <= 0.0: return
	var lift := 0.0 if wreck else h
	for i in 4:
		var base := Vector2(sin(i * 9.7 + variant) * size.x * 0.3, -size.y * (0.25 + float(i % 3) * 0.22) - lift)
		var phase := fposmod(time * 0.75 + i * 0.27, 1.0)
		var smoke := base + Vector2(sin(time * 1.5 + i) * 5 + phase * 9, -12 - phase * 42)
		draw_circle(smoke, 5 + phase * 8, Color(0.10, 0.10, 0.12, (1.0 - phase) * 0.65))
		var flame_h := (9.0 if wreck else 20.0) + sin(time * 16 + i * 2.3) * 4
		var flame := PackedVector2Array([base + Vector2(-6, 0), base + Vector2(-4, -flame_h * 0.5), base + Vector2(-2, -flame_h * 0.3), base + Vector2(2 + sin(time * 12 + i) * 3, -flame_h), base + Vector2(6, -flame_h * 0.3), base + Vector2(5, 1)])
		draw_colored_polygon(flame, Color("#ef5c24"))
		draw_colored_polygon(PackedVector2Array([base + Vector2(-3, 0), base + Vector2(1, -flame_h * 0.65), base + Vector2(3, 0)]), Color("#ffda73"))

# ---------------- cars ----------------
func _paint() -> Array:   # [body, dark accent] (a police cruiser is black and white)
	if police: return [Color("#e8ecf0"), Color("#15171c")]
	return [col, col.darkened(0.45)]

func _siren_on(red: bool) -> float:
	if record.get("burn_t", 0.0) > 0.0: return 0.0
	var ph := fmod(time * 2.6, 1.0)
	var on := (ph < 0.12 or (ph > 0.22 and ph < 0.34)) if red else (ph > 0.5 and ph < 0.62) or (ph > 0.72 and ph < 0.84)
	return 1.0 if on else 0.15

func _draw_car_h() -> void:
	var w := size.x; var d := size.y; var hw := w / 2.0
	if flip: draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	var pc := _paint(); var body: Color = pc[0]; var acc: Color = pc[1]
	var top := -d - h
	# wheels under the side skirt
	for wx in [-hw * 0.6, hw * 0.6]:
		_rr(Rect2(wx - 13, -14, 26, 16), Color("#0c0d10"), 6)
		_rr(Rect2(wx - 7, -10, 14, 9), Color("#3a3e44"), 4); draw_rect(Rect2(wx - 2, -7, 4, 3), Color("#8a9098"))
	# side (front face)
	_rr(Rect2(-hw, -h - 3, w, h + 1), body.darkened(0.28), 7)
	_grad(Rect2(-hw + 3, -h + 2, w - 6, h - 6), body.darkened(0.12), body.darkened(0.45))
	draw_rect(Rect2(-hw + 4, -h * 0.45, w - 8, 2), body.lightened(0.25))   # crease highlight
	if police:
		_grad(Rect2(-hw * 0.4, -h + 2, hw * 0.8, h - 6), Color("#f4f6f8"), Color("#a8b0b8"))
		draw_colored_polygon(PackedVector2Array([Vector2(-4, -h * 0.75), Vector2(0, -h * 0.75 - 4), Vector2(4, -h * 0.75), Vector2(0, -h * 0.75 + 4)]), Color("#ffd23c"))
	for wx in [-hw * 0.6, hw * 0.6]: draw_circle(Vector2(wx, -1), 12, Color("#08090b"))   # wheel arches
	for wx in [-hw * 0.6, hw * 0.6]:
		draw_circle(Vector2(wx, 0), 9, Color("#16181c")); draw_circle(Vector2(wx, 0), 5, Color("#7a828c")); draw_circle(Vector2(wx - 1, -1), 2, Color("#c8ccd0"))
	draw_rect(Rect2(-hw * 0.2, -h + 3, 1, h - 7), body.darkened(0.55))   # door seam
	draw_rect(Rect2(hw * 0.05, -h * 0.7, 5, 2), Color("#c8ccd0"))           # door handle
	# top face: bonnet / roof / boot
	draw_colored_polygon(_car_top(hw, top, d), acc if police else body.darkened(0.1))
	_fill_v(_car_top(hw, top, d, 2.5), body.lightened(0.12) if not police else acc.lightened(0.15), body.darkened(0.08) if not police else acc)
	if police:   # white roof band, clipped to the body outline
		var band := PackedVector2Array()
		for v in _car_top(hw, top, d, 2.0).slice(0, 33):
			if absf(v.x) <= hw * 0.42: band.append(v)
		band.append(Vector2(hw * 0.42, top + d - 2)); band.append(Vector2(-hw * 0.42, top + d - 2))
		_fill_v(band, Color("#f8fafc"), Color("#c8d0d8"))
	draw_rect(Rect2(-hw * 0.3, top + 2, hw * 0.45, 1), Color(1, 1, 1, 0.45))   # specular rim along the roofline
	var rim := _car_top(hw, top, d, 1.5)
	draw_polyline(rim.slice(0, rim.size() - 4), Color(1, 1, 1, 0.22), 1.0)   # light catching the roof, boot and bonnet edge
	draw_rect(Rect2(hw * 0.45, top + d * 0.4, 1, d * 0.6 - 6), Color(0, 0, 0, 0.25)); draw_rect(Rect2(-hw * 0.72, top + d * 0.4, 1, d * 0.6 - 6), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(hw * 0.6, top + d * 0.5 - 1, hw * 0.3, 2), Color(1, 1, 1, 0.12))   # bonnet crease
	# cabin: roof lifted 9 px, glass between roof and body
	var cx0 := -hw * 0.5; var cx1 := hw * 0.3; var cy0 := top + 9; var cy1 := top + d - 9
	var rx0 := cx0 + 9; var rx1 := cx1 - 6; var ry0 := cy0 - 5; var ry1 := cy1 - 9
	var glass := Color("#1a2a3c"); var glass2 := Color("#3a5a7c")
	_quad(Vector2(rx1, ry0), Vector2(cx1 + 7, cy0 + 2), Vector2(cx1 + 7, cy1 - 2), Vector2(rx1, ry1), glass2, glass)   # windscreen
	_quad(Vector2(rx0, ry0), Vector2(cx0 - 3, cy0 + 2), Vector2(cx0 - 3, cy1 - 2), Vector2(rx0, ry1), glass2, glass)   # rear window
	_quad(Vector2(rx0, ry1), Vector2(rx1, ry1), Vector2(cx1 + 7, cy1 - 2), Vector2(cx0 - 3, cy1 - 2), glass, glass2)   # side glass
	draw_line(Vector2(lerpf(rx0, rx1, 0.48), ry1), Vector2(lerpf(cx0, cx1, 0.48), cy1 - 2), body.darkened(0.3) if not police else acc, 2)   # B pillar
	draw_line(Vector2(rx1 + 2, ry0 + 4), Vector2(cx1 + 4, cy0 + 12), Color(1, 1, 1, 0.35), 1.5)   # glare
	_rr(Rect2(rx0, ry0, rx1 - rx0, ry1 - ry0), (acc.lightened(0.1) if police else body.lightened(0.08)), 5)
	draw_rect(Rect2(rx0 + 4, ry0 + 2, rx1 - rx0 - 8, 1), Color(1, 1, 1, 0.4))
	if police:   # light bar
		var by := (ry0 + ry1) / 2.0 - 4; var bx := (rx0 + rx1) / 2.0
		draw_rect(Rect2(bx - 5, by - 1, 10, 10), Color("#202228"))
		_rr(Rect2(bx - 4, by - 1, 8, 5), Color("#ff2a2a").lerp(Color("#4a0a0a"), 1.0 - _siren_on(true)), 2)
		_rr(Rect2(bx - 4, by + 4, 8, 5), Color("#2a6aff").lerp(Color("#0a1440"), 1.0 - _siren_on(false)), 2)
	else:
		draw_rect(Rect2(rx0 + 6, ry0 + 5, rx1 - rx0 - 12, 2), Color(1, 1, 1, 0.1))
	# lights: head at +x, tail at -x
	for y in [top + d * CAR_DECK + 4, top + d - 12]:   # far-side lights sit on the boot / bonnet ends
		_rr(Rect2(hw - 6, y, 5, 7), Color("#fff6d8"), 2); _rr(Rect2(-hw + 1, y, 4, 7), Color("#d82020"), 2)
	_rr(Rect2(hw - 7, -h + 2, 6, 5), Color("#fff6d8"), 2); _rr(Rect2(-hw + 1, -h + 2, 5, 5), Color("#d82020"), 2)
	draw_rect(Rect2(cx1 + 2, cy1 - 1, 5, 4), body.darkened(0.4))   # mirror
	draw_set_transform(Vector2.ZERO)

func _draw_car_v() -> void:
	var w := size.x; var d := size.y; var hw := w / 2.0; var top := -d - h
	var south := flip   # true: the bonnet faces south (headlights on the front face)
	var pc := _paint(); var body: Color = pc[0]; var acc: Color = pc[1]
	# wheels peeking out at the sides
	for wy in [top + d * 0.22, top + d * 0.74]:
		_rr(Rect2(-hw - 3, wy, 7, 22), Color("#0c0d10"), 3); _rr(Rect2(hw - 4, wy, 7, 22), Color("#0c0d10"), 3)
	# front face: bumper end
	_rr(Rect2(-hw, -h - 3, w, h + 2), body.darkened(0.3), 7)
	_grad(Rect2(-hw + 3, -h + 1, w - 6, h - 6), body.darkened(0.15), body.darkened(0.5))
	draw_rect(Rect2(-hw * 0.35, -h * 0.55, hw * 0.7, 6), Color("#e8e8d8") if not south else Color("#1a1c20"))   # plate / grille
	if south:
		for i in 4: draw_rect(Rect2(-hw * 0.33, -h * 0.55 + 1 + i * 1.5, hw * 0.66, 0.7), Color("#555a60"))
	var lc := Color("#fff6d8") if south else Color("#d82020")
	_rr(Rect2(-hw + 3, -h + 2, 9, 5), lc, 2); _rr(Rect2(hw - 12, -h + 2, 9, 5), lc, 2)
	_rr(Rect2(-hw - 1, -5, 12, 7), Color("#0c0d10"), 3); _rr(Rect2(hw - 11, -5, 12, 7), Color("#0c0d10"), 3)
	# top face
	_rr(Rect2(-hw, top, w, d), body.darkened(0.1) if not police else acc, 11)
	_grad(Rect2(-hw + 3, top + 3, w - 6, d - 6), body.lightened(0.12) if not police else acc.lightened(0.15), body.darkened(0.06) if not police else acc, true)
	if police: _grad(Rect2(-hw + 3, top + d * 0.3, w - 6, d * 0.4), Color("#f8fafc"), Color("#c8d0d8"), true)
	draw_rect(Rect2(-hw + 2, top + 8, 1, d - 16), Color(1, 1, 1, 0.45))
	# cabin
	var cy0 := top + d * 0.3; var cy1 := top + d * 0.72; var ry0 := cy0 - 6; var ry1 := cy1 - 16
	var glass := Color("#1a2a3c"); var glass2 := Color("#3a5a7c")
	_quad(Vector2(-hw + 6, ry1), Vector2(hw - 6, ry1), Vector2(hw - 4, cy1), Vector2(-hw + 4, cy1), glass2, glass)   # south glass
	_rr(Rect2(-hw + 6, ry0, w - 12, ry1 - ry0), body.lightened(0.08) if not police else acc.lightened(0.1), 5)
	_grad(Rect2(-hw + 7, ry0, w - 14, 9), glass2, glass)   # north glass strip on the roof
	draw_line(Vector2(-hw + 9, ry1 + 2), Vector2(-hw + 15, cy1 - 2), Color(1, 1, 1, 0.3), 1.5)
	if police:
		var by := (ry0 + ry1) / 2.0 + 4
		draw_rect(Rect2(-11, by - 3, 22, 8), Color("#202228"))
		_rr(Rect2(-10, by - 2, 10, 6), Color("#ff2a2a").lerp(Color("#4a0a0a"), 1.0 - _siren_on(true)), 2)
		_rr(Rect2(0, by - 2, 10, 6), Color("#2a6aff").lerp(Color("#0a1440"), 1.0 - _siren_on(false)), 2)
	# lamps on the top face ends
	var head_y := top + d - 7 if south else top + 2
	var tail_y := top + 2 if south else top + d - 7
	_rr(Rect2(-hw + 4, head_y, 8, 5), Color("#fff6d8"), 2); _rr(Rect2(hw - 12, head_y, 8, 5), Color("#fff6d8"), 2)
	_rr(Rect2(-hw + 4, tail_y, 8, 5), Color("#d82020"), 2); _rr(Rect2(hw - 12, tail_y, 8, 5), Color("#d82020"), 2)

# ---------------- bank pillar ----------------
func _draw_pillar() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	var stone := Color("#e8e2d4"); var dark := Color("#8a8476")
	_box(-hw, hw, 0, d, 12, stone.darkened(0.05), dark)                    # plinth
	_box(-hw + 4, hw - 4, -16, d - 8, 8, stone, dark.lightened(0.1))        # second step (sits on the plinth)
	var sx := hw - 9.0
	var base_y := -(d * 0.5 - sx) - 20.0; var top_y := -(d * 0.5 - sx) - h
	# cylindrical shaft: vertical strips lit from the upper left, fluted
	var n := 14
	for i in n:
		var u := (i + 0.5) / n; var x0 := -sx + 2 * sx * i / n
		var lit := clampf(0.5 + 0.65 * cos((u - 0.3) * PI), 0.22, 1.12)
		var c := Color(stone.r * lit, stone.g * lit, stone.b * lit)
		draw_rect(Rect2(x0, top_y, 2 * sx / n + 0.5, base_y - top_y), c)
		if i % 2 == 1: draw_rect(Rect2(x0 + 0.5, top_y + 8, 1, base_y - top_y - 12), c.darkened(0.22))
	_grad(Rect2(-sx, base_y - 10, 2 * sx, 10), Color(0, 0, 0, 0), Color(0, 0, 0, 0.25))   # contact darkening
	# echinus + abacus
	var ag := -5.0 - h
	_grad(Rect2(-sx - 5, ag - 1, 2 * sx + 10, 6), stone.lightened(0.05), dark)
	_box(-hw + 1, hw - 1, ag, d - 10, 8, stone.lightened(0.1), dark.lightened(0.15))
	draw_rect(Rect2(-hw + 1, ag - 6, w - 2, 2), Color("#c9a227"))           # gilded band

# ---------------- rooftop AC unit ----------------
func _draw_ac() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	var metal := Color("#9aa3ad")
	draw_rect(Rect2(hw - 2, -10, 14, 6), Color("#5a6068")); draw_rect(Rect2(hw + 8, -10, 6, 10), Color("#4a5058"))   # duct
	_box(-hw, hw, 0, d, h, metal, Color("#6a727c"))
	for i in range(3, int(h) - 2, 3): draw_rect(Rect2(-hw + 5, -h + i, w - 10, 1), Color("#3a4048"))   # louvres
	var c := Vector2(-hw * 0.2, -h - d / 2.0)
	var rf := minf(w, d) * 0.36
	draw_circle(c, rf + 3, Color("#5a626c")); draw_circle(c, rf, Color("#1c2026"))
	for i in 4:
		var a := i * TAU / 4.0 + time * (9.0 + variant)
		var p := PackedVector2Array([c, c + Vector2.from_angle(a - 0.25) * rf * 0.95, c + Vector2.from_angle(a + 0.2) * rf * 0.95])
		draw_colored_polygon(p, Color("#8a929c"))
	draw_arc(c, rf * 0.6, 0, TAU, 24, Color(0.55, 0.6, 0.66, 0.6), 1); draw_arc(c, rf, 0, TAU, 32, Color("#b8c0c8"), 1)
	draw_circle(c, 3, Color("#c8ccd0"))
	for b in [Vector2(-hw + 4, -h - d + 4), Vector2(hw - 5, -h - d + 4), Vector2(-hw + 4, -h - 5), Vector2(hw - 5, -h - 5)]: draw_rect(Rect2(b, Vector2(2, 2)), Color("#5a626c"))
	draw_rect(Rect2(hw * 0.45, -h - d + 8, hw * 0.4, d - 16), Color("#7a828c"))   # service panel
	if variant % 2 == 0:   # aviation beacon
		var on := fmod(time, 1.6) < 0.25
		draw_rect(Rect2(hw - 9, -h - d + 2, 6, 6), Color("#30343a")); draw_rect(Rect2(hw - 8, -h - d + 3, 4, 4), Color("#ff3030") if on else Color("#501010"))

# ---------------- police desk ----------------
func _draw_desk() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	var wood := Color("#6a4c30")
	draw_rect(Rect2(-hw + 2, -h, 5, h), Color("#3a2818")); draw_rect(Rect2(hw - 7, -h, 5, h), Color("#3a2818"))
	_box(-hw, hw, -h + 6, d, 6, wood.lightened(0.05), Color("#4a3420"))
	_box(hw * 0.3, hw - 8, 0, 4, h - 6, wood, Color("#5a3e26"))   # drawer pedestal
	for i in 2: draw_rect(Rect2(hw * 0.3 + 3, -h + 9 + i * 7, hw * 0.7 - 14, 5), Color("#4a3420")); draw_rect(Rect2(hw * 0.65 - 3, -h + 11 + i * 7, 6, 1), Color("#c8b080"))
	var ty := -h - d   # top face origin y (+6 lift already in _box)
	# papers, folder
	draw_set_transform(Vector2(-hw + 18, ty + 14), -0.18 + variant * 0.1)
	draw_rect(Rect2(-8, -6, 16, 12), Color("#e8e8e0"))
	for i in 4: draw_rect(Rect2(-6, -4 + i * 3, 10 - (i % 2) * 3, 1), Color("#8a8a90"))
	draw_set_transform(Vector2(-hw + 26, ty + 22), 0.25)
	draw_rect(Rect2(-7, -5, 14, 10), Color("#d8b050")); draw_rect(Rect2(-7, -5, 14, 2), Color("#e8c870"))
	draw_set_transform(Vector2.ZERO)
	# coffee mug
	var mug := Vector2(-hw + 42, ty + 30)
	draw_circle(mug, 4, Color("#e8e8e8")); draw_circle(mug, 3, Color("#3a2010")); draw_rect(Rect2(mug.x + 4, mug.y - 1, 2, 3), Color("#e8e8e8"))
	# CRT monitor
	var mx0 := hw * 0.05; var mx1 := hw * 0.05 + 28; var my := ty + d - 8
	_box(mx0, mx1, my, 16, 18, Color("#c8c4b8"), Color("#a8a498"))
	var scr := Rect2(mx0 + 3, my - 16, 22, 13)
	var flick := 0.85 + 0.15 * sin(time * 37.0 + variant)
	draw_rect(scr, Color("#0a1a2a"))
	_grad(scr.grow(-1), Color(0.3, 0.7, 1.0) * flick, Color(0.15, 0.4, 0.7) * flick)
	for i in range(0, 11, 3): draw_rect(Rect2(scr.position.x + 2, scr.position.y + 2 + i, 6 + (i * 7 + variant * 3) % 12, 1), Color(0.8, 0.95, 1, 0.8))
	draw_rect(Rect2(scr.position.x + 1, scr.position.y + 1 + fmod(time * 20.0, 11.0), 20, 1), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(mx0 - 2, my + 2, 30, 5), Color("#d8d4c8"))   # keyboard
	for i in 6: draw_rect(Rect2(mx0 + i * 5, my + 3, 3, 1), Color("#8a8680"))
	# phone with a blinking line light
	draw_rect(Rect2(hw - 20, ty + 8, 12, 8), Color("#1a1a20")); draw_rect(Rect2(hw - 19, ty + 6, 10, 3), Color("#2a2a30"))
	draw_rect(Rect2(hw - 11, ty + 13, 2, 2), Color("#ff3030") if fmod(time + variant, 1.0) < 0.5 else Color("#401010"))

# ---------------- museum display case ----------------
func _draw_case() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	if record.get("broken", false):
		for i in 12:
			var pos := Vector2(sin(i * 13.7) * (hw + 12), -d * 0.5 + cos(i * 7.3) * d * 0.6)
			draw_colored_polygon(PackedVector2Array([pos, pos + Vector2(6, -3), pos + Vector2(3, 4)]), Color(0.65, 0.85, 1.0, 0.65))
		return
	var ph := 22.0
	_box(-hw, hw, 0, d, ph, Color("#4a3420"), Color("#3a2818"))
	draw_rect(Rect2(-hw, -ph, w, 2), Color("#c9a227")); draw_rect(Rect2(-hw, -4, w, 2), Color("#a8861c"))
	draw_rect(Rect2(-6, -ph + 8, 12, 5), Color("#c9a227")); draw_rect(Rect2(-5, -ph + 9, 10, 3), Color("#2a1a0a"))   # plaque
	var gx := hw - 4; var gy := -4.0 - ph; var gd := d - 8; var gh := h - ph   # glass box
	var floor_c := Vector2(0, gy - gd * 0.5 + 6)
	draw_rect(Rect2(-gx, gy - gd - gh * 0.0, 2 * gx, gd), Color("#2a0e12"))   # velvet bed
	_artifact(floor_c)
	# glass: front + top, with reflections
	draw_rect(Rect2(-gx, gy - gh, 2 * gx, gh), Color(0.65, 0.85, 1.0, 0.13))
	draw_rect(Rect2(-gx, gy - gh - gd, 2 * gx, gd), Color(0.65, 0.85, 1.0, 0.10))
	_quad(Vector2(-gx + 6, gy - gh - gd + 2), Vector2(-gx + 12, gy - gh - gd + 2), Vector2(-gx + 4, gy - 2), Vector2(-gx + 1, gy - 2), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.05))
	_quad(Vector2(-gx + 16, gy - gh - gd + 2), Vector2(-gx + 18, gy - gh - gd + 2), Vector2(-gx + 10, gy - 2), Vector2(-gx + 8, gy - 2), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.0))
	var edge := Color(0.85, 0.95, 1.0, 0.55)
	draw_rect(Rect2(-gx, gy - gh - gd, 2 * gx, gd + gh), edge, false, 1.0)
	draw_line(Vector2(-gx, gy - gh), Vector2(gx, gy - gh), edge, 1.0)
	var damage := 1.0 - float(record.get("hp", 240.0)) / float(record.get("max_hp", 240.0))
	if damage > 0:
		var center := Vector2(0, gy - gh - gd * 0.5)
		for i in ceili(damage * 9):
			var end := center + Vector2.from_angle(i * 2.4) * (12 + damage * 20)
			draw_line(center, end, Color(0.9, 1, 1, 0.9), 1.0)
		draw_rect(Rect2(-hw, -d - h - 8, w, 3), Color("#281a1a"))
		draw_rect(Rect2(-hw, -d - h - 8, w * (1.0 - damage), 3), Color("#70dcff"))

func _artifact(c: Vector2) -> void:
	match variant % 4:
		0:   # the big diamond
			var gem := Color("#9af0ff")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -14), c + Vector2(9, -14), c + Vector2(12, -9), c + Vector2(0, 4), c + Vector2(-12, -9)]), gem)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -14), c + Vector2(0, -14), c + Vector2(-4, -9), c + Vector2(-12, -9)]), Color(1, 1, 1, 0.85))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(12, -9), c + Vector2(0, 4)]), gem.darkened(0.35))
			draw_line(c + Vector2(-12, -9), c + Vector2(12, -9), Color(1, 1, 1, 0.6), 1)
		1:   # golden idol
			var g := Color("#e8b820")
			draw_rect(Rect2(c.x - 6, c.y - 4, 12, 6), g.darkened(0.3)); draw_rect(Rect2(c.x - 4, c.y - 16, 8, 13), g)
			draw_circle(c + Vector2(0, -19), 5, g); draw_rect(Rect2(c.x - 3, c.y - 20, 2, 2), Color("#ff3030")); draw_rect(Rect2(c.x + 1, c.y - 20, 2, 2), Color("#ff3030"))
			draw_rect(Rect2(c.x - 3, c.y - 15, 2, 10), Color(1, 1, 0.8, 0.7))
		2:   # crown
			var g := Color("#f0c030")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 0), c + Vector2(-11, -12), c + Vector2(-6, -6), c + Vector2(0, -15), c + Vector2(6, -6), c + Vector2(11, -12), c + Vector2(11, 0)]), g)
			draw_rect(Rect2(c.x - 11, c.y - 3, 22, 3), g.darkened(0.3))
			for gx2 in [-6, 0, 6]: draw_circle(c + Vector2(gx2, -2), 1.6, [Color("#ff3050"), Color("#30a0ff"), Color("#30ff80")][(gx2 + 6) / 6])
		_:   # ming vase
			draw_circle(c + Vector2(0, -7), 8, Color("#e8f0f8")); draw_rect(Rect2(c.x - 3, c.y - 20, 6, 7), Color("#e8f0f8")); draw_rect(Rect2(c.x - 4, c.y - 21, 8, 2), Color("#e8f0f8"))
			draw_arc(c + Vector2(0, -7), 5, 0, TAU, 16, Color("#2a5ab8"), 1.5); draw_rect(Rect2(c.x - 3, c.y - 17, 6, 1), Color("#2a5ab8"))

# ---------------- harbour container ----------------
func _draw_container() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	var c := col
	_box(-hw, hw, 0, d, h, c.lightened(0.05), c.darkened(0.15))
	var horiz := w > d
	if horiz:
		for x in range(int(-hw) + 4, int(hw) - 3, 6):   # corrugation on the long side
			draw_rect(Rect2(x, -h + 3, 3, h - 6), c.darkened(0.3)); draw_rect(Rect2(x + 3, -h + 3, 1, h - 6), c.lightened(0.12))
		for x in range(int(-hw) + 6, int(hw) - 4, 10): draw_rect(Rect2(x, -h - d + 3, 1, d - 6), c.darkened(0.2))   # roof ribs
		draw_rect(Rect2(-hw * 0.5, -h * 0.66, hw * 0.9, 9), Color(0.95, 0.95, 0.9, 0.85))   # stencil band
		for i in 7: draw_rect(Rect2(-hw * 0.5 + 4 + i * 11, -h * 0.66 + 2, 7, 5), c.darkened(0.2))
		for i in 4: _grad(Rect2(-hw + 20 + i * 37 + variant * 5, -h + 4, 3, h * 0.8), Color(0.45, 0.22, 0.1, 0.5), Color(0.45, 0.22, 0.1, 0))   # rust streaks
	else:
		for y in range(int(-h - d) + 6, int(-h) - 4, 10): draw_rect(Rect2(-hw + 3, y, w - 6, 1), c.darkened(0.2))
		draw_rect(Rect2(-1, -h + 2, 2, h - 4), c.darkened(0.45))   # door split
		for x in [-hw + 8, -hw * 0.35, hw * 0.35 - 2, hw - 10]:   # locking bars
			draw_rect(Rect2(x, -h + 3, 2, h - 6), Color("#5a5a5a")); draw_rect(Rect2(x - 2, -h * 0.55, 6, 3), Color("#3a3a3a"))
		for x in range(int(-hw) + 4, int(hw) - 3, 5): draw_rect(Rect2(x, -h + 3, 1, h - 6), c.darkened(0.15))
	for p in [Vector2(-hw, -h - d), Vector2(hw - 5, -h - d), Vector2(-hw, -h - 5), Vector2(hw - 5, -h - 5), Vector2(-hw, -5), Vector2(hw - 5, -5)]:
		draw_rect(Rect2(p, Vector2(5, 5)), c.darkened(0.55))   # corner castings

# ---------------- spy HQ server rack ----------------
func _draw_server() -> void:
	var w := size.x; var hw := w / 2.0; var d := size.y
	_box(-hw, hw, 0, d, h, Color("#1a2028"), Color("#0e1218"))
	var ty := -h - d
	for i in range(int((d - 10) / 6)):   # roof vents
		draw_rect(Rect2(-hw + 6, ty + 5 + i * 6, w - 12, 2), Color("#0a0c10"))
	var pulse := 0.5 + 0.5 * sin(time * 3.0 + variant)
	draw_rect(Rect2(-hw + 2, ty + 2, 2, d - 4), lamp * (0.4 + 0.6 * pulse)); draw_rect(Rect2(hw - 4, ty + 2, 2, d - 4), lamp * (0.4 + 0.6 * pulse))
	# front: rack units with blinking LEDs
	for i in range(int((h - 6) / 6)):
		var y := -h + 3 + i * 6
		draw_rect(Rect2(-hw + 3, y, w - 6, 5), Color("#161c24")); draw_rect(Rect2(-hw + 3, y, w - 6, 1), Color("#26303c"))
		for k in 3:
			var on := int(time * 6.0 + i * 7 + k * 3 + variant * 11) % 5 != 0
			draw_rect(Rect2(-hw + 6 + k * 4, y + 2, 2, 2), (lamp if k != 2 else Color("#7dff3a")) if on else Color("#123"))
		var bar := 0.5 + 0.5 * sin(time * (2.0 + i * 0.7) + i)
		draw_rect(Rect2(hw - 18, y + 2, 12 * bar, 1), lamp.darkened(0.3))

# ---------------- street lamp post (solid base; elevated fixture) ----------------
func _draw_lamp_post() -> void:
	draw_rect(Rect2(-5, -6, 10, 6), Color("#22282a")); draw_rect(Rect2(-4, -7, 8, 2), Color("#3a4246"))
	_grad(Rect2(-2, -66, 4, 61), Color("#4a5458"), Color("#2a3032"), true)
	draw_rect(Rect2(-2, -68, 20, 3), Color("#3a4246"))
	_rr(Rect2(10, -70, 16, 7), Color("#2a3032"), 3)
	# The painted cap stays dark; the small underside is the exposed emitter.
	draw_rect(Rect2(10,-70,16,3),Color("#151c25"))
	draw_rect(Rect2(12, -64, 12, 2), lamp.lightened(0.4))

## Emissive points for the arena's light pool / additive layer: [{pos (global), col, e, r, glow}]
func glows() -> Array:
	var out: Array = []
	var gp := global_position
	if record.get("burn_t", 0.0) > 0.0 or record.get("fuse", -1.0) >= 0.0 or record.get("wreck_t", 0.0) > 0.0:
		out.append({"pos":gp + Vector2(0, -size.y * 0.5 - (0.0 if record.get("broken", false) else h)), "col":Color("#ff882d"), "e":1.1 + sin(time * 15) * 0.2, "r":110.0, "glow":26.0})
	if record.get("broken", false): return out
	match kind:
		"car":
			if police:
				var roof := gp + (Vector2(0, -size.y - h - 4) if size.x > size.y else Vector2(0, -h - size.y * 0.5 - 4))
				out.append({"pos": roof + Vector2(-6, 0), "col": Color("#ff2a2a"), "e": 1.6 * _siren_on(true), "r": 150.0, "glow": 16.0})
				out.append({"pos": roof + Vector2(6, 0), "col": Color("#2a6aff"), "e": 1.6 * _siren_on(false), "r": 150.0, "glow": 16.0})
			if size.x > size.y:
				var fx := (size.x / 2.0) * (-1.0 if flip else 1.0)
				out.append({"pos": gp + Vector2(fx, -size.y * 0.5 - h * 0.5), "col": Color("#fff0c8"), "e": 0.5, "r": 60.0, "glow": 7.0})
			elif flip:
				out.append({"pos": gp + Vector2(0, 2), "col": Color("#fff0c8"), "e": 0.5, "r": 60.0, "glow": 7.0})
		"server":
			out.append({"pos": gp + Vector2(0, -h * 0.5), "col": lamp, "e": 0.5, "r": 70.0, "glow": 0.0})
		"desk":
			out.append({"pos": gp + Vector2(size.x * 0.12, -size.y - 18), "col": Color("#4fb4ff"), "e": 0.55, "r": 55.0, "glow": 10.0})
		"case":
			if record.get("broken", false): return out
			var tw := 0.6 + 0.4 * sin(time * 2.3 + variant)
			out.append({"pos": gp + Vector2(0, -size.y * 0.5 - 30), "col": Color("#9af0ff") if variant % 4 == 0 else Color("#ffd870"), "e": 0.7 * tw, "r": 70.0, "glow": 0.0, "sparkle": tw})
		"ac_unit":
			if variant % 2 == 0 and fmod(time, 1.6) < 0.25: out.append({"pos": gp + Vector2(size.x / 2.0 - 6, -h - size.y + 5), "col": Color("#ff3030"), "e": 0.9, "r": 50.0, "glow": 6.0})
		"lamp_post":
			out.append({"pos": to_global(Vector2(18, -63)), "col": lamp, "e": 0.0, "r": 0.0, "glow": 12.0*scale.x})
	return out

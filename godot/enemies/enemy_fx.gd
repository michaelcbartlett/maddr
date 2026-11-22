extends Node2D
## Emissive (unlit, additive) overlays for one enemy: boss power effects, stun stars, mind-control
## swirl and drone beacons. Drawn as a child of the Enemy node so it follows it and sorts with it.
const Sheets = preload("res://enemies/enemy_sheets.gd")
static var _material: CanvasItemMaterial
var enemy

func _ready() -> void:
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = _material
	z_index = 1

func _draw() -> void:
	var e = enemy
	if e == null or e.dead: return
	var g: Dictionary = e.gfx
	if not g.has("state"): return
	var sheet := EnemyArt.sheet(EnemyView.sprite_key(e))
	draw_fx(self, sheet, g.state, g.frame, Vector2(0, sheet.foot - g.lift) + g.jitter, e.face, e.A.time if e.A else 0.0,
		{"hero": e.hero, "ally": e.ally, "type": e.type, "laser": e.laser, "frozen": e.frozen_t > 0.0 or e.time_lock > 0.0})

static func _w(sheet: Dictionary, st: String, fi: int, name: String, at: Vector2, face: int, fallback := Vector2(0, -30)) -> Vector2:
	var a := Sheets.anchor(sheet, st, fi, name, fallback)
	return at + Vector2(a.x * face, a.y)

## Shared with the gallery. `info` keys: hero, ally, type, laser, frozen.
static func draw_fx(ci: CanvasItem, sheet: Dictionary, st: String, fi: int, at: Vector2, face: int, t: float, info: Dictionary) -> void:
	var frozen: bool = info.get("frozen", false)
	if st == "stunned":
		var head := _w(sheet, st, fi, "head", at, face)
		var hr := 16.0 if sheet.family == "hero" else (8.0 if sheet.family != "human" else 11.0)
		for k in 3:
			var a := t * 4.0 + k * TAU / 3.0
			var p := head + Vector2(cos(a) * hr, -hr - 2 + sin(a) * 3.0)
			_star(ci, p.round(), Color("#ffe14a"))
	if info.get("ally", false):
		var head2 := _w(sheet, st, fi, "head", at, face)
		for k in 6:
			var a2 := t * 6.0 + k * TAU / 6.0
			ci.draw_rect(Rect2((head2 + Vector2(cos(a2) * 7.0, -14 + sin(a2) * 2.0)).round(), Vector2(2, 1)), Color("#d07bff", 0.8))
	if info.get("type", "") == "drone" and st != "death":
		var on := sin(t * 8.0) > 0.0
		var top := at + Vector2(0, -27)
		ci.draw_rect(Rect2(top + Vector2(-3, 0), Vector2(2, 2)), Color("#ff2a2a") if on else Color("#401010"))
		ci.draw_rect(Rect2(top + Vector2(2, 0), Vector2(2, 2)), Color("#2a5aff") if not on else Color("#101840"))
	if frozen or st == "death": return
	match info.get("hero", ""):
		"surge":
			# crackling static around the body, arcs from the hand while casting
			var c := _w(sheet, st, fi, "chest", at, face)
			var rng := RandomNumberGenerator.new(); rng.seed = int(t * 30.0)
			for k in 2 + (3 if st == "cast" or st == "blink" else 0):
				var a3 := c + Vector2(rng.randf_range(-16, 16), rng.randf_range(-30, 22))
				_bolt(ci, a3, a3 + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)), Color("#fff36b"), rng)
			if st == "cast":
				var hand := _w(sheet, st, fi, "hand_n", at, face)
				_bolt(ci, hand, hand + Vector2(face * 22, rng.randf_range(-6, 6)), Color("#fffbd0"), rng)
				ci.draw_circle(hand, 4.0, Color("#fff36b", 0.7))
		"glacia":
			var rng2 := RandomNumberGenerator.new(); rng2.seed = int(t * 8.0)
			var c2 := _w(sheet, st, fi, "chest", at, face)
			for k in 3:
				ci.draw_rect(Rect2((c2 + Vector2(rng2.randf_range(-18, 18), rng2.randf_range(-34, 26))).round(), Vector2(1, 1)), Color("#e8ffff"))
			if st == "nova" or st == "throw":
				for hn in ["hand_n", "hand_f"] if st == "nova" else ["hand_n"]:
					var h := _w(sheet, st, fi, hn, at, face)
					var r := 3.0 + fi * 2.0 + sin(t * 20.0)
					ci.draw_circle(h, r + 2.0, Color("#3a8ad0", 0.45)); ci.draw_circle(h, r, Color("#bff4ff", 0.8))
					_star(ci, h.round(), Color("#ffffff"))
		"ironclad":
			if st == "windup" or st == "slam":
				for hn2 in ["hand_n", "hand_f"]:
					var h2 := _w(sheet, st, fi, hn2, at, face)
					ci.draw_circle(h2, 6.0 + sin(t * 30.0), Color("#ffd890", 0.35)); ci.draw_circle(h2, 3.0, Color("#fff6d8", 0.7))
		"paragon":
			var hot := st == "laser"
			for en in ["eye", "eye_far"]:
				var p2 := _w(sheet, st, fi, en, at, face) + Vector2(face * 0.5, 0)
				var r2 := 1.5
				if hot: r2 = 2.5 + fi * 2.0 + sin(t * 40.0) * 0.6
				elif sin(t * 6.0) > 0.0: r2 = 2.0
				ci.draw_circle(p2, r2 + 1.5, Color("#ff8a20", 0.55)); ci.draw_circle(p2, r2 * 0.6, Color("#fff0c0"))

static func _star(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), col)
	ci.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), col)

static func _bolt(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array([a])
	for k in range(1, 4):
		pts.append(a.lerp(b, k / 4.0) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	pts.append(b)
	ci.draw_polyline(pts, col, 1.0)

extends Node2D
## The single arena: a 1600x1100 floor with a theme per wave (palette, floor, props, time of day).
## Destructible props start as solid obstacles; they use the same wall records as before
## ({rect, open}) so collide_walls(), ray_len() and enemy navigation work unchanged.
const Navigation = preload("res://levels/city_navigation.gd")
const AW = Levels.AW
const AH = Levels.AH

## name, ambient (time of day), wall colour, lamp colour, floor style, prop kind, light energy
const THEMES := {
	"street":  {"name":"CITY STREETS","ambient":Color(0.62,0.64,0.72),"wall":Color("#3a4648"),"trim":Color("#ffd23c"),"lamp":Color("#ffd9a0"),"floor":"street","prop":"car"},
	"bank":    {"name":"BANK LOBBY","ambient":Color(0.76,0.72,0.66),"wall":Color("#4a3a2a"),"trim":Color("#c9a227"),"lamp":Color("#ffe2a0"),"floor":"marble","prop":"pillar"},
	"rooftop": {"name":"ROOFTOP","ambient":Color(0.42,0.47,0.68),"wall":Color("#5a5f66"),"trim":Color("#9aa3ad"),"lamp":Color("#c8d8ff"),"floor":"gravel","prop":"ac_unit"},
	"police":  {"name":"POLICE HQ","ambient":Color(0.70,0.74,0.80),"wall":Color("#2c3c5c"),"trim":Color("#4f7fd8"),"lamp":Color("#e8f4ff"),"floor":"tile","prop":"desk"},
	"museum":  {"name":"MUSEUM","ambient":Color(0.52,0.50,0.56),"wall":Color("#5a2a2a"),"trim":Color("#c9a227"),"lamp":Color("#fff0c8"),"floor":"parquet","prop":"case"},
	"harbour": {"name":"HARBOUR","ambient":Color(0.74,0.60,0.54),"wall":Color("#2a4a5a"),"trim":Color("#e8e0c8"),"lamp":Color("#ffb070"),"floor":"planks","prop":"container"},
	"spyhq":   {"name":"SPY HQ","ambient":Color(0.40,0.42,0.56),"wall":Color("#14181f"),"trim":Color("#3ae0ff"),"lamp":Color("#5af0ff"),"floor":"grid","prop":"server"},
}
const ORDER := ["street","bank","rooftop","police","museum","harbour","spyhq"]
## Prop slots keep the centre (spawn) and the edges clear, like Brotato's open arena.
const SOLID_SLOTS := [Vector2(330,260),Vector2(1270,260),Vector2(330,840),Vector2(1270,840),Vector2(800,200),Vector2(800,900)]
const LAMP_SLOTS := [Vector2(150,150),Vector2(1450,150),Vector2(150,950),Vector2(1450,950),Vector2(560,550),Vector2(1040,550)]
const ROAD_LAMP_SLOTS := [Vector2(150,150),Vector2(1450,150),Vector2(150,950),Vector2(1450,950),Vector2(400,550),Vector2(1200,550),Vector2(800,330),Vector2(800,770)]
## footprint (the solid rect) and visual height of each prop kind; props are drawn in 3/4 view by PropView
const PROP_SIZE := {"car":Vector2(120,56),"pillar":Vector2(56,56),"ac_unit":Vector2(76,54),"desk":Vector2(100,46),"case":Vector2(58,58),"container":Vector2(172,62),"server":Vector2(46,96)}
const PROP_H := {"car":20.0,"pillar":88.0,"ac_unit":30.0,"desk":22.0,"case":46.0,"container":52.0,"server":72.0}
const PROP_DAMAGE := {
	"car": {"hp":160.0, "material":"metal", "flammable":true},
	"pillar": {"hp":600.0, "material":"stone", "flammable":false},
	"ac_unit": {"hp":120.0, "material":"metal", "flammable":false},
	"desk": {"hp":80.0, "material":"wood", "flammable":true},
	"case": {"hp":240.0, "material":"glass", "flammable":false},
	"container": {"hp":360.0, "material":"metal", "flammable":false},
	"server": {"hp":140.0, "material":"metal", "flammable":true},
}
const FLOOR_IDS := ["street","marble","gravel","tile","parquet","planks","grid"]
const PropView = preload("res://levels/prop_view.gd")
const FLOOR_SHADER = preload("res://levels/floor.gdshader")

var theme_id := "street"
var theme: Dictionary = THEMES.street
var walls: Array = []
var props: Array = []          # [{rect, kind, color}]
var lamps: Array = []          # world positions of theme lights
var prop_parent: Node          # the arena's y-sorted actor layer (props sort with the villain and cops)
var prop_nodes: Array = []     # PropView nodes: solid props + street lamp posts
var decor: Array = []          # floor details baked into the floor that the ambient layer animates ({pos, kind})
var navigation = Navigation.new()
var _floors := {}
var _floor_sprite: Sprite2D

func _ready() -> void:
	_floor_sprite = Sprite2D.new(); _floor_sprite.centered = false; _floor_sprite.z_index = -10; add_child(_floor_sprite)
	var m := ShaderMaterial.new(); m.shader = FLOOR_SHADER; _floor_sprite.material = m

static func theme_for_wave(wave: int, order: Array = ORDER) -> String:
	return order[(maxi(1,wave)-1) % order.size()]

func build(id: String) -> void:
	theme_id = id if THEMES.has(id) else "street"; theme = THEMES[theme_id]
	if _floor_sprite == null: _ready()
	decor.clear()
	if not _floors.has(theme_id): _floors[theme_id] = {"tex": ImageTexture.create_from_image(_make_floor(theme_id)), "decor": decor.duplicate()}
	_floor_sprite.texture = _floors[theme_id].tex; decor = _floors[theme_id].decor.duplicate()
	walls.clear(); props.clear(); lamps.clear()
	for n in prop_nodes: n.queue_free()
	prop_nodes.clear()
	var size: Vector2 = PROP_SIZE[theme.prop]
	var rng := RandomNumberGenerator.new(); rng.seed = hash(theme_id)
	for i in SOLID_SLOTS.size():
		var c: Vector2 = SOLID_SLOTS[i]
		var s := size
		if i >= 4 and theme.prop in ["container", "car"]: s = Vector2(size.y, size.x)   # the north/south pair is turned
		var rect := Rect2(c - s / 2.0, s)
		var p := {"rect": rect, "kind": theme.prop, "color": _prop_color(rng), "h": PROP_H[theme.prop], "flip": rng.randf() < 0.5,
			"police": theme.prop == "car" and i in [1, 4], "variant": i}
		props.append(p)
		var durability: Dictionary = PROP_DAMAGE[p.kind]
		p.merge({"hp":durability.hp, "max_hp":durability.hp, "material":durability.material, "flammable":durability.flammable,
			"broken":false, "marks":[], "burn_t":0.0, "burn_dps":0.0, "fuse":-1.0, "char":0.0, "flash":0.0, "wreck_t":0.0})
		walls.append({"rect": rect, "open": false, "prop_index": i})
		_spawn_prop(p)
	for p in (ROAD_LAMP_SLOTS if theme_id == "street" else LAMP_SLOTS):
		lamps.append(p)
		if theme.floor in ["street", "planks"]: _spawn_prop({"rect": Rect2(p - Vector2(1, 1), Vector2(2, 2)), "kind": "lamp_post", "color": Color.WHITE, "variant": prop_nodes.size()})
	navigation.configure(walls, Vector2(AW, AH))
	_update_floor_material()
	queue_redraw()

func shatter_case(p: Dictionary) -> void:
	break_prop(p)

func break_prop(p: Dictionary) -> void:
	p.broken = true; p.hp = 0.0; p.h = 0.0
	for wall in walls:
		if wall.get("prop_index", -1) == props.find(p): wall.open = true
	navigation.configure(walls, Vector2(AW, AH))
	_update_floor_material()

func _spawn_prop(p: Dictionary) -> void:
	var n := PropView.new(); n.setup(p, theme)
	(prop_parent if prop_parent != null else self).add_child(n); prop_nodes.append(n)

## Floor shader: per-theme animation, bump from the albedo, prop shadows and wall occlusion.
func _update_floor_material() -> void:
	var m: ShaderMaterial = _floor_sprite.material
	m.set_shader_parameter("theme_id", FLOOR_IDS.find(theme.floor))
	m.set_shader_parameter("world_size", Vector2(AW, AH))
	var rects: Array = []; var hs: Array = []
	for i in 8:
		var r: Rect2 = props[i].rect if i < props.size() else Rect2(-999, -999, 1, 1)
		rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y)); hs.append(props[i].h if i < props.size() else 0.0)
	m.set_shader_parameter("prop_rects", rects); m.set_shader_parameter("prop_h", PackedFloat32Array(hs))
	m.set_shader_parameter("prop_count", props.size())
	m.set_shader_parameter("lamp_col", theme.lamp)

func _prop_color(rng: RandomNumberGenerator) -> Color:
	match theme.prop:
		"car": return [Color("#b83232"),Color("#2f5fb8"),Color("#d8c040"),Color("#e8e8e8"),Color("#3a8a4a")][rng.randi() % 5]
		"container": return [Color("#b8452a"),Color("#2a6ab8"),Color("#3a8a5a"),Color("#c89a2a")][rng.randi() % 4]
	return theme.trim

# ---------------- floors (baked once per theme) ----------------
static func _blend(g: Image, r: Rect2i, c: Color) -> void:
	r = r.intersection(Rect2i(0, 0, g.get_width(), g.get_height()))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g.set_pixel(x, y, g.get_pixel(x, y).blend(c))

func _make_floor(id: String) -> Image:
	var t: Dictionary = THEMES[id]
	var g := Image.create(AW, AH, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = hash(id) + 17
	var ri := func(a: int, b: int) -> int: return rng.randi_range(a, b)
	match t.floor:
		"street":
			g.fill(Color("#232c2e"))
			var speck := [Color("#283234"), Color("#1f2729"), Color("#2b3537"), Color("#202a2b")]
			for i in 9000: g.fill_rect(Rect2i(ri.call(0, AW) & ~3, ri.call(0, AH) & ~3, 4, 4), speck[rng.randi() % 4])
			g.fill_rect(Rect2i(0, AH / 2 - 90, AW, 180), Color("#1b2224")); g.fill_rect(Rect2i(AW / 2 - 90, 0, 180, AH), Color("#1b2224"))
			for x in range(0, AW, 60):
				if absi(x + 20 - AW / 2) > 100: g.fill_rect(Rect2i(x, AH / 2 - 3, 32, 6), Color("#d8c040"))
			for y in range(0, AH, 60):
				if absi(y + 20 - AH / 2) > 100: g.fill_rect(Rect2i(AW / 2 - 3, y, 6, 32), Color("#d8c040"))
			for i in range(-80, 80, 20):
				var cw := Color("#c8ccd0")
				g.fill_rect(Rect2i(AW / 2 + i, AH / 2 - 130, 10, 34), cw); g.fill_rect(Rect2i(AW / 2 + i, AH / 2 + 96, 10, 34), cw)
				g.fill_rect(Rect2i(AW / 2 - 130, AH / 2 + i, 34, 10), cw); g.fill_rect(Rect2i(AW / 2 + 96, AH / 2 + i, 34, 10), cw)
			# sidewalks along the walls: concrete slabs with a kerb
			for side in [Rect2i(16, 16, AW - 32, 56), Rect2i(16, AH - 72, AW - 32, 56), Rect2i(16, 16, 56, AH - 32), Rect2i(AW - 72, 16, 56, AH - 32)]:
				g.fill_rect(side, Color("#4a5052"))
				for y in range(side.position.y, side.end.y, 28):
					for x in range(side.position.x, side.end.x, 28):
						g.fill_rect(Rect2i(x + 1, y + 1, 26, 26), [Color("#5a6062"), Color("#555b5d"), Color("#5e6466")][rng.randi() % 3])
			g.fill_rect(Rect2i(72, 72, AW - 144, 4), Color("#8a9092")); g.fill_rect(Rect2i(72, AH - 76, AW - 144, 4), Color("#8a9092"))
			g.fill_rect(Rect2i(72, 72, 4, AH - 144), Color("#8a9092")); g.fill_rect(Rect2i(AW - 76, 72, 4, AH - 144), Color("#8a9092"))
			# cracks and oil stains
			for i in 26:
				var p := Vector2(ri.call(90, AW - 90), ri.call(90, AH - 90)); var a := rng.randf() * TAU
				for k in ri.call(8, 22):
					a += rng.randf_range(-0.6, 0.6); p += Vector2.from_angle(a) * 2.0
					g.fill_rect(Rect2i(int(p.x), int(p.y), 2, 2), Color("#141a1b"))
			for i in 12:
				var x: int = ri.call(120, AW - 120); var y: int = ri.call(120, AH - 120)
				for k in 6: _blend(g, Rect2i(x + ri.call(-14, 10), y + ri.call(-8, 6), ri.call(10, 22), ri.call(6, 12)), Color(0.05, 0.04, 0.08, 0.25))
			for i in 14:   # storm drains (the ambient layer puffs steam out of these)
				var x: int = ri.call(100, AW - 100); var y: int = ri.call(100, AH - 100)
				g.fill_rect(Rect2i(x - 13, y - 13, 26, 26), Color("#3a4244")); g.fill_rect(Rect2i(x - 12, y - 12, 24, 24), Color("#0c1011"))
				for k in range(-8, 9, 4): g.fill_rect(Rect2i(x - 10, y + k, 20, 2), Color("#3a4648"))
				decor.append({"pos": Vector2(x, y), "kind": "grate"})
		"marble":
			for y in range(0, AH, 40):
				for x in range(0, AW, 40): g.fill_rect(Rect2i(x, y, 40, 40), Color("#d8d2c4") if ((x + y) / 40) % 2 else Color("#bdb6a6"))
			for i in 1800: _blend(g, Rect2i(ri.call(0, AW), ri.call(0, AH), ri.call(2, 10), 1), [Color(1, 1, 1, 0.18), Color(0.47, 0.43, 0.35, 0.12)][rng.randi() % 2])
			g.fill_rect(Rect2i(16, 500, AW - 32, 100), Color("#8a1a22")); g.fill_rect(Rect2i(16, 500, AW - 32, 4), Color("#c9a227")); g.fill_rect(Rect2i(16, 596, AW - 32, 4), Color("#c9a227"))
		"gravel":
			g.fill(Color("#3d4046"))
			for i in 16000: g.fill_rect(Rect2i(ri.call(0, AW), ri.call(0, AH), 2, 2), [Color("#4a4d54"), Color("#32353a"), Color("#555960")][rng.randi() % 3])
			for p in [Vector2i(560, 380), Vector2i(1040, 720), Vector2i(560, 720), Vector2i(1040, 380)]:   # skylights
				g.fill_rect(Rect2i(p.x - 40, p.y - 26, 80, 52), Color("#6a7480")); g.fill_rect(Rect2i(p.x - 36, p.y - 22, 72, 44), Color("#2a3a5a"))
				_blend(g, Rect2i(p.x - 30, p.y - 18, 16, 36), Color(0.8, 0.9, 1.0, 0.25))
			for x in range(40, AW - 40, 120): g.fill_rect(Rect2i(x, 60, 3, AH - 120), Color(0.2, 0.21, 0.24))   # tar seams
			_ring(g, Rect2i(800 - 60, 550 - 60, 120, 120), Color("#e8e0c8"), 6); g.fill_rect(Rect2i(800 - 20, 550 - 34, 8, 68), Color("#e8e0c8")); g.fill_rect(Rect2i(800 + 12, 550 - 34, 8, 68), Color("#e8e0c8")); g.fill_rect(Rect2i(800 - 20, 547, 40, 6), Color("#e8e0c8"))   # helipad H
		"tile":
			g.fill(Color("#9aa6b4"))
			for y in range(0, AH, 32):
				for x in range(0, AW, 32):
					g.fill_rect(Rect2i(x, y, 31, 31), Color("#a8b4c2") if ((x + y) / 32) % 2 else Color("#9eaab8"))
			for i in 900: _blend(g, Rect2i(ri.call(0, AW), ri.call(0, AH), ri.call(2, 6), ri.call(1, 3)), Color(0.2, 0.24, 0.3, 0.12))
			g.fill_rect(Rect2i(AW / 2 - 70, AH / 2 - 70, 140, 140), Color("#2c3c5c")); _ring(g, Rect2i(AW / 2 - 56, AH / 2 - 56, 112, 112), Color("#ffd23c"), 4)   # badge
		"parquet":
			g.fill(Color("#5a3a22"))
			for y in range(0, AH, 24):
				var off := (y / 24) % 2 * 48
				for x in range(-off, AW, 96): g.fill_rect(Rect2i(x + 1, y + 1, 94, 22), [Color("#6a4628"), Color("#644226"), Color("#704a2c")][rng.randi() % 3])
			_ring(g, Rect2i(120, 120, AW - 240, AH - 240), Color("#8a1a22"), 10)
		"planks":
			g.fill(Color("#5a4630"))
			for y in range(0, AH, 20):
				for x in range(-ri.call(0, 140), AW, 140): g.fill_rect(Rect2i(x + 1, y + 1, 138, 18), [Color("#7a6040"), Color("#6e5638"), Color("#826846")][rng.randi() % 3])
			for i in 400: g.fill_rect(Rect2i(ri.call(0, AW), ri.call(0, AH), 2, 2), Color("#3a2a1a"))   # nails
			g.fill_rect(Rect2i(16, AH - 70, AW - 32, 54), Color("#1a4a6a"))   # water at the south edge
			for i in 220: _blend(g, Rect2i(ri.call(16, AW - 40), ri.call(AH - 68, AH - 22), ri.call(8, 24), 2), Color(0.7, 0.9, 1.0, 0.25))
			g.fill_rect(Rect2i(16, AH - 74, AW - 32, 4), Color("#e8e0c8"))
		"grid":
			g.fill(Color("#0e1218"))
			for x in range(0, AW, 64): g.fill_rect(Rect2i(x, 0, 1, AH), Color("#16303a"))
			for y in range(0, AH, 64): g.fill_rect(Rect2i(0, y, AW, 1), Color("#16303a"))
			for i in 30:
				var y: int = ri.call(1, AH / 64 - 1) * 64; var x: int = ri.call(0, AW / 64 - 4) * 64
				g.fill_rect(Rect2i(x, y, 64 * ri.call(2, 6), 2), Color("#1f8aa0"))   # data traces
			_ring(g, Rect2i(AW / 2 - 90, AH / 2 - 90, 180, 180), Color("#3ae0ff"), 2); _ring(g, Rect2i(AW / 2 - 60, AH / 2 - 60, 120, 120), Color("#1f8aa0"), 2)
	# border wall with trim
	var wc: Color = t.wall; var trim: Color = t.trim
	g.fill_rect(Rect2i(0, 0, AW, 16), wc); g.fill_rect(Rect2i(0, AH - 16, AW, 16), wc); g.fill_rect(Rect2i(0, 0, 16, AH), wc); g.fill_rect(Rect2i(AW - 16, 0, 16, AH), wc)
	for x in range(0, AW, 40): g.fill_rect(Rect2i(x, 4, 20, 8), trim); g.fill_rect(Rect2i(x + 10, AH - 12, 20, 8), trim)
	for y in range(0, AH, 40): g.fill_rect(Rect2i(4, y, 8, 20), trim); g.fill_rect(Rect2i(AW - 12, y + 10, 8, 20), trim)
	return g

static func _ring(g: Image, r: Rect2i, c: Color, w: int) -> void:
	g.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, w), c); g.fill_rect(Rect2i(r.position.x, r.end.y - w, r.size.x, w), c)
	g.fill_rect(Rect2i(r.position.x, r.position.y, w, r.size.y), c); g.fill_rect(Rect2i(r.end.x - w, r.position.y, w, r.size.y), c)

# ---------------- floor fixtures (props themselves are PropView nodes in the actor layer) ----------------
func _draw() -> void:
	if theme.floor == "grid":
		for p in lamps: draw_rect(Rect2(p.x - 12, p.y - 3, 24, 6), Color("#1a2a33")); draw_rect(Rect2(p.x - 10, p.y - 1, 20, 2), theme.lamp)

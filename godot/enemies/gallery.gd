extends Node2D
## Enemy gallery: every enemy/NPC/boss in every baked state, animated, under a movable light.
## Mouse moves the light, wheel changes its height, Tab / PageUp / PageDown switch pages,
## 1-5 preview tints (none, hit flash, mind control, frozen, sick), F flips facing, O orbits the light,
## N cycles ambient light. Run with `-- --shot test-results/gallery.png` to save every page and quit.
const Painter = preload("res://enemies/enemy_painter.gd")
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Fx = preload("res://enemies/enemy_fx.gd")
const Flash = preload("res://enemies/muzzle_flash.gd")

const PAGES := [
	{"title": "Street response", "kinds": ["undercover", "undercover_hood", "interceptor", "swat_shield"]},
	{"title": "Military response", "kinds": ["robodog", "guard", "tank"]},
	{"title": "Police", "kinds": ["cop", "swat", "det", "riot", "dog", "drone"]},
	{"title": "Civilians", "kinds": ["civ_suit", "civ_tourist", "civ_granny", "civ_jogger"]},
	{"title": "Bosses I", "kinds": ["hero_ironclad", "hero_surge"]},
	{"title": "Bosses II", "kinds": ["hero_glacia", "hero_paragon"]},
	{"title": "Velvet Viper", "kinds": ["hero_viper"]},
]
const TINTS := [Color(0, 0, 0, 0), Color(1, 1, 1, 0.85), Color("#c46bff", 0.5), Color("#9ef0ff", 0.6), Color("#8fdc3a", 0.4)]
const AMBIENTS := [Color(0.62, 0.64, 0.72), Color(0.35, 0.36, 0.45), Color(1, 1, 1)]

var page := 0
var t := 0.0
var tint := 0
var face := 1
var orbit := false
var ambient_i := 0
var light: PointLight2D
var ambient: CanvasModulate
var cam: Camera2D
var sprites: Node2D
var fx: Node2D
var labels: Node2D
var flashes: Array = []
var layout: Array = []   # [{kind, state, pos}]
var _shot := ""
var floor_node: Node2D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size(): _shot = args[i + 1]
		if args[i] == "--page" and i + 1 < args.size(): page = int(args[i + 1])
	EnemyArt.build()
	RenderingServer.set_default_clear_color(Color("#2a2e38"))
	ambient = CanvasModulate.new(); ambient.color = AMBIENTS[0]; add_child(ambient)
	floor_node = Node2D.new(); floor_node.draw.connect(_draw_floor.bind(floor_node)); add_child(floor_node)
	sprites = Node2D.new(); sprites.draw.connect(_draw_sprites); add_child(sprites)
	fx = Node2D.new(); var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED; fx.material = m; fx.draw.connect(_draw_fx); add_child(fx)
	labels = Node2D.new(); var lm := CanvasItemMaterial.new(); lm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	labels.material = lm; labels.draw.connect(_draw_labels); add_child(labels)
	light = PointLight2D.new(); light.texture = preload("res://fx/light_pool.gd").light_tex(); light.texture_scale = 2.2
	light.energy = 1.4; light.height = 40.0; light.color = Color("#fff1d8"); light.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(light)
	cam = Camera2D.new(); cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT; add_child(cam)
	_layout()
	if _shot != "": _take_shots.call_deferred()

func _layout() -> void:
	layout.clear()
	for f in flashes: f.queue_free()
	flashes.clear()
	var y := 34.0; var width := 0.0
	for kind in PAGES[page].kinds:
		var sheet := EnemyArt.sheet(kind)
		var cell: Vector2 = sheet.cell
		var x := 96.0
		for st in Painter.states(kind):
			if x + cell.x > 956.0: x = 96.0; y += cell.y + 12
			var pos := Vector2(x + sheet.origin.x, y + sheet.origin.y)
			layout.append({"kind": kind, "state": st, "pos": pos, "sheet": sheet})
			if kind == "det" and st == "attack":
				var fl := Flash.new(); add_child(fl); fl.set_meta("pos", pos); flashes.append(fl)
			x += cell.x + 4
		width = maxf(width, x)
		y += sheet.cell.y + 14
	var view := get_viewport_rect().size
	var zoom := minf(2.0, minf(view.x / (width + 10), view.y / (y + 4)))
	if zoom >= 1.0: zoom = floorf(zoom * 2.0) / 2.0
	floor_node.queue_redraw()
	cam.zoom = Vector2(zoom, zoom)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: light.height = minf(200.0, light.height + 6.0)
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: light.height = maxf(0.0, light.height - 6.0)
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_TAB, KEY_PAGEDOWN: page = (page + 1) % PAGES.size(); _layout()
			KEY_PAGEUP: page = posmod(page - 1, PAGES.size()); _layout()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: tint = ev.keycode - KEY_1
			KEY_F: face = -face
			KEY_O: orbit = not orbit
			KEY_N: ambient_i = (ambient_i + 1) % AMBIENTS.size(); ambient.color = AMBIENTS[ambient_i]

func _process(dt: float) -> void:
	t += dt
	if _shot != "":
		light.position = Vector2(60, 300) / cam.zoom.x; light.height = 30.0; ambient.color = AMBIENTS[1]
	elif orbit:
		var c := get_viewport_rect().size / cam.zoom / 2.0
		light.position = c + Vector2(cos(t * 0.8), sin(t * 0.8) * 0.6) * c.x * 0.7
	else:
		light.position = get_global_mouse_position()
	for f in flashes:
		f.position = f.get_meta("pos") + Vector2(0, 0)
		var sheet := EnemyArt.sheet("det")
		var m := Sheets.anchor(sheet, "attack", 1, "muzzle")
		f.position += Vector2(m.x * face, m.y); f.rotation = 0.0 if face > 0 else PI
		if fmod(t, 0.8) < dt and _shot == "": f.fire()
		if _shot == "": f.tick(dt)
	sprites.queue_redraw(); fx.queue_redraw(); labels.queue_redraw()

func _frame(entry: Dictionary) -> int:
	var st: String = entry.state
	if st == "attack" and entry.kind == "det": return 1 if fmod(t, 0.8) < 0.12 else 0
	if st == "death": return mini(3, int(fmod(t, 2.0) * 8.0))
	return int(t * (10.0 if st in ["walk", "panic", "blink"] else 4.0))

func _draw_floor(ci: Node2D) -> void:
	for entry in layout:
		var p: Vector2 = entry.pos
		var sh: Vector2 = EnemyView.SHADOW[entry.sheet.family]
		ci.draw_rect(Rect2(p.x - entry.sheet.origin.x, p.y - 1, entry.sheet.cell.x, 3), Color("#4a5060"))
		ci.draw_set_transform(p + Vector2(0, 0), 0.0, sh)
		ci.draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.32))
		ci.draw_set_transform(Vector2.ZERO)

func _draw_sprites() -> void:
	for entry in layout:
		if entry.kind in ["tank","interceptor"]:
			var scale_factor := 0.29 if entry.kind == "tank" else 0.7
			sprites.draw_set_transform(entry.pos,0.0,Vector2.ONE*scale_factor)
			preload("res://enemies/vehicle_view.gd").draw(sprites,entry.kind,Vector2(face,0),Vector2.ZERO,t,TINTS[tint],1.0,entry.state=="death")
			sprites.draw_set_transform(Vector2.ZERO)
			continue
		var lift := 8.0 if entry.kind == "hero_paragon" else 0.0
		EnemyView.draw_sprite(sprites, entry.sheet, entry.state, _frame(entry), entry.pos - Vector2(0, lift), face, TINTS[tint])

func _draw_fx() -> void:
	for entry in layout:
		var lift := 8.0 if entry.kind == "hero_paragon" else 0.0
		Fx.draw_fx(fx, entry.sheet, entry.state, _frame(entry), entry.pos - Vector2(0, lift), face, t,
			{"hero": entry.kind.substr(5) if entry.kind.begins_with("hero_") else "", "type": entry.kind, "frozen": entry.state == "frozen"})

func _draw_labels() -> void:
	var font := ThemeDB.fallback_font
	labels.draw_string(font, Vector2(8, 16), "%s  (Tab: page  1-5: tint  F: flip  O: orbit light  N: ambient  wheel: light height %d)" % [PAGES[page].title, light.height], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e8ecf0"))
	var last := ""
	for entry in layout:
		var p: Vector2 = entry.pos
		var top: float = p.y - entry.sheet.origin.y
		labels.draw_string(font, Vector2(p.x - entry.sheet.origin.x + 2, top + 8), entry.state, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#aab4c4"))
		if entry.kind != last:
			last = entry.kind
			labels.draw_string(font, Vector2(6, p.y - 10), entry.kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd23c"))

func _take_shots() -> void:
	for i in PAGES.size():
		page = i; _layout()
		for k in 12: await get_tree().process_frame
		for f in flashes: f.fire(); f.life = 0.8
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = _shot.get_basename() + "_" + str(i) + "_" + PAGES[i].title.to_lower().replace(" ", "_") + ".png"
		img.save_png(path)
		print("saved ", path)
	get_tree().quit()

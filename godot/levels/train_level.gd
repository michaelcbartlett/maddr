extends RefCounted
## The train heist stage: a long armoured train running left to right, one car per room.
## The villain boards at the caboose (west end) and fights east, car by car, to the vault car behind the engine.
## Cars are connected rooms: solid walls above and below the cars, with a narrow gangway door at each coupling.
## Props (seats, mail racks, freight, safes) use the arena's normal destructible prop records.
## Built by levels/arena_level.gd when the theme is "train"; game/train_heist.gd owns the goal and spawning.

const CAR_LEN := 600.0       # interior length of one car
const GAP := 80.0            # coupling gangway between cars
const START := 160.0         # west end of the caboose (open track behind it)
const TOP := 230.0           # interior top (y)
const BOT := 530.0           # interior bottom (y)
const DOOR := 136.0          # gangway door height
const ENGINE_LEN := 560.0
const HEIGHT := 760.0
const GOAL_LEN := 150.0      # the vault strongroom at the front of the last car
const LENGTH_MULTIPLIER := 4
## name, floor style, props [kind, x offset in the car, y, turned]
const CARS := [
	{"name":"CABOOSE", "floor":"wood", "props":[["desk", 380, 300, false]]},
	{"name":"PASSENGER CAR", "floor":"wood", "props":[["desk", 150, 290, false], ["desk", 300, 470, false], ["desk", 460, 290, false]]},
	{"name":"DINING CAR", "floor":"carpet", "props":[["desk", 170, 470, false], ["pillar", 320, 300, false], ["desk", 470, 470, false]]},
	{"name":"MAIL CAR", "floor":"steel", "props":[["server", 160, 300, false], ["server", 300, 470, false], ["server", 440, 300, false]]},
	{"name":"FREIGHT CAR", "floor":"steel", "props":[["container", 190, 290, false], ["container", 420, 470, false]]},
	{"name":"FIRST CLASS", "floor":"carpet", "props":[["ac_unit", 150, 470, false], ["desk", 300, 290, false], ["ac_unit", 450, 470, false]]},
	{"name":"VAULT CAR", "floor":"steel", "props":[["pillar", 160, 300, false], ["pillar", 160, 460, false], ["server", 330, 380, false]]},
]

static func car_count() -> int: return CARS.size() * LENGTH_MULTIPLIER
## Keep one caboose and one final vault, with more passenger/dining/mail/freight/first-class cars between.
static func car_def(i: int) -> Dictionary:
	if i <= 0: return CARS[0]
	if i >= car_count()-1: return CARS[CARS.size()-1]
	return CARS[1+(i-1) % (CARS.size()-2)]
static func car_x(i: int) -> float: return START + i * (CAR_LEN + GAP)
static func train_end() -> float: return car_x(car_count() - 1) + CAR_LEN
static func size() -> Vector2: return Vector2(train_end() + ENGINE_LEN + 160.0, HEIGHT)
static func spawn() -> Vector2: return Vector2(START + 90.0, (TOP + BOT) / 2.0)
static func goal_rect() -> Rect2: return Rect2(train_end() - GOAL_LEN, TOP, GOAL_LEN, BOT - TOP)
static func car_rect(i: int) -> Rect2: return Rect2(car_x(i), TOP, CAR_LEN, BOT - TOP)

## Which car (0-based) a world x lies in; a gangway counts as the car behind it.
static func car_at(x: float) -> int:
	return clampi(floori((x - START) / (CAR_LEN + GAP)), 0, car_count() - 1)

## 0 at the caboose door, 1 at the vault.
static func progress(x: float) -> float:
	var a := spawn().x; var b := goal_rect().position.x
	return clampf((x - a) / (b - a), 0.0, 1.0)

static func walls() -> Array:
	var s := size(); var out: Array = []
	out.append({"rect": Rect2(0, 0, s.x, TOP), "open": false})
	out.append({"rect": Rect2(0, BOT, s.x, s.y - BOT), "open": false})
	out.append({"rect": Rect2(0, TOP, START, BOT - TOP), "open": false})
	out.append({"rect": Rect2(train_end(), TOP, s.x - train_end(), BOT - TOP), "open": false})
	var door_top := (TOP + BOT - DOOR) / 2.0; var door_bot := door_top + DOOR
	for i in car_count() - 1:
		var x := car_x(i) + CAR_LEN
		out.append({"rect": Rect2(x, TOP, GAP, door_top - TOP), "open": false})
		out.append({"rect": Rect2(x, door_bot, GAP, BOT - door_bot), "open": false})
	return out

## Fills an ArenaLevel (levels/arena_level.gd) with the train: walls, props, ceiling lamps.
static func build(level) -> void:
	for w in walls(): level.walls.append(w)
	var rng := RandomNumberGenerator.new(); rng.seed = 7171
	for i in car_count():
		for spec in car_def(i).props:
			var kind: String = spec[0]
			var s: Vector2 = level.PROP_SIZE[kind]
			if spec[3]: s = Vector2(s.y, s.x)
			var c := Vector2(car_x(i) + float(spec[1]), float(spec[2]))
			var rect := Rect2(c - s / 2.0, s)
			var color: Color = [Color("#b8452a"), Color("#2a6ab8"), Color("#3a8a5a")][rng.randi() % 3] if kind == "container" else level.theme.trim
			var p := {"rect": rect, "kind": kind, "color": color, "h": level.PROP_H[kind], "flip": rng.randf() < 0.5, "police": false, "variant": level.props.size()}
			var durability: Dictionary = level.PROP_DAMAGE[kind]
			p.merge({"hp":durability.hp, "max_hp":durability.hp, "material":durability.material, "flammable":durability.flammable,
				"broken":false, "marks":[], "burn_t":0.0, "burn_dps":0.0, "fuse":-1.0, "char":0.0, "flash":0.0, "wreck_t":0.0})
			level.walls.append({"rect": rect, "open": false, "prop_index": level.props.size()})
			level.props.append(p)
			level._spawn_prop(p)
		for f in [0.25, 0.75]: level.lamps.append(Vector2(car_x(i) + CAR_LEN * f, (TOP + BOT) / 2.0))

# ---------------- floor (baked once) ----------------
static func make_floor() -> Image:
	var s := size(); var W := int(s.x); var H := int(s.y)
	var g := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = 9090
	# countryside rushing past: dark grass with streaks, then the ballast bed and the rails
	g.fill(Color("#24331f"))
	for i in 5000:
		g.fill_rect(Rect2i(rng.randi_range(0, W), rng.randi_range(0, H), rng.randi_range(12, 60), 2), [Color("#2c3d25"), Color("#1d2a19"), Color("#33452a")][rng.randi() % 3])
	var bed := Rect2i(0, int(TOP) - 60, W, int(BOT - TOP) + 120)
	g.fill_rect(bed, Color("#4a4540"))
	for i in 14000: g.fill_rect(Rect2i(rng.randi_range(0, W), rng.randi_range(bed.position.y, bed.end.y), 3, 3), [Color("#5a544c"), Color("#3c3833"), Color("#6a6258")][rng.randi() % 3])
	for x in range(0, W, 36): g.fill_rect(Rect2i(x, int(TOP) - 40, 14, int(BOT - TOP) + 80), Color("#3a2a1c"))   # sleepers
	for y in [int(TOP) + 40, int(BOT) - 46]:
		g.fill_rect(Rect2i(0, y, W, 6), Color("#8a9098")); g.fill_rect(Rect2i(0, y, W, 2), Color("#c8ccd0"))
	# cars
	var livery := Color("#5a1e22"); var trim := Color("#c9a227")
	for i in car_count():
		var x0 := int(car_x(i)); var x1 := int(car_x(i) + CAR_LEN)
		g.fill_rect(Rect2i(x0 - 6, int(TOP) - 30, x1 - x0 + 12, int(BOT - TOP) + 60), livery)
		g.fill_rect(Rect2i(x0 - 6, int(TOP) - 30, x1 - x0 + 12, 4), trim); g.fill_rect(Rect2i(x0 - 6, int(BOT) + 26, x1 - x0 + 12, 4), trim)
		for wx in range(x0 + 30, x1 - 40, 90):   # windows in the side walls
			for wy in [int(TOP) - 22, int(BOT) + 6]:
				g.fill_rect(Rect2i(wx, wy, 52, 14), Color("#1a2630")); g.fill_rect(Rect2i(wx + 2, wy + 2, 48, 4), Color("#7fb4d0"))
		_car_floor(g, Rect2i(x0, int(TOP), x1 - x0, int(BOT - TOP)), car_def(i).floor, rng)
		g.fill_rect(Rect2i(x0, int(TOP), x1 - x0, 3), Color(0, 0, 0, 0.5)); g.fill_rect(Rect2i(x0, int(BOT) - 3, x1 - x0, 3), Color(0, 0, 0, 0.5))
		if i < car_count() - 1:   # gangway: steel plate between rubber bellows
			var door_top := int((TOP + BOT - DOOR) / 2.0)
			g.fill_rect(Rect2i(x1, door_top - 14, int(GAP), int(DOOR) + 28), Color("#1a1a1c"))
			for bx in range(x1 + 4, x1 + int(GAP) - 4, 8):
				g.fill_rect(Rect2i(bx, door_top - 14, 4, 14), Color("#2c2c30")); g.fill_rect(Rect2i(bx, door_top + int(DOOR), 4, 14), Color("#2c2c30"))
			g.fill_rect(Rect2i(x1, door_top, int(GAP), int(DOOR)), Color("#6a6e74"))
			for py in range(door_top + 6, door_top + int(DOOR), 12):
				for px in range(x1 + 4, x1 + int(GAP) - 4, 12): g.fill_rect(Rect2i(px, py, 6, 2), Color("#8a8e94"))
	# the vault strongroom: hazard stripes and a big round door on the front bulkhead
	var gr := goal_rect()
	for y in range(int(gr.position.y), int(gr.end.y), 4):
		for x in range(int(gr.position.x), int(gr.end.x), 4):
			if ((x + y) / 24) % 2 == 0: g.fill_rect(Rect2i(x, y, 4, 4), Color("#d8b020"))
	g.fill_rect(Rect2i(int(gr.position.x) + 10, int(gr.position.y) + 10, int(gr.size.x) - 20, int(gr.size.y) - 20), Color("#3a3226"))
	var vc := Vector2i(int(gr.end.x) - 40, int((TOP + BOT) / 2.0))
	for r in [96, 86, 70]:
		var col: Color = {96: Color("#6a6458"), 86: Color("#b8b0a0"), 70: Color("#8a8070")}[r]
		for y in range(-r, r + 1, 2):
			var hw := int(sqrt(float(r * r - y * y)) * 0.45)
			g.fill_rect(Rect2i(vc.x - hw, vc.y + y, hw * 2, 2), col)
	for a in 6:
		var d := Vector2.from_angle(a * TAU / 6.0)
		for k in range(10, 60, 3): g.fill_rect(Rect2i(vc.x + int(d.x * k * 0.45), vc.y + int(d.y * k), 4, 4), Color("#ffd23c"))
	# the engine (solid): boiler, smokebox, cab
	var ex := int(train_end()) + 8
	g.fill_rect(Rect2i(ex, int(TOP) - 10, int(ENGINE_LEN) - 40, int(BOT - TOP) + 20), Color("#1c2a22"))
	g.fill_rect(Rect2i(ex, int(TOP) - 10, 150, int(BOT - TOP) + 20), Color("#24342a"))   # cab
	g.fill_rect(Rect2i(ex + 20, int(TOP) + 20, 110, int(BOT - TOP) - 40), Color("#3a2a20"))
	g.fill_rect(Rect2i(ex + 40, int(TOP) + 100, 40, 100), Color("#ff7a20"))   # firebox glow
	for bx in range(ex + 160, ex + int(ENGINE_LEN) - 80, 50):
		g.fill_rect(Rect2i(bx, int(TOP) + 10, 6, int(BOT - TOP) - 20), trim)   # boiler bands
	g.fill_rect(Rect2i(ex + int(ENGINE_LEN) - 170, int(TOP) + 110, 80, 80), Color("#0c0c0c"))   # chimney
	g.fill_rect(Rect2i(ex + int(ENGINE_LEN) - 60, int(TOP) + 40, 24, int(BOT - TOP) - 80), Color("#8a1a1a"))   # cow-catcher
	return g

static func _car_floor(g: Image, r: Rect2i, style: String, rng: RandomNumberGenerator) -> void:
	match style:
		"wood":
			g.fill_rect(r, Color("#5a3e26"))
			for y in range(r.position.y, r.end.y, 18):
				for x in range(r.position.x - rng.randi_range(0, 120), r.end.x, 120):
					var a := maxi(x, r.position.x)
					g.fill_rect(Rect2i(a + 1, y + 1, mini(118, r.end.x - a - 1), 16), [Color("#6a4a2c"), Color("#644428"), Color("#704e30")][rng.randi() % 3])
			g.fill_rect(Rect2i(r.position.x, r.position.y + r.size.y / 2 - 20, r.size.x, 40), Color("#7a2a2a"))   # aisle runner
		"carpet":
			g.fill_rect(r, Color("#6a1a24"))
			for y in range(r.position.y + 10, r.end.y, 30):
				for x in range(r.position.x + 10, r.end.x, 30): g.fill_rect(Rect2i(x, y, 6, 6), Color("#c9a227"))
			g.fill_rect(Rect2i(r.position.x, r.position.y + 8, r.size.x, 3), Color("#c9a227")); g.fill_rect(Rect2i(r.position.x, r.end.y - 11, r.size.x, 3), Color("#c9a227"))
		_:
			g.fill_rect(r, Color("#5a5e64"))
			for y in range(r.position.y, r.end.y, 16):
				for x in range(r.position.x + ((y / 16) % 2) * 8, r.end.x, 16): g.fill_rect(Rect2i(x, y, 8, 3), Color("#72767c"))
			for x in range(r.position.x, r.end.x, 120): g.fill_rect(Rect2i(x, r.position.y, 2, r.size.y), Color("#3a3e44"))

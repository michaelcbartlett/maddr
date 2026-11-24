extends RefCounted
## Fixed-camera rooms east of the street. Door pairs share one graph for travel and signage.
const STREET_END = preload("res://levels/rainy_street.gd").SIZE.x
const SIZE := Vector2(960, 540)
const ROOMS := {
	"Lobby": Vector2(STREET_END, 0), "Teller hall": Vector2(STREET_END + 960, 0),
	"Deposit boxes": Vector2(STREET_END, 540), "Security": Vector2(STREET_END + 960, 540), "Vault": Vector2(STREET_END + 1920, 0)
}
const LINKS := {
	"Lobby": {"Teller hall": Vector2.RIGHT, "Deposit boxes":Vector2.DOWN},
	"Deposit boxes":{"Lobby":Vector2.UP},
	"Teller hall": {"Lobby": Vector2.LEFT, "Security": Vector2.DOWN, "Vault": Vector2.RIGHT},
	"Security": {"Teller hall": Vector2.UP}, "Vault": {"Teller hall": Vector2.LEFT}
}
const ROSTERS := {
	"Deposit boxes":["cop","det"], "Lobby": ["cop", "cop"], "Teller hall": ["cop", "det", "cop"],
	"Security": ["det", "cop", "cop"], "Vault": ["cop", "det", "cop", "cop"]
}
# The same footprints drive navigation, shots and the visible furniture.
const FITTINGS := {
	"Lobby":[Rect2(355,100,110,38),Rect2(355,400,110,38)],
	"Deposit boxes":[Rect2(245,120,65,220),Rect2(645,200,65,220)],
	"Teller hall":[Rect2(320,80,64,155),Rect2(320,320,64,150),Rect2(566,120,135,47)],
	"Security":[Rect2(220,190,175,52),Rect2(566,303,175,52)],
	"Vault":[Rect2(280,135,64,66),Rect2(280,338,64,66),Rect2(618,135,64,66),Rect2(618,338,64,66)]
}
const SPAWNS := {
	"Lobby":[Vector2(520,188),Vector2(660,365)],
	"Deposit boxes":[Vector2(365,362),Vector2(768,140)],
	"Teller hall":[Vector2(470,200),Vector2(780,145),Vector2(625,380)],
	"Security":[Vector2(790,390),Vector2(435,330),Vector2(615,210)],
	"Vault":[Vector2(415,165),Vector2(760,365),Vector2(540,375),Vector2(758,175)]
}
const FINISHES := {
	"Lobby":Color("#635147"), "Deposit boxes":Color("#485963"),
	"Teller hall":Color("#765041"), "Security":Color("#334c55"), "Vault":Color("#566477")
}
const PEDESTAL := Vector2(480, 265)
var room := ""
var cleared := {}
var keycard := false
var deposit_taken := false
var captain_deployed := false

func door(from: String, to: String) -> Vector2:
	return ROOMS[from] + SIZE / 2 + (LINKS[from][to] as Vector2) * (SIZE / 2 - Vector2(35, 35))

func begin(a) -> void:
	# Keep the street and its loot in world space. The bank uses a camera pinned to each room.
	a.AW = STREET_END + 2880
	a.AH = maxi(a.AH, 1080)
	a.level = "opening_bank"
	for name in ROOMS:
		var origin: Vector2 = ROOMS[name]
		for fitting: Rect2 in FITTINGS[name]:
			a.arena_level.walls.append({"rect":Rect2(origin + fitting.position,fitting.size), "open":false})
		for edge in [Rect2(0, 0, 960, 20), Rect2(0, 520, 960, 20), Rect2(0, 20, 20, 500), Rect2(940, 20, 20, 500)]:
			a.arena_level.walls.append({"rect":Rect2(origin + edge.position, edge.size), "open":false})
	a.walls = a.arena_level.walls
	a.nav.configure(a.walls, Vector2(a.AW, a.AH))
	a.ambient.color = Color("#dbd3c9")
	a.ambient_fx.floor_kind = "marble"
	a.ambient_fx.parts.clear()
	a.arena_level.lamps.clear()
	for origin: Vector2 in ROOMS.values():
		for inset in [Vector2(210, 110), Vector2(750, 410)]: a.arena_level.lamps.append(origin + inset)
	enter(a, "Lobby", Vector2.RIGHT)

func enter(a, next: String, travel: Vector2) -> void:
	room = next
	var origin: Vector2 = ROOMS[room]
	var arrival := origin + SIZE / 2 - travel * (SIZE / 2 - Vector2(95, 95))
	a.P.x = arrival.x
	a.P.y = arrival.y
	a.cam.limit_left = int(origin.x)
	a.cam.limit_top = int(origin.y)
	a.cam.limit_right = int(origin.x + SIZE.x)
	a.cam.limit_bottom = int(origin.y + SIZE.y)
	a.cam.position = origin + SIZE / 2
	a.cam.reset_smoothing()
	a.grapple.reset()
	a.banner_txt = room.to_upper()
	a.banner_t = 1.1
	if cleared.has(room): return
	for i in ROSTERS[room].size():
		var p: Vector2 = origin + SPAWNS[room][i]
		a.markers.append({"type":ROSTERS[room][i], "x":p.x, "y":p.y, "t":0.7 + 0.18 * i})

func update(a) -> void:
	var origin: Vector2 = ROOMS[room]
	var p := Vector2(a.P.x, a.P.y).clamp(origin + Vector2(30, 30), origin + SIZE - Vector2(30, 30))
	a.P.x = p.x
	a.P.y = p.y
	if not cleared.has(room):
		if not a.markers.is_empty() or not a.live_foes().is_empty(): return
		if room == "Vault" and not captain_deployed:
			captain_deployed = true
			var captain = a.make_enemy("det",origin.x + 740,origin.y + 265)
			captain.max_hp *= 4.0
			captain.hp = captain.max_hp
			for flank_y in [105,435]:
				a.markers.append({"type":"cop","x":origin.x + 505,"y":origin.y + flank_y,"t":1.2})
			a.banner_txt = "VAULT CAPTAIN"
			a.banner_t = 1.8
			return
		cleared[room] = true
		a.snd("gotkey")
	if p.distance_to(origin + PEDESTAL) < 37:
		if room == "Security" and not keycard:
			keycard = true
			a.banner_txt = "VAULT KEYCARD"
			a.banner_t = 1.4
			a.snd("key")
		if room == "Deposit boxes" and not deposit_taken:
			deposit_taken = true
			a.gain_scrap(8 * Run.payout_mult())
			a.P.hp = minf(Run.D.maxHp,a.P.hp + 8)
			a.snd("crate")
		if room == "Vault":
			a.gain_scrap(16 * Run.payout_mult())
			a.end_wave()
			return
	for next in LINKS[room]:
		if next == "Vault" and not keycard: continue
		if p.distance_to(door(room, next)) < 34:
			enter(a, next, LINKS[room][next])
			return

func objective() -> String:
	if room == "Vault" and captain_deployed and not cleared.has(room): return "DEFEAT THE VAULT DETAIL"
	if not cleared.has(room): return "CLEAR THE " + room.to_upper()
	match room:
		"Lobby": return "TELLERS EAST  /  DEPOSIT BOXES SOUTH"
		"Deposit boxes": return "LOBBY NORTH" if deposit_taken else "COLLECT THE RESERVE"
		"Teller hall": return "VAULT EAST" if keycard else "SECURITY SOUTH"
		"Security": return "TELLERS NORTH" if keycard else "TAKE THE KEYCARD"
	return "TAKE THE BULLION"

func draw(g: Node2D, font: Font) -> void:
	var origin: Vector2 = ROOMS[room]
	g.draw_set_transform(origin)
	var vault := room == "Vault"
	var tile := Color("#526477") if vault else Color("#877f71")
	g.draw_rect(Rect2(Vector2.ZERO, SIZE), Color("#28323c"))
	for y in range(22, 519, 44):
		for x in range(22, 936, 48):
			g.draw_rect(Rect2(x, y, 47, 43), tile.lightened(0.06 * ((x / 48 + y / 44) % 2)))
	g.draw_rect(Rect2(80, 84, 800, 372), Color("#c8ab74"), false, 4)
	g.draw_rect(Rect2(275, 210, 410, 115), Color("#413950") if vault else Color("#633341"))
	g.draw_rect(Rect2(282, 217, 396, 101), Color("#ac8653"), false, 2)
	for x in [130, 685]:
		for i in 4:
			g.draw_rect(Rect2(x + i * 36, 50, 34, 30), Color("#434952") if vault else Color("#544438"))
			g.draw_rect(Rect2(x + i * 36 + 10, 64, 13, 3), Color("#d0b779"))
	g.draw_string(font, Vector2(170, 169), room.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 620, 24, Color("#3a3436"))
	var finish: Color = FINISHES[room]
	for fitting: Rect2 in FITTINGS[room]:
		g.draw_rect(Rect2(fitting.position + Vector2(5,7),fitting.size), Color(0,0,0,0.25))
		g.draw_rect(fitting,finish.darkened(0.35))
		var top := Rect2(fitting.position - Vector2(0,8), fitting.size)
		g.draw_rect(top,finish)
		g.draw_rect(top.grow(-3),finish.lightened(0.21),false,2)
		match room:
			"Security":
				for x in [24,80,130]:
					g.draw_rect(Rect2(top.position + Vector2(x,8),Vector2(26,15)),Color("#68a99c"))
			"Deposit boxes":
				for y in range(6,int(top.size.y)-18,22):
					g.draw_rect(Rect2(top.position + Vector2(7,y),Vector2(51,18)),Color("#b6aa89"),false,1)
			"Teller hall":
				g.draw_line(top.position + Vector2(8,6),Vector2(top.position.x+8,top.end.y-6),Color("#ccbe91"),3)
	for next in LINKS[room]:
		var at := door(room, next) - origin
		var open: bool = cleared.has(room) and (next != "Vault" or keycard)
		var vertical: bool = LINKS[room][next].x != 0
		var panel := Vector2(50, 90) if vertical else Vector2(110, 45)
		g.draw_rect(Rect2(at - panel / 2, panel), Color("#c9a568"))
		g.draw_rect(Rect2(at - panel / 2 + Vector2(4,4), panel - Vector2(8,8)), Color("#193d37") if open else Color("#514146"))
		g.draw_circle(at, 6, Color("#80ffbc") if open else Color("#ff766d"))
		var label := at.clamp(Vector2(85, 85), SIZE - Vector2(85, 50))
		g.draw_string(font, label + Vector2(-70, 21), next.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color.WHITE)
	if cleared.has(room) and ((room == "Security" and not keycard) or (room == "Deposit boxes" and not deposit_taken) or vault):
		g.draw_arc(PEDESTAL, 26, 0, TAU, 32, Color("#ffdd91"), 2)
		g.draw_rect(Rect2(PEDESTAL - Vector2(16, 10), Vector2(32, 20)), Color.GOLD if vault else Color("#8eead4"))
		g.draw_rect(Rect2(PEDESTAL - Vector2(12, 5), Vector2(24, 4)), Color("#786033") if vault else Color("#305966"))
	g.draw_set_transform(Vector2.ZERO)

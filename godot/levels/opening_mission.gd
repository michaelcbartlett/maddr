extends RefCounted
const Bank = preload("res://levels/opening_bank.gd")
const BLOCKS := 5
const WIDTH := 640
const ENTRY := Vector2(3110, 1028)
const STOREFRONTS := preload("res://art/street/storefronts.png")
const SHOP_FRAMES := [
	Rect2(9, 178, 547, 435), Rect2(575, 178, 500, 435),
	Rect2(1101, 178, 513, 435), Rect2(1631, 178, 537, 435)
]
const SHOP_BASE := 991
# Local positions are measured from the west edge of each 640-unit block.
const STOPS := [
	{"name":"DINER CORNER", "rounds":4, "interval":7.0, "entries":[Vector2(568,1170)], "squad":[2,3]},
	{"name":"DELIVERY LANE", "rounds":7, "interval":9.5, "entries":[Vector2(566,1250),Vector2(58,1040)], "squad":[3,2,3]},
	{"name":"MARKET CROSSING", "rounds":7, "interval":9.0, "entries":[Vector2(555,1030),Vector2(555,1255)], "squad":[2,3,4]},
	{"name":"DISPATCH ALLEY", "rounds":8, "interval":9.5, "entries":[Vector2(552,1250),Vector2(58,1040)], "squad":[3,2,3]},
	{"name":"BANK CORDON", "rounds":8, "interval":10.0, "entries":[Vector2(562,1220),Vector2(58,1235),Vector2(550,1040)], "squad":[2,3,2]}
]
const RADIO_BLOCK := 3
const RADIO := Vector2(RADIO_BLOCK * WIDTH + 480, 1252)
var radio_cut := false

func rounds() -> int:
	var total: int = STOPS[block].rounds
	return total - 2 if block == RADIO_BLOCK and radio_cut else total

# Fixed world positions leave sightlines through the alleys at each intersection.
const SHOP_ROW := [[0, 1], [2, 3], [1, 2], [3, 0], [2, 1]]
var bank := Bank.new()
var block := 0
var patrol := 0
var delay := 0.0
var fighting := false

func update(a, dt: float) -> void:
	if not bank.room.is_empty():
		bank.update(a)
		return
	if block == BLOCKS:
		if Vector2(a.P.x,a.P.y).distance_to(ENTRY) < 45:
			bank.begin(a)
		return
	var west := block * WIDTH
	a.P.x = minf(a.P.x, west + WIDTH - 25)
	if a.P.x < west + 70 and not fighting: return
	if not fighting and block == BLOCKS - 1:
		a.crates.append({"x":west + 96, "y":1160, "v":3, "t":0.0, "got":false})
	fighting = true
	var foes: int = a.live_foes().size() + a.markers.size()
	var stop: Dictionary = STOPS[block]
	if block == RADIO_BLOCK and not radio_cut and Vector2(a.P.x,a.P.y).distance_to(RADIO) < 40:
		radio_cut = true
		a.snd("gotkey")
		a.banner_txt = "DISPATCH OFFLINE"
		a.banner_t = 1.5
	if patrol >= rounds():
		if foes == 0:
			a.crates.append({"x":west + WIDTH - 52, "y":1146, "v":3, "t":0.0, "got":false})
			block += 1
			fighting = false
			patrol = 0
			delay = 0
		return
	delay -= dt
	if delay > 0 or foes > (1 if block == BLOCKS - 1 else 2): return
	if patrol == int(stop.rounds) / 2:
		a.crates.append({"x":west + 58, "y":1150, "v":2, "t":0.0, "got":false})
	var count: int = stop.squad[patrol % stop.squad.size()]
	var entry: Vector2 = stop.entries[patrol % stop.entries.size()]
	for i in count:
		var spawn := Vector2(west + entry.x, entry.y + i * 7)
		if block == 2 and i % 2 == 1: spawn.y = 2285 - spawn.y
		if spawn.distance_to(Vector2(a.P.x,a.P.y)) < 135: spawn.x = west + (64 if entry.x > WIDTH / 2 else 568)
		# Both curbs stay usable as reinforcements even after a car is destroyed.
		if a.in_wall(spawn.x,spawn.y,22): spawn = Vector2(west + 56,1148 + i * 8)
		var detective := i == count - 1 and patrol % 3 == 2
		if block == 2 or block == 4: detective = i == count - 1 and patrol % 2 == 1
		a.markers.append({"x":spawn.x, "y":spawn.y, "t":0.9 + i * 0.38, "type":"det" if detective else "cop"})
	patrol += 1
	delay = stop.interval


func objective() -> String:
	if not bank.room.is_empty(): return bank.objective()
	if block == BLOCKS: return "ENTER THE BANK →"
	if block == RADIO_BLOCK and fighting and not radio_cut: return "OPTIONAL: CUT DISPATCH  ↘"
	return "%s  ·  %d / %d" % [STOPS[block].name, block + 1, BLOCKS] if fighting else "MOVE EAST →"

func bot_target(a, t: float) -> Vector2:
	if not bank.room.is_empty():
		var origin: Vector2 = bank.ROOMS[bank.room]
		if not bank.cleared.has(bank.room):
			return origin + bank.SIZE / 2 + Vector2(cos(t * 1.35) * 180, sin(t * 1.35) * 80)
		match bank.room:
			"Lobby": return bank.door("Lobby", "Teller hall" if bank.deposit_taken else "Deposit boxes")
			"Deposit boxes":
				if bank.deposit_taken: return bank.door("Deposit boxes", "Lobby")
			"Teller hall": return bank.door("Teller hall", "Vault" if bank.keycard else "Security")
			"Security":
				if bank.keycard: return bank.door("Security", "Teller hall")
		return origin + bank.PEDESTAL
	if a.P.hp < Run.D.maxHp - 4:
		for crate in a.crates:
			var supply := Vector2(crate.x,crate.y)
			if supply.distance_to(Vector2(a.P.x,a.P.y)) < 270:
				return supply
	if block == BLOCKS: return ENTRY
	if block == RADIO_BLOCK and fighting and not radio_cut and patrol >= 2: return RADIO
	if fighting:
		if block == BLOCKS - 1:
			return Vector2(block * WIDTH + 250 + 145 * cos(t),1205 + 59 * sin(t))
		return Vector2(block * WIDTH + 275 + 172 * cos(t), 1115 + 86 * sin(t))
	return Vector2(block * WIDTH + 95, 1148)

func draw_street(a, g: Node2D) -> void:
	var width: float = a.get_viewport_rect().size.x / a.cam.zoom.x
	var left: float = maxf(0, a.cam.get_screen_center_position().x - width / 2)
	g.draw_rect(Rect2(left, 790, width, 118), Color("#28344d"))
	for layer in 2:
		var pitch := 63 if layer == 0 else 98
		var scroll := left * (0.22 if layer == 0 else 0.58)
		var start := floori(scroll / pitch)
		for tower in range(start, start + ceili(width / pitch) + 2):
			var key := absi(hash(Vector2i(tower, layer)))
			var x := left + tower * pitch - scroll
			var roof := 841 + key % 29 + layer * 18
			var facade := Color("#68718a") if layer == 0 else Color("#3a465b")
			g.draw_rect(Rect2(x,roof,pitch-4,909-roof), facade)
			g.draw_rect(Rect2(x+9,roof-5,20,5),facade)
			if key % 3 == 0: g.draw_line(Vector2(x+18,roof-5),Vector2(x+18,roof-17),facade,2)
			for row in range(roof + 5, 906, 8):
				for col in range(6,pitch-6,12):
					if (key + col + row) % 5 < 2: g.draw_rect(Rect2(x+col,row,4,2),Color("#c09e82"))
	g.draw_rect(Rect2(left, SHOP_BASE - 6, width, 20), Color("#515763"))
	g.draw_rect(Rect2(left, SHOP_BASE + 14, width, 4), Color("#787b84"))
	for joint in range(floori(left / 60), ceili((left + width) / 60)):
		g.draw_line(Vector2(joint * 60, SHOP_BASE - 6), Vector2(joint * 60 - 5, SHOP_BASE + 14), Color("#454953"), 1)
	for street_block in BLOCKS:
		for bay in 2:
			if street_block == BLOCKS - 1 and bay == 1: continue
			var x := street_block * WIDTH + 38 + bay * 258
			if x > left + width or x + 240 < left: continue
			var region: Rect2 = SHOP_FRAMES[SHOP_ROW[street_block][bay]]
			var shop_size := Vector2(region.size.x * 0.44, 151)
			var bounds := Rect2(Vector2(x, SHOP_BASE - shop_size.y), shop_size)
			g.draw_rect(Rect2(x - 3, SHOP_BASE - 3, shop_size.x + 6, 11), Color("#51535b"))
			g.draw_texture_rect_region(STOREFRONTS, bounds, region)
	# Crosswalk stripes frame the two passages around the market cruiser.
	if left < 1930 and left + width > 1280:
		for curb_y in [1018,1208]:
			for stripe in range(0,74,13):
				g.draw_rect(Rect2(1375,curb_y+stripe,55,6),Color("#74767a"))
				g.draw_rect(Rect2(1776,curb_y+stripe,55,6),Color("#74767a"))
	if left < 1280 and left + width > 640:
		for stripe in range(684,968,24):
			g.draw_line(Vector2(stripe,1104),Vector2(stripe+16,1091),Color("#a39469"),3)
	# Paint the encounter boundaries and walking gaps onto the asphalt.
	for n in BLOCKS:
		var gate := (n + 1) * WIDTH - 25
		if gate < left or gate > left + width: continue
		var ink := Color("#729b89") if n < block else Color("#b59a66")
		for y in range(1018,1298,28):
			g.draw_line(Vector2(gate-6,y+8),Vector2(gate+2,y),ink,3)
	if block == RADIO_BLOCK:
		g.draw_rect(Rect2(RADIO - Vector2(14,33),Vector2(28,35)),Color("#34404c"))
		g.draw_line(RADIO + Vector2(9,-32),RADIO + Vector2(14,-48),Color("#acb5bf"),2)
		g.draw_circle(RADIO + Vector2(-5,-23),4,Color("#75dba0") if radio_cut else Color("#ffb65b"))
		if not radio_cut: g.draw_string(a.font,RADIO+Vector2(-40,-52),"RADIO",HORIZONTAL_ALIGNMENT_CENTER,80,13,Color("#ffd899"))
	for i in range(floori(left * 1.22 / 156), ceili((left * 1.22 + width) / 156)):
		var x := left + i * 156 - left * 1.22
		g.draw_rect(Rect2(x,1323,153,30),Color("#232831"))
		g.draw_rect(Rect2(x+7,1319,42,7),Color("#3b434c"))
	if left + width > 2920:
		_draw_bank_front(a.font,g)

func _draw_bank_front(font: Font, g: Node2D) -> void:
	var x := 2925
	g.draw_rect(Rect2(x,844,275,148),Color("#555d68"))
	for row in 6:
		for column in 5:
			var stone := Rect2(x + 3 + column * 54, 847 + row * 23, 52, 21)
			g.draw_rect(stone,Color("#75767a").lightened(0.035*((row + column) % 3)))
	g.draw_rect(Rect2(x-3,843,278,7),Color("#a29784"))
	g.draw_rect(Rect2(x+9,855,252,25),Color("#263543"))
	g.draw_string(font,Vector2(x+9,874),"MERCANTILE BANK",HORIZONTAL_ALIGNMENT_CENTER,252,17,Color("#ead09c"))
	for window_x in [x+20,x+77]:
		g.draw_rect(Rect2(window_x,890,48,79),Color("#313e4a"))
		for bar in 3: g.draw_rect(Rect2(window_x+7+bar*15,890,3,79),Color("#73777c"))
	var door_x := ENTRY.x-35
	g.draw_rect(Rect2(door_x-6,884,82,108),Color("#ac9b80"))
	g.draw_rect(Rect2(door_x,890,70,99),Color("#223944"))
	g.draw_line(Vector2(ENTRY.x,890),Vector2(ENTRY.x,989),Color("#988b71"),3)
	for offset in [-1,1]: g.draw_rect(Rect2(ENTRY.x+offset*8,943,3,16),Color("#d6bd80"))
	g.draw_rect(Rect2(door_x-9,990,88,9),Color("#93939a"))
	g.draw_rect(Rect2(door_x-18,999,106,9),Color("#747982"))
	g.draw_rect(Rect2(door_x-6,1010,82,22),Color("#704950"))

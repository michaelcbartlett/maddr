extends RefCounted
## Bank Lobby robbery (once per run, on a "bank" theme wave): one random customer carries the vault key. Drop them
## and the key falls out; carry it to the round vault door on the west wall to open the vault. Opening it spills
## cash and Run.claim_bank() unlocks this difficulty's bank reward (once per difficulty, saved) and bolts a free
## copy onto the gun. Customers are locked in during the robbery, so the key holder can't escape at the edges.

const DOOR := Vector2(58, 550)      # centre of the vault door set into the west wall (clear of the HUD)
const DOOR_REACH := 70.0
const KEY_REACH := 26.0
const HINT_RANGE := 130.0           # the key glints above its holder once the villain is this close

var active := false
var holder = null                   # Enemy carrying the key (null until a customer has walked in)
var key_pos = null                  # Vector2 of the dropped key, null when not on the floor
var has_key := false
var opened := false
var reward := ""
var unlocked := false
var message := ""
var message_t := 0.0

func reset(a) -> void:
	active = a.level == "bank" and not Run.bank_cracked
	holder = null; key_pos = null; has_key = false; opened = false
	reward = ""; unlocked = false; message = ""; message_t = 0.0

## Called from Arena._update_play every frame.
func update(a, dt: float) -> void:
	if message_t > 0.0: message_t -= dt
	if not active or opened: return
	for e in a.enemies:
		if e.civ: e.bank = true
	if holder == null and key_pos == null and not has_key:
		var customers: Array = a.enemies.filter(func(e): return e.civ and not e.dead and not e.ally)
		if not customers.is_empty(): holder = customers.pick_random(); holder.has_key = true
	elif holder != null and holder.dead:
		drop_key(a, Vector2(holder.x, holder.y))
	if key_pos != null and Vector2(a.P.x, a.P.y).distance_to(key_pos) < KEY_REACH:
		key_pos = null; has_key = true
		a.banner_txt = "GOT THE KEY! TO THE VAULT"; a.banner_t = 2.0; a.snd("gotkey")
	if has_key and Vector2(a.P.x, a.P.y).distance_to(DOOR) < DOOR_REACH: open(a)

func drop_key(a, at: Vector2) -> void:
	if holder != null: holder.has_key = false
	holder = null; key_pos = at
	a.add_num(at.x, at.y - 40, "🔑 VAULT KEY!", Color("#ffd23c"), true)
	a.banner_txt = "THE KEY! GRAB IT!"; a.banner_t = 1.6; a.snd("gotkey")

func open(a) -> void:
	opened = true; has_key = false
	Run.bank_cracked = true
	var got: Dictionary = Run.claim_bank()
	reward = got.id; unlocked = got.unlocked
	a.villain.set_items()
	# the vault spills its cash into the lobby
	for i in 36:
		var angle := randf_range(-PI / 2.0 + 0.15, PI / 2.0 - 0.15)
		var speed := randf_range(120.0, 320.0)
		a.pickups.append({"x": DOOR.x + 40, "y": DOOR.y, "v": 3.0 * Run.payout_mult(), "vx": cos(angle) * speed, "vy": sin(angle) * speed, "cash": 1})
	var item_name: String = Run.ITEM[reward].name.to_upper() if Run.ITEM.has(reward) else "LOOT"
	a.banner_txt = "VAULT OPEN!"; a.banner_t = 2.4
	message = ("🔓 %s UNLOCKED · INSTALLED" if unlocked else "%s INSTALLED") % item_name
	message_t = 4.0
	a.snd("vault"); a.shake = 10.0
	Controls.rumble(0.6, 1.0, 400)

## HUD objective line.
func objective() -> String:
	if message_t > 0.0 or opened: return message
	if has_key: return "🔑 TAKE THE KEY TO THE VAULT DOOR"
	if key_pos != null: return "🔑 GRAB THE VAULT KEY!"
	return "🔑 BANK ROBBERY · ONE OF THE CUSTOMERS HAS THE VAULT KEY"

## Vault door on the north wall (ground layer) plus the key / holder glint (top layer).
func draw_door(a, g: Node2D) -> void:
	if not active and not opened: return
	var c := DOOR
	g.draw_rect(Rect2(c.x - 48, c.y - 74, 82, 148), Color("#2c2f36"))
	g.draw_rect(Rect2(c.x - 48, c.y - 74, 82, 148), Color("#c9a227"), false, 3)
	if opened:
		g.draw_circle(c, 34, Color("#120f08"))
		for i in 6: g.draw_rect(Rect2(c.x - 6 + (i % 2) * 6, c.y - 26 + i * 9, 5, 8), Color("#e8b820"))
		g.draw_circle(c + Vector2(30, 58), 30, Color("#7d8590")); g.draw_arc(c + Vector2(30, 58), 30, 0, TAU, 32, Color("#c9a227"), 3)
		return
	g.draw_circle(c, 34, Color("#7d8590"))
	g.draw_arc(c, 34, 0, TAU, 40, Color("#c9a227"), 3)
	g.draw_arc(c, 24, 0, TAU, 32, Color("#4c535c"), 2)
	for i in 4:
		var d := Vector2.from_angle(i * PI / 2.0 + 0.4)
		g.draw_line(c + d * 6, c + d * 20, Color("#d6dbe0"), 3)
	g.draw_circle(c, 6, Color("#c9a227"))
	var lit := Color("#7dff3a") if has_key and sin(a.time * 8.0) > 0.0 else Color("#ff3030")
	g.draw_rect(Rect2(c.x - 4, c.y - 62, 7, 7), lit)

func draw_top(a, g: Node2D) -> void:
	if not active or opened: return
	var font: Font = a.font
	if key_pos != null:
		var p: Vector2 = key_pos + Vector2(0, -8 - sin(a.time * 4.0) * 3.0)
		g.draw_circle(key_pos, 20, Color(1.0, 0.82, 0.2, 0.18))
		g.draw_arc(key_pos, 18, a.time, a.time + TAU * 0.8, 24, Color("#ffd23c"), 2)
		g.draw_string(font, p + Vector2(-10, 8), "🔑", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	elif holder != null and not holder.dead and Vector2(a.P.x, a.P.y).distance_to(Vector2(holder.x, holder.y)) < HINT_RANGE:
		if sin(a.time * 5.0) > -0.2:
			g.draw_string(font, Vector2(holder.x - 7, holder.y - holder.r - 22), "🔑", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)

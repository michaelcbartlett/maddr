extends Control
## In-game HUD (index.html drawHUD + drawObjective). Drawn in the 960x540 UI space.

var A: Arena
var font: Font
var _last_hp := -1.0
var _hurt := 0.0     # seconds left on the red hit flash
var _last_t := 0.0

func _ready() -> void:
	font = UiKit.mono(); mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	# Main owns visibility, including title, shop, pause and ending screens.
	if visible: queue_redraw()

func _txt(p: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, shadow := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := p.x - (w / 2 if align == HORIZONTAL_ALIGNMENT_CENTER else (w if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	if shadow: draw_string(font, Vector2(x + 2, p.y + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw() -> void:
	if A == null: return
	if A.sandbox():
		var id: String = Run.selected_consumable
		var text := "X / Q: %s ×%d   D-UP / E: switch    B / SHIFT: dash, hold to sprint    1-4 / D-PAD: reactions    5 / BACK: time of day    LT / RMB: push    6 cop  7 detective  8 start waves" % [Run.CONSUMABLE_NAMES[id],Run.consumable_charges[id]]
		_txt(Vector2(16,size.y-14),text,11,Color("#b8cad9"))
		if A.P.size_t>0.0:
			_txt(Vector2(16,size.y-32),"%s · %.1fs" % [Run.CONSUMABLE_NAMES[A.P.size_effect],A.P.size_t],12,Color("#c8abff"))
		elif not A.consumables.coils.is_empty():
			_txt(Vector2(16,size.y-32),"Tesla coils · %d"%A.consumables.coils.size(),12,Color("#8beaff"))
		return
	var W := size.x; var H := size.y; var pad := 14.0
	var P := A.P; var D := Run.D
	var f := maxf(0.0, P.hp / D.maxHp)
	_danger(W, H, f)
	_threats(W, H)
	# HP
	draw_rect(Rect2(pad - 3, pad - 3, 226, 26), Color("#0a0f0f")); draw_rect(Rect2(pad, pad, 220, 20), Color("#401818"))
	var hp_col := Color("#e23a3a")
	if f < LOW_HP and A.state == "play": hp_col = hp_col.lerp(Color("#ffb0a0"), 0.5 + 0.5 * sin(A.time * 9.0))
	draw_rect(Rect2(pad, pad, 220 * f, 20), hp_col); draw_rect(Rect2(pad, pad, 220 * f, 4), Color(1, 1, 1, 0.2))
	_txt(Vector2(pad + 8, pad + 15), "%d / %d" % [ceili(P.hp), D.maxHp], 13, Color.WHITE)
	# scrap
	var sp := Vector2(pad + 8, pad + 40)
	draw_rect(Rect2(sp.x - 1, sp.y - 9, 18, 18), Color("#6a5a10")); draw_rect(Rect2(sp.x, sp.y - 8, 16, 16), UiKit.GOLD); draw_rect(Rect2(sp.x + 4, sp.y - 4, 8, 8), Color("#8a7a20"))
	_txt(Vector2(pad + 30, pad + 47), str(Run.scrap), 18, UiKit.GOLD)
	if A.mines.size() > 0: _txt(Vector2(pad, pad + 72), "📡 %d/8" % A.mines.size(), 12, Color("#ff6040"))
	var arm_text = "BIONIC FIST" if Run.CNT.get("bionic_arm",0)>0 else ""
	var arm_color = Color("#7defff")
	if Run.build.off!=null:
		var kind: String = Run.arm_off().get("kind","gun")
		if kind=="gun": arm_text = "REAR GUN"
		else:
			var melee := not Run.melee_spec().is_empty()
			var cooldown: float = A.P.melee_cd if melee else float(Run.arm_cooldowns.get(kind,0.0))
			arm_text = Run.arm_name(kind).to_upper()+ (" · READY" if cooldown<=0 else " · %.1fs" % cooldown)
			arm_color = Color("#78dbff") if kind=="time_freeze" else (Color(A.MELEE_COLORS[kind]) if melee else Color("#ff9670"))
	_txt(Vector2(pad,pad+92),arm_text,11,arm_color)
	var id: String = Run.selected_consumable
	var text := "X / Q  %s ×%d" % [Run.CONSUMABLE_NAMES[id].to_upper(),Run.consumable_charges[id]]
	if Run.consumable_charges.values().all(func(n): return n == 0): text = ""
	if A.consumables.pads.size() == 1: text = "Y / F  PLACE SECOND PAD"
	elif P.disguise_t > 0.0: text = "DISGUISED · %.1fs" % P.disguise_t
	if text != "": _txt(Vector2(pad,pad+110),text,11,Color("#a4e8c4"))
	if P.size_t>0.0: _txt(Vector2(pad+220,pad+110),"%s · %.1fs"%[Run.CONSUMABLE_NAMES[P.size_effect],P.size_t],11,Color("#c8abff"))
	if A.consumables.pads.size() == 2: _txt(Vector2(pad,pad+126),"STEP ON A PAD · ONE TRIP",10,Color("#bf9aff"))
	else:
		var carried := 0
		for key in Run.CONSUMABLE_IDS:
			if Run.consumable_charges[key] > 0: carried += 1
		if carried > 1: _txt(Vector2(pad,pad+126),"D-UP / E  SWITCH",10,Color("#a8bcb2"))
	var action := Run.equipped_action()
	if action != "":
		_txt(Vector2(pad,pad+144),"Y / F  " + Run.ITEM[action].name.to_upper() + (" · READY" if A.action_cooldown <= 0.0 else " · %.1fs" % A.action_cooldown),11,Color("#ffb2d8"))
	# wave / timer
	if A.opening_mission:
		_txt(Vector2(W / 2, pad + 10), "MERCANTILE DISTRICT", 14, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
		_txt(Vector2(W / 2, pad + 38), A.opening_mission.objective(), 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_txt(Vector2(W / 2, pad + 10), "WAVE %d / %d" % [Run.wave, int((A.WORLD_WAVES if A.studio_waves else int(Run.RULES.waves.last)))], 14, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
		_txt(Vector2(W / 2, pad + 42), str(ceili(A.wave_t)), 32, BAD_if(A.wave_t <= 5 and A.state == "play"), HORIZONTAL_ALIGNMENT_CENTER)
	var b := A.boss
	if b != null and not b.dead:
		var bw := minf(420.0, W * 0.5)
		draw_rect(Rect2(W / 2 - bw / 2 - 3, pad + 52, bw + 6, 18), Color("#0a0f0f")); draw_rect(Rect2(W / 2 - bw / 2, pad + 55, bw, 12), Color("#401818"))
		draw_rect(Rect2(W / 2 - bw / 2, pad + 55, bw * maxf(0, b.hp / b.max_hp), 12), UiKit.GOLD)
		_txt(Vector2(W / 2, pad + 84), b.hero_name, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if A.heist.active: _draw_heist(W, pad)
	if A.bank_vault.active or A.bank_vault.message_t > 0.0:
		var bv = A.bank_vault
		_txt(Vector2(W / 2, pad + 98), bv.objective(), 12, UiKit.GOLD if bv.opened else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if not bv.opened and Run.ITEM.has(Run.bank_reward()):
			_txt(Vector2(W / 2, pad + 113), "VAULT REWARD: " + Run.ITEM[Run.bank_reward()].name.to_upper(), 10, Color(1, 0.86, 0.4, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	# Capacitor charge
	if Run.CNT.get("capacitor",0)>0 and Run.has_laser():
		var charge := maxf(A.laser_charge_display(),A.laser_charge_display(true))
		var col := Color("#ffe7a0") if charge>=0.999 else Color("#bd9f70")
		_txt(Vector2(pad,H-pad-24),"CAPACITOR %d%% · ×%.2f" % [roundi(charge*100),1.0+A.CAPACITOR_BONUS*charge],10,col)
		draw_rect(Rect2(pad,H-pad-19,110,3),Color("#3d342b"))
		draw_rect(Rect2(pad,H-pad-19,110*charge,3),col)
	if A.banner_t > 0:
		var al := minf(1.0, A.banner_t * 2)
		_txt(Vector2(W / 2, H * 0.32), A.banner_txt, 38, Color(UiKit.NEON, al), HORIZONTAL_ALIGNMENT_CENTER)

## Train heist: one segment per car, filled up to the villain; the vault is the gold block at the end.
func _draw_heist(W: float, pad: float) -> void:
	var h = A.heist; var n: int = h.car_count()
	var bw := minf(440.0, W * 0.5); var x0 := W / 2 - bw / 2; var y := pad + 56
	var seg := (bw - (n - 1) * 3.0) / n
	var prog: float = 1.0 if h.won else h.progress(A.P.x)
	draw_rect(Rect2(x0 - 3, y - 3, bw + 6, 16), Color("#0a0f0f"))
	for i in n:
		var sx := x0 + i * (seg + 3.0)
		var last := i == n - 1
		draw_rect(Rect2(sx, y, seg, 10), Color("#4a3a10") if last else Color("#2a2420"))
		var fill := clampf(prog * n - i, 0.0, 1.0)
		if fill > 0.0: draw_rect(Rect2(sx, y, seg * fill, 10), UiKit.GOLD if last else Color("#c8603a"))
	var px := x0 + bw * prog
	draw_rect(Rect2(px - 2, y - 4, 4, 18), Color.WHITE)
	_txt(Vector2(x0 + bw + 8, y + 10), "VAULT", 10, UiKit.GOLD)
	var text := ""
	if h.message_t > 0.0 or h.won or h.failed: text = h.message
	else:
		var car: int = h.car_at(A.P.x)
		text = "TRAIN HEIST · %s (%d/%d) · REACH THE VAULT BEFORE TIME RUNS OUT" % [h.car_name(car), car + 1, n]
	_txt(Vector2(W / 2, y + 30), text, 12, UiKit.GOLD if h.won else (UiKit.BAD if h.failed else Color.WHITE), HORIZONTAL_ALIGNMENT_CENTER)
	if not h.won and not h.failed:
		_txt(Vector2(W / 2, y + 46), "REWARD: " + Run.ITEM[Run.heist_reward()].name.to_upper() if Run.ITEM.has(Run.heist_reward()) else "", 10, Color(1, 0.86, 0.4, 0.8), HORIZONTAL_ALIGNMENT_CENTER)

func BAD_if(c: bool) -> Color: return UiKit.BAD if c else Color.WHITE

const LOW_HP := 0.3

## Red screen-edge flash on every hit, and a slow pulse while health is low.
func _danger(W: float, H: float, f: float) -> void:
	var dt := clampf(A.time - _last_t, 0.0, 0.1); _last_t = A.time
	if _last_hp >= 0.0 and A.P.hp < _last_hp - 0.01: _hurt = 0.35
	_last_hp = A.P.hp
	_hurt = maxf(0.0, _hurt - dt)
	if A.state != "play": return
	var a := _hurt / 0.35 * 0.55
	if f < LOW_HP: a = maxf(a, (0.16 + 0.12 * sin(A.time * 5.0)) * (1.0 - f / LOW_HP * 0.5))
	if a <= 0.01: return
	for k in 6:   # soft border: stacked bands fading inward
		var t := 6.0 + k * 7.0; var c := Color(0.9, 0.06, 0.06, a * (1.0 - k / 6.0) * 0.45)
		draw_rect(Rect2(0, 0, W, t), c); draw_rect(Rect2(0, H - t, W, t), c)
		draw_rect(Rect2(0, t, t, H - t * 2), c); draw_rect(Rect2(W - t, t, t, H - t * 2), c)

## Edge arrows toward off-screen threats: the boss, vehicles, and anything winding up an attack.
func _threats(W: float, H: float) -> void:
	if A.state != "play" or A.cam == null: return
	var center: Vector2 = A.cam.get_screen_center_position()
	var half: Vector2 = get_viewport_rect().size / A.cam.zoom / 2.0
	var view := Rect2(center - half, half * 2.0)
	for e in A.enemies:
		if e.dead or e.ally or e.civ: continue
		var telegraph: bool = e.action_phase in ["windup", "swing"] or (e.hero == "ironclad" and (e.charge_t < 0.0 or e.slam != null)) or e.laser != null
		if not (e.boss or e.vehicle or telegraph): continue
		var w := Vector2(e.x, e.y)
		if view.grow(-8.0).has_point(w): continue
		var s := (w - view.position) / view.size * Vector2(W, H)
		var c := Vector2(W, H) / 2.0
		var dir := (s - c).normalized()
		# clamp to a margin inside the screen edge along the direction from the centre
		var m := Vector2(W / 2.0 - 22.0, H / 2.0 - 22.0)
		var k := minf(m.x / maxf(0.001, absf(dir.x)), m.y / maxf(0.001, absf(dir.y)))
		var p := c + dir * k
		var col := UiKit.GOLD if e.boss else Color("#ff7a3a")
		if telegraph: col = col.lerp(Color.WHITE, 0.2 + 0.2 * sin(A.time * 18.0))   # flicker, but keep the colour
		var size := 14.0 if e.boss else 10.0
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([p + dir * size, p - dir * size * 0.6 + side * size * 0.8, p - dir * size * 0.6 - side * size * 0.8]), Color(0, 0, 0, 0.6))
		draw_colored_polygon(PackedVector2Array([p + dir * (size - 2.0), p - dir * (size - 2.0) * 0.6 + side * (size - 2.0) * 0.8, p - dir * (size - 2.0) * 0.6 - side * (size - 2.0) * 0.8]), col)

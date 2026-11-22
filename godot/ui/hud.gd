extends Control
## In-game HUD (index.html drawHUD + drawObjective). Drawn in the 960x540 UI space.

var A: Arena
var font: Font

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
	var W := size.x; var H := size.y; var pad := 14.0
	var P := A.P; var D := Run.D
	# HP
	draw_rect(Rect2(pad - 3, pad - 3, 226, 26), Color("#0a0f0f")); draw_rect(Rect2(pad, pad, 220, 20), Color("#401818"))
	var f := maxf(0.0, P.hp / D.maxHp)
	draw_rect(Rect2(pad, pad, 220 * f, 20), Color("#e23a3a")); draw_rect(Rect2(pad, pad, 220 * f, 4), Color(1, 1, 1, 0.2))
	_txt(Vector2(pad + 8, pad + 15), "%d / %d" % [ceili(P.hp), D.maxHp], 13, Color.WHITE)
	# scrap
	var sp := Vector2(pad + 8, pad + 40)
	draw_rect(Rect2(sp.x - 1, sp.y - 9, 18, 18), Color("#6a5a10")); draw_rect(Rect2(sp.x, sp.y - 8, 16, 16), UiKit.GOLD); draw_rect(Rect2(sp.x + 4, sp.y - 4, 8, 8), Color("#8a7a20"))
	_txt(Vector2(pad + 30, pad + 47), str(Run.scrap), 18, UiKit.GOLD)
	if A.mines.size() > 0: _txt(Vector2(pad, pad + 72), "📡 %d/8" % A.mines.size(), 12, Color("#ff6040"))
	var arm_text = "BIONIC FIST" if Run.CNT.get("bionic_arm",0)>0 else ""
	var arm_color = Color("#7defff")
	if Run.build.off!=null:
		var kind: String = Run.build.off.get("kind","gun")
		if kind=="gun": arm_text = "REAR GUN"
		else:
			var cooldown: float = Run.arm_cooldowns[kind]
			arm_text = Run.arm_name(kind).to_upper()+ (" · READY" if cooldown<=0 else " · %.1fs" % cooldown)
			arm_color = Color("#78dbff") if kind=="time_freeze" else Color("#ff9670")
	_txt(Vector2(pad,pad+92),arm_text,11,arm_color)
	var id: String = Run.selected_consumable
	var text := "Y / Q  %s ×%d" % [Run.CONSUMABLE_NAMES[id].to_upper(),Run.consumable_charges[id]]
	if Run.consumable_charges.values().all(func(n): return n == 0): text = "Y / Q  NO CONSUMABLES"
	if A.consumables.pads.size() == 1: text = "Y / Q  PLACE SECOND PAD"
	elif P.disguise_t > 0.0: text = "DISGUISED · %.1fs" % P.disguise_t
	_txt(Vector2(pad,pad+110),text,11,Color("#a4e8c4"))
	if A.consumables.pads.size() == 2: _txt(Vector2(pad,pad+126),"ENTER A PAD · ONE TRIP",10,Color("#bf9aff"))
	else:
		var carried := 0
		for key in Run.CONSUMABLE_IDS:
			if Run.consumable_charges[key] > 0: carried += 1
		if carried > 1: _txt(Vector2(pad,pad+126),"D-UP / E  SWITCH",10,Color("#a8bcb2"))
	var action := Run.equipped_action()
	if action != "":
		_txt(Vector2(pad,pad+144),"B / SHIFT  " + Run.ITEM[action].name.to_upper() + (" · READY" if A.action_cooldown <= 0.0 else " · %.1fs" % A.action_cooldown),11,Color("#ffb2d8"))
	# wave / timer
	_txt(Vector2(W / 2, pad + 10), "WAVE %d / %d" % [Run.wave, int(Run.RULES.waves.last)], 14, UiKit.NEON, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(W / 2, pad + 42), str(ceili(A.wave_t)), 32, BAD_if(A.wave_t <= 5 and A.state == "play"), HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(W - pad, pad + 10), A.arena_level.theme.name, 11, Color(0.86, 0.9, 0.86, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	_txt(Vector2(W - pad, pad + 24), "★".repeat(Run.difficulty) + " " + Run.difficulty_name(), 11, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var b := A.boss
	if b != null and not b.dead:
		var bw := minf(420.0, W * 0.5)
		draw_rect(Rect2(W / 2 - bw / 2 - 3, pad + 52, bw + 6, 18), Color("#0a0f0f")); draw_rect(Rect2(W / 2 - bw / 2, pad + 55, bw, 12), Color("#401818"))
		draw_rect(Rect2(W / 2 - bw / 2, pad + 55, bw * maxf(0, b.hp / b.max_hp), 12), UiKit.GOLD)
		_txt(Vector2(W / 2, pad + 84), b.hero_name, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# weapon name / kills
	_txt(Vector2(pad, H - pad), Run.display_name(), 12, Color(0.7, 1, 0.24, 0.7))
	_txt(Vector2(W - pad, H - pad), "kills %d   %s M   START / ESC pause" % [Run.kills, "🔇" if Controls.muted else "🔊"], 12, Color(0.86, 0.9, 0.86, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	if A.banner_t > 0:
		var al := minf(1.0, A.banner_t * 2)
		_txt(Vector2(W / 2, H * 0.32), A.banner_txt, 38, Color(UiKit.NEON, al), HORIZONTAL_ALIGNMENT_CENTER)

func BAD_if(c: bool) -> Color: return UiKit.BAD if c else Color.WHITE

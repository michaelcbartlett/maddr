extends Node
## Game flow: title -> design -> difficulty -> waves (one arena) <-> shop -> game over / win at wave 20.
## Pause on Start / Esc.
## Port of index.html FLOW (show/newRun/startWave/openShop/gameOver).
## Test hooks (after `--`): --autoplay N  plays N seconds with a scripted pad-less bot and quits;
##                           --shot file.png  saves a screenshot at the end;  --wave W  start at wave W
##                           (add --heist to make it the train heist).

var state := "title"
var arena: Arena
var ui: CanvasLayer
var fit: Control
var hud: Control
var title_s: Control
var design_s: Control
var shop_s: Control
var difficulty_s: Control
var pause_s: Control
var over_s: Control
var over_title: Label
var over_text: Label
var level_music: AudioStreamPlayer
var character_studio := false

# test hooks
var _auto := -1.0
var _shot := ""
var _t := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Character art is the current default work surface. Combat scripts explicitly
	# exercise the preserved game; --character-studio lets its own test use startup.
	character_studio = bool(ProjectSettings.get_setting("art/character_studio",true)) and not args.has("--combat")
	if OS.get_cmdline_args().has("--script") and not args.has("--character-studio"): character_studio = false
	get_window().title = "The Diabolical Doctor"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Temporary run track; continues through shops and pauses with the game.
	level_music = AudioStreamPlayer.new()
	level_music.stream = preload("res://audio/doctor_diabolical_scratch.mp3").duplicate()
	level_music.stream.loop = true
	level_music.volume_db = -14.0
	level_music.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level_music)
	arena = Arena.new(); arena.character_studio = character_studio
	arena.studio_outdoors = not args.has("--blank-studio")
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE; add_child(arena)
	arena.cleared.connect(_on_cleared); arena.died.connect(func(): _game_over(false))
	arena.visible = false
	ui = CanvasLayer.new(); ui.layer = 10; add_child(ui)
	fit = Control.new(); fit.theme = UiKit.theme(); fit.size = UiKit.DESIGN; fit.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(fit)
	get_viewport().size_changed.connect(_fit); _fit()
	hud = preload("res://ui/hud.gd").new(); hud.A = arena; fit.add_child(hud)
	_build_title(); _build_pause(); _build_over()
	design_s = preload("res://ui/design_screen.gd").new(); design_s.begin.connect(_open_difficulty); fit.add_child(design_s)
	shop_s = preload("res://ui/shop_screen.gd").new(); shop_s.next_wave.connect(_start_wave); fit.add_child(shop_s)
	difficulty_s = preload("res://ui/difficulty_screen.gd").new(); fit.add_child(difficulty_s); difficulty_s.chosen.connect(func(_l): _start_wave())
	var i := args.find("--autoplay"); if i >= 0: _auto = float(args[i + 1])
	i = args.find("--shot"); if i >= 0: _shot = args[i + 1]
	_show("title")
	# Opening company logo (ui/splash.gd) over a hidden title screen; never in test runs or capture hooks.
	if not character_studio and not Run.is_test_process() and _shot == "":
		title_s.visible = false; state = "splash"
		var splash: Control = preload("res://ui/splash.gd").new(); fit.add_child(splash)
		splash.finished.connect(func(): _show("title"))
	i = args.find("--wave")
	if i >= 0:
		Run.new_run(); Run.wave = int(args[i + 1])
		if args.has("--heist"): Run.heist_wave = Run.wave   # play this wave as the train heist
		var j := args.find("--items")
		if j >= 0:
			for id in (args[j + 1] as String).split(","): Run.build.items.append(id)
			if Run.build.items.has("offhand"): Run.build.off = {"ammo": 1, "frame": 0, "items": []}
		# --ammo / --frame take an index or an id (e.g. --ammo hook --frame rifle)
		var k := args.find("--ammo"); if k >= 0: Run.build.ammo = _part_index(Run.AMMO, args[k + 1])
		k = args.find("--frame"); if k >= 0: Run.build.frame = _part_index(Run.FRAMES, args[k + 1])
		Run._rebuild_off()
		Run.recompute()
		_start_wave()
	elif character_studio:
		Run.new_run(); _start_wave()

func _part_index(table: Array, value: String) -> int:
	if value.is_valid_int(): return clampi(int(value), 0, table.size() - 1)
	var i := table.find_custom(func(d): return d.id == value)
	if i < 0: push_warning("unknown part: " + value)
	return maxi(i, 0)

func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := minf(vs.x / UiKit.DESIGN.x, vs.y / UiKit.DESIGN.y)
	fit.scale = Vector2(s, s); fit.size = vs / s

func is_playing() -> bool: return state == "play"

# =============== SCREENS ===============
func _build_title() -> void:
	var s := UiKit.screen(700); title_s = s[0]; fit.add_child(title_s); var vb: VBoxContainer = s[1]
	var pv := VillainPreview.new(3.0, Vector2(0, 220)); pv.aim_base = -0.25; vb.add_child(pv)
	vb.add_child(UiKit.title("THE DIABOLICAL DOCTOR", 44))
	var b := UiKit.button("Enter the Lab", _enter_lab); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; vb.add_child(b)
	title_s.set_meta("focus", b)

func _build_pause() -> void:
	var s := UiKit.screen(420); pause_s = s[0]; fit.add_child(pause_s); var vb: VBoxContainer = s[1]
	vb.add_child(UiKit.title("PAUSED", 40))
	vb.add_child(UiKit.label("Even villains need a coffee break.", 13, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var controls := UiKit.label("", 12, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER); vb.add_child(controls); pause_s.set_meta("controls", controls)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 12); vb.add_child(row)
	var r := UiKit.button("Resume", _resume); row.add_child(r)
	if character_studio: row.add_child(UiKit.button("Weapon Lab",_enter_lab))
	else: row.add_child(UiKit.button("Give Up", func(): _game_over(false), true))
	if character_studio:
		for id in ["shrink_pill","enlarge_pill","tesla_coil"]:
			vb.add_child(UiKit.button("Test "+Run.CONSUMABLE_NAMES[id],_studio_supply.bind(id)))
	pause_s.set_meta("focus", r)

func _build_over() -> void:
	var s := UiKit.screen(600); over_s = s[0]; fit.add_child(over_s); var vb: VBoxContainer = s[1]
	over_title = UiKit.title("BUSTED!", 44, UiKit.BAD); vb.add_child(over_title)
	over_text = UiKit.label("", 16, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER); vb.add_child(over_text)
	var b := UiKit.button("Back to the Lab", _enter_lab); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; vb.add_child(b)
	over_s.set_meta("focus", b)

func _show(st: String) -> void:
	state = st
	title_s.visible = st == "title"; design_s.visible = st == "design"; shop_s.visible = st == "shop"
	difficulty_s.visible = st == "difficulty"
	pause_s.visible = st == "paused"; over_s.visible = st == "over"
	hud.visible = not character_studio and (st == "play" or st == "paused")
	arena.visible = st in ["play", "paused"]
	arena.fx_layer.visible = arena.visible
	get_tree().paused = st == "paused"
	if st in ["play", "shop"] and not character_studio:
		if not level_music.playing: level_music.play()
	elif st != "paused":
		level_music.stop()
	if st == "paused":
		var controls: Label = pause_s.get_meta("controls")
		controls.text = "L / R sticks · Move / Aim\nRT · Fire    LT · Push / Arm\nB · Dash (hold to sprint)\nX · Consumable    Y · Ability\nLB / RB · Detonate\nStart · Resume" if Controls.aim_src == "pad" else "WASD · Move    Mouse · Aim\nLMB · Fire    RMB · Push / Arm\nShift · Dash (hold to sprint)\nQ · Consumable    F · Ability\nSpace · Detonate    M · Mute\nEsc · Resume"
		if Run.has_primary_melee():
			controls.text = "L stick · Move    R stick · Swing\nLT · Rear gun (if equipped)\nSecondary melee swings automatically\nA · Highlighted button    Start · Resume" if Controls.aim_src == "pad" else "WASD · Move    Sweep mouse · Swing\nRMB · Rear gun (if equipped)\nSecondary melee swings automatically\nEsc · Resume"
	match st:
		"title": (title_s.get_meta("focus") as Control).grab_focus()
		"paused": (pause_s.get_meta("focus") as Control).grab_focus()
		"over": (over_s.get_meta("focus") as Control).grab_focus()
		"design": design_s.call_deferred("focus_default")
		"shop": shop_s.call_deferred("focus_default")
		"difficulty": difficulty_s.call_deferred("focus_default")
		"play": var f := get_viewport().gui_get_focus_owner(); if f: f.release_focus()

# =============== FLOW ===============
func _enter_lab() -> void:
	Run.new_run(); design_s.refresh(); _show("design")

## After designing the weapon: pick the run's difficulty.
func _open_difficulty() -> void:
	if character_studio: _start_wave(); return
	difficulty_s.refresh(); _show("difficulty")

func _start_wave() -> void:
	if not character_studio: Run.note_wave_reached(Run.wave)   # meta unlocks: "reach wave N"
	arena.start_wave(); _show("play")

func _on_cleared() -> void:
	if Run.wave >= int(Run.RULES.waves.last): _game_over(true); return
	Run.open_shop_for_next_wave(); shop_s.refresh(); _show("shop")

func _resume() -> void: _show("play")

func _studio_supply(id: String) -> void:
	Run.consumable_charges[id] = 3; Run.selected_consumable = id
	arena.consumables.use_cd = 0.0; arena.consumables.activate(arena)
	_resume()

func _game_over(win: bool) -> void:
	arena.state = "over"
	over_title.text = "CITY CONQUERED!" if win else ["BUSTED!","FOILED AGAIN!","CURSES!","MEDDLING COPPERS!"].pick_random()
	over_title.add_theme_color_override("font_color", UiKit.NEON if win else UiKit.BAD)
	if win: over_text.text = "You survived all 20 waves on %s.\nThe city is yours.\n%d cops defeated · %d scrap looted" % [Run.difficulty_name(), Run.kills, Run.total_scrap]
	else: over_text.text = "Arrested on wave %d (%s).\n%d cops defeated · %d scrap looted · %d modules" % [Run.wave, Run.difficulty_name(), Run.kills, Run.total_scrap, Run.build.items.size()]
	over_text.text += "\n" + Run.display_name()
	if not win and Run.unlocks.best_wave > 0: over_text.text += "  ·  furthest: wave %d" % Run.unlocks.best_wave
	if not Run.unlocks.fresh.is_empty():
		over_text.text += "\n\n🔓 %s" % ", ".join(Run.unlocks.fresh.map(Run.part_name))
	if Run.unlocks.fresh_difficulty > 0:
		over_text.text += "\n\n🔓 " + Run.difficulty_name(Run.unlocks.fresh_difficulty)
	Sfx.play("win" if win else "lose")
	_show("over")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("menu_back") and state in ["design","difficulty"]:
		_show("design" if state == "difficulty" else "title")
		Sfx.play("ui"); get_viewport().set_input_as_handled(); return
	if e.is_action_pressed("pause"):
		if state == "play": _show("paused"); get_viewport().set_input_as_handled()
		elif state == "paused": _resume(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and _auto < 0: _show("paused")

# =============== TEST HOOKS ===============
func _process(dt: float) -> void:
	if character_studio and state == "play":
		hud.visible = arena.P.size_t>0.0 or not arena.consumables.coils.is_empty() or Run.consumable_charges.values().any(func(n): return n>0)
	if _auto < 0: return
	_t += dt
	if state == "title": _enter_lab()
	elif state == "design" and _t > 0.5: _open_difficulty()
	elif state == "difficulty": difficulty_s.first_button.pressed.emit()
	elif state == "shop":
		for i in Run.offers.size(): Run.buy(i)
		_start_wave()
	elif state == "over" and _t < _auto - 0.5: _enter_lab()
	if state == "play": _bot(dt)
	if _t >= _auto: _finish()

func _bot(_dt: float) -> void:
	# a dumb bot: circle the arena centre, aim at the nearest cop, hold fire (via the input actions)
	var P := arena.P
	var c: Vector2 = arena.arena_level.spawn + Vector2(cos(_t * 0.7), sin(_t * 0.7)) * 220
	var mv := (c - Vector2(P.x, P.y)).limit_length(60) / 60.0
	_axis("move_right", maxf(0, mv.x)); _axis("move_left", maxf(0, -mv.x)); _axis("move_down", maxf(0, mv.y)); _axis("move_up", maxf(0, -mv.y))
	var e := arena.nearest_foe(P.x, P.y)
	if e: P.aim = atan2(e.y - P.y, e.x - P.x)
	Controls.aim_src = "pad"
	if e: Input.action_press("fire")
	else: Input.action_release("fire")
	if Run.build.off != null: Input.action_press("fire_off")
	if arena.mines.size() > 3: Input.action_press("detonate")
	else: Input.action_release("detonate")

func _axis(a: String, v: float) -> void:
	if v > 0.05: Input.action_press(a, v)
	else: Input.action_release(a)

func _finish() -> void:
	_auto = -1
	print("AUTOPLAY done: state=%s wave=%d kills=%d scrap=%d hp=%.1f enemies=%d lights=%d" % [state, Run.wave, Run.kills, Run.scrap, arena.P.hp, arena.enemies.size(), arena.lights.count()])
	if _shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		print("shot saved: ", _shot)
	get_tree().quit()

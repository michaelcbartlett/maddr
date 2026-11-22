extends SceneTree
## Trailer director. Plays the song and drives a scripted shot list cut on the song's bar grid, rendered with Godot's
## Movie Maker at a fixed frame rate so picture and music stay in sync:
##   1. create godot/override.cfg (temporary, delete afterwards) so the movie writer captures full HD:
##        [display]
##        window/size/viewport_width=1920 / viewport_height=1080 / window_width_override=1920 / window_height_override=1080
##        window/stretch/mode="canvas_items"
##        [editor]
##        movie_writer/mjpeg_quality=0.92
##   2. Godot --path . --resolution 1920x1080 --fixed-fps 30 --quit-after 3150 --write-movie build/trailer/<out.avi> --script res://tools/trailer/trailer.gd
##   (--quit-after is a safety cap: if this script ever fails to compile, the game would otherwise record forever)
## The beat grid (FIRST_BEAT, 146.7 BPM) comes from tools/trailer/analyse_song.gd. Text cards: TRAILER_NOTES.md.
## Clean plates: no HUD, banners or pop-up text (titles are added in the edit; see TRAILER_NOTES.md).
const SONG := "C:/Users/micha/Downloads/mashed with deep perfection.mp3"
const FPS := 30.0
const FIRST_BEAT := 0.092       # from tools/trailer/analyse_song.gd (146.7 BPM)
const BAR := 4.0 * 60.0 / 146.7
const END_BAR := 60.0            # music fades out over bars 58-60, then a short hold on black
const TAIL := 0.7
const SFX_DB := -11.0            # game sounds sit under the music

# [start bar, shot id] in order; each shot runs until the next one starts
const SHOTS := [
	[0, "logo"], [4, "street_open"], [8, "carpet_lasers"], [10, "build"], [14, "grapple"],
	[18, "katana"], [20, "whip"], [22, "shrink"], [26, "freeze"], [30, "bank"],
	[34, "drop"], [36, "train"], [40, "boss_ironclad"], [42, "boss_surge"], [44, "boss_viper"], [46, "boss_glacia"],
	[48, "power_police"], [51, "power_spy"], [54, "climax"], [58, "endcard"]]

var run; var scene; var a
var player: AudioStreamPlayer
var frame := 0
var shot := ""
var shot_t := 0.0
var shot_len := 0.0
var overlay: Control = null     # splash / preview overlays for non-arena shots
var data := {}                  # per-shot scratch state
var rng := RandomNumberGenerator.new()
var ready := false

func _initialize() -> void: call_deferred("_setup")

func _setup() -> void:
	rng.seed = 2026; seed(2026)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false)
	scene._auto = 0.0   # a recording has no window focus: don't auto-pause on focus loss
	a = scene.arena; a.set_process(false)
	var controls = root.get_node("Controls"); controls.aim_src = "pad"; controls.device = -1
	var stream := AudioStreamMP3.new(); stream.data = FileAccess.get_file_as_bytes(SONG)
	player = AudioStreamPlayer.new(); player.stream = stream; root.add_child(player)
	run.unlocks.highest_difficulty = 5
	ready = true

func bar_time(b: float) -> float: return FIRST_BEAT + b * BAR

func _process(_dt: float) -> bool:
	if not ready: return false
	var t := frame / FPS
	if frame == 0:
		player.play()
		for p in root.get_node("Sfx")._players: p.volume_db = SFX_DB
	# music fade over the last two bars
	var fade_from := bar_time(END_BAR - 2.0); var fade_to := bar_time(END_BAR)
	if t > fade_from: player.volume_db = linear_to_db(clampf(1.0 - (t - fade_from) / (fade_to - fade_from), 0.0001, 1.0))
	# which shot is live?
	var current := ""; var start := 0.0; var stop := bar_time(END_BAR)
	for i in SHOTS.size():
		if t >= bar_time(SHOTS[i][0]):
			current = SHOTS[i][1]; start = bar_time(SHOTS[i][0])
			stop = bar_time(SHOTS[i + 1][0]) if i + 1 < SHOTS.size() else bar_time(END_BAR)
	if t < FIRST_BEAT: current = ""
	if current != shot:
		_release_all(); _clear_overlay(); data = {}
		shot = current; shot_len = stop - start
		if shot != "": call("_setup_" + shot)
	shot_t = t - start
	if t > bar_time(END_BAR): _clear_overlay(); scene._show("none")
	elif shot != "":
		call("_tick_" + shot, shot_t)
		if a.state != "none" and scene.state == "play":
			a.P.inv = 0.29 + 1.0 / FPS           # invulnerable with no hurt flash/blink: stays in (0.28, 0.3] after this frame's tick
			a.P.hp = maxf(a.P.hp, 1.0)
			a._process(1.0 / FPS)
			if a.state == "clear" or a.state == "done": a.state = "play"
			a.nums.clear(); a.banner_t = 0.0    # clean plates: no pop-up text or banners
			scene.hud.visible = false
	frame += 1
	return t > bar_time(END_BAR) + TAIL

# ================= helpers =================
func _release_all() -> void:
	for act in ["move_left", "move_right", "move_up", "move_down", "fire", "fire_off", "boss_action", "consume"]:
		Input.action_release(act)

func _move(v: Vector2) -> void:
	for act in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(act)
	if v.length() < 0.05: return
	v = v.limit_length(1.0)
	if v.x > 0.0: Input.action_press("move_right", v.x)
	elif v.x < 0.0: Input.action_press("move_left", -v.x)
	if v.y > 0.0: Input.action_press("move_down", v.y)
	elif v.y < 0.0: Input.action_press("move_up", -v.y)

func _fire(on: bool) -> void:
	if on: Input.action_press("fire")
	else: Input.action_release("fire")

func _aim_at(p: Vector2) -> void:
	var s: Vector2 = a.villain.shoulder_global()
	a.P.aim = (p - s).angle()

func _nearest(max_d := 2000.0):
	var best = null; var bd := max_d
	for e in a.live_foes():
		if e.civ: continue
		var d := Vector2(e.x - a.P.x, e.y - a.P.y).length()
		if d < bd: bd = d; best = e
	return best

func _aim_nearest() -> bool:
	var e = _nearest()
	if e == null: return false
	_aim_at(Vector2(e.x, e.y - 8)); return true

func _clear_overlay() -> void:
	if overlay != null and is_instance_valid(overlay): overlay.queue_free()
	overlay = null

func _begin(theme: String, wave: int, items: Array, ammo := "laser", frame_id := "pistol", zoom := 1.0, at := Vector2(800, 550), spawns := false, difficulty := 1) -> void:
	run.new_run(); run.unlocks.highest_difficulty = 5; run.set_difficulty(difficulty)
	run.build.ammo = run.AMMO.find_custom(func(d): return d.id == ammo)
	run.build.frame = run.FRAMES.find_custom(func(d): return d.id == frame_id)
	run.build.items = items.duplicate(); run.build.off = null; run._rebuild_off(); run.recompute()
	run.heist_wave = wave if theme == "train" else 0
	var order: Array = []
	for i in 7: order.append(theme if theme != "train" else "street")
	run.theme_order = order
	run.wave = wave
	scene._start_wave(); scene._show("play"); scene.hud.visible = false
	a.civ_t = 1000.0; a.crate_t = 1000.0
	if not spawns: a.spawn_t = 1000.0
	for e in a.enemies: e.dead = true
	a.markers.clear(); a.pickups.clear()
	if theme != "train": a.P.x = at.x; a.P.y = at.y
	a.villain.set_items()
	a.cam.zoom *= zoom
	a.cam.position = Vector2(a.P.x, a.P.y); a.cam.reset_smoothing()

func _cop(type: String, x: float, y: float, hp := 60.0, speed_mul := 1.0):
	var e = a.make_enemy(type, x, y); e.hp = hp; e.max_hp = hp; e.spd *= speed_mul
	return e

func _ring(type: String, n: int, r0: float, r1: float, hp := 60.0, speed_mul := 1.0, center := Vector2.INF) -> void:
	var c := Vector2(a.P.x, a.P.y) if center == Vector2.INF else center
	for i in n:
		var ang := rng.randf() * TAU; var r := rng.randf_range(r0, r1)
		_cop(type, c.x + cos(ang) * r, c.y + sin(ang) * r, hp, speed_mul)

# ================= shots =================
# --- logo: the AngryRatGames animation, without its caption (the studio name goes in during the edit) ---
func _setup_logo() -> void:
	scene._show("none")
	overlay = load("res://ui/splash.gd").new(); scene.fit.add_child(overlay)
	overlay._name.visible = false
func _tick_logo(_t: float) -> void:
	if overlay != null and is_instance_valid(overlay): overlay._name.visible = false

# --- night street: stroll in, cops close in, open fire on bar 6 ---
func _setup_street_open() -> void:
	_begin("street", 1, ["coat"], "laser", "pistol", 1.0, Vector2(560, 560))
	for i in 7: _cop("cop" if i % 3 else "det", rng.randf_range(1080, 1350), rng.randf_range(400, 700), 60.0, 0.8)
func _tick_street_open(t: float) -> void:
	if t < 2.0 * BAR: _move(Vector2(0.45, 0.0)); a.P.aim = 0.0; _fire(false)
	else: _move(Vector2.ZERO); _fire(_aim_nearest())

# --- bank carpet close-up: repeater lasers down the red carpet ---
func _setup_carpet_lasers() -> void:
	_begin("bank", 3, ["cell", "fins", "scope"], "laser", "repeater", 2.0, Vector2(640, 545))
	for i in 6: _cop("cop", 820 + i * 46, 520 + (i % 2) * 50, 40.0, 0.35)
func _tick_carpet_lasers(_t: float) -> void:
	_move(Vector2.ZERO); _fire(_aim_nearest())

# --- gun build: one part bolts onto the gun every beat ---
const BUILD_STEPS := ["scope", "cell", "fins", "flare", "drill", "capacitor", "tesla_helmet", "monocle", "coat", "boots",
	"split", "gLaser", "bionic_arm", "katana", "gBullet", "reactor"]
func _setup_build() -> void:
	scene._show("none")
	run.new_run(); run.build.items = []; run.build.off = null; run.recompute()
	overlay = load("res://ui/villain_preview.gd").new(6.0, Vector2(960, 540)); overlay.size = Vector2(960, 540); scene.fit.add_child(overlay)
	data.step = -1
func _tick_build(t: float) -> void:
	var beat := int(t / (BAR / 4.0))
	if beat != data.step and beat < BUILD_STEPS.size():
		data.step = beat
		run.build.items.append(BUILD_STEPS[beat]); run._rebuild_off(); run.recompute()
		root.get_node("Sfx").play("buy1")

# --- shock grapple: swing between pillars, the chain zaps cops in between ---
func _setup_grapple() -> void:
	_begin("bank", 4, ["tesla"], "hook", "pistol", 1.4, Vector2(800, 560))
	for p in [Vector2(1040, 400), Vector2(980, 330), Vector2(560, 700), Vector2(620, 760), Vector2(1100, 470), Vector2(480, 640)]:
		_cop("cop", p.x, p.y, 60.0, 0.4)
func _tick_grapple(t: float) -> void:
	_move(Vector2.ZERO)
	var phase := fmod(t, 2.0 * BAR)
	var target := Vector2(1270, 230) if t < 2.0 * BAR else Vector2(330, 870)
	if phase < 0.15: _fire(false)
	else: _aim_at(target); _fire(phase < 1.6 * BAR)

# --- katana in the bank crowd ---
func _setup_katana() -> void:
	_begin("bank", 4, ["bionic_arm", "katana", "fins", "servos"], "laser", "pistol", 2.0, Vector2(800, 550))
	_ring("cop", 7, 45.0, 75.0, 400.0, 0.15)
func _tick_katana(t: float) -> void:
	_move(Vector2(sin(t * 2.0) * 0.25, 0.0)); _fire(_aim_nearest())

# --- whip crack down a line of cops on the street ---
func _setup_whip() -> void:
	_begin("street", 3, ["bionic_arm", "whip"], "bullet", "pistol", 2.0, Vector2(700, 560))
	for i in 5: _cop("cop", 760 + i * 30, 556 + (i % 2) * 8 - 4, 400.0, 0.1)
	for i in 3: _cop("riot", 600 - i * 40, 520 + i * 30, 400.0, 0.3)
func _tick_whip(_t: float) -> void:
	_move(Vector2.ZERO); _fire(_aim_nearest())

# --- shrink ray: shrink, then stomp ---
func _setup_shrink() -> void:
	_begin("museum", 5, ["bionic_arm", "shrink_ray", "boots"], "laser", "pistol", 1.8, Vector2(800, 550))
	_ring("cop", 7, 130.0, 230.0, 500.0, 0.25)
func _tick_shrink(t: float) -> void:
	_fire(false)
	var target = null; var bd := 1e9
	for e in a.live_foes():
		if e.shrunk_t > 0.0:
			var d := Vector2(e.x - a.P.x, e.y - a.P.y).length()
			if d < bd: bd = d; target = e
	if target != null and t > 1.0: _move((Vector2(target.x, target.y) - Vector2(a.P.x, a.P.y)).normalized())
	else: _move(Vector2.ZERO)
	_aim_nearest()

# --- freeze ray: freeze, then kick the ice block into the crowd ---
func _setup_freeze() -> void:
	_begin("street", 6, ["bionic_arm", "freeze_ray"], "laser", "pistol", 1.6, Vector2(640, 560))
	_cop("cop", 760, 560, 500.0, 0.0)
	_cop("cop", 700, 470, 500.0, 0.0)
	for p in [Vector2(870, 530), Vector2(900, 595), Vector2(930, 555), Vector2(880, 640), Vector2(940, 480)]:
		_cop("cop", p.x, p.y, 500.0, 0.0)
func _tick_freeze(_t: float) -> void:
	_fire(false)
	for e in a.live_foes(): e.spd = 0.0
	var target = null
	for e in a.live_foes():
		if e.frozen_t > 0.0 and e.slide == Vector2.ZERO and e.x < 820: target = e; break
	if target != null: _move((Vector2(target.x, target.y) - Vector2(a.P.x - 0.0, a.P.y)).normalized())
	else: _move((Vector2(640, 560) - Vector2(a.P.x, a.P.y)) * 0.01)
	_aim_nearest()

# --- bank robbery: drop the key holder, grab the key, open the vault just before the drop ---
func _setup_bank() -> void:
	_begin("bank", 4, ["fins"], "laser", "pistol", 1.4, Vector2(390, 560))
	data.holder = _cop("civ", 250, 520, 1.0, 0.0); data.holder.civ = true
	_cop("civ", 300, 680, 30.0, 0.0).civ = true
	_cop("civ", 180, 400, 30.0, 0.0).civ = true
	a.bank_vault.update(a, 0.0)
	if a.bank_vault.holder != null: a.bank_vault.holder.has_key = false
	a.bank_vault.holder = data.holder; data.holder.has_key = true
	for p in [Vector2(620, 430), Vector2(650, 690), Vector2(700, 560)]: _cop("cop", p.x, p.y, 60.0, 0.3)
func _tick_bank(t: float) -> void:
	var bv = a.bank_vault
	for e in a.live_foes():
		if e.civ: e.spd = 0.0
	var holder_ok: bool = is_instance_valid(data.holder) and not data.holder.dead
	if t < 0.9 * BAR and holder_ok:
		_move(Vector2.ZERO); _aim_at(Vector2(data.holder.x, data.holder.y - 8)); _fire(true)
		if t > 0.6 * BAR: a.hit(data.holder, 999.0, {})   # make sure the key drops on cue
	elif t < 0.9 * BAR:
		_move(Vector2.ZERO); _fire(false)
	elif bv.key_pos != null:
		_fire(false); _move((bv.key_pos - Vector2(a.P.x, a.P.y)).normalized())
	elif bv.has_key:
		_fire(false); _move((bv.DOOR + Vector2(40, 0) - Vector2(a.P.x, a.P.y)).normalized())
	else:
		_move(Vector2(0.2, 0.0)); _fire(_aim_nearest())

# --- the drop: everything at once ---
func _setup_drop() -> void:
	_begin("street", 14, ["split", "split", "grenade", "nuke", "storm", "tesla", "thermite", "orb", "fins", "cell", "reactor"], "laser", "blunder", 1.0, Vector2(800, 550), true, 2)
	_ring("cop", 12, 140.0, 330.0, 50.0, 0.7)
	_ring("riot", 5, 220.0, 360.0, 80.0, 0.7)
	_ring("det", 4, 260.0, 380.0, 50.0, 0.7)
func _tick_drop(t: float) -> void:
	_move(Vector2(cos(t * 1.3), sin(t * 1.3)) * 0.35)
	a.P.aim = t * 2.4; _fire(true)

# --- train heist: fight east through the cars ---
func _setup_train() -> void:
	_begin("train", 8, ["fins", "cell", "split", "boots"], "razor", "pistol", 1.0, Vector2.ZERO, true, 2)
func _tick_train(_t: float) -> void:
	_move(Vector2(0.85, 0.0))
	if not _aim_nearest(): a.P.aim = 0.0
	_fire(true)

# --- bosses: two bars each ---
func _boss(wave: int, items: Array, ammo := "laser", frame_id := "pistol") -> void:
	_begin("police" if wave == 10 else ("harbour" if wave == 12 else ("rooftop" if wave == 15 else "street")), wave, items, ammo, frame_id, 1.25, Vector2(700, 560))
	data.boss = a.make_enemy("boss", 1000, 540); a.boss = data.boss
	_ring("cop", 4, 250.0, 340.0, 50.0, 0.6)
func _tick_boss(t: float) -> void:
	var b = data.boss
	var away := Vector2(a.P.x - b.x, a.P.y - b.y)
	var side := away.orthogonal().normalized() * (1.0 if fmod(t, 2.4) < 1.2 else -1.0)
	_move((side * 0.8 + away.normalized() * (0.4 if away.length() < 240 else -0.2)))
	_aim_at(Vector2(b.x, b.y - 18)); _fire(true)
	if not b.dead: b.hp = maxf(b.hp, b.max_hp * 0.4)   # keep the boss on screen for its whole shot
func _setup_boss_ironclad() -> void: _boss(5, ["fins", "cell", "coat"], "bullet")
func _tick_boss_ironclad(t: float) -> void: _tick_boss(t)
func _setup_boss_surge() -> void: _boss(10, ["fins", "cell", "tesla", "storm"], "laser", "repeater")
func _tick_boss_surge(t: float) -> void: _tick_boss(t)
func _setup_boss_viper() -> void: _boss(12, ["fins", "cell", "split", "thermite"], "razor")
func _tick_boss_viper(t: float) -> void: _tick_boss(t)
func _setup_boss_glacia() -> void: _boss(15, ["cell", "reactor", "grenade", "nuke"], "laser", "blunder")
func _tick_boss_glacia(t: float) -> void: _tick_boss(t)

# --- late-game power fantasy ---
const POWER := ["moon", "orb", "orb", "storm", "tesla", "hive", "hypno", "reactor", "fins", "cell", "split", "split", "remote", "clock"]
func _setup_power_police() -> void:
	_begin("police", 17, POWER, "laser", "pistol", 1.0, Vector2(800, 550), true, 3)
	_ring("cop", 10, 150.0, 340.0, 60.0, 0.7); _ring("swat", 4, 260.0, 380.0, 80.0, 0.7)
func _tick_power_police(t: float) -> void:
	_move(Vector2(sin(t * 0.9), cos(t * 1.1)) * 0.3); _fire(_aim_nearest())
func _setup_power_spy() -> void:
	_begin("spyhq", 18, POWER + ["sustain", "lens", "lens"], "laser", "pistol", 1.0, Vector2(800, 550), true, 3)
	_ring("cop", 10, 150.0, 340.0, 60.0, 0.7); _ring("robodog", 3, 260.0, 380.0, 80.0, 0.7)
func _tick_power_spy(t: float) -> void:
	_move(Vector2(cos(t * 0.8), sin(t * 1.2)) * 0.3)
	a.P.aim = t * 1.1; _fire(true)

# --- climax: the final boss against a maxed-out gun ---
func _setup_climax() -> void:
	_begin("spyhq", 20, ["singular", "nuke", "moon", "storm", "orb", "orb", "split", "split", "gLaser", "gBullet", "gRazor", "reactor", "fins", "grenade", "tesla"], "laser", "repeater", 1.0, Vector2(650, 560), true, 3)
	data.boss = a.make_enemy("boss", 1050, 520); a.boss = data.boss
	_ring("cop", 10, 200.0, 380.0, 60.0, 0.7)
func _tick_climax(t: float) -> void: _tick_boss(t)

# --- end card: the doctor and his fully loaded gun on the lab grid (title goes on top in the edit) ---
func _setup_endcard() -> void:
	scene._show("none")
	run.new_run(); run.build.items = ["scope", "cell", "fins", "flare", "drill", "capacitor", "tesla_helmet", "monocle", "coat", "boots", "split", "gLaser", "bionic_arm", "katana", "reactor"]
	run.build.off = null; run._rebuild_off(); run.recompute()
	overlay = load("res://ui/villain_preview.gd").new(5.0, Vector2(960, 540)); overlay.size = Vector2(960, 540); scene.fit.add_child(overlay)
func _tick_endcard(_t: float) -> void: pass

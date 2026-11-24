extends SceneTree
## Imported enemy clips: gait by speed, 24 fps timing, reactions, aiming and special deaths.
const View = preload("res://enemies/enemy_view.gd")
const Sheets = preload("res://enemies/enemy_sheets.gd")
var checks := 0
var failures := 0
class Stage extends Node:
	var P := {"x": 400.0, "y": 0.0, "r": 12.0, "disguise_t": 0.0}
	var time := 0.0
func _init() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _make(type: String, stage):
	var e = load("res://game/enemy.gd").new(); e.A = stage; e.type = type; e.spr = type; e.ranged = type == "det"
	e.gfx = {"speed":0.0,"seed":0.0,"t":0.0,"dt":0.0,"shot_t":9.0}
	return e
func _run() -> void:
	root.get_node("Run").new_run()
	var stage := Stage.new()
	for kind in ["cop","det"]:
		var sheet := Sheets.cached(kind)
		for state in Sheets.states(kind):
			_check(Sheets.EditedArt.has(kind,state),"%s %s is imported" % [kind,state])
			for rect in sheet.frames[state]:
				_check(Rect2(Vector2.ZERO,sheet.albedo.get_size()).encloses(rect),"%s %s stays inside the atlas" % [kind,state])
		_check(Sheets.frame_origin(sheet,"walk") == Vector2(98,108),kind+" is aligned at its foot point")
	var cop = _make("cop",stage); var g: Dictionary = cop.gfx
	View._pick(cop,g,0.0); _check(g.state == "idle","stands still")
	g.speed = 40.0; View._pick(cop,g,0.0); _check(g.state == "walk","slow movement walks")
	g.speed = 108.0; View._pick(cop,g,0.0); _check(g.state == "run" and g.frame == 0,"a chase runs, from its first frame")
	g.dt = 1.0/24.0
	for i in range(1,12): View._pick(cop,g,0.0); _check(g.frame == i,"run advances at 24 fps (%d)" % i)
	View._pick(cop,g,0.0); _check(g.frame == 0,"run loops")
	g.dt = 0.0; cop.flash = 0.1; View._pick(cop,g,0.0); _check(g.state == "hurt","a hit flinches")
	g.dt = 0.25; cop.flash = 0.0; View._pick(cop,g,0.0); g.dt = 0.0; View._pick(cop,g,0.0); _check(g.state == "run","and it ends")
	cop.burn_t = 1.0; View._pick(cop,g,0.0); _check(g.state == "burning","on fire"); cop.burn_t = 0.0
	cop.frozen_t = 1.0; View._pick(cop,g,0.0); _check(g.state == "frozen" and g.frame == 0,"frozen solid"); cop.frozen_t = 0.0
	g.speed = 0.0; cop.sick_t = 1.0; View._pick(cop,g,0.0); _check(g.state == "sick","sick when he stops"); cop.sick_t = 0.0
	var modes := {"":{},"melt":{"rad_t":1.0},"burnt":{"burn_t":1.0},"poison":{"poison_t":1.0},"ebola":{"ebola_t":1.0,"burn_t":1.0},"shatter":{"frozen_t":1.0,"rad_t":1.0}}
	for mode in modes:
		var e = _make("cop",stage)
		for field in modes[mode]: e.set(field,modes[mode][field])
		_check(View.corpse_mode(e) == mode,"death cause '%s' (%s)" % [mode,View.corpse_mode(e)]); e.free()
	var full = _make("cop",stage); full.gfx.rad_seen = 4.9; full.gfx.t = 5.0
	_check(View.corpse_mode(full) == "melt","a full radiation dose still melts"); full.free()
	var det = _make("det",stage); g = det.gfx; det.x = 150.0
	View._pick(det,g,0.0); _check(g.state == "attack","the detective aims in range")
	var level: int = g.frame
	stage.P.y = 260.0; View._pick(det,g,0.0); var low: int = g.frame
	stage.P.y = -260.0; View._pick(det,g,0.0); var high: int = g.frame
	_check(low<level and level<high,"aim frame follows the target (%d %d %d)" % [low,level,high]); stage.P.y = 0.0
	det.action_phase = "flee"; g.speed = 110.0; View._pick(det,g,0.0); _check(g.state == "flee","he runs away")
	det.action_phase = "cornered"; View._pick(det,g,0.0); _check(g.state == "cornered","cornered pose")
	det.action_phase = ""; g.speed = 50.0; det.x = 280.0; View._pick(det,g,0.0); _check(g.state == "backpedal","backs away while aiming")
	det.free(); cop.free(); stage.free()
	print("ENEMY CLIPS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

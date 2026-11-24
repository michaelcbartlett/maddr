extends SceneTree
## Contact timing and the rendered frame must share the complete 33-frame attack clock.
const View = preload("res://enemies/enemy_view.gd")
var checks := 0
var failures := 0

class StrikeArena extends Node:
	var P := {"x": 20.0, "y": 0.0, "r": 12.0}
	var contacts: Array = []
	func hurt_player(amount: float) -> void:
		contacts.append(amount)
	func hit(_victim, amount: float, _flags: Dictionary) -> void:
		contacts.append(amount)

func _init() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var arena := StrikeArena.new()
	var cop = load("res://game/enemy.gd").new(); cop.A = arena; cop.gfx = {"speed": 0.0, "seed": 0.0}
	var profile: Dictionary = cop.strike_profile()
	_check(profile.frame_count == 36 and profile.fps == 24, "native strike has all 36 frames at 24 fps")
	cop._swing(0.0, 20.0)
	_check(is_equal_approx(cop.action_t, 1.5), "attack starts its full 1.5 second clock")
	View._pick(cop, cop.gfx, 0.0)
	_check(cop.gfx.state == "attack" and cop.gfx.frame == 0, "starts at the first authored frame")
	for i in range(1, 36):
		cop._swing(1.0 / 24.0, 20.0)
		View._pick(cop, cop.gfx, 0.0)
		_check(cop.gfx.state == "attack" and cop.gfx.frame == i, "attack frame %d follows gameplay clock" % (i + 1))
		_check(arena.contacts.size() == (0 if i < 11 else 1 if i < 19 else 2), "damage only at strike contact frames (%d)" % (i + 1))
	_check(is_equal_approx(float(arena.contacts[0]) + float(arena.contacts[1]), cop.dmg), "combo divides base damage between the two contacts")
	cop._swing(1.0 / 24.0, 20.0)
	View._pick(cop, cop.gfx, 0.0)
	_check(cop.action_phase == "" and cop.atk_cd == 1.0 and cop.gfx.state == "idle", "full recovery returns to idle and starts cooldown")
	cop.gfx.moving = true; cop.gfx.speed = 40.0
	View._pick(cop, cop.gfx, 0.0)
	_check(cop.gfx.state == "walk", "movement resumes during attack cooldown")
	_check(View.strike_frame(profile, -1.0) == 35, "completed clip clamps at final frame")
	# A whole skipped render interval still dispatches each contact exactly once.
	arena.contacts.clear(); cop.atk_cd = 0.0; cop.x = 0.0
	cop._swing(0.0, 20.0); cop._swing(1.1, 20.0)
	_check(arena.contacts.size() == 2, "large timestep keeps both contact events")
	cop._swing(0.1, 20.0)
	_check(arena.contacts.size() == 2, "contacts never repeat during recovery")
	# Walking away makes both swings miss; re-entering during recovery causes no late hit.
	arena.contacts.clear(); cop.action_phase = ""; cop.atk_cd = 0.0; cop.x = 0.0
	cop._swing(0.0, 20.0); arena.P.x = 200.0
	cop._swing(1.1, 200.0); arena.P.x = 20.0; cop._swing(0.1, 20.0)
	_check(arena.contacts.is_empty(), "both swings can be dodged without delayed damage")
	# Status pauses also pause the shared animation clock.
	var remaining: float = cop.action_t
	cop.time_lock = 0.2; cop.tick(0.1)
	_check(cop.action_t == remaining, "time lock pauses the strike")
	cop.time_lock = 0.0; cop.frozen_t = 0.2; cop.tick(0.1)
	_check(cop.action_t == remaining, "freezing pauses the strike")
	# Mind-controlled cops use the same complete combo against enemies.
	root.get_node("Run").new_run()
	var victim = load("res://game/enemy.gd").new(); victim.x = 20.0
	cop.ally = true; cop.frozen_t = 0.0; cop.action_phase = ""; cop.atk_cd = 0.0; cop.x = 0.0
	arena.contacts.clear()
	cop._strike(0.0, 20.0, profile, victim); cop._strike(1.1, 20.0, profile, victim)
	_check(arena.contacts.size() == 2 and cop.action_phase == "swing", "allied cop lands both hits and keeps its recovery")
	cop._strike(0.45, 20.0, profile, victim)
	_check(cop.action_phase == "" and cop.atk_cd == 0.5, "allied combo finishes before starting cooldown")
	victim.free()
	cop.free(); arena.free()
	print("COP STRIKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

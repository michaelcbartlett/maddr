extends SceneTree
## Authored contacts, pursuit and player damage grace share the full combo clock.
const View = preload("res://enemies/enemy_view.gd")
var checks := 0
var failures := 0

class StrikeArena extends Node:
	var P := {"x": 20.0, "y": 0.0, "r": 12.0}
	var contacts: Array = []
	func hurt_player(amount: float) -> bool:
		contacts.append(amount)
		return true
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
	_check(profile.frame_count == 36 and profile.fps == 30, "native strike has all 36 frames at 30 fps")
	cop._swing(0.0, 20.0)
	_check(is_equal_approx(cop.action_t, 1.2), "attack starts its full 1.2 second clock")
	View._pick(cop, cop.gfx, 0.0)
	_check(cop.gfx.state == "attack" and cop.gfx.frame == 0, "starts at the first authored frame")
	for i in range(1, 36):
		cop._swing(1.0 / 30.0, 20.0)
		View._pick(cop, cop.gfx, 0.0)
		_check(cop.gfx.state == "attack" and cop.gfx.frame == i, "attack frame %d follows gameplay clock" % (i + 1))
		_check(arena.contacts.size() == (0 if i < 11 else 1 if i < 19 else 2), "damage only at strike contact frames (%d)" % (i + 1))
	_check(is_equal_approx(float(arena.contacts[0]) + float(arena.contacts[1]), cop.dmg), "combo divides base damage between the two contacts")
	cop._swing(1.0 / 30.0, 20.0)
	View._pick(cop, cop.gfx, 0.0)
	_check(cop.action_phase == "" and cop.atk_cd == 0.75 and cop.gfx.state == "idle", "full recovery returns to idle and starts cooldown")
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
	_test_live_damage()
	print("COP STRIKE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _live_cop(scene):
	scene._start_wave()
	var a=scene.arena
	a.spawn_t=1000.0; a.civ_t=1000.0; a.crate_t=1000.0
	var cop=a.make_enemy("cop",a.P.x-24.0,a.P.y)
	cop.atk_cd=0.0
	return cop

func _advance_live(a,cop,velocity:=Vector2.ZERO) -> Array:
	var contacts: Array=[]
	for frame in 78:
		a.P.inv=maxf(0.0,a.P.inv-1.0/60.0)
		a.P.x+=velocity.x/60.0; a.P.y+=velocity.y/60.0
		var before: float=a.P.hp
		cop.tick(1.0/60.0)
		if a.P.hp<before: contacts.append(frame)
	return contacts

func _test_live_damage() -> void:
	# Exercise actual HP, scaled shared hit grace and pursuit, not just attempts.
	var run=root.get_node("Run"); run.new_run()
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	var cop=_live_cop(scene)
	var contacts:=_advance_live(a,cop)
	_check(contacts.size()==2,"both authored club blows cause real HP loss when the doctor stays close")
	if contacts.size()==2:
		_check(is_equal_approx(float(contacts[1]-contacts[0])/60.0,8.0/30.0),"the second real hit lands when the default damage-based grace expires")
	cop=_live_cop(scene); cop.dmg=12.0
	_check(_advance_live(a,cop).size()==1,"a heavier first blow gives enough shared protection to block the follow-up")
	cop=_live_cop(scene); contacts=_advance_live(a,cop,Vector2(0,60))
	_check(contacts.size()==2,"a small sidestep does not automatically evade the whole combo")
	cop=_live_cop(scene); contacts=_advance_live(a,cop,Vector2(float(run.D.speed),0))
	_check(not contacts.is_empty(),"walking directly away after being caught still lets the first follow-through connect")
	_check(contacts.size()<2,"sustained retreat can escape the follow-up instead of magnetizing the combo")
	cop=_live_cop(scene); contacts=_advance_live(a,cop,Vector2(float(run.D.speed)*1.45,0))
	_check(contacts.is_empty(),"a fast committed escape clears the club's reach")
	cop=_live_cop(scene); a.dash.safe_t=2.0
	_check(_advance_live(a,cop).is_empty(),"phase-dash safety blocks both club blows")
	_live_cop(scene); a.dash.reset()
	_check(a.hurt_player(2.0),"first contact is accepted")
	_check(not a.hurt_player(2.0),"all attackers respect the same hit grace without a combo exception")
	a.P.inv=1000.0
	_check(not a.hurt_player(2.0),"long invulnerability still blocks damage")
	a.P.inv=0.0
	_check(a.hurt_player(2.0),"damage resumes after the grace expires")
	# The attack step is collision-aware and club reach cannot cross a wall.
	cop=_live_cop(scene)
	a.walls=[{"rect":Rect2(a.P.x-12,a.P.y-60,8,120),"open":false}]
	a.nav.configure(a.walls,Vector2(a.AW,a.AH))
	var before: float=a.P.hp
	cop._swing(0.0,24.0); cop._swing(1.1,24.0)
	_check(a.P.hp==before,"a nearby club combo cannot damage the doctor through a wall")
	_check(cop.x<a.P.x-12,"the follow-through step stops on the cop's side of the wall")
	scene.free()

extends SceneTree
## Phase dash: direction, invulnerability, walls, cooldown, sprint carry and buttons.
var checks := 0
var failures := 0
var a
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _steps(n: int, dt := 1.0/60.0) -> void:
	for i in n: a._process(dt)
func _release() -> void:
	for action in ["dash","move_left","move_right","move_up","move_down","fire"]: Input.action_release(action)
func _tap(dt := 1.0/60.0) -> void:
	a.dash.press(); a._update_play(dt); a._sync_villain()
func _fresh() -> void:
	_release(); a.dash.reset(); a.P.x = 800.0; a.P.y = 550.0; a.P.aim = 0.0; a.P.inv = 0.0; a.P.hp = 30.0; a.walls = []; a.ebul.clear()
	a.villain.rig.set_state({"time":a.time})

func _run() -> void:
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	var bound := func(action: String, button: int) -> bool:
		return InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton and e.button_index == button)
	_check(bound.call("dash",JOY_BUTTON_B) and bound.call("consume",JOY_BUTTON_X) and bound.call("boss_action",JOY_BUTTON_Y),"B dashes, X uses consumables, Y uses abilities")
	_check(not bound.call("detonate",JOY_BUTTON_X) and bound.call("detonate",JOY_BUTTON_LEFT_SHOULDER),"detonate left X but stays on the shoulders")
	for pair in [["dash","consume"],["dash","boss_action"],["consume","boss_action"],["consume","detonate"],["boss_action","detonate"]]:
		for e in InputMap.action_get_events(pair[0]):
			_check(not InputMap.action_get_events(pair[1]).any(func(f): return f.is_match(e)),"%s and %s share no button" % pair)
	await process_frame; await process_frame
	Input.action_press("dash"); a._update_play(1.0/60.0); _check(a.dash.active(),"the real button starts a dash")
	_release(); await process_frame; await process_frame
	for fps in [30,60,144]:
		_fresh(); Input.action_press("move_up"); _tap(1.0/fps)
		for i in int(fps*0.3):
			if a.dash.active(): a._update_play(1.0/fps)
			if not a.dash.active(): break
		_check(absf((550.0-a.P.y)-a.dash.DISTANCE)<1.0 and absf(a.P.x-800.0)<0.01,"dash travels its exact distance at %d FPS" % fps)
	_fresh(); a.P.aim = PI; _tap(); _check(a.dash.dir.is_equal_approx(Vector2.from_angle(PI)) or a.dash.dir.x<-0.9,"with no stick the dash follows the aim")
	_fresh(); Input.action_press("move_left"); _tap()
	_check(a.dash.active() and a.dash.safe(),"dash starts on the press")
	var rig = a.villain.rig
	_check(rig.is_dashing() and not rig.gun_pivot.visible and not rig.rest_pivot.visible,"weapon and arms vanish while phased")
	_check(rig.body.self_modulate.a<1.0,"the body turns translucent")
	a.character_studio = false
	a.hurt_player(10.0); _check(a.P.hp == 30.0,"no damage while phased")
	a.character_studio = true
	_release(); _steps(20)
	_check(not a.dash.active() and not rig.is_dashing() and rig.gun_pivot.visible and rig.body.self_modulate == Color.WHITE,"he returns solid and armed")
	var ended: float = a.P.x
	_tap(); _check(not a.dash.active(),"a second dash waits for the cooldown")
	_release(); _steps(12); _check(absf(a.P.x-ended)<1.0,"an early press outside the buffer is dropped")
	_steps(40); _tap(); _check(a.dash.active(),"dash is ready again after the cooldown")
	a.dash.reset(); a.dash.cd = 1e-9; _tap(); _check(a.dash.active(),"a rounding crumb on the cooldown does not eat the press")
	var run = root.get_node("Run"); run.selected_consumable = run.CONSUMABLE_IDS[0]
	for id in run.CONSUMABLE_IDS: run.consumable_charges[id] = 0
	run.consumable_charges[run.CONSUMABLE_IDS[-1]] = 1; run.cycle_consumable()
	_check(run.selected_consumable == run.CONSUMABLE_IDS[-1],"switching reaches every consumable")
	a.character_studio = false; a.dash.t = 0.0; a.dash.safe_t = 0.0; a.hurt_player(5.0)
	_check(a.P.hp < 30.0,"damage lands again after the dash"); a.character_studio = true
	# bullets pass straight through a phased body
	_fresh(); Input.action_press("move_up"); _tap(); _release()
	a.ebul.append({"x":a.P.x,"y":a.P.y,"vx":0.0,"vy":0.0,"t":1.0,"r":5.0,"dmg":5.0,"zap":true}); a.P.zap_t = 0.0
	a._update_play(0.001); _check(a.ebul.size()==1 and a.P.zap_t<=0.0,"a bullet is not absorbed by a phased body")
	# walls
	_fresh()
	a.walls = [{"rect":Rect2(860,450,40,200),"open":false}]
	Input.action_press("move_right"); _tap(); _release(); _steps(20)
	_check(a.P.x<=860.0-a.P.r+0.5 and a.P.x>820.0,"a wall stops the dash (%.1f)" % a.P.x)
	# every direction has a body pose
	for face_dir in [1,-1]:
		for entry in [[Vector2.UP,"dash_up"],[Vector2.DOWN,"dash_down"],[Vector2(face_dir,0),"dash_forward"],[Vector2(-face_dir,0),"dash_back"]]:
			_fresh(); rig.set_state({"aim":0.0 if face_dir>0 else PI,"time":a.time+1.0}); rig.set_state({"time":a.time+2.0})
			rig.set_state({"dash_dir":entry[0],"dash_progress":0.5})
			_check(rig.dash_clip()==entry[1] and load("res://character/scientist_sprites.gd").has_clip(entry[1]),"%s facing %d" % [entry[1],face_dir])
			rig.set_state({"dash_dir":Vector2.ZERO})
	# sprint
	_fresh(); Input.action_press("move_right"); Input.action_press("dash"); await process_frame; await process_frame
	a.dash.press(); a._update_play(1.0/60.0); _steps(18)
	_check(a.dash.sprinting and rig.sprinting,"holding the button carries into a sprint")
	var x0: float = a.P.x; _steps(20); var sprint: float = a.P.x-x0
	Input.action_press("fire"); _steps(2); _check(not a.dash.sprinting,"firing drops out of the sprint"); Input.action_release("fire"); _steps(2)
	Input.action_release("dash"); _steps(2); x0 = a.P.x; _steps(20)
	_check(sprint>(a.P.x-x0)*1.3,"sprint is faster than walking")
	Input.action_press("dash"); await process_frame; await process_frame
	_steps(3)
	_check(not a.dash.sprinting,"holding without a dash does not sprint"); _release()
	print("PHASE DASH TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

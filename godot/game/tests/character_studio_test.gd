extends SceneTree
## Run with -- --character-studio to exercise the current default startup path.
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _run() -> void:
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false)
	var a = scene.arena; a.set_process(false)
	_check(scene.character_studio and a.character_studio,"default entry opens the character studio")
	_check(scene.state == "play" and a.state == "play","studio starts directly in the arena")
	_check(not scene.hud.visible and scene.level_music.playing,"practice hides the wave HUD while level music plays")
	_check(a.level == "rainy_street" and a.arena_level.theme_id == "rainy_street","opening uses the rebuilt rainy street")
	_check(a.AW==3200 and a.AH==2200 and a.cam.limit_right==3200 and a.cam.limit_bottom==2200,"map and camera bounds double in each dimension")
	_check(a.arena_level.props.size()>=14 and a.arena_level.prop_nodes.size()==a.walls.size() and a.arena_level.lamps.size()==20,"parked vehicles and twenty solid street lights populate the opening")
	_check(a.arena_level.prop_nodes.all(func(n): return n.kind in ["lamp_post","car"]),"only the requested vehicles and streetlights populate the opening")
	_check(a.ambient_fx.visible and not a.heist.active and not a.bank_vault.active,"rain is active while world objectives stay inactive")
	_check(a.actors.get_children().filter(func(c): return c == a.villain or not a.arena_level.prop_nodes.has(c)).size()==1 and a.villain.get_parent()==a.actors,"only the main character and the street light occupy the arena")
	_check(a.make_enemy("cop",900,550)==null,"direct enemy creation is blocked in the studio")
	a.spawn_group(); a.end_wave()
	_check(a.state=="play" and a.markers.is_empty(),"encounter and wave-completion entry points stay inactive")
	var start: float = a.P.x
	Input.action_press("move_right"); Input.action_press("fire")
	var walk_frames := {}; var shot_seen := false
	for i in 180:
		a._process(1.0/60.0)
		walk_frames[a.villain.rig._body_frame.native_index] = true
		shot_seen = shot_seen or a.P.recoil>0.0 or not a.projs.is_empty() or not a.beams.is_empty()
	Input.action_release("move_right"); Input.action_release("fire")
	_check(a.P.x>start and walk_frames.size()>8,"movement still plays the imported walk animation")
	_check(shot_seen,"manual shooting stays active")
	a.hurt_player(99999.0)
	_check(a.P.hp>0.0 and a.P.inv==0.0 and a.state=="play","weapon testing cannot interrupt the studio with player death")
	for wave in [1,8,12,18,20]:
		root.get_node("Run").wave = wave; a.start_wave()
		for i in 1400: a._process(0.05)
		_check(a.state=="play" and a.wave_t==0.0,"no timeout or shop transition at wave %d"%wave)
		_check(a.enemies.is_empty() and a.markers.is_empty() and a.crates.is_empty() and a.pickups.is_empty(),"no regular, boss, civilian or crate spawns at wave %d"%wave)
		_check(a.level=="rainy_street" and a.walls.size()>=14,"special waves keep the parked rainy street")
	scene._show("paused"); _check(paused,"pause still works")
	scene._resume(); _check(not paused and scene.state=="play","resume returns to the studio")
	scene._enter_lab(); _check(scene.state=="design","weapon lab remains available")
	scene._open_difficulty(); _check(scene.state=="play" and not scene.hud.visible,"lab returns directly to the empty arena")
	scene._show("paused"); scene._studio_supply("shrink_pill")
	_check(scene.state=="play" and a.P.size_scale<1.0,"pause-menu shrink preview works without adding enemies")
	scene._show("paused"); scene._studio_supply("enlarge_pill")
	_check(a.P.size_scale>1.0 and a.enemies.is_empty(),"enlargement can be previewed in the blank studio")
	scene._show("paused"); scene._studio_supply("tesla_coil")
	_check(a.consumables.coils.size()==1 and a.enemies.is_empty(),"coil can be placed without enabling enemy spawns")
	# Free practice: one cop, he comes back, and the villain only flinches.
	a.studio_force = true; a.P.inv = 0.0; a.dash.reset()
	for i in 150: a._update_sparring(1.0/60.0)
	_check(a.enemies.size()==1 and a.enemies[0].type=="cop","one cop joins free practice")
	_check(not a.in_wall(a.enemies[0].x,a.enemies[0].y,a.enemies[0].r),"he appears on open ground")
	var health: float = a.P.hp; a.hurt_player(9.0); _check(a.P.hp==health and a.P.flinch_t>0.0,"his hits flinch without costing health")
	var cop = a.enemies[0]; cop.hp = 0.0; a.kill(cop); a.enemies = a.enemies.filter(func(e): return not e.dead)
	for i in 120: a._update_sparring(1.0/60.0)
	_check(a.enemies.is_empty(),"a fallen partner stays down a moment")
	for i in 80: a._update_sparring(1.0/60.0)
	_check(a.enemies.size()==1,"then returns")
	a.studio_sparring = false; a.enemies.clear(); a._update_sparring(9.0); _check(a.enemies.is_empty(),"and can be switched off"); a.studio_force = false
	# First-world waves: the real rules, cops only.
	var run = root.get_node("Run")
	for wave in [1,3,5]:
		a.studio_mode(true); run.wave = wave; a.start_wave()
		_check(a.wave_t==run.wave_len(wave) and a.level=="rainy_street","wave %d has its real length on the street" % wave)
		var seen := {}; var peak := 0
		for i in int(run.wave_len(wave)*20.0)-4:
			a.P.hp = run.D.maxHp; a.P.inv = 1.0; a._process(0.05)
			for e in a.enemies:
				if seen.has(e): continue
				seen[e] = e.type
				if Vector2(e.x,e.y).distance_to(Vector2(a.P.x,a.P.y))>900.0: _check(false,"wave %d spawns near the fight" % wave)
			peak = maxi(peak,a.enemies.filter(func(e): return not e.dead).size())
		_check(seen.size()>15 and seen.values().all(func(t): return t=="cop"),"wave %d sends only cops (%d, peak %d)" % [wave,seen.size(),peak])
		print("  wave %d: %d cops in %ds, health %.0f" % [wave,seen.size(),run.wave_len(wave),3.0+2.0*(wave-1)])
		_check(a.state=="play","wave %d is still running" % wave)
		for i in 8: a._process(0.05)
		_check(a.state=="clear" and a.enemies.all(func(e): return e.dead),"wave %d ends on time" % wave)
	for i in 80: a._process(0.05)
	_check(scene.state=="over" and scene.over_title.text=="STREET CLEARED!","the world ends after wave 5")
	a.studio_mode(true); scene._show("play")
	_check(scene.hud.visible,"the wave HUD is back")
	for i in 660: a.P.hp = run.D.maxHp; a.P.inv = 1.0; a._process(0.05)
	_check(scene.state=="shop" and run.wave==2,"the shop opens between waves")
	scene._start_wave(); a.P.inv = 0.0; a.dash.reset(); a.hurt_player(9999.0)
	_check(scene.state=="over","he can be busted")
	a.studio_mode(false); _check(a.sandbox() and a.enemies.is_empty() and a.wave_t==0.0,"8 returns to free practice")
	print("CHARACTER STUDIO TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

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
	_check(not scene.hud.visible and not scene.level_music.playing,"wave HUD and scratch music are disabled")
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
	# Sparring partners: one of each, they come back, and he only flinches.
	a.studio_force = true; a.P.inv = 0.0; a.dash.reset()
	for i in 150: a._update_sparring(1.0/60.0)
	_check(a.enemies.size()==2 and a.enemies.any(func(e): return e.type=="cop") and a.enemies.any(func(e): return e.type=="det"),"a cop and a detective join the playtest")
	for foe in a.enemies: _check(not a.in_wall(foe.x,foe.y,foe.r),"%s appears on open ground" % foe.type)
	var health: float = a.P.hp; a.hurt_player(9.0); _check(a.P.hp==health and a.P.flinch_t>0.0,"their hits flinch him without costing health")
	var cop = a.enemies.filter(func(e): return e.type=="cop")[0]; cop.hp = 0.0; a.kill(cop); a.enemies = a.enemies.filter(func(e): return not e.dead)
	for i in 120: a._update_sparring(1.0/60.0)
	_check(a.enemies.size()==1,"a fallen partner stays down a moment")
	for i in 80: a._update_sparring(1.0/60.0)
	_check(a.enemies.size()==2,"then returns")
	a.studio_sparring = false; a.enemies.clear(); a._update_sparring(9.0); _check(a.enemies.is_empty(),"and can be switched off"); a.studio_force = false
	print("CHARACTER STUDIO TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

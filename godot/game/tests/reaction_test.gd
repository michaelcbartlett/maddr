extends SceneTree
## Hurt, cackle, burn and tazed reactions, and that burning has no trigger yet.
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _run() -> void:
	var scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); var a = scene.arena; a.set_process(false)
	var rig = a.villain.rig; var P = a.P
	var Scientist = load("res://character/scientist_sprites.gd")
	for name in ["hurt","cackle","burn","tazed"]:
		_check(Scientist.reaction(name,0.0) != null,name+" art is present")
		var used: Rect2i = Scientist.reaction(name,0.0).get_image().get_used_rect() if not Scientist.reaction(name,0.0) is CanvasTexture else Scientist.reaction(name,0.0).diffuse_texture.get_image().get_used_rect()
		_check(used.end.y>=121 and used.end.y<=125,"%s stands on the ground line (%d)" % [name,used.end.y])
		_check(used.size.y>90,"%s keeps his height" % name)
	a._update_play(1.0/60.0); a._sync_villain()
	_check(rig.reaction == "" and rig.gun_pivot.visible,"no reaction by default")
	# hurt
	a.character_studio = false
	P.hp = 30.0; P.inv = 0.0; a.dash.reset(); a.hurt_player(3.0); a._sync_villain()
	_check(rig.reaction == "hurt" and not rig.gun_pivot.visible,"a hit plays the flinch")
	a.character_studio = true
	var x: float = P.x; Input.action_press("move_right")
	for i in 14: a._update_play(1.0/60.0)
	Input.action_release("move_right"); a._sync_villain()
	_check(P.x>x+5.0,"he stays controllable while flinching")
	_check(rig.reaction == "" and rig.gun_pivot.visible,"the gun returns right after the flinch")
	# burn: ticks, no grace, dash puts it out
	a.character_studio = false
	P.hp = 30.0; P.inv = 5.0; a.ignite_player(3.0,4.0); a._sync_villain()
	_check(rig.reaction == "burn","catching fire plays the panic pose")
	a._update_reactions(0.51); a._sync_villain()
	_check(P.hp == 28.0,"burn ticks through the hit grace (%.1f)" % P.hp)
	_check(rig.reaction == "" and P.burn_t>0.0,"he fights on while still burning")
	for i in 60: a._update_reactions(0.05)
	_check(P.burn_t == 0.0 and P.hp == 18.0,"three seconds of burn deals its full damage once (%.1f)" % P.hp)
	a.ignite_player(); a.dash.reset(); a.dash.press(); a.dash.update(a,0.016,Vector2.RIGHT,0.0,false,false); a._update_reactions(0.016)
	_check(P.burn_t == 0.0,"a dash puts the fire out")
	a.ignite_player(); _check(P.burn_t == 0.0,"he cannot catch fire while phased")
	a.dash.reset(); P.hp = 1.0; var died := [false]; a.died.connect(func(): died[0] = true)
	a.ignite_player(); a._update_reactions(0.6); _check(died[0] and a.state == "over","burning can finish him")
	a.state = "play"; P.hp = 30.0; P.burn_t = 0.0
	# nothing in the game sets him alight yet
	for path in ["enemy","enemy_tactics","scenery_damage","viper_boss","rival_scientist"]:
		_check(not FileAccess.get_file_as_string("res://game/%s.gd" % path).contains("ignite_player"),path+" does not burn him yet")
	# cackle
	a.character_studio = true; P.moving = false; P.firing_t = 0.0; P.cackle_t = 1.0; a._sync_villain()
	_check(rig.reaction == "cackle","cackle plays")
	Input.action_press("move_left"); a._update_play(1.0/60.0); Input.action_release("move_left"); a._sync_villain()
	_check(rig.reaction == "","moving cuts the cackle short")
	a.character_studio = false; a.end_wave(); a._sync_villain()
	_check(a.state == "clear" and rig.reaction == "cackle","clearing a wave earns a cackle")
	print("REACTION TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

extends SceneTree
## Intro timing, control lock, pose restoration, shared water and replay safety.
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+label)
func _run() -> void:
	var scene=load("res://game/main.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.set_process(false);var a=scene.arena;a.set_process(false)
	a.studio_mode(true);scene._show("play");a.begin_arrival()
	var arrival=a.teleport_arrival;var at:=Vector2(a.P.x,a.P.y);var timer: float=a.wave_t;var spawn: float=a.spawn_t
	_check(arrival.active and arrival.reveal_height==0,"arrival begins with the scientist unrevealed")
	Input.action_press("move_right");Input.action_press("fire");Input.action_press("dash")
	for i in 24:a._process(1./60.)
	_check(Vector2(a.P.x,a.P.y)==at and a.projs.is_empty() and a.beams.is_empty(),"movement, shooting and dash do not run during materialization")
	_check(a.wave_t==timer and a.spawn_t==spawn and a.enemies.is_empty(),"the wave timer and spawning wait until arrival finishes")
	_check(arrival.reveal_height>0 and arrival.reveal_height<100,"the scientist assembles progressively from the feet upward")
	_check(a.villain.rig.body.material==arrival._wipe and a.villain.rig.near_arm.material==arrival._wipe,"body and modular arm share the same reveal")
	var wet: ShaderMaterial=a.arena_level._floor_sprite.material
	_check(int(wet.get_shader_parameter("wet_glow_count"))>0,"the beam supplies green reflection light to the shared water shader")
	var entry: Dictionary=a.water_reflections.entries[a.villain.get_instance_id()]
	_check(is_equal_approx(float(entry.material.get_shader_parameter("arrival_reveal_height")),arrival.reveal_height),"the reflected scientist uses the same materialization height")
	for i in 50:a._process(1./60.)
	_check(not arrival.active and not arrival.visible,"the arrival ends after its short animation")
	_check(not a.villain.has_meta("arrival_reveal_height") and a.villain.rig.body.material==null,"normal character rendering is restored")
	Input.action_release("dash");Input.action_release("fire");a._process(1./60.)
	_check(a.P.x>at.x and a.wave_t<timer,"movement and the wave clock resume afterward")
	Input.action_release("move_right")
	a.begin_arrival();a._process(.05);a.start_wave()
	_check(not arrival.active and not a.villain.has_meta("arrival_reveal_height"),"restarting a wave safely cancels an old arrival")
	a.begin_arrival();a._process(.05)
	_check(arrival.active,"the next run can teleport in again")
	if OS.get_cmdline_user_args().has("--render-check"):
		a.cam.zoom=Vector2.ONE*2.;a.banner_t=0
		for i in 12:a._process(.025)
		await process_frame;await RenderingServer.frame_post_draw
		var output:=ProjectSettings.globalize_path("res://test-results");DirAccess.make_dir_recursive_absolute(output)
		root.get_texture().get_image().save_png(output+"/teleport-arrival.png")
	scene.free()
	print("TELEPORT ARRIVAL TESTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

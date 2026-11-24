extends SceneTree
## Graphical check: real roof lights shade the native body, without a sprite tint.
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED; root.size=Vector2i(1280,720)
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	root.get_node("Controls").aim_src="pad"
	a.arena_level.parking_seed=231123; scene._start_wave()
	var cruiser
	for prop in a.arena_level.prop_nodes:
		if prop.kind=="car" and prop.record.police: cruiser=prop; break
	a.P.x=cruiser.position.x-100; a.P.y=cruiser.to_global(cruiser._bulbs[0]).y+35
	_check(not a.in_wall(a.P.x,a.P.y,a.P.r),"lighting is checked from an accessible position beside the cruiser")
	a.P.aim=0.0; a.P.moving=false
	a.cam.position=Vector2(a.P.x,a.P.y); a.cam.reset_smoothing()
	var images: Array[Image]=[]; var samples: Array[Vector2i]=[]
	var output:=ProjectSettings.globalize_path("res://test-results")
	DirAccess.make_dir_recursive_absolute(output)
	for row in [[0.05,"red"],[0.5,"blue"]]:
		a.time=5.4+row[0]-cruiser._phase; a.lights.begin(); a._sync(0.0)
		a.villain.rig.set_state({"time":10.0,"aim":0.0,"moving":false})
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image(); images.append(image)
		image.save_png(output.path_join("police-scientist-%s.png"%row[1]))
		if samples.is_empty():
			var sprite: Sprite2D=a.villain.rig.body
			_check(sprite.texture is CanvasTexture and sprite.texture.normal_texture!=null,"the scientist body uses its real normal map")
			_check(sprite.modulate==Color.WHITE and sprite.self_modulate==Color.WHITE,"the roof flash is not a uniform sprite tint")
			var source: Image=sprite.texture.diffuse_texture.get_image()
			for y in source.get_height():
				for x in source.get_width():
					if source.get_pixel(x,y).a<0.8: continue
					var point: Vector2=sprite.get_global_transform_with_canvas()*Vector2(x+0.5,y+0.5)
					var pixel:=Vector2i(point)
					if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel): samples.append(pixel)
	var red_change:=0.0; var blue_change:=0.0; var lit:=0
	for point in samples:
		var red:=images[0].get_pixelv(point); var blue:=images[1].get_pixelv(point)
		red_change+=red.r-blue.r; blue_change+=blue.b-red.b
		if red.r-blue.r>0.03 and blue.b-red.b>0.03: lit+=1
	_check(lit>100 and red_change/samples.size()>0.02 and blue_change/samples.size()>0.02,"red and blue flashes shade visible body pixels on the GPU")
	print("POLICE LIGHTING TESTS: %d checks, %d failures; %d shaded body samples"%[checks,failures,lit]); quit(1 if failures else 0)

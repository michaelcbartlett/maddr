extends SceneTree
## Character art, collisions, y-sort and reflections share a ground plane.
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	var scene=load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene=scene
	scene.set_process(false); var a=scene.arena; a.set_process(false)
	for size in [0.55,1.0,1.6]:
		a.P.size_scale=size; a.P.x=1600; a.P.y=1160; a._sync_villain()
		_check(a.villain.ground_global().is_equal_approx(Vector2(a.P.x,a.P.y)),"size %.2f sorts at the same point as collision"%size)
		_check(a.villain.feet_global().distance_to(a.villain.ground_global())<0.01,"size %.2f keeps the rendered feet on the sorting plane"%size)
		_check(a.villain.muzzle_global().distance_to(a.villain.rig.anchor_global("gun.muzzle"))<0.001,"size %.2f keeps the muzzle on the complete grounded rig"%size)
		a.villain.set_ground_lift(40.0)
		_check(absf(a.villain.feet_global().y-(a.P.y-40.0))<0.01 and absf(a.villain.position.y-a.P.y)<0.01,"an airborne pose lifts the art without changing its ground depth")
		a.villain.set_ground_lift(0.0)
	var vehicle
	for prop in a.arena_level.prop_nodes:
		if prop.kind=="car": vehicle=prop; break
	a.P.size_scale=1.0
	for delta in [-8.0,8.0]:
		a.P.y=vehicle.global_position.y+delta; a._sync_villain()
		_check((a.villain.global_position.y>vehicle.global_position.y)==(delta>0.0),"a character in front of the tire line sorts in front, and behind sorts behind")
	if OS.get_cmdline_user_args().has("--render-check"): await _render_depth(a)
	print("CHARACTER GROUND TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)

func _render_depth(a) -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED; root.size=Vector2i(960,540)
	for prop in a.arena_level.prop_nodes:
		if prop.kind=="car": prop.visible=false
	var vehicles=load("res://levels/parked_vehicle.gd")
	var size: Vector2=vehicles.footprint("compact-hatchback","left")
	var rect:=Rect2(Vector2(1650,1160)-size/2.0,size)
	var car=vehicles.new(); car.setup({"rect":rect,"vehicle_id":"compact-hatchback","view":"left"}); a.actors.add_child(car)
	a.P.x=rect.get_center().x; a.P.size_scale=1.0; a.P.moving=false; a.P.aim=0.0
	a.cam.position=Vector2(1650,1140); a.cam.zoom=Vector2.ONE*2.0; a.cam.reset_smoothing()
	var output:=ProjectSettings.globalize_path("res://test-results"); DirAccess.make_dir_recursive_absolute(output)
	for front in [true,false]:
		a.P.y=rect.end.y+12.0 if front else rect.position.y-12.0
		a.lights.begin(); a._sync(0.0); a.villain.rig.set_state({"time":10.0,"moving":false})
		car.visible=false
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var expected: Image=root.get_texture().get_image()
		car.visible=true
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var rendered: Image=root.get_texture().get_image()
		rendered.save_png(output.path_join("vehicle-depth-%s.png"%("front" if front else "behind")))
		var body: Sprite2D=a.villain.rig.body
		var image: Image=body.texture.diffuse_texture.get_image(); image.decompress()
		var painted: Image=car.sprite.texture.get_image(); painted.decompress()
		var count:=0; var changed:=0
		for y in image.get_height():
			if front and y>55: continue # specifically verify his head/upper torso
			for x in image.get_width():
				if image.get_pixel(x,y).a<0.99: continue
				var world: Vector2=body.to_global(Vector2(x+0.5,y+0.5))
				var local: Vector2=car.sprite.to_local(world)
				if not Rect2(Vector2.ZERO,car.sprite.region_rect.size).has_point(local): continue
				var texel:=Vector2i(car.sprite.region_rect.position+local)
				if painted.get_pixelv(texel).a<0.99: continue
				var pixel:=Vector2i(body.get_global_transform_with_canvas()*Vector2(x+0.5,y+0.5))
				if not Rect2i(Vector2i.ZERO,rendered.get_size()).has_point(pixel): continue
				var before:=expected.get_pixelv(pixel); var after:=rendered.get_pixelv(pixel)
				count+=1
				if maxf(absf(before.r-after.r),maxf(absf(before.g-after.g),absf(before.b-after.b)))>0.025: changed+=1
		if front: _check(count>30 and changed<count*0.05,"GPU keeps the upper body in front of the lower car body when his feet are in front (%d/%d obscured)"%[changed,count])
		else: _check(count>10 and changed>count*0.65,"GPU allows the car to hide the lower body when he stands behind it (%d/%d obscured)"%[changed,count])

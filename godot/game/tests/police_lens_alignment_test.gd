extends SceneTree
## Flash overlays must follow the painted glass in every perspective.
const Vehicles=preload("res://levels/parked_vehicle.gd")
var checks:=0
var failures:=0
var cars: Array=[]
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func _run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED; root.size=Vector2i(1280,720)
	var background:=ColorRect.new(); background.size=Vector2(1280,720); background.color=Color("#26313e"); root.add_child(background)
	var model: Dictionary=Vehicles.model("police-sedan")
	var source: Image=(load(model.sheet) as Texture2D).get_image(); source.decompress()
	var index:=0
	for view in model.frames:
		var size:=Vehicles.footprint(model.id,view)
		var car:=Vehicles.new(); car.setup({"rect":Rect2(Vector2.ZERO,size),"vehicle_id":model.id,"view":view})
		root.add_child(car); car.position=Vector2(160+(index%4)*320,300+(index/4)*360); cars.append(car)
		var frame: Dictionary=model.frames[view]
		for color_index in 2:
			var lens: Sprite2D=car.lens_red if color_index==0 else car.lens_blue
			var mask: Image=lens.texture.get_image(); var valid:=true; var count:=0
			for y in mask.get_height():
				for x in mask.get_width():
					if mask.get_pixel(x,y).a<0.01: continue
					count+=1
					var world:=lens.to_global(Vector2(x+0.5,y+0.5)+lens.offset)
					var painted:=car.sprite.to_local(world)
					var texel:=Vector2i(painted+Vector2(frame.region[0],frame.region[1]))
					var color:=source.get_pixelv(texel)
					var expected: bool=(color.r>color.g*1.45 and color.r>color.b*1.2) if color_index==0 else (color.b>color.r*1.35 and color.b>color.g*1.08)
					valid=valid and expected and color.a>0.5
			_check(valid and count>300,"%s / %s flash mask maps onto its painted glass"%[view,"red" if color_index==0 else "blue"])
		var label:=Label.new(); label.text=view; label.position=Vector2(16+(index%4)*320,330+(index/4)*360); root.add_child(label)
		index+=1
	if OS.get_cmdline_user_args().has("--render-check"): await _render_check()
	print("POLICE LENS ALIGNMENT TESTS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)

func _capture(clock: float) -> Image:
	for car in cars: car.update_visual(clock)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _render_check() -> void:
	var output:=ProjectSettings.globalize_path("res://test-results"); DirAccess.make_dir_recursive_absolute(output)
	var baseline: Image=await _capture(0.87)
	for color_index in 2:
		var image: Image=await _capture(0.05 if color_index==0 else 0.5)
		image.save_png(output.path_join("police-lenses-%s.png"%("red" if color_index==0 else "blue")))
		for index in cars.size():
			var changed:=0; var spill:=0
			for y in range((index/4)*360,(index/4+1)*360):
				for x in range((index%4)*320,(index%4+1)*320):
					var before:=baseline.get_pixel(x,y); var after:=image.get_pixel(x,y)
					if maxf(absf(before.r-after.r),maxf(absf(before.g-after.g),absf(before.b-after.b)))<0.015: continue
					changed+=1
					var painted: bool=(before.r>before.g*1.4 and before.r>before.b*1.15) if color_index==0 else (before.b>before.r*1.3 and before.b>before.g*1.05)
					if not painted: spill+=1
			_check(changed>100 and spill==0,"GPU %s / %s flash stays inside the glass (%d spill pixels)"%[cars[index].record.view,"red" if color_index==0 else "blue",spill])

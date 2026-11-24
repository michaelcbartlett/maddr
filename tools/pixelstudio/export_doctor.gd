extends SceneTree
## Export the real doctor body and separate, articulated melee arms into PixelStudio v2.
const Rig = preload("res://character/villain.gd")
const Capture = preload("res://capture_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const SIZE := Vector2i(192,160)
const ORIGIN := Vector2(72,112)

func _initialize() -> void: call_deferred("_run")

func _pose(pivot: Vector2, shoulder: Vector2, angle: float) -> Dictionary:
	var moved := shoulder+(pivot-shoulder).rotated(angle)
	return {"x":moved.x-pivot.x,"y":moved.y-pivot.y,"sx":1,"sy":1,"angle":rad_to_deg(angle),"px":pivot.x,"py":pivot.y}

func _posed_image(image: Image, pose: Dictionary) -> Image:
	var out := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	var pivot := Vector2(pose.px,pose.py); var translation := Vector2(pose.x,pose.y)
	for y in SIZE.y:
		for x in SIZE.x:
			var source := (Vector2(x+0.5,y+0.5)-pivot-translation).rotated(-deg_to_rad(pose.angle))+pivot
			var sx := floori(source.x+0.00000001); var sy := floori(source.y+0.00000001)
			if sx >= 0 and sy >= 0 and sx < SIZE.x and sy < SIZE.y: out.set_pixel(x,y,image.get_pixel(sx,sy))
	return out

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var setup := args[0]; var output := args[1]
	var kind := "knife" if setup.ends_with("knife") else "katana"
	var dual := setup.begins_with("dual-")
	var rig = Rig.new(); root.add_child(rig)
	rig.set_items(["bionic_arm",kind] if dual else [],kind,"pistol",{"kind":kind} if dual else null)
	rig.set_state({"aim":0.0,"off_aim":0.0,"white":false,"melee_extension":0.5,"melee_active":dual,"melee_aim":0.0,"time":1.0})
	var images := {}; var poses := {}; var layer_info := {}
	var body := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	var body_image: Image = rig._body_frame.img
	body.blit_rect(body_image,Rect2i(Vector2i.ZERO,body_image.get_size()),Vector2i(ORIGIN-rig.BODY_PADDING))
	images["doctor-body"] = body; poses["doctor-body"] = _pose(ORIGIN,ORIGIN,0)
	layer_info["doctor-body"] = {"name":"Doctor body · paintable","parent":""}
	for primary in ([false,true] if dual else [true]):
		var prefix := "primary-" if primary else "secondary-"
		var shoulder: Vector2 = ORIGIN+(rig.gun_pivot.position if primary else rig.off_pivot.position)
		var grip: Vector2 = rig.melee_grip_local(primary)
		var canvas = Capture.new(SIZE.x,SIZE.y); canvas.set_meta("hand",prefix)
		var pen = Pen.new(canvas,shoulder.x,shoulder.y)
		rig._draw_melee_arm(pen,grip,not primary)
		canvas.part(prefix+"weapon",shoulder+grip,prefix+"hand")
		rig._draw_melee_weapon(pen,grip,kind,rig.MELEE_REACH[kind],1.0,rig.upright_blade(primary))
		canvas.part(prefix+"hand",shoulder+grip,prefix+"forearm")
		rig._draw_gripping_fist(pen,grip,not primary)
		for key in canvas.parts:
			images[key] = canvas.parts[key]
			poses[key] = _pose(canvas.joints[key]-Vector2.ONE,shoulder,0.0 if primary else -0.85)
			if key.ends_with("weapon"): poses[key].attachmentAngle = -90.0 if rig.upright_blade(primary) else 0.0
			layer_info[key] = {"name":key.capitalize().replace("-"," "),"parent":canvas.parents[key]}
	var order: Array = []
	if dual: order.append_array(["secondary-upper-arm","secondary-forearm","secondary-weapon","secondary-hand"])
	order.append("doctor-body"); order.append_array(["primary-upper-arm","primary-forearm","primary-weapon","primary-hand"])
	var layers: Array = []; var cels := {}; var stored_poses := {}; var palette := {}
	var composite := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	for key in order:
		var id: String = "layer-"+key
		var layer := {"id":id,"name":layer_info[key].name,"visible":true,"locked":false,"opacity":100}
		if layer_info[key].parent != "": layer.parent = "layer-"+str(layer_info[key].parent)
		layers.append(layer); cels[id] = Marshalls.raw_to_base64(images[key].get_data()); stored_poses[id] = poses[key]
		var posed := _posed_image(images[key],poses[key])
		composite.blend_rect(posed,Rect2i(Vector2i.ZERO,SIZE),Vector2i.ZERO)
	var bytes := composite.get_data()
	for i in range(0,bytes.size(),4):
		if bytes[i+3] > 0: palette["#%02x%02x%02x" % [bytes[i],bytes[i+1],bytes[i+2]]] = true
	var empty := PackedByteArray(); empty.resize(SIZE.x*SIZE.y*4)
	var mask := PackedByteArray(); mask.resize(SIZE.x*SIZE.y)
	var main_grip: Vector2 = ORIGIN+rig.gun_pivot.position+rig.melee_grip_local(true)
	var frame := {"base":Marshalls.raw_to_base64(empty),"original":Marshalls.raw_to_base64(bytes),"overlay":Marshalls.raw_to_base64(empty),
		"mask":Marshalls.raw_to_base64(mask),"cels":cels,"poses":stored_poses,"hold":1,"maps":{},"gradientBoxes":[],"gradientBoxIndex":-1,
		"socket":{"x":main_grip.x,"y":main_grip.y,"angle":0.0}}
	var project := {"format":"pixel-motion-studio","version":2,"width":SIZE.x,"height":SIZE.y,"fps":6,"currentFrame":0,
		"activeLayer":"layer-primary-weapon","layers":layers,"palette":palette.keys().slice(0,64),"frames":[frame],"reference":null,
		"settings":{"clipMask":false,"rigFollow":true,"rigBones":true,"showSocket":true,"exScale":1},
		"godotSource":{"adapter":"mad-villain-doctor-melee-v1","character":"doctor","animation":setup,"script":"character/villain.gd",
			"primary":kind,"secondary":kind if dual else "","foot_origin":[ORIGIN.x,ORIGIN.y],"lighting":"generated-from-current-artwork"}}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Could not write doctor project"); quit(1); return
	file.store_string(JSON.stringify(project)); file.close()
	composite.save_png(output.get_basename()+".png")
	print("Exported doctor ",setup,": ",layers.size()," linked parts; weapons rotate about the hand grips.")
	quit()

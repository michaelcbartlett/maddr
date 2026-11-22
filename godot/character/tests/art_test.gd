extends SceneTree
## Reference tests captured from the original browser renderer before the transfer.
## Exercises every item, all poses, 12 ammo/frame pairs, stacked modules and mixed builds.
const Art = preload("res://character/art_renderer.gd")
const Rig = preload("res://character/villain.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Pixels = preload("res://character/pixel_canvas.gd")
const REFERENCE = "res://character/tests/reference/"
var failures := 0
var comparisons := 0
var worst_delta := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(731)
	var started = Time.get_ticks_msec()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE+"cases.json"))
	var sheets = {}
	for name in ["body","body-normal","xray","gun","gun-normal","off","off-normal"]:
		sheets[name] = Image.load_from_file(REFERENCE+name+".png")
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://character/art/gear.json"))
	for table in ["ammo","frames","items"]:
		var game_table = JSON.parse_string(FileAccess.get_file_as_string("res://data/"+table+".json"))
		_check(game_table == definitions[table],"character/game definitions agree: "+table)
	for index in manifest.cases.size():
		var config: Dictionary = manifest.cases[index]
		var art = Art.new()
		art.configure(config.items,definitions.ammo[int(config.ammo)].id,definitions.frames[int(config.frame)].id)
		var body = art.body_frame(int(config.pose),config.armed,config.get("hurt",false))
		var gun = art.weapon_frame(int(config.bend))
		var off = art.weapon_frame(int(config.bend),config.off,true)
		_check(gun.muz == config.muzzle,config.name+": main muzzle")
		_check(off.muz == config.offMuzzle,config.name+": off muzzle")
		_check(_equivalent(gun.gunY,config.gunY),config.name+": extra gun positions")
		_check(_equivalent(gun.anchors,config.anchors),config.name+": gun anchors")
		_check(_equivalent(body.anchors,config.bodyAnchors),config.name+": body anchors")
		for name in sheets:
			var image: Image
			match name:
				"body": image = body.img
				"body-normal": image = body.depth.normal_image()
				"xray": image = art.xray_texture(body).get_image()
				"gun": image = gun.cv
				"gun-normal": image = gun.depth.normal_image()
				"off": image = off.cv
				"off-normal": image = off.depth.normal_image()
			var size = image.get_size()
			var expected = (sheets[name] as Image).get_region(Rect2i(Vector2i(index%int(manifest.columns),index/int(manifest.columns))*size,size))
			_compare(image,expected,config.name+"/"+name)
		var effects = Pixels.new(260,140)
		var pen = Pen.new(effects,35,59)
		var state = {"moving":true,"firing":true,"recoil":0.5,"flash":0.1}
		for effect in body.anims+gun.anims+off.anims: art.draw_effect(pen,effect,state,0.37)
		art.draw_shout(pen,0.37)
	_test_rig()
	_test_dense_build()
	print("CHARACTER TESTS: %d cases, %d image comparisons, maximum channel delta %d, %d failures, %d ms" % [manifest.cases.size(),comparisons,worst_delta,failures,Time.get_ticks_msec()-started])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1; push_error("FAIL: "+label)

func _equivalent(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _equivalent(a[i],b[i]): return false
		return true
	return a == b

func _compare(actual: Image, expected: Image, label: String) -> void:
	comparisons += 1
	_check(actual.get_size() == expected.get_size(),label+": dimensions")
	var a = actual.get_data(); var b = expected.get_data()
	if a == b: return
	var delta = 0; var alpha_delta = 0; var differences = 0
	for i in a.size():
		var difference = absi(int(a[i])-int(b[i]))
		delta = maxi(delta,difference)
		if i%4 == 3: alpha_delta = maxi(alpha_delta,difference)
		if difference: differences += 1
	worst_delta = maxi(worst_delta,delta)
	# Canvas and Image use slightly different rounding for translucent glass and HSL shades.
	if delta > 2 or alpha_delta > 1:
		actual.save_png("res://test-results/"+label.replace("/","-")+".png")
		_check(false,"%s: %d channels differ, delta=%d alpha=%d" % [label,differences,delta,alpha_delta])

func _test_rig() -> void:
	var rig = Rig.new()
	rig.set_items(["scope","drill","gLaser","gBullet","gRazor"],"laser","rifle",{"ammo":1,"frame":2,"items":["drill"]})
	root.add_child(rig)
	rig.position = Vector2(100,90); rig.scale = Vector2(2,2)
	for angle in [0.0,PI,PI/2.0,-PI/2.0,0.7,2.4]:
		for phase in 8:
			rig.set_state({"aim":angle,"off_aim":angle-0.2,"moving":true,"walk_phase":phase/8.0,"recoil":0.8,"recoil2":0.4})
			_check(rig.pose == 11+phase,"eight-frame walk advances")
			_check(rig.muzzle_global().distance_to(rig.anchor_global("gun.muzzle")) < 0.001,"muzzle marker matches gameplay, both facings")
			_check(rig.off_muzzle_global().distance_to(rig.off_muzzle_light.global_position) < 0.001,"off-hand light matches muzzle")
			_check(rig.gun_offset(3) == -21,"stacked gun offset")
	rig.t = 0.0; rig.set_state({"zap":true,"flash":0.1,"flash2":0.1})
	_check(rig.body.material != null,"x-ray uses an unlit skeleton")
	_check(rig.off_muzzle_light.color == Color("#ffd76a"),"off-hand uses its own ammo color")
	rig.set_items(["bionic_arm"],"razor","pistol")
	_check(not rig.off_gun.visible and rig.bionic.visible,"removing the arm weapon restores the bionic fist")
	rig.free()

func _test_dense_build() -> void:
	var art = Art.new()
	var ids: Array = []
	var defs = JSON.parse_string(FileAccess.get_file_as_string("res://character/art/gear.json"))
	for item in defs.items:
		if item.has("wv"):
			for stack in 3: ids.append(item.id)
	art.configure(ids,"laser","rifle")
	var gun = art.weapon_frame(1)
	_check(gun.cv.get_width()>232,"dense builds expand the drawing canvas")
	_check(gun.muz+35<gun.cv.get_width(),"dense build muzzle remains inside its texture")

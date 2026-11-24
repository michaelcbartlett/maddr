extends SceneTree
## Every worn item must visibly change the native scientist, in every movement clip, without moving him.
const Rig = preload("res://character/villain.gd")
const Gear = preload("res://character/scientist_gear.gd")
const Scientist = preload("res://character/scientist_sprites.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
func _difference(a: Image, b: Image) -> int:
	var n := 0
	for y in 128:
		for x in 128:
			if a.get_pixel(x,y) != b.get_pixel(x,y): n += 1
	return n
func _run() -> void:
	var items := {}
	for it in JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json")): items[it.id] = it
	for id in Gear.WORN: _check(items.has(id),"%s is a real item" % id)
	var plain := Scientist._tile("idle",0,false).img as Image
	for id in Gear.WORN:
		var gear = Gear.new().build([id])
		var out: Array = gear.dress(plain,Scientist._tile("idle",0,false).texture.normal_texture.get_image(),Vector2i.ZERO,Vector2i.ZERO)
		var changed := _difference(plain,out[0])
		_check(changed>=6 or not out[2].is_empty(),"%s shows on the body (%d pixels)" % [id,changed])
		_check(changed<6000,"%s does not repaint the whole figure (%d)" % [id,changed])
		for y in range(40,44): _check(out[1].get_size()==Vector2i(128,128),"normals keep the cell"); break
	var rig = Rig.new(); root.add_child(rig)
	rig.set_items(["coat","mutagen","core_battery","goggles","boots"],"laser","pistol")
	rig.set_state({"aim":0.0,"off_aim":0.0,"time":1.0}); rig.set_state({"time":2.0})
	_check(rig.near_arm.texture != Scientist.part("near_arm",rig._native_near_pose.index),"the worn coat recolors the sleeve")
	_check(rig.near_hand.texture != Scientist.part("near_hand",rig._native_near_pose.index),"mutagen recolors the hand")
	for mode in [{"moving":false},{"moving":true},{"moving":true,"sprinting":true},{"dash_dir":Vector2.UP,"dash_progress":0.5}]:
		rig.set_state(mode); _check(_difference(rig._body_frame.img,Scientist._tile("idle",0,false).img)>500,"gear is worn in %s" % str(mode.keys()))
	rig.set_state({"dash_dir":Vector2.ZERO,"sprinting":false,"moving":false,"firing":true,"time":3.0})
	_check(rig.body.texture != rig._body_frame.texture,"the shout works while dressed")
	rig.set_state({"firing":false}); rig.set_items([],"laser","pistol"); rig.set_state({"time":4.0})
	_check(rig.gear == null and rig._body_frame.anims.is_empty(),"taking everything off restores the plain body")
	rig.set_items(["hive"],"laser","pistol"); rig.set_state({"time":5.0})
	_check(not rig._body_frame.anims.is_empty(),"gear effects come with the item")
	print("SCIENTIST GEAR TESTS: %d checks, %d failures" % [checks,failures])
	rig.free(); quit(1 if failures else 0)

extends SceneTree
## Native scientist integration: free aiming, live gun modules and shared muzzle transforms.
const Rig = preload("res://character/villain.gd")
const Scientist = preload("res://character/scientist_sprites.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _run() -> void:
	var rig = Rig.new(); root.add_child(rig)
	rig.set_items([],"laser","pistol")
	rig.set_state({"moving":true,"time":0.0,"aim":0.0})
	_check(rig._body_frame.skin == "scientist_h3","new scientist is the default player skin")
	_check(rig._body_frame.img.get_size() == Vector2i(128,128),"body retains native 128px pixels")
	_check(rig.near_arm.visible and rig.near_hand.visible,"gun arm and hand are separate layers")
	_check(not rig.far_arm.visible,"unequipped rear gun arm is hidden")
	var first: int = rig._body_frame.native_index
	rig.set_state({"time":1.0/48.0})
	_check(rig._body_frame.native_index == first,"animation holds each frame for 1/24 second")
	rig.set_state({"time":1.0/24.0})
	_check(rig._body_frame.native_index == first+1,"walk advances at 24fps")
	rig.set_state({"time":float(Scientist.data().clips.walk.count)/24.0})
	_check(rig._body_frame.native_index == first,"walk loops every imported frame")
	var walk: Dictionary = Scientist.data().clips.walk
	_check(walk.count > 8,"walk preserves more than the legacy eight samples")
	rig.set_items(["gLaser","gBullet","scope"],"bullet","rifle",{"ammo":"laser","frame":"pistol","items":["drill"]})
	for angle in [0.0,0.6,PI/2.0,PI,-PI/2.0,-2.4]:
		for kick in [0.0,1.0]:
			rig.set_state({"aim":angle,"off_aim":angle+PI,"recoil":kick,"recoil2":kick,"flash":0.05,"flash2":0.05})
			_check(rig.muzzle_global().distance_to(rig.anchor_global("gun.muzzle"))<0.001,"primary shot origin follows rendered muzzle at all angles")
			_check(rig.off_muzzle_global().distance_to(rig.off_muzzle_light.global_position)<0.001,"rear shot origin follows its rendered light")
			var expected := Scientist.grip_offset("near",rig._native_near_pose)-Vector2(roundf(kick*3.0),0)
			var grip: Vector2 = rig.gun.position+Vector2(35,59)+rig._vector(rig._gun_frame.anchors.grip)
			_check(grip.distance_to(expected)<0.001,"live upgraded gun stays attached to the new hand")
			var socket: Vector2 = rig.near_arm.transform*Scientist.pose_point(rig._native_near_pose,"shoulder")
			_check(socket.length()<0.001,"the arm shoulder stays pinned during aim and recoil")
			var hand_grip: Vector2 = rig.near_hand.transform*Scientist.pose_point(rig._native_near_pose,"grip")
			_check(hand_grip.distance_to(grip)<0.001,"rendered fingers and live gun share the same grip")
			_check(rig.far_arm.visible and rig.far_hand.visible,"dual guns keep both arm layers")
	_check(rig._gun_frame.muzzles.size()==3,"stacked gun modules retain separate muzzles")
	_check(rig.off_pivot.get_index()<rig.body_root.get_index(),"far arm draws behind body and head")
	_check(rig.gun_pivot.get_index()>rig.body_root.get_index(),"near arm draws in front of torso")
	rig.set_state({"aim":0.0,"recoil":0.0})
	var held_pose: int = rig._native_near_pose.index
	rig.set_state({"aim":-1.3})
	_check(rig._native_near_pose.index != held_pose,"right-stick elevation selects a different drawn arm pose")
	var raised_pose: int = rig._native_near_pose.index
	rig.set_state({"time":2.0})
	_check(rig._native_near_pose.index == raised_pose,"holding the aim direction holds the arm pose")
	rig.set_state({"aim":0.0,"recoil":1.0})
	_check(rig._native_near_pose.kind == "recoil_high" and rig._native_near_pose.source == "73-near-natural-jolt","firing plays the matched arm recoil")
	rig.set_state({"recoil":0.0})
	_check(rig._native_near_pose.index == held_pose,"recoil returns to the held aim pose")
	rig.set_state({"aim":0.0,"white":false,"zap":false})
	for degrees in [-88.0,-92.0,-89.0,-91.0]:
		rig.set_state({"aim":deg_to_rad(degrees)})
		_check(rig.face == 1 and rig.gun_pivot.scale.y == 1,"vertical stick jitter holds both body and arm facing")
		_check(not rig.head_occluder.visible,"overhead near arm does not fade behind the head")
	rig.set_state({"aim":deg_to_rad(-105.0)})
	var turn_start: float = rig.t
	rig.set_state({"time":turn_start+0.055})
	_check(rig._body_frame.get("turn_front",false),"body uses the real front-facing bridge during a turn")
	rig.set_state({"time":turn_start+0.13})
	_check(rig.face == -1 and rig.gun_pivot.scale.y == -1,"clear left aim switches body and arm facing together")
	_check(rig.primary_arm_view == "far" and rig._native_near_pose.source == "72-far-natural-sweep","left-facing primary uses the opposite view of the same hand")
	_check(rig.gun_pivot.get_index()<rig.body_root.get_index(),"the same physical primary hand is behind the torso when facing left")
	_check(rig.rest_pivot.visible and rig.rest_arm.texture == Scientist.part("rest_near") and not rig.rest_hand.visible or rig.has_bionic,"an empty off hand uses the relaxed arm, not a gun grip")
	rig.set_state({"aim":deg_to_rad(-89.0)})
	_check(rig.face == -1,"crossing vertical alone does not flip the body back")
	rig.set_state({"aim":0.0,"time":10.0,"recoil":0.0})
	for i in range(1,25):
		rig.set_state({"aim":-PI/2.0*i/24.0,"time":10.0+i/24.0})
	_check(rig._native_near_pose.kind == "aim","a slow upward sweep keeps the straight arm")
	rig.set_state({"aim":0.0,"time":12.0})
	rig.set_state({"aim":-1.3,"time":12.0+1.0/24.0})
	_check(rig._native_near_pose.kind == "aim","a quick flick uses the same natural arm, with no separate clip to jump to")
	rig.set_state({"time":12.4})
	_check(rig._native_near_pose.kind == "aim" and rig._native_near_pose.source == "71-near-natural-sweep","the raised arm finishes straight")
	rig.set_state({"aim":PI,"time":14.0}); rig.set_state({"time":14.2})
	rig.set_state({"aim":-PI+1.3,"time":14.2+1.0/24.0})
	_check(rig._native_near_pose.kind == "aim" and rig.primary_arm_view == "far","left-facing flicks use the natural arm too")
	rig.set_state({"time":14.5})
	_check(rig._native_near_pose.kind == "aim","left-facing quick raises also finish straight")
	# A sleeve hidden behind the head in its source frame must not import as a hole.
	for side in ["near","far"]:
		var areas: Array = []
		for i in Scientist.data().poses[side].size():
			if Scientist.data().poses[side][i].kind != "aim": continue
			var image: Image = Scientist.part(side+"_arm",i).diffuse_texture.get_image()
			var area := 0
			for y in 128:
				for x in 128:
					if image.get_pixel(x,y).a>0.5: area += 1
			areas.append(area)
		_check(areas.min()>areas.max()*0.75,"%s sleeve is complete at every aim angle (%d..%d px)" % [side,areas.min(),areas.max()])
	rig.set_state({"aim":0.0,"off_aim":0.0,"time":30.0,"recoil":0.0,"zap":false,"white":false}); rig.set_state({"time":30.5})
	var level: float = Scientist.grip_offset("near",Scientist.aim_pose("near",0.0)).length()
	for angle in [-PI/2.0,PI/2.0]:
		_check(Scientist.grip_offset("near",Scientist.aim_pose("near",angle)).length()>level*1.05,"the elbow is bent when level and opens toward straight up and down")
	for side in ["near","far"]:
		var previous: float = -1.0
		for degrees in range(-90,91,5):
			var reach: float = Scientist.grip_offset(side,Scientist.aim_pose(side,deg_to_rad(degrees))).length()
			if previous>0.0: _check(absf(reach-previous)<4.0,"%s reach changes smoothly at %d" % [side,degrees])
			previous = reach
	for clip in ["idle","walk","run"]:
		for i in int(Scientist.data().clips[clip].count):
			_check(Scientist.jaw_row(Scientist._tile(clip,i,false))>0,"%s %d has a jaw to open" % [clip,i])
	rig.set_state({"aim":0.0,"time":20.0,"firing":true,"white":false,"zap":false}); rig.set_state({"time":20.3})
	_check(rig.body.texture != rig._body_frame.texture,"firing opens the jaw")
	rig.set_state({"firing":false})
	_check(rig.body.texture == rig._body_frame.texture,"the face closes when he stops firing")
	rig.set_state({"zap":true,"time":0.0})
	_check(rig.body.texture.get_width()==128 and rig.body.material!=null,"native x-ray retains body size and unlit material")
	rig.set_state({"zap":false,"white":true,"time":0.2})
	_check(rig.body.texture!=null,"hit flash supports imported textures")
	rig.set_items([],"katana","pistol")
	_check(not rig.gun.visible and not rig.near_arm.visible,"melee draws its own arm without a duplicate shooting arm")
	_check(rig.melee_local_points(true).size()>0,"existing melee geometry remains active")
	if OS.get_cmdline_user_args().has("--render-check"): await _render_check()
	print("SCIENTIST SPRITE TESTS: %d checks, %d failures" % [checks,failures])
	rig.free(); quit(1 if failures else 0)

func _render_check() -> void:
	# Frame counters cannot detect CanvasTexture/AtlasTexture UV mistakes. Compare
	# actual rendered alpha against two different imported walk cells on the GPU.
	for index in [0,17]:
		var tile := Scientist._tile("walk",index,false)
		var view := SubViewport.new(); view.size = Vector2i(128,128)
		view.transparent_bg = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var sprite := Sprite2D.new(); sprite.centered = false; sprite.texture = tile.texture
		view.add_child(sprite)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var rendered: Image = view.get_texture().get_image()
		var expected: Image = tile.img
		var differences := 0
		for y in 128:
			for x in 128:
				if (rendered.get_pixel(x,y).a>0.5) != (expected.get_pixel(x,y).a>0.5): differences += 1
		_check(differences<8,"GPU draws the selected walk cell %d (%d different alpha pixels)" % [index,differences])
		view.queue_free(); await process_frame

extends Node2D
## Self-contained procedural villain. One sprite pixel = one world unit.
## set_items(items, ammo_id, frame_id, off_spec) rebuilds any loadout natively.
## set_state({aim, off_aim, moving, walk_phase, recoil, flash, recoil2, flash2,
##            firing, firing2, white, zap}) drives the rig from gameplay.
## Angles are world-space radians; walk_phase is one stride in 0..1.
const Art = preload("res://character/art_renderer.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Scientist = preload("res://character/scientist_sprites.gd")
const Gear = preload("res://character/scientist_gear.gd")
static var _gear_cache: Dictionary = {}
var gear = null   # worn items for the native sprite, or null
const BODY_ORIGIN = Vector2(29,46)
const BODY_PADDING = Vector2(30,47)
const WEAPON_PADDING = Vector2(35,59)
const AMMO_COL = {"laser":Color("#ff4a4a"),"bullet":Color("#ffd76a"),"razor":Color("#dfe6ec"),"hook":Color("#7df9ff")}
const CACHE_LIMIT = 6
static var _build_cache: Dictionary = {}
static var _build_order: Array[String] = []

@export var auto_demo := false
@export var native_scientist := true
var near_arm: Sprite2D
var near_hand: Sprite2D
var far_arm: Sprite2D
var far_hand: Sprite2D
var rest_pivot: Node2D
var dash_dir := Vector2.ZERO    # non-zero only while phased
var dash_progress := 0.0
var sprinting := false
var sprint_dir := 1
var reaction := ""           # hurt, cackle or burn: a full-body pose that hides the gun layers
var reaction_time := 0.0
var rest_arm: Sprite2D
var rest_hand: Sprite2D
var primary_arm_view := "near"
var secondary_arm_view := "far"
var _native_near_pose: Dictionary = {}
var _native_far_pose: Dictionary = {}
var _off_face := 1
var _last_native_time := -1.0
var head_occluder: Sprite2D
const FACING_HYSTERESIS := 0.18
const TURN_TIME := 3.0/24.0
var _turn_from_face := 1
var _turn_target_face := 1
var _turn_started := -10.0
var turn_progress := 1.0
var aim := 0.0
var off_aim := 0.0
var moving := false
var walk_phase := 0.0
var recoil := 0.0
var flash := 0.0
var recoil2 := 0.0
var flash2 := 0.0
var gun_flashes: Array = []
var capacitor_charge := 0.0
var capacitor_charge_off := 0.0
var melee_extension := 0.0
var melee_aim := 1.2
var melee_active := false
var melee_reach := 0.0
var primary_melee_reach := 0.0
var arm_mode := "fist"
var has_bionic := false
var bionic: Sprite2D
var _bionic_frame: Dictionary
var firing := false
var firing2 := false
var white := false
var zap := false
var hook_out := false   # Shock Grapple: the claw has left the muzzle
var armed := false
var items: Array[String] = []
var ammo := "laser"
var frame_id := "pistol"
var off_spec = null
var art
var body_root: Node2D
var body: Sprite2D
var body_anchors: Node2D
var gun_pivot: Node2D
var gun: Sprite2D
var gun_anchors: Node2D
var off_pivot: Node2D
var off_gun: Sprite2D
var muzzle_light: PointLight2D
var off_muzzle_light: PointLight2D
var emissive: Node2D
var body_fx: Node2D
var gun_fx: Node2D
var off_fx: Node2D
var t := 0.0
var pose := 6
var face := 1
var _demo_cd := 0.0
var _body_frame: Dictionary
var _gun_frame: Dictionary
var _off_frame: Dictionary
var _unshaded: CanvasItemMaterial
var _external_clock := false

func _ready() -> void:
	_unshaded = CanvasItemMaterial.new(); _unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	off_pivot = Node2D.new(); off_pivot.name = "OffPivot"; add_child(off_pivot)
	far_arm = _sprite("FarArm",off_pivot)
	off_gun = _sprite("OffGun",off_pivot)
	far_hand = _sprite("FarHand",off_pivot)
	bionic = _sprite("BionicArm",off_pivot)
	off_fx = _overlay("Effects",off_pivot,_draw_off_fx)
	body_root = Node2D.new(); body_root.name = "Body"; add_child(body_root)
	emissive = _overlay("Emissive",body_root,_draw_rear_fx)
	body = _sprite("Sprite",body_root); body.position = -BODY_PADDING
	body_fx = _overlay("Effects",body_root,_draw_body_fx)
	body_anchors = Node2D.new(); body_anchors.name = "Anchors"; body_root.add_child(body_anchors)
	gun_pivot = Node2D.new(); gun_pivot.name = "GunPivot"; add_child(gun_pivot)
	near_arm = _sprite("NearArm",gun_pivot)
	gun = _sprite("Gun",gun_pivot)
	near_hand = _sprite("NearHand",gun_pivot)
	gun_fx = _overlay("Effects",gun_pivot,_draw_gun_fx)
	gun_anchors = Node2D.new(); gun_anchors.name = "Anchors"; gun.add_child(gun_anchors)
	head_occluder = _sprite("OverheadHead",self)
	rest_pivot = Node2D.new(); rest_pivot.name = "RestingArm"; add_child(rest_pivot)
	rest_arm = _sprite("Sleeve",rest_pivot); rest_hand = _sprite("Hand",rest_pivot)
	muzzle_light = _flash_light()
	off_muzzle_light = _flash_light(); off_gun.add_child(off_muzzle_light)
	set_items(items,ammo,frame_id,off_spec)
	_marker(gun_anchors,"muzzle").add_child(muzzle_light)
	_update()

func _sprite(node_name: String, parent: Node) -> Sprite2D:
	var sprite = Sprite2D.new(); sprite.name = node_name; sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; parent.add_child(sprite)
	return sprite

func _overlay(node_name: String, parent: Node, callback: Callable) -> Node2D:
	var layer = Node2D.new(); layer.name = node_name; layer.material = _unshaded
	layer.draw.connect(callback); parent.add_child(layer)
	return layer

func _marker(parent: Node, node_name: String) -> Marker2D:
	var marker = parent.get_node_or_null(NodePath(node_name)) as Marker2D
	if marker == null:
		marker = Marker2D.new(); marker.name = node_name; parent.add_child(marker)
	return marker

func set_items(p_items: Array, p_ammo: String = "laser", p_frame: String = "pistol", p_off_spec = null) -> void:
	items.assign(p_items.duplicate()); ammo = p_ammo; frame_id = p_frame
	off_spec = p_off_spec.duplicate(true) if p_off_spec is Dictionary else null
	arm_mode = str(off_spec.get("kind","gun")) if off_spec!=null else "fist"
	has_bionic = items.has("bionic_arm") or off_spec!=null
	armed = arm_mode=="gun"
	if armed: off_spec.bionic = true
	if body == null: return
	var key = JSON.stringify([items,ammo,frame_id])
	if not _build_cache.has(key):
		var renderer = Art.new(); renderer.configure(items,"laser" if ammo in MELEE_WEAPONS else ammo,frame_id)
		_build_cache[key] = renderer; _build_order.append(key)
		while _build_order.size() > CACHE_LIMIT: _build_cache.erase(_build_order.pop_front())
	art = _build_cache[key]
	gear = null
	if Gear.has_any(items):
		var worn := items.filter(func(id): return id in Gear.WORN); worn.sort()
		var worn_key := JSON.stringify(worn)
		if not _gear_cache.has(worn_key):
			if _gear_cache.size()>CACHE_LIMIT: _gear_cache.clear()
			_gear_cache[worn_key] = Gear.new().build(worn)
		gear = _gear_cache[worn_key]
	if armed and items.has("capacitor"):
		var rear_context: Dictionary = art.weapon_context(off_spec)
		if art.AMMO[rear_context.ammo].id == "laser":
			var rear_items: Array = off_spec.get("items",[]).duplicate()
			if not rear_items.has("capacitor"): rear_items.append("capacitor")
			off_spec.items = rear_items
	muzzle_light.color = AMMO_COL.get(ammo,Color.WHITE)
	if armed:
		var context: Dictionary = art.weapon_context(off_spec)
		off_muzzle_light.color = Color(art.AMMO[context.ammo].col)
	_update()

func set_state(state: Dictionary) -> void:
	for key in state:
		match key:
			"aim": aim = float(state[key])
			"off_aim": off_aim = float(state[key])
			"moving": moving = bool(state[key])
			"walk_phase": walk_phase = float(state[key])
			"recoil": recoil = float(state[key])
			"flash": flash = float(state[key])
			"recoil2": recoil2 = float(state[key])
			"flash2": flash2 = float(state[key])
			"gun_flashes": gun_flashes = state[key].duplicate()
			"capacitor_charge": capacitor_charge = float(state[key])
			"capacitor_charge_off": capacitor_charge_off = float(state[key])
			"time": t = float(state[key]); _external_clock = true
			"dash_dir": dash_dir = state[key]
			"dash_progress": dash_progress = float(state[key])
			"reaction": reaction = String(state[key])
			"reaction_time": reaction_time = float(state[key])
			"sprinting": sprinting = bool(state[key])
			"sprint_dir": sprint_dir = int(state[key])
			"melee_extension": melee_extension = float(state[key])
			"melee_aim": melee_aim = float(state[key])
			"melee_active": melee_active = bool(state[key])
			"melee_reach": melee_reach = float(state[key])
			"primary_melee_reach": primary_melee_reach = float(state[key])
			"firing": firing = bool(state[key])
			"firing2": firing2 = bool(state[key])
			"white": white = bool(state[key])
			"zap": zap = bool(state[key])
			"hook_out": hook_out = bool(state[key])
	if body != null: _update()

func prepare_for_play() -> void:
	# Bake on the wave transition so a first walk, hit or aim change doesn't stall combat.
	for index in [6,7,8,9,10,11,12,13,14,15,16,17,18]:
		art.body_frame(index,has_bionic)
		var hurt = art.body_frame(index,has_bionic,true)
		art.xray_texture(hurt)
	for bend in range(-2,5):
		art.weapon_frame(bend)
		if armed: art.weapon_frame(bend,off_spec,true)
	if has_bionic:
		for step in 9: art.bionic_frame(step/8.0)
	if _native_skin():
		for clip in Scientist.data().clips:
			for index in int(Scientist.data().clips[clip].count):
				Scientist.frame(art.body_frame(6,has_bionic),clip,index,has_bionic,gear)
		art.weapon_frame(1,null,false,true)
		if armed: art.weapon_frame(1,off_spec,true,true)
		for side in ["near","far"]:
			for index in Scientist.data().poses[side].size():
				Scientist.part(side+"_arm",index); Scientist.part(side+"_hand",index)

func shoulder_global() -> Vector2: return gun_pivot.global_position
func off_shoulder_global() -> Vector2: return off_pivot.global_position
func muzzle_global(gun_index: int = 0, shot_index: int = -1) -> Vector2:
	if ammo in MELEE_WEAPONS:
		var points := melee_local_points(true)
		return gun_pivot.to_global(points[points.size()-1])
	# Sample the rendered sprite transform directly, including recoil and large-world precision.
	return gun.to_global(_muzzle_point(_gun_frame,gun_index,shot_index)+WEAPON_PADDING)
func off_muzzle_global(shot_index: int = -1) -> Vector2:
	if _off_frame.is_empty(): return off_shoulder_global()
	return off_gun.to_global(_muzzle_point(_off_frame,0,shot_index)+WEAPON_PADDING)

func _muzzle_point(frame: Dictionary, gun_index: int, shot_index: int) -> Vector2:
	var muzzle: Dictionary = frame.muzzles[clampi(gun_index,0,frame.muzzles.size()-1)]
	var y: float = muzzle.y
	if shot_index>=0: y += muzzle.nozzles[clampi(shot_index,0,muzzle.nozzles.size()-1)]
	return Vector2(muzzle.x,y)
func anchor_global(node_name: String) -> Vector2:
	var marker: Node2D
	if node_name.begins_with("gun."): marker = gun_anchors.get_node_or_null(NodePath(node_name.substr(4)))
	else: marker = body_anchors.get_node_or_null(NodePath(node_name))
	return marker.global_position if marker else global_position
func gun_offset(gun_index: int) -> float:
	var rows: Array = _gun_frame.get("gunY",[0])
	return float(rows[clampi(gun_index,0,rows.size()-1)])

func visual_bounds() -> Rect2:
	var bounds = _sprite_bounds(body,_body_frame.img.get_used_rect())
	if ammo in MELEE_WEAPONS:
		for point in melee_local_points(true): bounds = bounds.expand(to_local(gun_pivot.to_global(point)))
	else: bounds = bounds.merge(_sprite_bounds(gun,_gun_frame.cv.get_used_rect()))
	if armed: bounds = bounds.merge(_sprite_bounds(off_gun,_off_frame.cv.get_used_rect()))
	elif has_bionic and not _bionic_frame.is_empty(): bounds = bounds.merge(_sprite_bounds(bionic,_bionic_frame.cv.get_used_rect()))
	if arm_mode in MELEE_WEAPONS:
		for point in melee_local_points(false): bounds = bounds.expand(to_local(off_pivot.to_global(point)))
	if _native_skin():
		for sprite in [near_arm,near_hand,far_arm,far_hand]:
			if sprite.is_visible_in_tree(): bounds = bounds.merge(_sprite_bounds(sprite,sprite.get_meta("native_bounds")))
	return bounds.grow(3.0)

func _sprite_bounds(sprite: Sprite2D, bounds: Rect2) -> Rect2:
	var transform = global_transform.affine_inverse()*sprite.global_transform
	var result = Rect2(transform*bounds.position,Vector2.ZERO)
	for corner in [Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		result = result.expand(transform*corner)
	return result

func bend_for_aim(angle: float) -> int:
	var up = -sin(angle)
	# up: elbow folds (+1..+4). down: the gun is pulled in (-1 = 3 px, -2 = 6 px at straight down) so the arm isn't too long.
	return clampi(int(floor(1.0+3.0*up+0.5)),-2,4)
func pose_index() -> int:
	if moving: return 11+int(floor(fposmod(walk_phase,1.0)*8.0))
	if fmod(t,3.4) < 0.13: return 10
	return 6+int(t*2.2)%4

func _process(dt: float) -> void:
	if not is_visible_in_tree() or _external_clock: return
	t += dt
	if auto_demo:
		if moving: walk_phase = fposmod(walk_phase+dt*10.7/8.0,1.0)
		_demo_cd -= dt
		if (firing or firing2) and _demo_cd <= 0.0:
			_demo_cd = 0.6
			if firing: recoil = 1.0; flash = 0.08
			if firing2: recoil2 = 1.0; flash2 = 0.08
		recoil = maxf(0.0,recoil-dt*9.0); flash -= dt
		recoil2 = maxf(0.0,recoil2-dt*9.0); flash2 -= dt
	_update()

func _update() -> void:
	if art == null: return
	var native := _native_skin()
	if native:
		if t<_last_native_time:
			_turn_started = t-TURN_TIME; _last_native_time = -1.0;
		# Hold body/arm mirroring near vertical. Otherwise stick noise flips both
		# the body and bent elbow over the head at every crossing of cos(aim)=0.
		if absf(cos(aim))>FACING_HYSTERESIS:
			var desired := 1 if cos(aim)>0.0 else -1
			if desired != _turn_target_face:
				_turn_from_face = face; _turn_target_face = desired; _turn_started = t
		turn_progress = clampf((t-_turn_started)/TURN_TIME,0.0,1.0)
		face = _turn_from_face if turn_progress<0.5 else _turn_target_face
		if absf(cos(off_aim))>FACING_HYSTERESIS: _off_face = 1 if cos(off_aim)>0.0 else -1
	else: face = 1 if cos(aim)>=0.0 else -1
	pose = pose_index()
	primary_arm_view = "far" if native and face<0 else "near"
	secondary_arm_view = "near" if native and face<0 else "far"
	_order_arm_layers(native)
	_body_frame = art.body_frame(6 if native else pose,has_bionic,white or zap)
	if native:
		var clip := "walk" if moving else "idle"; var index := int(floor(t*24.0))
		if sprinting and Scientist.has_clip("run"):
			clip = "run"
			if sprint_dir*face<0: index = -index   # backpedalling
		if is_dashing():
			clip = dash_clip()
			if not Scientist.has_clip(clip): clip = "idle"
			index = mini(int(dash_progress*Scientist.data().clips[clip].count),int(Scientist.data().clips[clip].count)-1)
		_body_frame = Scientist.frame(_body_frame,clip,index,has_bionic or face<0 or is_dashing(),gear)
		if turn_progress>=1.0/3.0 and turn_progress<2.0/3.0 and not is_dashing():
			_body_frame = Scientist.front_frame(_body_frame,moving)
		_last_native_time = t
		_native_near_pose = Scientist.aim_pose(primary_arm_view,aim,recoil,face)
		_native_far_pose = Scientist.aim_pose(secondary_arm_view,off_aim,recoil2,_off_face)
	_gun_frame = art.weapon_frame(1 if native else bend_for_aim(aim),null,false,native)
	var kick = -1.0 if recoil>0.55 or white or zap else 0.0
	body_root.scale.x = 1 if native and _body_frame.get("turn_front",false) else face
	body_root.position = Vector2(kick*face,0)
	body.texture = _body_frame.texture; body.material = null
	if native and firing and not is_dashing() and not _body_frame.get("turn_front",false):
		body.texture = Scientist.shout_texture(_body_frame,3 if int(t*14.0)%2 == 0 else 2)
	body.position = -Scientist.ORIGIN*Scientist.WORLD_SCALE if native else -BODY_PADDING
	body.scale = Vector2.ONE*(Scientist.WORLD_SCALE if native else 1.0)
	if zap:
		if _xray_on():
			var shocked: Texture2D = Scientist.reaction("tazed",t) if native else null
			if shocked == null: shocked = Scientist.xray(_body_frame) if native else art.xray_texture(_body_frame)
			body.texture = shocked; body.material = _unshaded
		else: body.texture = art.tinted_texture(_body_frame,Color("#fff36b"),0.45,"yellow")
	elif white:
		var phase = int(t*20.0)%3
		if phase == 0: body.texture = art.tinted_texture(_body_frame,Color.WHITE,0.85,"white")
		elif phase == 1: body.texture = art.tinted_texture(_body_frame,Color("#ff2020"),0.55,"red")
	for node_name in _body_frame.anchors:
		_marker(body_anchors,node_name).position = _vector(_body_frame.anchors[node_name])-BODY_ORIGIN
	var shoulder = _vector(_body_frame.anchors.shoulderNear if native and face<0 else _body_frame.anchors.shoulderFar)-BODY_ORIGIN
	gun_pivot.position = Vector2((shoulder.x+kick)*face,shoulder.y)
	if native: gun_pivot.position += _shoulder_travel(aim)
	gun_pivot.rotation = aim; gun_pivot.scale = Vector2(1,face if native else (-1 if cos(aim)<0.0 else 1))
	_set_weapon(gun,gun_fx,_gun_frame,recoil)
	if native: _attach_native_gun(gun,gun_fx,_gun_frame,primary_arm_view)
	gun.visible = not ammo in MELEE_WEAPONS
	_update_native_arm(near_arm,near_hand,primary_arm_view,native and gun.visible,recoil)
	if not gun.visible: gun_fx.position = Vector2.ZERO
	for node_name in _gun_frame.anchors:
		_marker(gun_anchors,node_name).position = _vector(_gun_frame.anchors[node_name])+WEAPON_PADDING
	muzzle_light.energy = 2.6 if flash>0.0 and gun.visible else 0.0
	off_pivot.visible = has_bionic; off_gun.visible = armed; bionic.visible = has_bionic and not armed and not arm_mode in ["knife","katana"]
	if armed:
		_off_frame = art.weapon_frame(1 if native else bend_for_aim(off_aim),off_spec,true,native)
		var off_shoulder = _vector(_body_frame.anchors.shoulderFar if native and face<0 else _body_frame.anchors.shoulderNear)-BODY_ORIGIN
		off_pivot.position = Vector2((off_shoulder.x+kick)*face,off_shoulder.y)
		if native: off_pivot.position += _shoulder_travel(off_aim)
		off_pivot.rotation = off_aim; off_pivot.scale = Vector2(1,_off_face if native else (-1 if cos(off_aim)<0.0 else 1))
		_set_weapon(off_gun,off_fx,_off_frame,recoil2)
		if native: _attach_native_gun(off_gun,off_fx,_off_frame,secondary_arm_view)
		off_muzzle_light.position = Vector2(_off_frame.muz,0)+WEAPON_PADDING
		off_muzzle_light.energy = 2.6 if flash2>0.0 else 0.0
	else:
		off_muzzle_light.energy = 0.0; _off_frame = {}
		var shoulder_point = _vector(_body_frame.anchors.shoulderFar if native and face<0 else _body_frame.anchors.shoulderNear)-BODY_ORIGIN
		off_pivot.position = Vector2((shoulder_point.x+kick)*face,shoulder_point.y)
		off_pivot.rotation = melee_aim if melee_active or melee_extension>0.0 else (1.2 if face>0 else PI-1.2)
		off_pivot.scale = Vector2(1,-1 if cos(off_pivot.rotation)<0.0 else 1)
		var extension := 0.125 if arm_mode == "knife" else (0.25 if arm_mode == "katana" else melee_extension)
		_bionic_frame = art.bionic_frame(extension)
		bionic.texture = _bionic_frame.texture; bionic.position = -Vector2(13,17)
		if _xray_on(): bionic.texture = art.tinted_texture(_bionic_frame,Color("#3a68ff"),0.65,"blue")
		off_fx.position = Vector2.ZERO
	_update_native_arm(far_arm,far_hand,secondary_arm_view,native and armed,recoil2)
	rest_pivot.visible = native and face<0 and not has_bionic
	if rest_pivot.visible:
		# Empty off hand: the relaxed drawn arm, never the gun pose without its gun.
		rest_pivot.z_index = 0; rest_hand.visible = false; rest_arm.visible = true
		var stride := fposmod(t*24.0,float(Scientist.data().clips.walk.count))/float(Scientist.data().clips.walk.count)
		rest_pivot.position = off_pivot.position; rest_pivot.scale = Vector2(face,1)
		rest_pivot.rotation = sin(stride*TAU)*0.09*face if moving else 0.0
		rest_arm.texture = Scientist.worn_part("rest_near",-1,gear)
		rest_arm.scale = Vector2.ONE*Scientist.WORLD_SCALE; rest_arm.rotation = 0.0
		rest_arm.position = -Scientist.arm_point("near","shoulder")*Scientist.WORLD_SCALE
		var tint := Color("#7c9bff") if _xray_on() else (Color("#fff36b") if zap else Color.WHITE)
		if white and int(t*20.0)%3 == 0: tint = Color(2,2,2)
		rest_arm.modulate = tint
	if native and turn_progress<1.0:
		gun_pivot.position = _turn_socket(true)+Vector2(kick*face,0)
		off_pivot.position = _turn_socket(false)+Vector2(kick*face,0)
		rest_pivot.position = off_pivot.position
	# Phased: arms and weapons are gone and the body is a translucent energy image.
	var phased := native and is_dashing()
	var posed := native and zap and _xray_on() and Scientist.reaction("tazed",t) != null
	if native and reaction != "" and not phased and not (zap and _xray_on()):
		var pose_texture := Scientist.reaction(reaction,reaction_time)
		if pose_texture != null:
			posed = true; body.texture = pose_texture
			body.material = _unshaded if reaction == "burn" else null
	gun_pivot.visible = not phased and not posed
	if phased or posed: off_pivot.visible = false; rest_pivot.visible = false
	body.self_modulate = Color(AMMO_COL.get(ammo,Color("#9d7bff")).lerp(Color.WHITE,0.45),0.7) if phased else Color.WHITE
	# Depth belongs to the limb, not to an aim-angle fade. The near arm stays
	# foreground; OffPivot already draws the far arm behind the torso and head.
	head_occluder.visible = false
	emissive.queue_redraw(); body_fx.queue_redraw(); gun_fx.queue_redraw(); off_fx.queue_redraw()

## A raised arm lifts its shoulder; a reaching one slides forward. A nailed-down socket reads as a puppet.
func _shoulder_travel(angle: float) -> Vector2:
	var up := -sin(angle)
	return Vector2(cos(angle)*0.8,-1.6*maxf(up,0.0)+0.6*maxf(-up,0.0))

func is_dashing() -> bool: return dash_dir != Vector2.ZERO

func dash_clip() -> String:
	if absf(dash_dir.y)>absf(dash_dir.x)*1.35: return "dash_up" if dash_dir.y<0.0 else "dash_down"
	return "dash_forward" if dash_dir.x*face>=0.0 else "dash_back"

func _native_skin() -> bool:
	return native_scientist and Art.body_skin == "scientist"

func _order_arm_layers(native: bool) -> void:
	# Child order changes depth within this actor without negative/global z values
	# hiding the rear gun behind UI backgrounds or breaking arena actor y-sorting.
	var order: Array = [off_pivot,body_root,gun_pivot,rest_pivot]
	if native and face<0: order = [gun_pivot,body_root,off_pivot,rest_pivot]
	for i in order.size():
		order[i].z_index = 0
		if order[i].get_index()!=i: move_child(order[i],i)

func _turn_socket(primary: bool) -> Vector2:
	var old_side := "near" if (_turn_from_face>0)==primary else "far"
	var new_side := "near" if (_turn_target_face>0)==primary else "far"
	var old_point := (Scientist.arm_point(old_side,"shoulder")-Scientist.ORIGIN)*Scientist.WORLD_SCALE
	var new_point := (Scientist.arm_point(new_side,"shoulder")-Scientist.ORIGIN)*Scientist.WORLD_SCALE
	old_point.x *= _turn_from_face; new_point.x *= _turn_target_face
	var front := (Vector2(39 if primary else 87,53)-Scientist.ORIGIN)*Scientist.WORLD_SCALE
	return old_point.lerp(front,turn_progress*2.0) if turn_progress<0.5 else front.lerp(new_point,(turn_progress-0.5)*2.0)

func _attach_native_gun(sprite: Sprite2D, effects: Node2D, frame: Dictionary, side: String) -> void:
	var pose: Dictionary = _native_near_pose if sprite == gun else _native_far_pose
	var offset := Scientist.grip_offset(side,pose)-_vector(frame.anchors.grip)
	sprite.position += offset; effects.position += offset

func _update_native_arm(arm: Sprite2D, hand: Sprite2D, side: String, enabled: bool, kick: float, override_pose: Dictionary = {}) -> void:
	arm.visible = enabled; hand.visible = enabled
	if not enabled: return
	var pose: Dictionary = override_pose if not override_pose.is_empty() else (_native_near_pose if arm == near_arm else _native_far_pose)
	arm.texture = Scientist.worn_part(side+"_arm",pose.index,gear); hand.texture = Scientist.worn_part(side+"_hand",pose.index,gear)
	arm.set_meta("native_bounds",Scientist.part_bounds(side+"_arm",pose.index))
	hand.set_meta("native_bounds",Scientist.part_bounds(side+"_hand",pose.index))
	var rotation := -float(pose.weapon_angle)
	var start := (-Scientist.pose_point(pose,"shoulder")*Scientist.WORLD_SCALE).rotated(rotation)
	var base := Transform2D(rotation,Vector2.ONE*Scientist.WORLD_SCALE,0.0,start)
	var reach := Scientist.grip_offset(side,pose)
	var length_squared := maxf(1.0,reach.length_squared())
	var pull := roundf(kick*3.0)
	# Recoil moves the hand/gun while leaving the shoulder at the origin. Moving
	# the entire arm image backward was sliding the socket over the lab coat.
	var recoil_warp := Transform2D(Vector2(1.0-pull*reach.x/length_squared,0),Vector2(-pull*reach.y/length_squared,1),Vector2.ZERO)
	arm.transform = recoil_warp*base; hand.transform = arm.transform
	var tint := Color("#7c9bff") if _xray_on() else (Color("#fff36b") if zap else Color.WHITE)
	if white and int(t*20.0)%3 == 0: tint = Color(2,2,2)
	arm.modulate = tint; hand.modulate = tint

func _set_weapon(sprite: Sprite2D, effects: Node2D, frame: Dictionary, kick: float) -> void:
	sprite.texture = frame.texture
	if _xray_on(): sprite.texture = art.tinted_texture(frame,Color("#3a68ff"),0.75,"blue")
	elif white and int(t*20.0)%2 == 0: sprite.texture = art.tinted_texture(frame,Color.WHITE,0.85,"white")
	sprite.position = -WEAPON_PADDING-Vector2(roundf(kick*3.0),0)
	effects.position = Vector2(-roundf(kick*3.0),0)

func _vector(point: Dictionary) -> Vector2: return Vector2(point.x,point.y)
func _xray_on() -> bool: return zap and int(t*14.0)%2 == 0

func _draw_rear_fx() -> void:
	if _body_frame.is_empty(): return
	var p = Pen.new(emissive,-BODY_ORIGIN.x,-BODY_ORIGIN.y)
	if not has_bionic and (not _native_skin() or face>0) and not is_dashing():
		var hand: Dictionary = _body_frame.hand; var color = "#"+AMMO_COL.get(ammo,Color.WHITE).to_html(false)
		var pulse = 1.0+0.2*sin(t*8.0)+(0.35 if firing else 0.0)
		p.alpha = 0.22; p.ell(hand.x,hand.y+1,roundf(4*pulse),roundf(4*pulse),color)
		p.alpha = 0.7; p.ell(hand.x,hand.y+1,2,2,color); p.alpha = 1.0
		p.R(hand.x,hand.y+1,2,2,"#fff")
	if art.CNT.has("boots"):
		for foot in _body_frame.feet:
			var length = randi_range(3,7) if moving else randi_range(1,2)
			p.R(foot.x-1,foot.y+1,3,length,"#ff7a20"); p.R(foot.x,foot.y+1,1,length+1,"#ffd23c")

func _effect_state(off: bool = false) -> Dictionary:
	return {"moving":moving,"firing":firing2 if off else firing,"recoil":recoil2 if off else recoil,"flash":flash2 if off else flash,"hook_out":hook_out and not off,"capacitor_charge":capacitor_charge_off if off else capacitor_charge}
func _draw_body_fx() -> void:
	if _body_frame.is_empty(): return
	var p = Pen.new(body_fx,-BODY_ORIGIN.x,-BODY_ORIGIN.y)
	if not _xray_on():
		for effect in _body_frame.anims: art.draw_effect(p,effect,_effect_state(),t)
	if firing and not white and not zap:
		if _native_skin(): pass   # the shout is part of the body frame
		elif _body_frame.has("skin"): art.draw_skin_shout(p,_body_frame.anchors.mouth,t)
		else: art.draw_shout(Pen.new(body_fx,_body_frame.lean-BODY_ORIGIN.x,_body_frame.bob-BODY_ORIGIN.y),t)
	if zap:
		for node_name in ["head","chest","handOff"]:
			var point = _vector(_body_frame.anchors[node_name])
			for segment in 4:
				var next = point+Vector2(randi_range(-5,5),randi_range(-5,5))
				p.line(point.x,point.y,next.x,next.y,"#fff36b" if segment%2 else "#bff4ff"); point = next

func _draw_weapon_fx(target: Node2D, frame: Dictionary, off: bool) -> void:
	if frame.is_empty(): return
	var p = Pen.new(target)
	if _xray_on():
		var elbow: Dictionary = frame.anchors.elbow; var grip: Dictionary = frame.anchors.grip
		p.line(0,0,elbow.x,elbow.y,"#f6fbff",2); p.line(elbow.x,elbow.y,grip.x,grip.y,"#f6fbff",2)
		p.R(grip.x-1,grip.y-2,4,1,"#f6fbff"); p.R(grip.x-1,grip.y,4,1,"#f6fbff")
	var state = _effect_state(off)
	for effect in frame.anims:
		if effect.k == "muzzle":
			for index in frame.muzzles.size():
				var duration = float(state.flash) if off or gun_flashes.is_empty() else float(gun_flashes[index] if index<gun_flashes.size() else 0.0)
				if duration<=0.0: continue
				var muzzle: Dictionary = frame.muzzles[index]
				var hex = "#"+AMMO_COL.get(muzzle.ammo,Color.WHITE).to_html(false)
				var x: float = muzzle.x; var y: float = muzzle.y
				p.R(x,y-2,5,5,hex); p.R(x+5,y-1,5,3,"#fff"); p.R(x+1,y-5,2,11,hex); p.R(x-1,y-1,3,3,"#fff")
				for nozzle_y in muzzle.nozzles: p.R(x,y+nozzle_y-1,4,3,hex); p.P(x+3,y+nozzle_y,"#fff")
		else: art.draw_effect(p,effect,state,t)
func _draw_gun_fx() -> void:
	if ammo in MELEE_WEAPONS:
		var p = Pen.new(gun_fx)
		var grip := melee_grip_local(true)
		_draw_melee_arm(p,grip,false)
		_draw_melee_weapon(p,grip,ammo,primary_melee_reach,1.0,upright_blade(true))
		_draw_gripping_fist(p,grip,false)
	else: _draw_weapon_fx(gun_fx,_gun_frame,false)
func _draw_off_fx() -> void:
	if not has_bionic: return
	if armed: _draw_weapon_fx(off_fx,_off_frame,true)
	elif not _bionic_frame.is_empty():
		var p = Pen.new(off_fx); var fist: Vector2 = _bionic_frame.fist
		var color = "#ff8060" if arm_mode=="proximity_bomb" else "#73f4ff"
		p.P(fist.x,-3,color)
		if arm_mode=="time_freeze": p.ring(fist.x+2,0,5,color); p.line(fist.x+2,0,fist.x+2,-3,"#fff")
		elif arm_mode=="proximity_bomb": p.ell(fist.x+2,0,4,4,"#242d38"); p.P(fist.x+3,-2,color)
		elif arm_mode=="seeker_rack":
			for i in 3:
				p.R(fist.x-5,-7+i*5,13,4,"#394258"); p.R(fist.x-4,-6+i*5,10,1,"#b8c6d8"); p.R(fist.x+7,-6+i*5,3,2,"#ff70b8")
		elif arm_mode == "shrink_ray":   # violet dish
			p.R(fist.x+5,-3,4,7,"#3a2f4a"); p.ell(fist.x+11,0,3,6,"#c08bff"); p.ell(fist.x+11,0,1,3,"#f3e8ff")
		elif arm_mode == "freeze_ray":   # frosted cryo nozzle
			p.R(fist.x+5,-3,8,7,"#2f4a58"); p.R(fist.x+13,-2,4,5,"#8fe6ff"); p.P(fist.x+15,-1,"#ffffff"); p.P(fist.x+7,-4,"#dff8ff")
		elif arm_mode in MELEE_WEAPONS:
			var grip := melee_grip_local(false)
			if arm_mode in ["knife","katana"]: _draw_melee_arm(p,grip,true)
			_draw_melee_weapon(p,grip,arm_mode,melee_reach,1.0 if arm_mode != "whip" else melee_extension)
			_draw_gripping_fist(p,grip,true)

const MELEE_WEAPONS := ["knife","katana","whip"]
const MELEE_REACH := {"knife":48.0,"katana":84.0,"whip":150.0}

## Like the edited cop baton, the weapon is attached to the palm and exits across the forearm.
## The hand-drawn scientist skin is shorter, so his sword arm is shorter and thinner and the elbow hangs
## below the fist (forearm still upright, crossing the blade) instead of rising over his face.
func _skinned() -> bool: return Art.body_skin != ""

## Scientist katana stance (hand-posed in PixelStudio): fist low and forward, forearm level, blade straight up.
## The blade keeps that 90 degree offset from the aim when cutting, so hits follow the drawn blade.
func upright_blade(primary: bool) -> bool: return primary and _skinned() and ammo == "katana"

func melee_grip_local(primary: bool) -> Vector2:
	if upright_blade(primary): return Vector2(18,7)
	if primary: return Vector2(14,1) if _skinned() else Vector2(22,0)
	return (_bionic_frame.get("fist",Vector2(22,0)) as Vector2)+Vector2(2,0)

func melee_elbow_local(primary: bool) -> Vector2:
	return melee_grip_local(primary)+_elbow_offset(primary)

func _elbow_offset(primary: bool) -> Vector2:
	if upright_blade(primary): return Vector2(-8,0)
	return Vector2(0,7) if _skinned() and primary else Vector2(0,-13)

func _draw_melee_arm(p, grip: Vector2, mechanical: bool) -> void:
	var small := _skinned() and not mechanical
	var elbow := grip+_elbow_offset(not mechanical)
	var widths := [6,4,1] if small else [8,5,1]
	for segment in [[Vector2.ZERO,elbow],[elbow,grip]]:
		var a: Vector2 = segment[0]; var b: Vector2 = segment[1]
		p.line(a.x,a.y,b.x,b.y,"#263b4b" if mechanical else "#526070",widths[0])
		p.line(a.x,a.y-1,b.x,b.y-1,"#819eae" if mechanical else "#d7e3eb",widths[1])
		p.line(a.x,a.y-2,b.x,b.y-2,"#d4e8e8" if mechanical else "#f3f7f8",widths[2])
	if mechanical:
		p.ell(elbow.x,elbow.y,4,4,"#364e60"); p.ell(elbow.x,elbow.y,2,2,"#a9c7d0"); p.P(elbow.x,elbow.y,"#73f4ff")

func _draw_gripping_fist(p, grip: Vector2, mechanical: bool) -> void:
	# Fingers cover the middle of the hilt; the guard and blade exit from the thumb side.
	var x := grip.x; var y := grip.y
	p.box(x-3,y-3,7,7,"#688a9c" if mechanical else "#b27d60")
	p.R(x-2,y-2,5,3,"#c4dce4" if mechanical else "#e5ba92")
	p.line(x-2,y+1,x+2,y+1,"#244c65" if mechanical else "#91634f",1)
	p.R(x+2,y-3,2,3,"#d4e8e8" if mechanical else "#f0cba5")

func _blade_points(kind: String, fist: Vector2, reach: float, extension: float, upright := false) -> PackedVector2Array:
	if reach <= 0.0: reach = MELEE_REACH[kind]
	if upright:
		var base := fist+Vector2(0,-5)
		return PackedVector2Array([base,Vector2(fist.x+1,fist.y-maxf(20.0,reach-fist.x))])
	var start := Vector2(fist.x+(5 if kind == "knife" else 7), -1 if kind == "knife" else 0)
	if kind != "whip": return PackedVector2Array([start,Vector2(reach,-4 if kind == "katana" else -1)])
	var points := PackedVector2Array([start])
	for i in range(1,11):
		var u := i/10.0
		points.append(start+Vector2(maxf(0.0,reach-start.x)*extension*u,sin(u*TAU*1.5+t*30.0)*5.0*u*extension))
	return points

func melee_local_points(primary: bool) -> PackedVector2Array:
	var kind := ammo if primary else arm_mode
	if not kind in MELEE_WEAPONS: return PackedVector2Array()
	var fist := melee_grip_local(primary)
	return _blade_points(kind,fist,primary_melee_reach if primary else melee_reach,1.0 if primary or kind != "whip" else melee_extension,upright_blade(primary))

## This exact centerline is also used by collision and trail sampling.
func melee_sample(primary: bool) -> Dictionary:
	var points := melee_local_points(primary)
	if points.is_empty(): return {}
	var pivot: Node2D = gun_pivot if primary else off_pivot
	var angle := pivot.global_rotation
	var local := PackedVector2Array()
	for point in points: local.append((pivot.to_global(point)-pivot.global_position).rotated(-angle))
	return {"origin":pivot.global_position,"angle":angle,"points":local}

func _draw_melee_weapon(p, fist: Vector2, kind: String, reach: float, extension: float, upright := false) -> void:
	var x := fist.x
	var points := _blade_points(kind,fist,reach,extension,upright)
	var start: Vector2 = points[0]; var tip: Vector2 = points[points.size()-1]
	if upright:
		p.R(x-1,fist.y-3,3,10,"#2a1830"); p.R(x-4,fist.y-5,9,2,"#d4a640")
		p.line(start.x,start.y,tip.x,tip.y,"#b8c4d2",3); p.line(start.x-1,start.y,tip.x-1,tip.y,"#f4f8ff",1)
		p.line(start.x+1,start.y-5,tip.x+1,tip.y+2,"#ff5ad0",1); p.P(tip.x,tip.y,"#ffffff")
		return
	match kind:
		"knife":
			p.R(x-5,-2,9,5,"#3b2a22"); p.R(x+4,-3,1,7,"#a5acb5")
			p.line(start.x,start.y,tip.x,tip.y,"#9aa6b2",3); p.line(start.x,start.y-1,tip.x,tip.y-1,"#f4f8fb",1); p.P(tip.x,tip.y,"#ffffff")
		"katana":
			p.R(x+5,-4,2,9,"#d4a640"); p.R(x-6,-1,11,3,"#2a1830")
			p.line(start.x,start.y,tip.x,tip.y,"#b8c4d2",3); p.line(start.x,start.y-1,tip.x,tip.y-1,"#f4f8ff",1)
			p.line(start.x+5,1,tip.x-2,tip.y+1,"#ff5ad0",1); p.P(tip.x,tip.y,"#ffffff")
		"whip":
			p.R(x-2,-2,4,5,"#5a3a24")
			if extension<=0.0:
				p.ring(x+1,7,4,"#7a4a2a"); p.ring(x+1,7,2,"#7df9ff")
			else:
				var last := start
				for point in points.slice(1):
					p.line(last.x,last.y,point.x,point.y,"#6a4026",3); p.line(last.x,last.y,point.x,point.y,"#7df9ff",1)
					last = point
				p.P(last.x,last.y,"#ffffff")

func _flash_light() -> PointLight2D:
	var light = PointLight2D.new(); light.texture = _light_tex(); light.texture_scale = 0.35
	light.color = AMMO_COL.laser; light.energy = 0.0; light.height = 10.0
	return light
static func _light_tex() -> Texture2D:
	var gradient = Gradient.new(); gradient.set_color(0,Color.WHITE); gradient.set_color(1,Color(1,1,1,0))
	var texture = GradientTexture2D.new(); texture.gradient = gradient; texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5); texture.fill_to = Vector2(1.0,0.5); texture.width = 256; texture.height = 256
	return texture

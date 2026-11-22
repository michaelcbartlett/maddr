extends Node2D
## Self-contained procedural villain. One sprite pixel = one world unit.
## set_items(items, ammo_id, frame_id, off_spec) rebuilds any loadout natively.
## set_state({aim, off_aim, moving, walk_phase, recoil, flash, recoil2, flash2,
##            firing, firing2, white, zap}) drives the rig from gameplay.
## Angles are world-space radians; walk_phase is one stride in 0..1.
const Art = preload("res://character/art_renderer.gd")
const Pen = preload("res://character/pixel_pen.gd")
const BODY_ORIGIN = Vector2(29,46)
const BODY_PADDING = Vector2(30,47)
const WEAPON_PADDING = Vector2(35,59)
const AMMO_COL = {"laser":Color("#ff4a4a"),"bullet":Color("#ffd76a"),"razor":Color("#dfe6ec"),"hook":Color("#7df9ff")}
const CACHE_LIMIT = 6
static var _build_cache: Dictionary = {}
static var _build_order: Array[String] = []

@export var auto_demo := false
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
	off_gun = _sprite("OffGun",off_pivot)
	bionic = _sprite("BionicArm",off_pivot)
	off_fx = _overlay("Effects",off_pivot,_draw_off_fx)
	body_root = Node2D.new(); body_root.name = "Body"; add_child(body_root)
	emissive = _overlay("Emissive",body_root,_draw_rear_fx)
	body = _sprite("Sprite",body_root); body.position = -BODY_PADDING
	body_fx = _overlay("Effects",body_root,_draw_body_fx)
	body_anchors = Node2D.new(); body_anchors.name = "Anchors"; body_root.add_child(body_anchors)
	gun_pivot = Node2D.new(); gun_pivot.name = "GunPivot"; add_child(gun_pivot)
	gun = _sprite("Gun",gun_pivot)
	gun_fx = _overlay("Effects",gun_pivot,_draw_gun_fx)
	gun_anchors = Node2D.new(); gun_anchors.name = "Anchors"; gun.add_child(gun_anchors)
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
		var renderer = Art.new(); renderer.configure(items,ammo,frame_id)
		_build_cache[key] = renderer; _build_order.append(key)
		while _build_order.size() > CACHE_LIMIT: _build_cache.erase(_build_order.pop_front())
	art = _build_cache[key]
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
			"melee_extension": melee_extension = float(state[key])
			"melee_aim": melee_aim = float(state[key])
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

func shoulder_global() -> Vector2: return gun_pivot.global_position
func off_shoulder_global() -> Vector2: return off_pivot.global_position
func muzzle_global(gun_index: int = 0, shot_index: int = -1) -> Vector2:
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
	bounds = bounds.merge(_sprite_bounds(gun,_gun_frame.cv.get_used_rect()))
	if armed: bounds = bounds.merge(_sprite_bounds(off_gun,_off_frame.cv.get_used_rect()))
	elif has_bionic and not _bionic_frame.is_empty(): bounds = bounds.merge(_sprite_bounds(bionic,_bionic_frame.cv.get_used_rect()))
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
	face = 1 if cos(aim)>=0.0 else -1; pose = pose_index()
	_body_frame = art.body_frame(pose,has_bionic,white or zap)
	_gun_frame = art.weapon_frame(bend_for_aim(aim))
	var kick = -1.0 if recoil>0.55 or white or zap else 0.0
	body_root.scale.x = face; body_root.position = Vector2(kick*face,0)
	body.texture = _body_frame.texture; body.material = null
	if zap:
		if _xray_on(): body.texture = art.xray_texture(_body_frame); body.material = _unshaded
		else: body.texture = art.tinted_texture(_body_frame,Color("#fff36b"),0.45,"yellow")
	elif white:
		var phase = int(t*20.0)%3
		if phase == 0: body.texture = art.tinted_texture(_body_frame,Color.WHITE,0.85,"white")
		elif phase == 1: body.texture = art.tinted_texture(_body_frame,Color("#ff2020"),0.55,"red")
	for node_name in _body_frame.anchors:
		_marker(body_anchors,node_name).position = _vector(_body_frame.anchors[node_name])-BODY_ORIGIN
	var shoulder = _vector(_body_frame.anchors.shoulderFar)-BODY_ORIGIN
	gun_pivot.position = Vector2((shoulder.x+kick)*face,shoulder.y)
	gun_pivot.rotation = aim; gun_pivot.scale = Vector2(1,-1 if cos(aim)<0.0 else 1)
	_set_weapon(gun,gun_fx,_gun_frame,recoil)
	for node_name in _gun_frame.anchors:
		_marker(gun_anchors,node_name).position = _vector(_gun_frame.anchors[node_name])+WEAPON_PADDING
	muzzle_light.energy = 2.6 if flash>0.0 else 0.0
	off_pivot.visible = has_bionic; off_gun.visible = armed; bionic.visible = has_bionic and not armed
	if armed:
		_off_frame = art.weapon_frame(bend_for_aim(off_aim),off_spec,true)
		var off_shoulder = _vector(_body_frame.anchors.shoulderNear)-BODY_ORIGIN
		off_pivot.position = Vector2((off_shoulder.x+kick)*face,off_shoulder.y)
		off_pivot.rotation = off_aim; off_pivot.scale = Vector2(1,-1 if cos(off_aim)<0.0 else 1)
		_set_weapon(off_gun,off_fx,_off_frame,recoil2)
		off_muzzle_light.position = Vector2(_off_frame.muz,0)+WEAPON_PADDING
		off_muzzle_light.energy = 2.6 if flash2>0.0 else 0.0
	else:
		off_muzzle_light.energy = 0.0; _off_frame = {}
		var shoulder_point = _vector(_body_frame.anchors.shoulderNear)-BODY_ORIGIN
		off_pivot.position = Vector2((shoulder_point.x+kick)*face,shoulder_point.y)
		off_pivot.rotation = melee_aim if melee_extension>0.0 else (1.2 if face>0 else PI-1.2)
		off_pivot.scale = Vector2(1,-1 if cos(off_pivot.rotation)<0.0 else 1)
		_bionic_frame = art.bionic_frame(melee_extension)
		bionic.texture = _bionic_frame.texture; bionic.position = -Vector2(13,17)
		if _xray_on(): bionic.texture = art.tinted_texture(_bionic_frame,Color("#3a68ff"),0.65,"blue")
		off_fx.position = Vector2.ZERO
	emissive.queue_redraw(); body_fx.queue_redraw(); gun_fx.queue_redraw(); off_fx.queue_redraw()

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
	if not has_bionic:
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
		art.draw_shout(Pen.new(body_fx,_body_frame.lean-BODY_ORIGIN.x,_body_frame.bob-BODY_ORIGIN.y),t)
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
func _draw_gun_fx() -> void: _draw_weapon_fx(gun_fx,_gun_frame,false)
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
		elif arm_mode in MELEE_WEAPONS: _draw_melee_weapon(p,fist)

const MELEE_WEAPONS := ["knife","katana","whip"]
## Blades are held past the bionic fist; the whip uncoils to its full 150px reach mid-swing.
func _draw_melee_weapon(p, fist: Vector2) -> void:
	var x := fist.x+7
	match arm_mode:
		"knife":
			p.R(x-1,-2,3,5,"#3b2a22")
			p.line(x+2,0,x+15,-1,"#9aa6b2",3); p.line(x+2,-1,x+15,-1,"#f4f8fb",1); p.P(x+16,-1,"#ffffff")
		"katana":
			p.R(x-1,-4,2,9,"#d4a640"); p.R(x-6,-1,5,3,"#2a1830")
			p.line(x+1,0,x+40,-3,"#b8c4d2",3); p.line(x+1,-1,x+40,-4,"#f4f8ff",1)
			p.line(x+6,1,x+38,-2,"#ff5ad0",1); p.P(x+41,-4,"#ffffff")
		"whip":
			p.R(x-2,-2,4,5,"#5a3a24")
			if melee_extension<=0.0:
				p.ring(x+1,7,4,"#7a4a2a"); p.ring(x+1,7,2,"#7df9ff")
			else:
				var length := (150.0-fist.x-7.0)*melee_extension
				var last := Vector2(x+2,0)
				for i in range(1,11):
					var u := i/10.0
					var point := Vector2(x+2+length*u,sin(u*TAU*1.5+t*30.0)*5.0*u)
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

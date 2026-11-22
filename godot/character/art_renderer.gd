extends RefCounted
## Native procedural art, ported from villain.js. Godot owns subsequent art changes.
## Each instance describes one build; frames and normal maps are shared by the rig cache.
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Profiles = preload("res://character/height_profiles.gd")
const VG = {"w":60,"h":68,"cx":29,"cy":46,"sx":25,"sy":30,"ox":35,"oy":29}
const WG = {"w":230,"h":96,"px":34,"py":58}
const WBEND0 = 1
var CNT = {}
var build = {}
var AMMO = []
var FRAMES = []
var ITEMS = []
var S = {}
var D = {}
var bodies = {}
var weapons = {}
var off_weapons = {}
var bionic_frames = {}
static var _definitions: Dictionary = {}

func configure(item_ids: Array, ammo_id: String, frame_id: String) -> void:
	if _definitions.is_empty():
		_definitions = JSON.parse_string(FileAccess.get_file_as_string("res://character/art/gear.json"))
	AMMO = _definitions.ammo; FRAMES = _definitions.frames; ITEMS = _definitions.items
	build = {"ammo": _index(AMMO, ammo_id), "frame": _index(FRAMES, frame_id), "items": item_ids.duplicate()}
	for id in item_ids: CNT[id] = CNT.get(id, 0) + 1
	var context = weapon_context(build)
	S = {"guns": context.guns, "rangeAdd": context.rangeAdd}
	D = {"width": context.width, "shots": context.shots}

func _index(table: Array, value) -> int:
	if value is int or value is float: return clampi(int(value), 0, table.size() - 1)
	for i in table.size():
		if table[i].id == value: return i
	return 0

func worn_core() -> String:
	for i in range(build.items.size() - 1, -1, -1):
		if str(build.items[i]).begins_with("core_"): return str(build.items[i]).substr(5)
	return ""

func weapon_context(spec = null) -> Dictionary:
	if spec == null:
		return {"cnt": CNT, "ammo": build.ammo, "frame": build.frame, "guns": S.guns, "rangeAdd": S.rangeAdd, "width": D.width, "shots": D.shots}
	var counts = {}; var stats = {"rangeAdd":0.0,"width":10.0,"widthPct":0.0,"shots":1.0,"guns":[]}
	var ai = _index(AMMO, spec.get("ammo", 0)); var fi = _index(FRAMES, spec.get("frame", 0))
	_apply_visual(stats, AMMO[ai]); _apply_visual(stats, FRAMES[fi])
	for id in spec.get("items", []):
		counts[id] = counts.get(id, 0) + 1
		for item in ITEMS:
			if item.id == id: _apply_visual(stats, item); break
	return {"cnt":counts,"ammo":ai,"frame":fi,"guns":[AMMO[ai].id] + stats.guns,"rangeAdd":stats.rangeAdd,"width":stats.width * (1.0 + stats.widthPct),"shots":min(9, stats.shots)}

func _apply_visual(stats: Dictionary, definition: Dictionary) -> void:
	for key in definition.get("set", {}):
		if stats.has(key): stats[key] = definition.set[key]
	for key in definition.get("add", {}):
		if stats.has(key): stats[key] += definition.add[key]
	if definition.has("gun"): stats.guns.append(definition.gun)

func body_frame(index: int, armed: bool, hurt: bool = false) -> Dictionary:
	var key = "%d/%s/%s" % [index, armed, hurt]
	if not bodies.has(key):
		var pose = pose_at(index); pose.hurt = hurt
		var frame = render_body(pose, {"armed":armed})
		frame.texture = _texture(frame.img, frame.depth)
		bodies[key] = frame
	return bodies[key]

func weapon_frame(bend: int, spec = null, off: bool = false) -> Dictionary:
	var cache = off_weapons if off else weapons
	var key = str(bend) + "/" + JSON.stringify(spec)
	if not cache.has(key):
		var frame = render_weapon(bend, spec, off)
		var context = weapon_context(spec)
		var flare = clampi(int(js_round(context.width/3.0)),2,22)
		var nozzles: Array = []
		for i in int(context.shots):
			nozzles.append(js_round(-(flare-1)+2.0*(flare-1)*i/(context.shots-1)) if context.shots>1 else 0.0)
		frame.muzzles = [{"x":frame.muz,"y":0.0,"ammo":context.guns[0],"nozzles":nozzles}]
		for i in range(1,context.guns.size()):
			# Extra hardware ends at the barrel cap (or the saw's forward tooth).
			var x = frame.anchors.barrelEnd.x+(8.0 if context.guns[i]=="razor" else 0.0)
			frame.muzzles.append({"x":x,"y":frame.gunY[i],"ammo":context.guns[i],"nozzles":[0.0]})
		frame.texture = _texture(frame.cv, frame.depth)
		cache[key] = frame
	return cache[key]

func _texture(image: Image, pixels) -> CanvasTexture:
	var texture = CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.normal_texture = ImageTexture.create_from_image(pixels.normal_image())
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return texture

func bionic_frame(extension: float) -> Dictionary:
	var step = clampi(roundi(extension*8.0),0,8)
	if bionic_frames.has(step): return bionic_frames[step]
	var amount = step/8.0
	var pixels = Pixels.new(86,48); var p = Pen.new(pixels,12,16)
	var elbow = Vector2(7+amount*16,6*(1-amount)); var fist = Vector2(16+amount*42,0)
	p.layer(10,Profiles.dome(0,0,4,4,3)); p.ell(0,0,4,4,"#364e60"); p.ell(0,0,2,2,"#a9c7d0")
	for segment in [[Vector2.ZERO,elbow],[elbow,fist]]:
		var start: Vector2 = segment[0]; var finish: Vector2 = segment[1]
		p.layer(12,Profiles.cap(start.x,start.y,finish.x,finish.y,3,3))
		p.line(start.x,start.y,finish.x,finish.y,"#263b4b",7)
		p.line(start.x,start.y-1,finish.x,finish.y-1,"#819eae",5)
		p.line(start.x,start.y-2,finish.x,finish.y-2,"#d4e8e8",1)
	p.layer(15,Profiles.dome(elbow.x,elbow.y,3,3,2)); p.ell(elbow.x,elbow.y,3,3,"#4d6f80"); p.P(elbow.x,elbow.y,"#80e9ff")
	p.layer(17,Profiles.slab(fist.x-3,-5,fist.x+7,5,3,2)); p.box(fist.x-3,-5,11,11,"#688a9c")
	p.R(fist.x+4,-4,3,9,"#c4dce4"); p.R(fist.x-1,-4,2,8,"#244c65"); p.P(fist.x,-3,"#73f4ff")
	var image = pixels.outlined_image()
	var result = {"cv":image,"texture":_texture(image,pixels),"fist":fist,"step":step}
	bionic_frames[step] = result
	return result

const WALK_X = [5,3,0,-3,-5,-3,0,3]
const WALK_LIFT = [0,0,0,0,0,2,3,2]
const WALK_BOB = [0,1,1,0,0,1,1,0]
func _walk_key(values: Array, phase: float) -> float:
	var f = fposmod(phase, 1.0) * 8.0; var i = int(floor(f)); var weight = f - i
	return lerpf(values[i], values[(i + 1) % 8], weight)

func pose_at(index: int) -> Dictionary:
	if index < 6 or index >= 11:
		var phase = index / 6.0 if index < 6 else (index - 11) / 8.0
		var front = _walk_key(WALK_X, phase); var back = _walk_key(WALK_X, phase + 0.5)
		var bob = js_round(_walk_key(WALK_BOB, phase))
		return {"aF":js_round(front),"aB":js_round(back),"lF":js_round(_walk_key(WALK_LIFT, phase)),"lB":js_round(_walk_key(WALK_LIFT, phase + 0.5)),"bob":bob,"swing":-js_round(front * 0.5),"tail":-1-bob,"hair":js_round(_walk_key(WALK_BOB, phase - 0.125))-bob,"lean":1,"walk":true,"heelF":front<=-4,"heelB":back<=-4}
	var idle = 0 if index == 10 else index - 6
	return {"aF":0,"aB":0,"lF":0,"lB":0,"bob":1 if idle>=2 else 0,"swing":1 if idle==1 or idle==2 else 0,"tail":-1 if idle>=2 else 0,"hair":1 if idle==2 else (-1 if idle==3 else 0),"lean":0,"breath":idle==1 or idle==2,"blink":index==10}

static func truth(value) -> bool:
	if value == null: return false
	if value is bool: return value
	if value is int or value is float: return value != 0
	if value is String: return value != ""
	return true

static func getv(value, key):
	if value is Dictionary: return value.get(key, null)
	if value is Array: return value[int(key)] if int(key) >= 0 and int(key) < value.size() else null
	if value is Object:
		if key == "globalAlpha": return value.alpha
		return value.get(key)
	return null

static func js_round(value) -> float: return floor(float(value) + 0.5)

static func merge(target: Dictionary, first: Dictionary, second: Dictionary = {}) -> Dictionary:
	target.merge(first, true); target.merge(second, true)
	return target

static func sum_width(values: Array) -> float:
	var result = 0.0
	for item in values: result += item.wv.w * 2 + 2
	return result

static func shade(hex: String, amount: float) -> String:
	return Pixels.shade(hex, amount)

func tinted_texture(frame: Dictionary, color: Color, weight: float, key: String) -> CanvasTexture:
	if frame.has(key): return frame[key]
	var original: Image = frame.get("img", frame.get("cv"))
	var image = original.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			var pixel = original.get_pixel(x,y)
			if pixel.a == 0: continue
			image.set_pixel(x,y,pixel.lerp(Color(color,pixel.a),weight))
	var texture = CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.normal_texture = frame.texture.normal_texture
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame[key] = texture
	return texture

func xray_texture(frame: Dictionary) -> Texture2D:
	if frame.has("xray"): return frame.xray
	if not frame.pose.get("hurt",false):
		var hurt = render_body(merge(frame.pose.duplicate(),{"hurt":true}),frame.opt)
		frame.xray = xray_texture(hurt)
		return frame.xray
	var original: Image = frame.img
	var size = original.get_size()
	var pixels = Pixels.new(size.x,size.y)
	for y in size.y:
		for x in size.x:
			if original.get_pixel(x,y).a == 0: continue
			var rim = false
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbor = Vector2i(x,y)+delta
				if neighbor.x<0 or neighbor.y<0 or neighbor.x>=size.x or neighbor.y>=size.y or original.get_pixelv(neighbor).a == 0:
					rim = true; break
			var color = Color("#96f0ff") if rim else Color("#2848c8")
			color.a = original.get_pixel(x,y).a
			pixels.image.set_pixel(x,y,color)
	var p = Pen.new(pixels,1,1)
	var a: Dictionary = frame.anchors
	var bone = func(start: Dictionary, finish: Dictionary, width = 2): p.line(start.x,start.y,finish.x,finish.y,"#f6fbff",width)
	bone.call(a.shoulderFar,a.shoulderNear,1); bone.call(a.neck,a.hip)
	var y = a.neck.y+1
	while y < a.hip.y: p.P(a.neck.x-1,y,"#a8c4ff"); y += 3
	for rib in 4:
		y = a.chest.y-5+rib*3; p.R(a.chest.x-7+rib,y,13-2*rib,1,"#f6fbff"); p.P(a.neck.x,y,"#a8c4ff")
	p.R(a.hip.x-4,a.hip.y-1,9,2,"#f6fbff"); p.P(a.hip.x-4,a.hip.y+1,"#f6fbff"); p.P(a.hip.x+4,a.hip.y+1,"#f6fbff")
	for side in ["Back","Front"]:
		var hip = {"x":a.hip.x+(-3 if side=="Back" else 2),"y":a.hip.y}
		bone.call(hip,a["knee"+side]); bone.call(a["knee"+side],a["foot"+side])
		var foot = a["foot"+side]; p.R(foot.x-2,foot.y-1,5,1,"#f6fbff")
	if not frame.opt.armed:
		bone.call(a.shoulderNear,a.elbowOff); bone.call(a.elbowOff,a.handOff)
		p.P(a.handOff.x+1,a.handOff.y+1,"#f6fbff"); p.P(a.handOff.x-1,a.handOff.y+1,"#f6fbff")
	var head = a.head
	p.ell(head.x+1,head.y-1,6,6,"#f6fbff"); p.R(head.x-1,head.y+4,8,3,"#f6fbff")
	p.R(a.eyeFar.x-1,a.eyeFar.y-1,3,3,"#0c1440"); p.R(a.eyeNear.x-1,a.eyeNear.y-1,3,3,"#0c1440")
	p.P(a.nose.x-1,a.nose.y+1,"#0c1440"); p.P(a.nose.x-2,a.nose.y+1,"#0c1440"); p.R(a.mouth.x-3,a.mouth.y,7,1,"#0c1440")
	for x in range(int(a.mouth.x-3),int(a.mouth.x+4),2): p.P(x,a.mouth.y,"#f6fbff")
	p.P(head.x-3,head.y-4,"#a8c4ff"); p.P(head.x+3,head.y-5,"#a8c4ff")
	frame.xray = ImageTexture.create_from_image(pixels.image)
	return frame.xray

func skin_palette():
	var mut = ((getv(CNT, "mutagen") if truth(getv(CNT, "mutagen")) else 0) > 0)
	return ({"s": "#8fcf5a", "L": "#d2f08e", "D": "#4f9a4e", "DD": "#2c5e4c", "mut": mut} if truth(mut) else {"s": "#e8a070", "L": "#fcd4a2", "D": "#c06a52", "DD": "#86404a", "mut": mut})

func coat_palette():
	var lvl = (getv(CNT, "coat") if truth(getv(CNT, "coat")) else 0)
	return ({"c": "#c2c8d2", "L": "#e8eae4", "M": "#a2a8c4", "D": "#7e84aa", "DD": "#4e5278", "lvl": lvl} if truth(lvl) else {"c": "#eceef4", "L": "#fffcf2", "M": "#ced2ea", "D": "#a6a8d2", "DD": "#6c6c9e", "lvl": lvl})

## Paint body layers back to front, recording height alongside albedo.
func render_body(pose, opt = {}):
	var c = Pixels.new(getv(VG, "w"), getv(VG, "h"))
	var g = c
	var Z = c
	var b = getv(pose, "bob")
	var ln = (getv(pose, "lean") if truth(getv(pose, "lean")) else 0)
	var U = Pen.new(g, ln, b)
	var Lg = Pen.new(g, 0, 0)
	var n = func(id = null):
		return (getv(CNT, id) if truth(getv(CNT, id)) else 0)
	var core = worn_core()
	var anims = []
	var feet = []
	var A = func(o = null):
		anims.append(merge(o, {"x": (getv(o, "x") + ln), "y": (getv(o, "y") + b), "x2": ((getv(o, "x2") + ln) if truth((getv(o, "x2") != null)) else null), "y2": ((getv(o, "y2") + b) if truth((getv(o, "y2") != null)) else null)}))
	var sk = skin_palette()
	var mut = getv(sk, "mut")
	var skin = getv(sk, "s")
	var skinL = getv(sk, "L")
	var skinD = getv(sk, "D")
	var skinDD = getv(sk, "DD")
	var icy = (n.call("zero") > 0)
	var hairC = ("#c8ecff" if truth(icy) else "#a8a8c0")
	var hairL = ("#f4fbff" if truth(icy) else "#eceae2")
	var hairD = ("#6e98d8" if truth(icy) else "#6a6894")
	var hairDD = ("#3e62a8" if truth(icy) else "#3e3c66")
	var cp = coat_palette()
	var lvl = getv(cp, "lvl")
	var coat = getv(cp, "c")
	var coatL = getv(cp, "L")
	var coatM = getv(cp, "M")
	var coatD = getv(cp, "D")
	var coatDD = getv(cp, "DD")
	var shirt = "#9fb8dc"
	var shirtD = "#6c82c0"
	var shirtL = "#d2e2ee"
	var pants = "#8c5260"
	var pantsD = "#5e3450"
	var pantsL = "#b47676"
	var boots = (n.call("boots") > 0)
	var hasPack = (not truth((not truth((((core if truth(core) else n.call("magnet")) if truth((core if truth(core) else n.call("magnet"))) else n.call("remote")) if truth(((core if truth(core) else n.call("magnet")) if truth((core if truth(core) else n.call("magnet"))) else n.call("remote"))) else n.call("moon"))))))
	var AN = {}
	var an = func(k = null, x = null, y = null, raw = null):
		AN[k] = {"x": (x + (0 if truth(raw) else ln)), "y": (y + (0 if truth(raw) else b))}
	an.call("head", 29, 15)
	an.call("helmet", 29, 6)
	an.call("brow", 32, 12)
	an.call("eyeFar", 30, 15)
	an.call("eyeNear", 34, 15)
	an.call("nose", 37, 16)
	an.call("mouth", 33, 21)
	an.call("ear", 25, 17)
	an.call("neck", 29, 25)
	an.call("chest", 31, 34)
	an.call("belt", 31, 43)
	an.call("hip", 29, 46)
	an.call("back", 20, 33)
	an.call("backpack", 12, 36)
	an.call("shoulderFar", getv(VG, "sx"), getv(VG, "sy"))
	an.call("shoulderNear", getv(VG, "ox"), getv(VG, "oy"))
	var torsoP = func(x_2 = null, y_2 = null):
		var r = (6 if truth((y_2 < 29)) else min(12, (8.5 + max(0, ((y_2 - 38) / float(4))))))
		var u = ((x_2 - 29.5) / float((r + 0.5)))
		var d = (1 - (u * u))
		return ((((5 * sqrt(d)) if truth((d > 0)) else 0) - (((30 - y_2) * 0.7) if truth((y_2 < 30)) else 0)) - (((y_2 - 46) * 0.25) if truth((y_2 > 46)) else 0))
	if truth(n.call("syringe")):
		U.layer(2, Profiles.cylV(27, 11, 3))
		var y_3 = 27
		while truth((y_3 <= 56)):
			var t = ((y_3 - 27) / float(29))
			var xl = js_round(((21 - (t * 8)) + (getv(pose, "tail") if truth((y_3 > 44)) else 0)))
			var xr = js_round((37 + (t * 3)))
			U.R(xl, y_3, (xr - xl), 1, "#7a1020")
			U.R(xl, y_3, 2, 1, "#540814")
			if truth((fmod((y_3 + getv(pose, "tail")), 6) == 0)):
				U.R((xl + 2), y_3, 3, 1, "#8e1828")
			if truth((fmod(y_3, 5) == 2)):
				U.P((xl + 5), y_3, "#9a2030")
			y_3 += 1
		var x_3 = (13 + getv(pose, "tail"))
		while truth((x_3 < 40)):
			U.R(x_3, 57, 2, 1, "#540814")
			x_3 += 3
		U.layer(4, Profiles.cylV(20.5, 1.5, 1.5))
		U.R(19, 19, 3, 9, "#a01828")
		U.R(20, 20, 1, 7, "#e03848")
		U.layer(4, Profiles.cylV(38.5, 1.5, 1.5))
		U.R(37, 19, 3, 9, "#a01828")
		U.R(38, 20, 1, 7, "#e03848")
	if truth((core == "isotope")):
		U.layer(5, Profiles.slab(7, 24, 17, 26, 1.5, 1))
		U.box(7, 24, 11, 3, "#8a8a8a")
		U.P(8, 24, "#c8c8c8")
		U.layer(4, Profiles.cylV(12, 6.5, 4))
		U.R(6, 27, 13, 18, "#24342a")
		U.layer(5, Profiles.cylV(12, 5.5, 4.5))
		U.R(7, 29, 11, 15, "#4dc81a")
		U.R(7, 29, 11, 2, "#8dff4a")
		U.R(8, 31, 2, 12, "#b8ff80")
		U.P(8, 31, "#f0ffe0")
		U.R(16, 31, 1, 12, "#3a9a14")
		U.R(7, 31, 1, 12, "#2e8a10")
		U.layer(5, Profiles.slab(7, 45, 17, 47, 1.5, 1))
		U.box(7, 45, 11, 3, "#8a8a8a")
		U.layer(6, Profiles.dome(12.5, 24.5, 2, 1, 1))
		U.R(11, 25, 3, 1, "#ffd23c")
		U.P(12, 24, "#ffd23c")
		U.layer(4, Profiles.cylV(12, 6.5, 4))
		for yy in [33, 38]:
			U.R(6, yy, 13, 1, "#2a3a2e")
		U.layer(6, Profiles.cap(18, 33, 21, 34, 1, 1))
		U.line(18, 33, 21, 34, "#3a3a3a", 2)
		A.call({"k": "tank", "x": 7, "y": 31, "w": 11, "h": 13, "c": "#e0ffc8"})
		A.call({"k": "pulse", "x": 12, "y": 37, "r": 5, "c": "#7dff3a", "a": 0.18})
	else:
		if truth((core == "hamster")):
			U.layer(4, Profiles.slab(18, 34, 21, 36, 1, 1))
			U.R(18, 34, 4, 3, "#666")
			U.R(18, 34, 4, 1, "#888")
			U.layer(3, Profiles.cylV(7, 1, 1))
			U.R(6, 44, 2, 5, "#666")
			U.layer(3, Profiles.cylV(16, 1, 1))
			U.R(15, 44, 2, 5, "#666")
			U.layer(3, Profiles.cylH(48, 0.5, 0.5))
			U.R(5, 48, 13, 1, "#555")
			U.layer(4, Profiles.dome(11, 35, 9, 9, 2))
			U.ring(11, 35, 9, "#8a8e96")
			U.ring(11, 35, 8, "#5a5e66")
			A.call({"k": "wheel", "x": 11, "y": 35, "r": 9})
		else:
			if truth((core == "battery")):
				U.layer(4, Profiles.slab(5, 29, 19, 45, 4, 3))
				U.box(5, 29, 15, 17, "#26282c")
				U.R(5, 29, 15, 3, "#c83030")
				U.R(5, 29, 15, 1, "#ff6a6a")
				U.R(6, 32, 1, 13, "#3a3e44")
				U.R(18, 32, 1, 13, "#18191c")
				U.layer(6, Profiles.dome(8, 27, 1.5, 1.5, 1.5))
				U.box(7, 26, 3, 3, "#c83030")
				U.P(8, 27, "#fff")
				U.layer(6, Profiles.dome(16, 27, 1.5, 1.5, 1.5))
				U.box(15, 26, 3, 3, "#9aa4ae")
				U.P(16, 27, "#222")
				U.layer(8.5, Profiles.slab(8, 36, 16, 40, 0.6, 1))
				U.R(8, 36, 9, 5, "#ffd23c")
				U.R(10, 37, 3, 1, "#26282c")
				U.R(12, 38, 3, 1, "#26282c")
				U.R(11, 39, 2, 1, "#26282c")
				A.call({"k": "spark", "x": 8, "y": 25})
				A.call({"k": "spark", "x": 16, "y": 25})
			else:
				if truth((core == "brain")):
					U.layer(5, Profiles.slab(5, 22, 19, 24, 1.5, 1))
					U.box(5, 22, 15, 3, "#7a7a7a")
					U.layer(4, Profiles.cylV(12, 7.5, 5))
					U.R(5, 25, 15, 20, "#5fa6b8")
					U.R(6, 26, 13, 18, "#9ed8e6")
					U.R(6, 26, 2, 18, "#dcf4fa")
					U.R(18, 26, 1, 18, "#78b8c8")
					U.layer(5, Profiles.dome(12, 34, 5, 4, 4))
					U.ell(12, 34, 5, 4, "#ff8fb0")
					U.R(9, 32, 1, 4, "#d0607e")
					U.R(12, 31, 1, 5, "#d0607e")
					U.R(15, 33, 1, 3, "#d0607e")
					U.R(10, 30, 4, 1, "#ffc0d4")
					U.R(12, 38, 1, 5, "#e07090")
					U.layer(5, Profiles.slab(5, 45, 19, 47, 1.5, 1))
					U.box(5, 45, 15, 3, "#7a7a7a")
					A.call({"k": "jar", "x": 7, "y": 27, "w": 11, "h": 16})
					A.call({"k": "pulse", "x": 12, "y": 34, "r": 4, "c": "#ff8fb0", "a": 0.15})
	if truth((((n.call("magnet") if truth(n.call("magnet")) else n.call("remote")) if truth((n.call("magnet") if truth(n.call("magnet")) else n.call("remote"))) else n.call("moon")) if truth((not truth(core))) else (not truth(core)))):
		U.layer(4, Profiles.slab(8, 27, 17, 41, 3, 2))
		U.box(8, 27, 10, 15, "#5a5e66")
		U.R(9, 30, 8, 1, "#3a3e46")
		U.R(9, 35, 8, 1, "#3a3e46")
		U.P(16, 29, "#3f3")
	if truth(n.call("magnet")):
		U.layer(3, Profiles.slab(2, 9, 13, 21, 2.5, 2))
		U.R(2, 9, 4, 12, "#d83030")
		U.R(10, 9, 4, 12, "#d83030")
		U.R(2, 18, 12, 4, "#d83030")
		U.R(2, 9, 1, 13, "#ff7a7a")
		U.R(10, 9, 1, 9, "#ff7a7a")
		U.R(2, 21, 12, 1, "#8a1818")
		U.layer(4, Profiles.slab(2, 7, 13, 9, 1.5, 1))
		U.box(2, 7, 4, 3, "#e8e8f0")
		U.box(10, 7, 4, 3, "#e8e8f0")
		U.layer(4, Profiles.cylV(7.5, 1, 1))
		U.R(7, 22, 2, 3, "#555")
		A.call({"k": "spark", "x": 8, "y": 5, "c": "#8fd8ff"})
	if truth(n.call("remote")):
		U.layer(5, Profiles.cap(18, 25, 20, 6, 1, 0.8))
		U.line(18, 25, 20, 6, "#8a8a8a")
		U.R(17, 24, 3, 2, "#333")
		A.call({"k": "led", "x": 20, "y": 5, "c": "#ff3030"})
	if truth(n.call("moon")):
		U.layer(4, Profiles.cap(9, 24, 8, 13, 1, 1))
		U.line(9, 24, 8, 13, "#777", 2)
		U.layer(5, Profiles.cylH(11.5, 2, 1.5))
		U.R(1, 12, 14, 1, "#e8e8f0")
		U.R(2, 11, 12, 1, "#c8c8d0")
		U.R(4, 10, 8, 1, "#a8a8b0")
		U.R(2, 13, 12, 1, "#8a8a92")
		U.R(7, 6, 2, 4, "#888")
		A.call({"k": "led", "x": 7, "y": 5, "c": "#ff3030"})
	# Hair silhouette and strands.
	var spL = [1, 3, 4, 6, 8, 9, 8, 10, 11, 10, 12, 11, 9, 10, 8, 9, 7, 5, 4, 2, 1]
	var hb = (2 if truth(getv(pose, "hurt")) else getv(pose, "hair"))
	U.layer(9, Profiles.dome(23, 14, 11, 11, 6))
	var i = 0
	while truth((i < spL.size())):
		var y_4 = (4 + i)
		var x0 = ((23 - getv(spL, i)) - (hb if truth(((i > 3) if truth((fmod(i, 3) == 0)) else (fmod(i, 3) == 0))) else 0))
		U.R(x0, y_4, (26 - x0), 1, hairC)
		U.R(22, y_4, 4, 1, hairD)
		U.P(x0, y_4, (hairL if truth(fmod(i, 2)) else hairD))
		if truth((getv(spL, i) > 3)):
			U.R((x0 + 3), y_4, 2, 1, hairD)
			U.P((x0 + 1), y_4, hairL)
			U.P((x0 + 6), y_4, hairL)
		i += 1
	var i_2 = 0
	while truth((i_2 < spL.size())):
		var y_5 = (5 + i_2)
		U.R(((23 - getv(spL, i_2)) + 2), y_5, 4, 1, hairDD)
		i_2 += 4
	var spR = [2, 4, 5, 7, 6, 4, 3, 2]
	U.layer(10, Profiles.dome(35, 8, 6, 5, 4))
	var i_3 = 0
	while truth((i_3 < spR.size())):
		var y_6 = (4 + i_3)
		var dx = (hb if truth(((i_3 <= 4) if truth((i_3 >= 2)) else (i_3 >= 2))) else 0)
		U.R(32, y_6, ((getv(spR, i_3) + 3) + dx), 1, hairC)
		U.P(((34 + getv(spR, i_3)) + dx), y_6, hairL)
		U.P(33, y_6, hairD)
		if truth((getv(spR, i_3) > 4)):
			U.P(36, y_6, hairL)
		i_3 += 1
	U.layer(12, null)
	U.line(25, 8, (22 - hb), 2, hairC)
	U.line(28, 7, 28, (1 + abs(hb)), hairC)
	U.line(31, 7, (33 + hb), 2, hairC)
	U.line(26, 8, (24 - hb), 4, hairD)
	U.P((22 - hb), 2, hairL)
	U.P(28, (1 + abs(hb)), hairL)
	U.P((33 + hb), 2, hairL)
	# Legs and shoes follow the stride anchors.
	var seg = func(P = null, x0_2 = null, y0 = null, x1 = null, y1 = null, pc = null, pcD = null, pcL = null):
		var n2 = max(1, (y1 - y0))
		var y_7 = y0
		while truth((y_7 <= y1)):
			var x_4 = js_round((x0_2 + (((x1 - x0_2) * (y_7 - y0)) / float(n2))))
			P.R((x_4 - 2), y_7, 5, 1, pc)
			P.P((x_4 - 2), y_7, pcD)
			P.P((x_4 + 2), y_7, pcL)
			y_7 += 1
	var leg = func(hx = null, ax = null, lift = null, back = null):
		var pc_2 = (pantsD if truth(back) else pants)
		var pcD_2 = ("#3c2240" if truth(back) else pantsD)
		var pcL_2 = (pants if truth(back) else pantsL)
		var baseValue = (6 if truth(back) else 13)
		var hipY = (46 + b)
		var fy = (58 - lift)
		var fx = (hx + ax)
		var ky = 50
		var kx = js_round(((hx + (ax * 0.45)) + (1.5 if truth(lift) else 0)))
		var heel = (getv(pose, "heelB") if truth(back) else getv(pose, "heelF"))
		var nm = ("Back" if truth(back) else "Front")
		an.call(("knee" + nm), kx, ky, 1)
		an.call(("foot" + nm), (fx + 1), (fy + 3), 1)
		Lg.layer(baseValue, Profiles.cap(hx, hipY, kx, ky, 2.5, 2.5))
		seg.call(Lg, hx, hipY, kx, ky, pc_2, pcD_2, pcL_2)
		Lg.layer(baseValue, Profiles.cap(kx, ky, fx, (fy - 1), 2.5, 2.5))
		seg.call(Lg, kx, ky, fx, (fy - 1), pc_2, pcD_2, pcL_2)
		Lg.R((fx - 2), (fy - 1), 5, 1, pcD_2)
		var toe = ((-1) if truth((lift > 0)) else 0)
		if truth(boots):
			var bc = ("#a01e1e" if truth(back) else "#c82828")
			Lg.layer((baseValue + 1), Profiles.dome((fx + 1), fy, 4.5, 3, 2.5))
			Lg.box((fx - 3), (fy - 3), 8, 6, bc)
			Lg.R((fx - 3), (fy - 3), 8, 1, ("#d04a4a" if truth(back) else "#ff6a6a"))
			Lg.R((fx + 4), ((fy - 1) + toe), 2, 3, bc)
			Lg.P((fx + 5), ((fy - 1) + toe), ("#d04a4a" if truth(back) else "#ff6a6a"))
			Lg.layer(baseValue, Profiles.cylV((fx - 4.5), 1, 1))
			Lg.box((fx - 5), (fy - 2), 2, 4, "#5a5a5a")
			Lg.layer(baseValue, null)
			Lg.R((fx - 3), (fy + 3), 9, 1, "#2a2a2a")
			Lg.layer((baseValue + 2), null)
			Lg.P(fx, (fy - 1), "#ffd23c")
			feet.append({"x": (fx - 4), "y": (fy + 2)})
		else:
			var sc = ("#c0c0d6" if truth(back) else "#eeeef6")
			var scL = ("#dcdce8" if truth(back) else "#fffcf2")
			var scD = ("#9494b8" if truth(back) else "#babad6")
			Lg.layer((baseValue + 1), Profiles.dome((fx + 1), (fy + 1), 4.5, 2.5, 2.5))
			Lg.R((fx - 3), fy, 7, 1, sc)
			Lg.R((fx - 3), (fy + 1), 9, 2, sc)
			Lg.R((fx + 4), (fy + toe), 2, 1, sc)
			Lg.R((fx - 2), fy, 5, 1, scL)
			Lg.R((fx + 3), ((fy + 1) + toe), 2, 1, scL)
			Lg.R((fx - 3), (fy + 1), 1, 2, scD)
			Lg.P((fx + 5), (fy + 2), scD)
			Lg.P((fx - 1), fy, "#9aa4c0")
			Lg.P((fx + 1), fy, "#9aa4c0")
			Lg.P(fx, (fy + 1), "#9aa4c0")
			Lg.layer(baseValue, null)
			if truth(heel):
				Lg.R((fx - 1), (fy + 3), 7, 1, "#7c7c98")
				Lg.clearRect((fx - 3), (fy + 2), 2, 1)
				Lg.R((fx - 3), (fy + 2), 2, 1, "#5e5e80")
			else:
				Lg.R((fx - 3), (fy + 3), 9, 1, "#7c7c98")
				Lg.R((fx - 3), (fy + 3), 3, 1, "#5e5e80")
			feet.append({"x": (fx - 3), "y": (fy + 2)})
	leg.call(26, getv(pose, "aB"), getv(pose, "lB"), true)
	leg.call(31, getv(pose, "aF"), getv(pose, "lF"), false)
	# The off arm sits behind the coat; the armed body leaves it to the off gun.
	var ax0 = getv(VG, "ox")
	var ay0 = getv(VG, "oy")
	var hx_2 = (40 + getv(pose, "swing"))
	var hy = 41
	var ex = (38 + js_round((getv(pose, "swing") / float(2))))
	var ey = 35
	an.call("elbowOff", ex, ey)
	an.call("handOff", hx_2, (hy + 1))
	if truth((not truth(getv(opt, "armed")))):
		for tuple in [[ax0, ay0, ex, ey], [ex, ey, hx_2, (hy - 2)]]:
			var x0_3 = tuple[0]
			var y0_2 = tuple[1]
			var x1_2 = tuple[2]
			var y1_2 = tuple[3]
			U.layer(9, Profiles.cap(x0_3, y0_2, x1_2, y1_2, 2.5, 2.5))
			U.line(x0_3, y0_2, x1_2, y1_2, coatDD, 5)
		for tuple_2 in [[ax0, ay0, ex, ey], [ex, ey, hx_2, (hy - 2)]]:
			var x0_4 = tuple_2[0]
			var y0_3 = tuple_2[1]
			var x1_3 = tuple_2[2]
			var y1_3 = tuple_2[3]
			U.layer(9, Profiles.cap(x0_4, y0_3, x1_3, y1_3, 2.5, 2.5))
			U.line(x0_4, y0_3, x1_3, y1_3, coatM, 3)
			U.line((x0_4 - 1), (y0_3 + 1), (x1_3 - 1), y1_3, coatD, 1)
			U.line((x0_4 + 1), (y0_3 - 1), (x1_3 + 1), (y1_3 - 1), coat, 1)
		U.layer(9, Profiles.dome(ex, ey, 2, 2, 2.5))
		U.P((ex - 1), (ey + 1), coatD)
		U.P((ex - 2), ey, coatD)
		U.layer(9, Profiles.cap((hx_2 - 1), (hy - 2), (hx_2 + 1), (hy - 2), 1.5, 2))
		U.R((hx_2 - 2), (hy - 2), 5, 2, coatM)
		U.R((hx_2 - 2), (hy - 2), 5, 1, coat)
		U.P((hx_2 - 2), (hy - 1), coatD)
		if truth(n.call("orb")):
			U.lift(0.8)
			U.R((hx_2 - 2), (hy - 4), 4, 2, "#c99a3a")
			U.R((hx_2 - 2), (hy - 4), 4, 1, "#ffe08a")
			U.P(hx_2, (hy - 4), "#7dff3a")
			U.lift(0)
		U.layer(10, Profiles.dome(hx_2, (hy + 1), 2, 2, 2))
		U.box((hx_2 - 1), hy, 3, 3, skin)
		U.P(hx_2, hy, skinL)
		U.P((hx_2 - 1), (hy + 2), skinD)
	else:
		U.layer(9, Profiles.dome(ax0, ay0, 2.5, 2.5, 2.5))
		U.ell(ax0, (ay0 + 1), 2, 2, coatM)
		U.P(ax0, ay0, coat)
	U.layer(12, torsoP)
	var y_8 = 27
	while truth((y_8 <= 51)):
		var xl_2 = null
		var xr_2 = null
		if truth((y_8 == 27)):
			xl_2 = 24
			xr_2 = 34
		else:
			if truth((y_8 == 28)):
				xl_2 = 22
				xr_2 = 36
			else:
				xl_2 = (21 - max(0, floor(((y_8 - 38) / float(4)))))
				xr_2 = (37 + max(0, floor(((y_8 - 40) / float(5)))))
		if truth(((y_8 <= 40) if truth(((y_8 >= 29) if truth(getv(pose, "breath")) else getv(pose, "breath"))) else ((y_8 >= 29) if truth(getv(pose, "breath")) else getv(pose, "breath")))):
			xr_2 += 1
		if truth((y_8 >= 46)):
			xl_2 += getv(pose, "tail")
		if truth((y_8 == 51)):
			xl_2 += 1
			xr_2 -= 1
		if truth((y_8 <= 28)):
			U.R(xl_2, y_8, ((xr_2 - xl_2) + 1), 1, coatM)
			U.R((xl_2 + 2), y_8, ((xr_2 - xl_2) - 3), 1, (coatL if truth((y_8 == 27)) else coat))
			y_8 += 1
			continue
		U.R(xl_2, y_8, (29 - xl_2), 1, coat)
		U.R(33, y_8, (xr_2 - 32), 1, coat)
		U.P(xl_2, y_8, coatDD)
		U.R((xl_2 + 1), y_8, 2, 1, coatD)
		U.P((xl_2 + 3), y_8, coatM)
		U.P(33, y_8, coatM)
		U.P((xr_2 - 1), y_8, coatL)
		U.P(xr_2, y_8, coatM)
		if truth((y_8 >= 44)):
			U.lift((-0.9))
			U.P(((25 + ((-1) if truth((y_8 > 48)) else 0)) + (getv(pose, "tail") if truth((y_8 >= 46)) else 0)), y_8, coatM)
			U.P((35 + (1 if truth((y_8 > 49)) else 0)), y_8, coatM)
			U.lift(0)
		if truth(((int(y_8) & int(1)) if truth(((y_8 <= 37) if truth((y_8 >= 31)) else (y_8 >= 31))) else ((y_8 <= 37) if truth((y_8 >= 31)) else (y_8 >= 31)))):
			U.lift((-0.5))
			U.P((24 + (1 if truth((y_8 > 34)) else 0)), y_8, coatM)
			U.lift(0)
		if truth((y_8 >= 47)):
			U.P(28, y_8, coatD)
			U.P(33, y_8, coatD)
		y_8 += 1
	U.R((22 + getv(pose, "tail")), 51, 7, 1, coatDD)
	U.R(33, 51, 5, 1, coatDD)
	U.R((23 + getv(pose, "tail")), 50, 5, 1, coatD)
	U.R(33, 50, 4, 1, coatM)
	U.R(22, 29, 3, 1, coatM)
	U.lift((-0.6))
	U.R(29, 28, 4, 16, shirt)
	U.R(29, 28, 1, 16, shirtD)
	U.R(32, 29, 1, 13, shirtL)
	for yy_2 in [31, 35, 39]:
		U.P(31, yy_2, "#5a70a0")
	U.lift(0.6)
	U.R(28, 26, 2, 3, "#dce8fa")
	U.R(32, 26, 2, 3, "#dce8fa")
	U.P(29, 28, "#9ab0d8")
	U.P(33, 26, "#ffffff")
	U.lift(0.3)
	U.R(29, 42, 4, 2, "#3a2818")
	U.R(30, 42, 2, 2, "#c9a227")
	U.P(30, 42, "#fff0a0")
	U.R(29, 44, 4, 3, pants)
	U.P(29, 44, pantsD)
	U.lift(1)
	U.R(27, 28, 2, 8, coatD)
	U.R(28, 28, 1, 7, coatL)
	U.R(33, 28, 1, 8, coatD)
	U.R(34, 29, 1, 5, coatL)
	U.P(28, 35, coatM)
	U.lift(0.4)
	U.R(22, 42, 5, 1, coatD)
	U.R(22, 43, 1, 3, coatM)
	U.R(34, 38, 3, 1, coatD)
	U.lift(1.2)
	U.R(34, 35, 1, 3, "#3a6ad8")
	U.R(35, 34, 1, 4, "#d83a3a")
	U.P(34, 35, "#8ab0ff")
	U.P(35, 34, "#ff9a9a")
	U.lift(0)
	if truth(lvl):
		U.lift(0.4)
		for tuple_3 in [[24, 31], [24, 37], [24, 43], [36, 37], [36, 43], [26, 49]]:
			var x_5 = tuple_3[0]
			var y_9 = tuple_3[1]
			U.P(x_5, y_9, "#4a4a52")
		U.lift(0)
		U.R(25, 29, 1, 22, shade(coat, (-0.12)))
	if truth((lvl >= 2)):
		U.layer(15, Profiles.dome(23, 27, 4, 3, 2.5))
		U.box(19, 25, 8, 5, "#6a7282")
		U.P(21, 26, "#aab")
		U.P(24, 26, "#aab")
		U.R(20, 25, 6, 1, "#9aa2b2")
		U.layer(12, torsoP)
	if truth((lvl >= 3)):
		U.lift(1.5)
		U.box(28, 29, 6, 11, "#7a8292")
		U.R(29, 30, 4, 1, "#9aa2b2")
		U.P(29, 31, "#444")
		U.P(32, 31, "#444")
		U.P(29, 37, "#444")
		U.P(32, 37, "#444")
		U.lift(0)
	if truth(hasPack):
		U.lift(0.8)
		U.R(21, 28, 2, 12, "#4a3424")
		U.R(21, 28, 1, 12, "#5e4430")
		U.R(21, 33, 2, 2, "#c9a227")
		U.P(21, 33, "#fff0a0")
		U.lift(0)
	if truth(n.call("bleed")):
		U.lift(0.1)
		for tuple_4 in [[25, 35], [26, 36], [24, 37], [35, 40], [36, 41], [36, 39], [24, 48], [34, 47], [35, 48]]:
			var x_6 = tuple_4[0]
			var y_10 = tuple_4[1]
			U.P(x_6, y_10, "#a01020")
		U.lift(0)
	if truth(n.call("acid")):
		U.lift(0.1)
		U.R(22, 49, 3, 2, "#b8c830")
		U.R(35, 45, 2, 3, "#b8c830")
		U.P(23, 50, "#1a1a1a")
		U.P(36, 46, "#1a1a1a")
		U.P(24, 46, "#d8e840")
		U.lift(0)
	if truth(n.call("nuke")):
		U.lift(1)
		U.box(23, 36, 5, 5, "#ffd23c")
		U.P(25, 38, "#222")
		U.P(24, 37, "#222")
		U.P(26, 37, "#222")
		U.P(25, 39, "#222")
		U.lift(0)
	if truth(n.call("hypno")):
		U.layer(15, Profiles.dome(25, 46, 2, 2, 1.5))
		U.ell(25, 46, 2, 2, "#9a40d0")
		U.P(25, 46, "#fff")
		U.P(26, 45, "#f0c8ff")
		U.P(24, 47, "#f0c8ff")
		U.layer(12, torsoP)
	if truth(n.call("reactor")):
		U.layer(17, Profiles.dome(31, 34, 3, 3, 2))
		U.ell(31, 34, 3, 3, "#2f6a2a")
		U.ell(31, 34, 2, 2, "#7dff3a")
		U.P(31, 34, "#e8ffe0")
		U.P(30, 33, "#c8ffb0")
		U.layer(12, torsoP)
		A.call({"k": "pulse", "x": 31, "y": 34, "r": 3, "c": "#7dff3a", "a": 0.35})
	if truth(n.call("grenade")):
		U.lift(1.2)
		U.line(24, 28, 35, 45, "#5a4020", 2)
		U.line(25, 28, 36, 45, "#7a5a30")
		for t_2 in [0.25, 0.5, 0.75]:
			var x_7 = js_round((24 + (11 * t_2)))
			var y_11 = js_round((28 + (17 * t_2)))
			U.lift(2.2)
			U.ell((x_7 + 1), y_11, 1, 2, "#4a6a2a")
			U.P((x_7 + 1), (y_11 - 1), "#6a8a3a")
			U.P((x_7 + 1), (y_11 - 3), "#ccc")
		U.lift(0)
	if truth(n.call("greed")):
		U.lift(1)
		U.line(25, 27, 31, 33, "#e8c030")
		U.line(31, 33, 36, 27, "#e8c030")
		U.layer(16, Profiles.dome(31, 35, 2, 2, 1.5))
		U.ell(31, 35, 2, 2, "#ffd23c")
		U.P(31, 35, "#b08a18")
		U.P(30, 34, "#fff6c0")
		U.layer(12, torsoP)
	var belt = []
	if truth(n.call("serum")):
		belt.append("#7dff3a")
	if truth(n.call("acid")):
		belt.append("#e8f040")
	if truth(n.call("poison")):
		belt.append("#3ad83a")
	if truth(n.call("virus")):
		belt.append("#b0d030")
	if truth((belt.size() if truth(belt.size()) else n.call("clock"))):
		U.lift(1)
		U.R(33, 42, 10, 2, "#3a2818")
		U.R(33, 42, 10, 1, "#5a4028")
		var x_8 = 34
		for col in belt:
			U.layer(15, Profiles.cylV((x_8 + 0.5), 1, 1.2))
			U.R(x_8, 44, 2, 5, col)
			U.P(x_8, 44, shade(col, 0.5))
			U.P(x_8, 45, shade(col, 0.3))
			U.R(x_8, 48, 2, 1, shade(col, (-0.3)))
			U.R(x_8, 43, 2, 1, "#d8d8e0")
			U.R(x_8, 42, 2, 1, "#a07040")
			x_8 += 3
		if truth(n.call("clock")):
			U.layer(15, Profiles.dome((x_8 + 2), 46, 2, 2, 1.5))
			U.ell((x_8 + 2), 46, 2, 2, "#eee")
			U.P(x_8, 43, "#c33")
			U.P((x_8 + 4), 43, "#c33")
			U.P((x_8 + 2), 46, "#222")
			U.R(x_8, 48, 5, 1, "#c8302a")
			A.call({"k": "clock", "x": (x_8 + 2), "y": 46})
		U.layer(12, torsoP)
	U.layer(13, Profiles.cylV(29, 3, 2))
	U.R(26, 22, 6, 6, skinD)
	U.R(27, 22, 4, 5, skin)
	U.P(30, 23, skinL)
	U.layer(16, Profiles.dome(29, 15, 7, 8, 7))
	U.ell(29, 15, 7, 8, skin)
	U.R(22, 11, 2, 10, skinD)
	U.R(23, 9, 1, 2, skinD)
	U.R(22, 13, 1, 6, skinDD)
	U.R(24, 8, 2, 1, skinD)
	U.ell(31, 10, 3, 2, skinL)
	U.P(30, 9, "#fff8f0")
	U.P(32, 9, "#fff8f0")
	U.P(34, 11, skinL)
	U.R(25, 21, 11, 3, skin)
	U.R(25, 23, 11, 1, skinD)
	U.R(25, 21, 1, 2, skinD)
	U.lift(0.6)
	U.R(24, 15, 3, 5, skinD)
	U.R(25, 16, 1, 3, skinDD)
	U.P(26, 15, skin)
	U.lift(0)
	U.lift((-0.5))
	U.R(29, 11, 1, 1, skinD)
	U.R(31, 10, 3, 1, skinD)
	U.P(28, 12, skinD)
	U.lift(0)
	if truth(mut):
		U.line(26, 9, 27, 13, skinDD)
		U.P(33, 8, skinDD)
		U.P(34, 9, skinDD)
		U.ell(25, 11, 1, 1, skinL)
	U.lift((-1.6))
	U.R(28, 13, 4, 1, skinDD)
	U.R(33, 13, 3, 1, skinDD)
	U.R(28, 14, 1, 3, skinD)
	U.R(29, 17, 3, 1, skinD)
	U.R(33, 17, 3, 1, skinD)
	U.P(36, 14, skinD)
	U.lift((-1.2))
	U.R(29, 14, 3, 3, "#1c1214")
	U.R(33, 14, 3, 3, "#1c1214")
	if truth(getv(pose, "blink")):
		U.lift((-1))
		U.R(29, 14, 3, 3, skinD)
		U.R(33, 14, 3, 3, skinD)
		U.R(29, 16, 3, 1, skinDD)
		U.R(33, 16, 3, 1, skinDD)
	else:
		if truth((n.call("hypno") if truth(n.call("hypno")) else n.call("hive"))):
			U.P(30, 15, "#d07bff")
			U.P(31, 15, "#fff")
			U.P(34, 15, "#d07bff")
			U.P(35, 15, "#fff")
		else:
			U.P(31, 15, "#ffffff")
			U.P(35, 15, "#ffffff")
			U.P(30, 16, "#5a3a3a")
			U.P(34, 16, "#5a3a3a")
	U.lift(0.2)
	U.P(32, 15, skin)
	U.lift(1.4)
	U.R(27, 12, 3, 1, hairC)
	U.R(29, 13, 3, 1, hairC)
	U.R(33, 13, 2, 1, hairC)
	U.R(34, 12, 3, 1, hairC)
	U.P(27, 11, hairL)
	U.P(36, 11, hairL)
	U.P(30, 13, hairD)
	U.P(34, 13, hairD)
	U.lift(0)
	if truth(getv(pose, "hurt")):
		U.lift((-1.2))
		U.R(29, 14, 3, 3, skinD)
		U.R(33, 14, 3, 3, skinD)
		U.R(29, 15, 3, 1, "#1c1214")
		U.R(33, 15, 3, 1, "#1c1214")
		U.P(28, 16, skinDD)
		U.P(36, 16, skinDD)
		U.lift(1.4)
		U.R(28, 13, 3, 1, hairC)
		U.R(33, 13, 3, 1, hairC)
		U.P(31, 12, hairC)
		U.P(32, 12, hairC)
		U.lift(0)
	if truth(n.call("disint")):
		U.layer(19, Profiles.dome(34, 15, 2.5, 2.5, 2))
		U.R(32, 13, 5, 5, "#6a6a72")
		U.R(32, 13, 5, 1, "#9a9aa2")
		U.R(33, 14, 3, 3, "#ff2a2a")
		U.P(34, 15, "#ffd0d0")
		U.P(36, 13, "#aaa")
		A.call({"k": "pulse", "x": 34, "y": 15, "r": 2, "c": "#ff2a2a", "a": 0.4})
		U.layer(16, Profiles.dome(29, 15, 7, 8, 7))
	if truth(n.call("monocle")):
		var mx = (29 if truth(n.call("telescope")) else 31)
		var my = 15
		var br = "#c9a227"
		var brL = "#ffe08a"
		var brD = "#8a6a18"
		var brDD = "#5a4210"
		U.layer(21, Profiles.dome(mx, my, 5.5, 5.5, 2.2))
		U.ell(mx, my, 5, 5, brD)
		U.ell(mx, my, 4, 4, br)
		U.P((mx - 3), (my - 3), brL)
		U.P((mx - 2), (my - 4), brL)
		U.P((mx - 4), (my - 2), brL)
		U.P((mx - 1), (my - 5), brL)
		U.P((mx + 3), (my + 3), brDD)
		U.P((mx + 4), (my + 2), brDD)
		U.P((mx + 2), (my + 4), brDD)
		U.P((mx + 5), my, brDD)
		U.P(mx, (my + 5), brDD)
		U.P((mx + 4), (my - 3), br)
		U.P((mx - 5), (my + 1), brD)
		U.layer(21.5, Profiles.dome(mx, my, 3.5, 3.5, 3.2))
		U.ell(mx, my, 3, 3, "#9ccbe0")
		U.R((mx - 2), (my - 1), 4, 3, "#1c1214")
		U.R((mx - 1), (my - 2), 2, 1, "#1c1214")
		if truth(((not truth(getv(pose, "hurt"))) if truth((not truth(getv(pose, "blink")))) else (not truth(getv(pose, "blink"))))):
			U.R(mx, (my - 1), 2, 2, "#ffffff")
			U.P((mx - 1), (my + 1), "#5a3a3a")
		else:
			U.R((mx - 2), my, 4, 1, "#c06a52")
		U.P((mx - 2), (my - 2), "#e8f8ff")
		U.P((mx - 1), (my - 3), "#ffffff")
		U.P((mx - 3), (my - 1), "#e8f8ff")
		U.P((mx + 2), (my + 2), "#6a9ab8")
		U.P((mx + 1), (my + 2), "#7aaac8")
		U.layer(19, null)
		var i_4 = 0
		while truth((i_4 <= 8)):
			var t_3 = (i_4 / float(8))
			var x_9 = js_round(((mx - 4) - (3 * t_3)))
			var y_12 = js_round(((my + 4) + (8 * t_3)))
			U.P(x_9, y_12, (brD if truth(fmod(i_4, 2)) else br))
			if truth((fmod(i_4, 2) == 0)):
				U.P((x_9 + 1), y_12, brL)
			i_4 += 1
		U.layer(17, Profiles.dome(24, 28, 1, 1, 1))
		U.R(23, 27, 2, 2, br)
		U.P(23, 27, brL)
		U.layer(16, Profiles.dome(29, 15, 7, 8, 7))
		A.call({"k": "glint", "x": (mx - 2), "y": (my - 3)})
	if truth(n.call("telescope")):
		var ey_2 = 15
		var br_2 = "#c9a227"
		var brL_2 = "#ffe08a"
		var brD_2 = "#8a6a18"
		var st = "#9aa4ae"
		var stL = "#d4dce4"
		var stD = "#5f6872"
		var lth = "#4a3424"
		var lthL = "#6a4a30"
		U.layer(16, Profiles.dome(29, 15, 7, 8, 7))
		U.lift(1)
		U.line(33, 12, 23, 10, lth, 2)
		U.line(33, 12, 24, 9, lthL)
		U.R(25, 9, 2, 3, br_2)
		U.P(25, 9, brL_2)
		U.line(33, 18, 24, 19, lth)
		U.lift(0)
		U.layer(22, Profiles.dome(34, ey_2, 2.5, 2.5, 2))
		U.ell(34, ey_2, 2, 2, brD_2)
		U.R(33, (ey_2 - 1), 3, 3, "#1c1214")
		U.P(33, (ey_2 - 2), brL_2)
		U.layer(23, Profiles.cylH(ey_2, 2.5, 2.5))
		U.R(36, (ey_2 - 2), 4, 5, br_2)
		U.R(36, (ey_2 - 2), 4, 1, brL_2)
		U.R(36, (ey_2 + 2), 4, 1, brD_2)
		U.R(39, (ey_2 - 2), 1, 5, brD_2)
		U.P(37, (ey_2 - 1), "#fff4c0")
		U.layer(24, Profiles.cylH(ey_2, 1.5, 2))
		U.R(40, (ey_2 - 1), 2, 3, st)
		U.R(40, (ey_2 - 1), 2, 1, stL)
		U.R(40, (ey_2 + 1), 2, 1, stD)
		U.layer(24.5, Profiles.cylH(ey_2, 1.5, 2))
		U.R(42, (ey_2 - 1), 1, 3, br_2)
		U.P(42, (ey_2 - 1), brL_2)
		U.layer(25, Profiles.dome(43, ey_2, 0.5, 1.5, 1.5))
		U.R(43, (ey_2 - 1), 1, 3, "#9ccbe0")
		U.P(43, (ey_2 - 1), "#ffffff")
		an.call("telescopeTip", 44, ey_2)
		A.call({"k": "tscope", "x": 40, "y": ey_2})
	U.layer(20, Profiles.dome(37, 16, 2, 3, 2.5))
	U.R(36, 14, 2, 5, skin)
	U.R(38, 16, 1, 3, skin)
	U.R(36, 18, 3, 1, skinD)
	U.P(37, 18, skinDD)
	U.P(37, 14, skinL)
	U.P(37, 15, skinL)
	U.P(38, 17, skinD)
	U.layer(16, Profiles.dome(29, 15, 7, 8, 7))
	U.P(35, 19, skinD)
	U.lift((-1))
	U.R(30, 20, 6, 2, "#3a1010")
	U.R(31, 20, 4, 1, "#f0ece0")
	U.P(33, 20, "#c8c0b0")
	if truth(getv(pose, "hurt")):
		U.R(30, 20, 6, 2, "#f0ece0")
		U.R(30, 22, 6, 1, "#3a1010")
		U.P(31, 20, "#8a6a6a")
		U.P(33, 21, "#8a6a6a")
		U.P(35, 20, "#8a6a6a")
	if truth(n.call("greed")):
		U.P(33, 20, "#ffd23c")
	if truth(n.call("syringe")):
		U.P(31, 21, "#fff")
		U.P(34, 21, "#fff")
	U.layer(18, Profiles.dome(32, 22, 5.5, 3, 2.5))
	U.R(29, 19, 8, 1, hairC)
	U.P(29, 20, hairC)
	U.P(36, 20, hairC)
	U.R(28, 22, 9, 2, hairC)
	U.R(29, 24, 7, 1, hairD)
	U.R(27, 20, 2, 3, hairC)
	U.P(28, 24, hairD)
	U.P(31, 25, hairD)
	U.P(34, 25, hairC)
	U.P(36, 24, hairD)
	U.R(28, 23, 9, 1, hairD)
	U.R(29, 22, 7, 1, hairC)
	U.P(30, 22, hairL)
	U.P(33, 22, hairL)
	U.P(35, 22, hairL)
	U.P(30, 19, hairL)
	U.P(34, 19, hairL)
	U.P(27, 21, hairD)
	if truth(n.call("poison")):
		U.layer(17, Profiles.dome(31, 26, 4, 2, 2))
		U.ell(31, 26, 4, 2, "#3a5a3a")
		U.R(28, 25, 7, 1, "#4a6a4a")
		U.layer(19, Profiles.cylV(36.5, 1.5, 1.5))
		U.box(35, 24, 3, 4, "#2a2a2a")
		U.P(36, 25, "#7dff3a")
		U.layer(17, null)
		U.P(26, 26, "#222")
	U.layer(21, null)
	U.R(22, 7, 2, 4, hairC)
	U.P(23, 6, hairL)
	U.R(35, 6, 1, 3, hairC)
	U.P(24, 8, hairD)
	U.P(22, 10, hairD)
	if truth((core == "isotope")):
		U.P(14, 9, "#9dff4a")
		U.P(12, 15, "#9dff4a")
		U.P(13, 16, "#9dff4a")
		U.P(37, 6, "#9dff4a")
		U.P(38, 7, "#9dff4a")
	if truth(n.call("thermite")):
		for tuple_5 in [[14, 9], [11, 15], [15, 21], [(22 - hb), 2], [28, 1], [(33 + hb), 2], [38, 6]]:
			var x_10 = tuple_5[0]
			var y_13 = tuple_5[1]
			A.call({"k": "flame", "x": x_10, "y": y_13})
	if truth((core == "battery")):
		U.layer(20, null)
		U.line(8, 25, 9, 15, "#d02020")
		U.line(9, 15, 23, 14, "#d02020")
		U.layer(21, Profiles.dome(24, 14, 1, 1.5, 1))
		U.box(23, 13, 2, 3, "#c83030")
		U.layer(20, null)
		U.line(16, 25, 19, 19, "#222")
		U.line(19, 19, 23, 19, "#222")
		U.layer(21, Profiles.dome(24, 19, 1, 1, 1))
		U.box(23, 18, 2, 2, "#555")
	if truth((core == "brain")):
		U.layer(20, null)
		U.line(16, 22, 17, 13, "#3a8ad0")
		U.line(17, 13, 23, 12, "#3a8ad0")
		U.layer(21, Profiles.dome(24, 12, 1, 1, 1))
		U.box(23, 11, 2, 2, "#aaa")
	if truth(n.call("goggles")):
		U.layer(22, Profiles.cylH(9.5, 1, 1))
		U.R(22, 9, 15, 2, "#3a3a3a")
		U.R(22, 9, 15, 1, "#5a5a5a")
		for ex_2 in [29, 34]:
			U.layer(23, Profiles.dome(ex_2, 9, 2, 2, 2))
			U.ell(ex_2, 9, 2, 2, "#5a3a1a")
			U.R((ex_2 - 1), 8, 3, 3, "#ffb030")
			U.P((ex_2 - 1), 8, "#fff")
			U.P((ex_2 + 1), 10, "#c06a10")
	if truth(n.call("tesla")):
		U.layer(20, null)
		U.line(24, 8, 20, 1, "#9a9aa4")
		U.R(23, 6, 2, 1, "#c97a3a")
		U.layer(21, Profiles.dome(20, 1, 1, 1, 1))
		U.ell(20, 1, 1, 1, "#fff36b")
		A.call({"k": "spark", "x": 20, "y": 1})
	if truth(n.call("storm")):
		U.layer(20, null)
		U.line(34, 7, 38, 1, "#9a9aa4")
		U.R(35, 5, 2, 1, "#c97a3a")
		U.layer(21, Profiles.dome(38, 1, 1, 1, 1))
		U.ell(38, 1, 1, 1, "#fff36b")
		A.call({"k": "spark", "x": 38, "y": 1})
		if truth(n.call("tesla")):
			A.call({"k": "arc", "x": 21, "y": 1, "x2": 37, "y2": 1})
	if truth((n.call("cryo") if truth(n.call("cryo")) else icy)):
		U.layer(17, null)
		for sx in [21, 36]:
			U.R(sx, 23, 1, 4, "#bff4ff")
			U.R((sx + 1), 24, 1, 3, "#e8ffff")
			U.R((sx - 1), 25, 1, 2, "#9ad8f0")
		A.call({"k": "mist", "x": 36, "y": 24})
	if truth(n.call("hive")):
		U.layer(17, Profiles.dome(29, 11, 10, 9, 8))
		g.alpha = 0.32
		U.ell(29, 11, 10, 9, "#a8dcff")
		g.alpha = 1
		U.layer(18, Profiles.dome(29, 6, 5, 3, 3))
		U.ell(29, 6, 5, 3, "#ff8fb0")
		U.R(27, 5, 1, 3, "#d0607e")
		U.R(30, 4, 1, 3, "#d0607e")
		U.R(32, 6, 1, 2, "#d0607e")
		U.layer(19, Profiles.cylH(19.5, 1, 1))
		U.R(19, 19, 21, 2, "#9aa4ae")
		U.R(19, 19, 21, 1, "#d0d8e0")
		U.layer(26, null)
		U.R(23, 3, 3, 1, "#ffffff")
		U.P(21, 6, "#ffffff")
		A.call({"k": "pulse", "x": 29, "y": 6, "r": 4, "c": "#ff8fb0", "a": 0.3})
	if truth(n.call("singular")):
		A.call({"k": "sing", "x": 49, "y": 12})
	if truth(n.call("tesla_helmet")):
		U.layer(28, Profiles.dome(29, 7, 9, 5, 6))
		U.line(21, 10, 37, 10, "#596775", 3)
		U.line(22, 8, 24, 3, "#e4edf4", 1)
		U.line(24, 3, 29, 1, "#a6bccb", 1)
		U.line(29, 1, 35, 3, "#e4edf4", 1)
		U.line(35, 3, 37, 8, "#a6bccb", 1)
		U.line(24, 4, 35, 7, "#bacad6", 1)
		U.line(25, 8, 34, 3, "#bacad6", 1)
		U.line(29, 2, 29, 9, "#f2f6fa", 1)
		for x in [22, 29, 36]:
			U.layer(29, Profiles.cylV(x, 2, 2))
			U.R(x - 1, 0, 2, 6, "#c58e4b")
			U.R(x - 2, 0, 4, 2, "#b1eeff")
			U.P(x - 1, 0, "#ffffff")
			A.call({"k":"pulse", "x":x, "y":1, "r":2, "c":"#70dcff", "a":0.35})
		U.line(22, 11, 23, 19, "#566679", 1)
		U.R(21, 10, 3, 3, "#bb8742")
	return {"img": c.outlined_image(), "depth": Z, "bob": b, "lean": ln, "hand": {"x": (hx_2 + ln), "y": ((hy + 1) + b)}, "feet": feet, "anims": anims, "anchors": AN, "pose": pose, "opt": opt}

## Lay out all hardware first, then paint stock, arm, receiver, modules and muzzle.
func render_weapon(bend = WBEND0, spec = null, off = false):
	var c = Pixels.new(getv(WG, "w"), getv(WG, "h"))
	var g = c
	var Z = c
	var p = Pen.new(g, getv(WG, "px"), getv(WG, "py"))
	var obj = p
	var R = obj.R
	var P = obj.P
	var box = obj.box
	var ell = obj.ell
	var line = obj.line
	var lift = obj.lift
	var X = weapon_context(spec)
	var zo = ((-14) if truth(off) else 0)
	var layer = func(b2 = null, pr = null):
		p.layer((b2 + zo), pr)
	var n = func(id = null):
		return (getv(getv(X, "cnt"), id) if truth(getv(getv(X, "cnt"), id)) else 0)
	var ammo = getv(AMMO, getv(X, "ammo"))
	var fr = getv(getv(FRAMES, getv(X, "frame")), "id")
	var anims = []
	var gold = (n.call("greed") > 0)
	var metal = ("#e8c030" if truth(gold) else "#9aa4ae")
	var metalD = ("#a07a10" if truth(gold) else "#5f6872")
	var metalL = ("#fff4b0" if truth(gold) else "#d4dce4")
	var dark = ("#8a6a10" if truth(gold) else "#3a4048")
	var darkL = ("#c09a28" if truth(gold) else "#5a626c")
	var wood = "#7a4a28"
	var woodD = "#4e2e16"
	var woodL = "#a06a40"
	var brass = ("#ffd24a" if truth(gold) else "#c99a3a")
	var sk = skin_palette()
	var skin = getv(sk, "s")
	var skinL = getv(sk, "L")
	var skinD = getv(sk, "D")
	var cp = coat_palette()
	var lvl = getv(cp, "lvl")
	var coat = (getv(cp, "M") if truth(off) else getv(cp, "c"))
	var coatL = (getv(cp, "c") if truth(off) else getv(cp, "L"))
	var coatM = (getv(cp, "D") if truth(off) else getv(cp, "M"))
	var coatD = (getv(cp, "DD") if truth(off) else getv(cp, "D"))
	if off and spec!=null and spec.get("bionic",false):
		skin = "#a9c7d0"; skinL = "#e5f7f4"; skinD = "#587a8b"
		coat = "#819eae"; coatL = "#d4e8e8"; coatM = "#587a8b"; coatD = "#304c60"
	# Arm reach: shoulder -> grip. Downward bends (-1, -2) pull the whole gun in by 3/6 px so a gun aimed at
	# the floor is held around mid-thigh instead of hanging below the feet; the elbow folds out to take the slack.
	var pull = maxi(0, -int(bend)) * 3
	var G = 22 - pull
	# Modules occupy top, bottom and wrap rails; each stack gets its own slot.
	var tops = []
	var bots = []
	var wraps = []
	for it in ITEMS:
		var k = n.call(getv(it, "id"))
		if truth(((not truth(k)) if truth((not truth(k))) else (not truth(getv(it, "wv"))))):
			continue
		var i = 0
		while truth((i < min(k, 3))):
			(tops if truth((getv(getv(it, "wv"), "s") == "top")) else (bots if truth((getv(getv(it, "wv"), "s") == "bot")) else wraps)).append(it)
			i += 1
	var sumW = func(a = null):
		return sum_width(a)
	var L0 = (G + getv({"pistol": 21, "blunder": 23, "rifle": 41, "repeater": 29}, fr))
	var extra = getv(X, "guns").slice(1)
	var L = max(max(max((L0 + clamp(js_round((getv(X, "rangeAdd") / float(5))), 0, 36)), ((G + sumW.call(tops)) + 4)), ((G + 16) + sumW.call(bots))), ((G + 16) + sumW.call(wraps)))
	# Dense late-game builds grow their canvas as well as their barrel.
	c.ensure_width(int(ceil(L+64)))
	var F = clamp(js_round((getv(X, "width") / float(3))), 2, 22)
	var h0 = (3 if truth((fr == "blunder")) else (4 if truth((fr == "repeater")) else 2))
	var topBase = ((-6) - (extra.size() * 6))
	var gunY = [0]
	var A2 = func(o = null):
		anims.append(o)
	var barrelP = Profiles.cylH(0, (h0 + 1), (h0 + 1))
	if truth((fr == "rifle")):
		layer.call(18, Profiles.cylH(0.5, 3.5, 2))
		box.call((G - 24), (-3), 22, 7, wood)
		R.call((G - 24), (-3), 22, 1, woodL)
		R.call((G - 22), 1, 18, 1, woodD)
		layer.call(19, Profiles.slab((G - 26), (-5), (G - 24), 5, 1.5, 1))
		box.call((G - 26), (-5), 3, 11, dark)
		layer.call(18, null)
		R.call((G - 18), (-5), 8, 2, woodD)
	else:
		if truth((fr == "blunder")):
			layer.call(18, Profiles.cylH(0.5, 3.5, 2))
			box.call((G - 14), (-3), 12, 7, wood)
			R.call((G - 14), (-3), 12, 1, woodL)
			layer.call(19, Profiles.slab((G - 15), (-4), (G - 14), 4, 1.5, 1))
			box.call((G - 15), (-4), 2, 9, brass)
	var list = extra
	for index in list.size():
		var t = list[index]
		var i_2 = index
		var y = ((-9) - (i_2 * 6))
		gunY.append(y)
		layer.call(20, Profiles.cylH(y, 2.5, 2))
		box.call((G + 2), (y - 2), ((L - G) - 6), 4, metalD)
		R.call((G + 2), (y - 2), ((L - G) - 6), 1, metalL)
		R.call((G + 8), (y + 2), 2, 3, dark)
		R.call((L - 10), (y + 2), 2, 3, dark)
		layer.call(21, Profiles.slab((G - 1), (y - 3), (G + 3), (y + 2), 1.5, 1))
		box.call((G - 1), (y - 3), 5, 6, dark)
		layer.call(20, Profiles.cylH(y, 2.5, 2))
		if truth((t == "laser")):
			R.call((G + 6), (y - 2), ((L - G) - 12), 1, "#ff6a6a")
			box.call((L - 4), (y - 3), 3, 6, dark)
			P.call((L - 2), y, "#ff4a4a")
			A2.call({"k": "led", "x": (L - 1), "y": y, "c": "#ff4a4a"})
		else:
			if truth((t == "bullet")):
				box.call((L - 4), (y - 2), 4, 4, dark)
				R.call((L - 3), (y - 1), 1, 2, "#111")
				box.call((G + 4), (y + 2), 3, 5, "#2a2e33")
				P.call((G + 5), (y + 2), "#ffd76a")
			else:
				A2.call({"k": "saw", "x": (L + 3), "y": y, "r": 4})
	layer.call(24, Profiles.dome(0, 0, 3, 3, 3))
	ell.call(0, 0, 3, 3, coat)
	R.call((-2), (-3), 4, 1, coatL)
	R.call((-3), 1, 1, 2, coatD)
	P.call(1, (-2), coatL)
	var elb = js_round((G * 0.45))
	var elbow_out = (bend if bend >= 0 else js_round(pull * 0.7))   # >0: elbow drops below the arm line
	var ey = (js_round(((3 * elb) / float((G - 2)))) + elbow_out)
	var ax = (G - 2)
	var ay = 3
	var armY = func(x = null):
		return (((ey * x) / float(elb)) if truth((x <= elb)) else (ey + (((ay - ey) * (x - elb)) / float((ax - elb)))))
	var x_2 = 0
	while truth((x_2 <= ax)):
		var y_2 = js_round(armY.call(x_2))
		var th = (6 if truth((x_2 < elb)) else 5)
		var top = ((y_2 - 3) + (6 - th))
		layer.call(24, (Profiles.cap(0, 0, elb, ey, 3, 2.8) if truth((x_2 <= elb)) else Profiles.cap(elb, ey, ax, ay, 2.5, 2.8)))
		R.call(x_2, top, 1, th, coat)
		P.call(x_2, top, coatL)
		if truth((fmod(x_2, 6) != 3)):
			P.call(x_2, (top + 1), coatL)
		P.call(x_2, ((top + th) - 2), coatM)
		P.call(x_2, ((top + th) - 1), coatD)
		x_2 += 1
	layer.call(24.5, Profiles.dome(elb, ey, 3, 3, 2.8))
	ell.call(elb, ey, 2, 2, coat)
	P.call((elb - 1), (ey - 2), coatL)
	P.call(elb, (ey + 2), coatM)
	P.call((elb + 1), (ey + 2), coatD)
	if truth((elbow_out >= 1)):
		P.call(elb, (ey - 2), coatD)
		P.call((elb + 1), (ey - 2), coatM)
		P.call((elb - 1), (ey - 1), coatM)
	else:
		if truth((elbow_out <= (-1))):
			P.call(elb, (ey + 1), coatD)
			P.call((elb + 1), (ey + 1), coatD)
			P.call((elb - 1), (ey + 1), coatM)
		else:
			R.call(elb, (ey - 2), 1, 4, coatD)
			P.call((elb + 1), (ey + 1), coatM)
	layer.call(25, Profiles.cylV((G - 2.5), 1.5, 1.5))
	R.call((G - 4), 0, 3, 6, coatM)
	R.call((G - 4), 0, 3, 1, coatL)
	R.call((G - 2), 1, 1, 5, coatD)
	if truth(n.call("virus")):
		layer.call(25, Profiles.slab(7, (-2), 10, 1, 1, 1))
		box.call(7, (-2), 4, 4, "#c8e030")
		P.call(8, (-1), "#222")
		P.call(9, 0, "#222")
		P.call(7, (-2), "#f0ff80")
	if truth((lvl >= 2)):
		layer.call(26, Profiles.dome(0, (-1), 4, 3, 2.5))
		ell.call(0, (-1), 4, 3, "#6a7282")
		R.call((-2), (-3), 4, 1, "#9aa2b2")
		P.call((-1), (-3), "#aab")
		P.call(2, (-3), "#aab")
	if truth((n.call("cryo") if truth(n.call("cryo")) else n.call("zero"))):
		layer.call(27, null)
		R.call((-1), (-6), 1, 4, "#bff4ff")
		R.call(0, (-5), 1, 3, "#e8ffff")
		R.call(1, (-4), 1, 2, "#9ad8f0")
	if truth((fr == "pistol")):
		layer.call(26, Profiles.slab((G - 3), (-5), (G + 11), 3, 2.5, 2))
		box.call((G - 3), (-5), 15, 9, dark)
		var i_3 = 0
		while truth((i_3 < 3)):
			R.call((G + (i_3 * 2)), (-3), 1, 3, darkL)
			i_3 += 1
		layer.call(27, Profiles.dome((G - 4), (-5), 1, 1, 1))
		box.call((G - 5), (-6), 3, 3, dark)
		layer.call(27, barrelP)
		box.call((G + 12), ((-h0) - 1), ((L - G) - 12), ((2 * h0) + 1), metal)
		R.call((G + 12), ((-h0) - 1), ((L - G) - 12), 1, metalL)
		R.call((G + 12), h0, ((L - G) - 12), 1, metalD)
		R.call((G + 12), (-h0), ((L - G) - 12), 1, shade(metal, 0.15))
	else:
		if truth((fr == "blunder")):
			layer.call(26, Profiles.slab((G - 3), (-5), (G + 11), 4, 2.5, 2))
			box.call((G - 3), (-5), 15, 10, brass)
			lift.call(0.4)
			P.call((G - 1), (-3), "#7a5a18")
			P.call((G + 9), (-3), "#7a5a18")
			P.call((G - 1), 2, "#7a5a18")
			P.call((G + 9), 2, "#7a5a18")
			layer.call(27, Profiles.cylH(0.5, (h0 + 1), (h0 + 1)))
			box.call((G + 12), ((-h0) - 1), ((L - G) - 12), ((2 * h0) + 2), brass)
			R.call((G + 12), ((-h0) - 1), ((L - G) - 12), 1, "#fff0b0")
			var x_3 = (G + 16)
			while truth((x_3 < (L - 2))):
				lift.call(0.7)
				box.call(x_3, ((-h0) - 2), 2, ((2 * h0) + 4), shade(brass, (-0.3)))
				lift.call(0)
				x_3 += 8
		else:
			if truth((fr == "rifle")):
				layer.call(26, Profiles.slab((G - 3), (-5), (G + 13), 3, 2.5, 2))
				box.call((G - 3), (-5), 17, 9, dark)
				R.call((G + 5), (-6), 5, 1, "#c0c8d0")
				layer.call(28, Profiles.dome((G + 10), (-7.5), 1, 1.5, 1))
				box.call((G + 9), (-9), 2, 3, "#c0c8d0")
				layer.call(27, barrelP)
				box.call((G + 14), (-h0), ((L - G) - 14), ((2 * h0) + 1), metal)
				R.call((G + 14), (-h0), ((L - G) - 14), 1, metalL)
				layer.call(28, Profiles.cylH((-0.5), 4, 2))
				box.call((G + 14), (-4), 16, 8, woodD)
				R.call((G + 14), (-4), 16, 1, "#7a4a28")
				var x_4 = (G + 16)
				while truth((x_4 < (G + 28))):
					P.call(x_4, 0, "#3a2010")
					x_4 += 3
				layer.call(28, Profiles.slab((L - 6), ((-h0) - 1), (L - 5), (h0 + 1), 1, 1))
				box.call((L - 6), ((-h0) - 1), 2, ((2 * h0) + 3), dark)
			else:
				layer.call(26, Profiles.slab((G - 4), (-6), (G + 8), 5, 2.5, 2))
				box.call((G - 4), (-6), 13, 12, dark)
				R.call((G - 2), (-4), 9, 1, darkL)
				layer.call(27, Profiles.dome((G + 3), 8, 5, 3, 2.5))
				ell.call((G + 3), 8, 5, 3, darkL)
				R.call(G, 8, 6, 1, "#2a3038")
				P.call((G + 1), 6, "#7a848e")
				for y_3 in [(-4), (-1), 2]:
					layer.call(27, Profiles.cylH((y_3 + 0.5), 1, 1.2))
					R.call((G + 9), y_3, ((L - G) - 9), 2, metal)
					R.call((G + 9), y_3, ((L - G) - 9), 1, metalL)
				layer.call(28, Profiles.cylH((-0.5), 6, 2))
				box.call((G + 13), (-6), 2, 11, dark)
				box.call((L - 7), (-6), 2, 11, dark)
				layer.call(26, null)
				box.call((G - 7), (-2), 3, 2, "#888")
				R.call((G - 8), (-4), 1, 6, "#888")
				A2.call({"k": "gat", "x": (G + 9), "y": (-4), "w": ((L - G) - 9)})
	layer.call(25, Profiles.slab((G - 3), 4, (G + 5), 13, 1.8, 2))
	var i_4 = 0
	while truth((i_4 < 10)):
		R.call((G - floor((i_4 / float(4)))), (4 + i_4), 6, 1, (woodD if truth((fmod(i_4, 3) == 0)) else wood))
		P.call(((G - floor((i_4 / float(4)))) + 4), (4 + i_4), woodL)
		i_4 += 1
	R.call((G - 2), 13, 6, 1, woodD)
	layer.call(26, null)
	R.call((G + 5), 4, 5, 1, dark)
	R.call((G + 9), 4, 1, 5, dark)
	R.call((G + 5), 8, 5, 1, dark)
	R.call((G + 6), 5, 1, 2, "#aaa")
	if truth((getv(ammo, "id") == "laser")):
		layer.call(27, Profiles.slab(G, (-6), (G + 7), 4, 2.5, 2))
		lift.call(0.6)
		R.call((G + 1), (-6), 1, 11, "#ff4a4a")
		R.call((G + 4), (-6), 1, 11, "#ff4a4a")
		R.call((G + 7), (-6), 1, 11, "#ff4a4a")
		layer.call(27, barrelP)
		lift.call(0.3)
		R.call((G + 13), ((-h0) - 1), max(2, ((L - G) - 16)), 1, "#ff7a7a")
		A2.call({"k": "pulse", "x": (G + 4), "y": (-1), "r": 3, "c": "#ff4a4a", "a": 0.25})
	else:
		if truth((getv(ammo, "id") == "bullet")):
			layer.call(27, Profiles.slab((G + 3), 4, (G + 9), 13, 1.8, 1.5))
			var i_5 = 0
			while truth((i_5 < 10)):
				R.call(((G + 3) + floor((i_5 / float(3)))), (4 + i_5), 5, 1, "#2a2e33")
				i_5 += 1
			R.call((G + 4), 4, 3, 1, "#ffd76a")
			R.call((G + 4), 5, 3, 1, "#c9a227")
			layer.call(27, null)
			R.call((G + 3), (-4), 5, 2, "#161a1e")
			P.call((G + 4), (-4), "#ffd76a")
		elif truth((getv(ammo, "id") == "hook")):
			# Shock Grapple: a chain reel on top of the gun, with a live coil lead down to the barrel.
			layer.call(27, Profiles.dome((G + 3), (-11), 6, 6, 2.5))
			ell.call((G + 3), (-11), 6, 6, "#2a3038")
			ell.call((G + 3), (-11), 5, 5, "#5a626c")
			for ry in [(-15), (-13), (-11), (-9), (-7)]:
				R.call((G - 1), ry, 9, 1, "#aab8c6")
			R.call((G + 2), (-12), 3, 3, "#161a1e")
			P.call((G + 3), (-11), "#7df9ff")
			layer.call(27, null)
			R.call((G + 2), (-5), 2, 2, "#2a3038")
			R.call((G + 9), (-h0) - 2, max(2, ((L - G) - 12)), 1, "#3a8a9a")
			A2.call({"k": "pulse", "x": (G + 3), "y": (-11), "r": 2, "c": "#7df9ff", "a": 0.35})
		else:
			layer.call(27, Profiles.slab((G - 2), (-12), (G + 9), (-6), 2, 2))
			box.call((G - 2), (-12), 12, 7, "#5a626c")
			R.call((G - 1), (-13), 10, 1, "#dfe6ec")
			R.call(G, (-11), 8, 1, "#aab4be")
			R.call(G, (-9), 8, 1, "#aab4be")
			R.call((G + 3), (-6), 4, 1, "#111")
	layer.call(30, Profiles.dome((G + 1.5), 4, 3.5, 3, 2.5))
	box.call((G - 1), 2, 6, 5, skin)
	R.call((G - 1), 2, 6, 1, skinL)
	R.call((G + 4), 3, 1, 3, skinD)
	R.call(G, 6, 4, 1, skinD)
	P.call((G + 1), 4, skinD)
	P.call((G + 3), 4, skinD)
	P.call((G + 1), 5, skinD)
	P.call((G + 3), 5, skinD)
	layer.call(31, Profiles.dome((G - 1), 1.5, 1.5, 1, 1.5))
	R.call((G - 2), 1, 3, 2, skin)
	P.call((G - 2), 1, skinL)
	P.call(G, 2, skinD)
	if truth(getv(sk, "mut")):
		P.call((G + 1), 3, "#bff08a")
	var wx = (G + 15)
	for it_2 in wraps:
		var x_5 = wx
		var ww = (getv(getv(it_2, "wv"), "w") * 2)
		layer.call(28, Profiles.cylH(0, 7, 3))
		if getv(it_2, "id") == "steam_piston":   # train heist (Menace): brass piston rings that puff steam
			for rx in [x_5, x_5 + 3]:
				box.call(rx, -6, 2, 12, "#9a7a3a")
				R.call(rx, -6, 1, 12, "#e8c870")
			R.call(x_5 + 2, -2, 1, 4, "#5a4a2a")
			A2.call({"k": "mist", "x": x_5 + 2, "y": -6})
		elif truth((getv(it_2, "id") == "fins")):
			for fx in [x_5, (x_5 + 2)]:
				R.call(fx, (-7), 1, 14, "#c0c8d0")
				P.call(fx, (-7), "#fff")
				P.call(fx, 6, "#7a848e")
			R.call((x_5 + 1), (-7), 1, 14, "#6a747e")
		else:
			if truth((getv(it_2, "id") == "cryo")):
				layer.call(28, Profiles.cylH(0, 5, 2.5))
				var y_4 = (-4)
				while truth((y_4 <= 4)):
					R.call((x_5 + fmod(((y_4 + 4) / float(2)), 2)), y_4, 3, 1, "#8ff0ff")
					y_4 += 2
				R.call(x_5, (-5), 4, 1, "#e8ffff")
				A2.call({"k": "mist", "x": (x_5 + 2), "y": 0})
			else:
				if truth((getv(it_2, "id") == "sustain")):
					for rx in [x_5, (x_5 + 4)]:
						box.call(rx, (-6), 3, 12, "#7a1818")
						R.call((rx + 1), (-6), 1, 12, "#ff4a4a")
						P.call((rx + 1), (-6), "#ffd0d0")
					R.call((x_5 + 3), (-1), 1, 2, "#ff4a4a")
					A2.call({"k": "pulse", "x": (x_5 + 4), "y": 0, "r": 4, "c": "#ff4a4a", "a": 0.25})
				else:
					if truth((getv(it_2, "id") == "zero")):
						layer.call(28, Profiles.cylH(0, 5, 2.5))
						R.call(x_5, (-4), 4, 1, "#e8ffff")
						R.call((x_5 + 1), (-5), 2, 1, "#ffffff")
						R.call(x_5, 4, 1, 3, "#bff4ff")
						R.call((x_5 + 2), 4, 1, 2, "#bff4ff")
						R.call((x_5 + 3), 4, 1, 4, "#9ad8f0")
						A2.call({"k": "mist", "x": (x_5 + 2), "y": 3})
		wx += (ww + 2)
	var tx = (G - 2)
	var tb = topBase
	for it_3 in tops:
		var x_6 = tx
		var ww_2 = (getv(getv(it_3, "wv"), "w") * 2)
		layer.call(28, Profiles.dome((x_6 + (ww_2 / float(2))), (tb - 6), ((ww_2 / float(2)) + 1), 7, 3))
		match getv(it_3, "id"):
			"headlamp":   # train heist (Arch-Nemesis): a huge brass locomotive headlamp facing down the barrel
				layer.call(28, Profiles.dome(x_6 + 6, tb - 6, 6, 6, 3))
				box.call(x_6, tb - 11, 10, 10, "#8a6a2a")
				R.call(x_6 + 1, tb - 10, 8, 1, "#e8c870")
				R.call(x_6 + 3, tb - 1, 4, 1, "#5a4a2a")
				box.call(x_6 + 10, tb - 12, 2, 12, "#c9a227")
				lift.call(0.5)
				R.call(x_6 + 11, tb - 10, 1, 8, "#fff8d0")
				P.call(x_6 + 11, tb - 7, "#ffffff")
				lift.call(0)
				A2.call({"k": "pulse", "x": x_6 + 12, "y": tb - 6, "r": 6, "c": "#fff0b0", "a": 0.35})
			"capacitor":
				layer.call(28, Profiles.slab(x_6,tb-10,x_6+10,tb-1,3,1))
				box.call(x_6,tb-10,10,9,"#ad783f")
				R.call(x_6+1,tb-9,8,1,"#efd49a")
				R.call(x_6+1,tb-7,8,5,"#372f37")
				for window in 3: R.call(x_6+2+window*2,tb-6,1,3,"#725842")
				R.call(x_6+2,tb-1,2,2,"#6b8491"); R.call(x_6+7,tb-1,2,2,"#6b8491")
				A2.call({"k":"capacitor","x":x_6+2,"y":tb-6})
			"scope":
				layer.call(28, Profiles.cylH((tb - 3.5), 2.5, 2.5))
				box.call(x_6, (tb - 6), 12, 5, "#2a2e33")
				R.call((x_6 + 1), (tb - 5), 10, 1, "#4a4e54")
				box.call((x_6 + 12), (tb - 7), 2, 7, "#3a4048")
				lift.call(0.5)
				R.call((x_6 + 13), (tb - 6), 1, 5, "#7ad0ff")
				P.call((x_6 + 13), (tb - 6), "#e8f8ff")
				lift.call(0)
				box.call((x_6 - 1), (tb - 5), 1, 3, "#555")
				R.call((x_6 + 2), (tb - 1), 2, 1, dark)
				R.call((x_6 + 8), (tb - 1), 2, 1, dark)
				box.call((x_6 + 5), (tb - 9), 2, 3, "#555")
			"acid":
				layer.call(28, Profiles.cylV((x_6 + 2.5), 3, 2.5))
				box.call(x_6, (tb - 9), 6, 9, "#a8b020")
				R.call((x_6 + 1), (tb - 7), 3, 4, "#f0ff60")
				P.call((x_6 + 1), (tb - 7), "#ffffc0")
				R.call(x_6, (tb - 3), 6, 1, "#222")
				P.call((x_6 + 1), (tb - 3), "#ffd23c")
				P.call((x_6 + 3), (tb - 3), "#ffd23c")
				box.call((x_6 + 1), (tb - 10), 4, 1, "#777")
				R.call((x_6 + 6), (tb - 5), 2, 1, "#777")
				A2.call({"k": "bubble", "x": (x_6 + 1), "y": (tb - 7), "w": 3, "h": 4, "c": "#ffffc0"})
			"poison":
				layer.call(28, Profiles.cylV((x_6 + 1.5), 2, 2))
				box.call(x_6, (tb - 8), 4, 8, "#2aa82a")
				R.call((x_6 + 1), (tb - 7), 1, 6, "#9affa0")
				R.call((x_6 + 1), (tb - 10), 2, 2, "#cde")
				R.call((x_6 + 1), (tb - 11), 2, 1, "#a07040")
				R.call((x_6 + 1), (tb - 5), 2, 2, "#f0f0f0")
				P.call((x_6 + 1), (tb - 4), "#222")
				A2.call({"k": "bubble", "x": x_6, "y": (tb - 8), "w": 4, "h": 7, "c": "#d0ffd0"})
			"tesla":
				layer.call(28, Profiles.cylV((x_6 + 1.5), 1, 1))
				R.call((x_6 + 1), (tb - 11), 2, 11, "#8a8a92")
				layer.call(29, Profiles.cylV((x_6 + 1.5), 2, 1.5))
				for y_5 in [(-9), (-7), (-5), (-3)]:
					R.call(x_6, (tb + y_5), 4, 1, "#c97a3a")
				layer.call(29, Profiles.dome((x_6 + 2), (tb - 13), 2, 2, 2))
				ell.call((x_6 + 2), (tb - 13), 2, 2, "#fff36b")
				P.call((x_6 + 1), (tb - 14), "#ffffff")
				A2.call({"k": "spark", "x": (x_6 + 2), "y": (tb - 13)})
			"hypno":
				R.call((x_6 + 3), (tb - 2), 2, 2, dark)
				layer.call(29, Profiles.dome((x_6 + 4), (tb - 6), 4, 4, 2))
				ell.call((x_6 + 4), (tb - 6), 4, 4, "#7a20b0")
				A2.call({"k": "hypno", "x": (x_6 + 4), "y": (tb - 6), "r": 4})
			"clock":
				R.call(x_6, (tb - 3), 8, 3, "#c8302a")
				R.call(x_6, (tb - 2), 8, 1, "#a02018")
				R.call((x_6 + 2), (tb - 3), 1, 3, "#222")
				R.call((x_6 + 5), (tb - 3), 1, 3, "#222")
				layer.call(29, Profiles.dome((x_6 + 4), (tb - 7), 3, 3, 2))
				ell.call((x_6 + 4), (tb - 7), 3, 3, "#c33")
				ell.call((x_6 + 4), (tb - 7), 2, 2, "#f4f4f4")
				layer.call(29, Profiles.dome((x_6 + 1), (tb - 11), 1, 1, 1))
				ell.call((x_6 + 1), (tb - 11), 1, 1, "#c33")
				layer.call(29, Profiles.dome((x_6 + 7), (tb - 11), 1, 1, 1))
				ell.call((x_6 + 7), (tb - 11), 1, 1, "#c33")
				A2.call({"k": "clock", "x": (x_6 + 4), "y": (tb - 7)})
			"remote":
				box.call(x_6, (tb - 4), 4, 4, "#333")
				P.call((x_6 + 1), (tb - 3), "#3f3")
				layer.call(28, null)
				R.call((x_6 + 1), (tb - 14), 1, 10, "#8a8a92")
				A2.call({"k": "led", "x": (x_6 + 1), "y": (tb - 15), "c": "#ff3030"})
			"syringe":
				layer.call(28, Profiles.cylH((tb - 3.5), 2, 2))
				box.call(x_6, (tb - 5), 10, 4, "#e8e8f0")
				R.call((x_6 + 1), (tb - 4), 6, 2, "#c01828")
				P.call((x_6 + 1), (tb - 4), "#ff6070")
				R.call((x_6 - 3), (tb - 4), 3, 2, "#999")
				R.call((x_6 - 4), (tb - 6), 1, 6, "#999")
				R.call((x_6 + 10), (tb - 4), 1, 2, "#bbb")
				R.call((x_6 + 11), (tb - 3), 4, 1, "#ddd")
				R.call((x_6 + 3), (tb - 1), 1, 2, "#c01828")
				A2.call({"k": "bubble", "x": (x_6 + 1), "y": (tb - 4), "w": 6, "h": 2, "c": "#ff9aa0"})
			"hive":
				R.call((x_6 + 3), (tb - 8), 2, 8, "#8a8a92")
				layer.call(29, Profiles.dome((x_6 + 4), (tb - 11), 4, 4, 3))
				g.alpha = 0.4
				ell.call((x_6 + 4), (tb - 11), 4, 4, "#a8dcff")
				g.alpha = 1
				ell.call((x_6 + 4), (tb - 11), 3, 2, "#ff8fb0")
				P.call((x_6 + 3), (tb - 12), "#d0607e")
				P.call((x_6 + 5), (tb - 11), "#d0607e")
				A2.call({"k": "pulse", "x": (x_6 + 4), "y": (tb - 11), "r": 3, "c": "#ff8fb0", "a": 0.3})
			"storm":
				layer.call(28, Profiles.cylV((x_6 + 0.5), 1, 1))
				R.call(x_6, (tb - 13), 2, 13, "#9a9aa4")
				layer.call(28, Profiles.cylV((x_6 + 6.5), 1, 1))
				R.call((x_6 + 6), (tb - 13), 2, 13, "#9a9aa4")
				layer.call(29, null)
				ell.call((x_6 + 1), (tb - 14), 1, 1, "#fff36b")
				ell.call((x_6 + 7), (tb - 14), 1, 1, "#fff36b")
				layer.call(28, null)
				R.call(x_6, (tb - 2), 8, 2, dark)
				A2.call({"k": "arc", "x": (x_6 + 1), "y": (tb - 14), "x2": (x_6 + 7), "y2": (tb - 14)})
			"nuke":
				layer.call(28, Profiles.cylH((tb - 3), 3, 2.5))
				box.call(x_6, (tb - 6), 8, 6, "#ffd23c")
				R.call((x_6 + 8), (tb - 5), 2, 4, "#ffd23c")
				R.call((x_6 + 10), (tb - 4), 1, 2, "#e8b020")
				R.call((x_6 - 2), (tb - 7), 2, 2, "#8a8a92")
				R.call((x_6 - 2), (tb - 1), 2, 1, "#8a8a92")
				lift.call(0.3)
				P.call((x_6 + 4), (tb - 3), "#222")
				P.call((x_6 + 3), (tb - 4), "#222")
				P.call((x_6 + 5), (tb - 4), "#222")
				P.call((x_6 + 4), (tb - 2), "#222")
				R.call((x_6 + 1), (tb - 6), 6, 1, "#fff0a0")
				lift.call(0)
			"moon":
				layer.call(29, Profiles.cylH((tb - 9), 1.5, 1.5))
				R.call(x_6, (tb - 10), 10, 1, "#f0f0f8")
				R.call((x_6 + 1), (tb - 9), 8, 1, "#c8c8d0")
				R.call((x_6 + 2), (tb - 8), 6, 1, "#a8a8b0")
				layer.call(28, null)
				R.call((x_6 + 4), (tb - 14), 2, 4, "#8a8a92")
				R.call((x_6 + 4), (tb - 7), 2, 7, "#777")
				A2.call({"k": "led", "x": (x_6 + 5), "y": (tb - 15), "c": "#ff3030"})
		tx += (ww_2 + 2)
	var bx = (G + 15)
	var bb = (h0 + 2)
	for it_4 in bots:
		var x_7 = bx
		var ww_3 = (getv(getv(it_4, "wv"), "w") * 2)
		layer.call(27, Profiles.dome((x_7 + (ww_3 / float(2))), (bb + 3), ((ww_3 / float(2)) + 1), 4, 2.5))
		match getv(it_4, "id"):
			"bullion":   # train heist (Petty Crook): a stolen gold bar strapped under the barrel
				layer.call(27, Profiles.slab(x_7, bb, x_7 + 10, bb + 5, 2.5, 1))
				box.call(x_7, bb, 10, 5, "#c9a227")
				R.call(x_7 + 1, bb, 8, 1, "#fff0a0")
				R.call(x_7 + 2, bb + 2, 6, 1, "#e8c840")
				R.call(x_7 + 3, bb - 1, 1, 6, "#5a4a2a")
				R.call(x_7 + 7, bb - 1, 1, 6, "#5a4a2a")
				A2.call({"k": "pulse", "x": x_7 + 5, "y": bb + 2, "r": 3, "c": "#ffe070", "a": 0.25})
			"rail_spike":   # train heist (Nuisance): an iron rail spike lashed under the muzzle, point forward
				layer.call(27, Profiles.cylH(bb + 2, 2, 2))
				R.call(x_7, bb, 3, 4, "#4a4e54")
				R.call(x_7 + 3, bb + 1, 7, 2, "#7a7e86")
				R.call(x_7 + 3, bb + 1, 7, 1, "#a8acb4")
				R.call(x_7 + 10, bb + 1, 2, 1, "#c8ccd0")
				R.call(x_7 + 4, bb - 1, 1, 4, "#8a5a2a")
				R.call(x_7 + 8, bb - 1, 1, 4, "#8a5a2a")
			"firebox":   # train heist (Supervillain): a glowing coal firebox under the gun
				layer.call(27, Profiles.cylH(bb + 3, 3.5, 2.5))
				box.call(x_7, bb, 10, 7, "#2a2a2e")
				R.call(x_7 + 1, bb + 1, 8, 1, "#4a4a52")
				R.call(x_7 + 2, bb + 3, 6, 3, "#ff7a20")
				R.call(x_7 + 3, bb + 4, 4, 1, "#ffd040")
				R.call(x_7 + 1, bb - 1, 2, 1, dark)
				R.call(x_7 + 10, bb + 1, 2, 2, "#555")
				A2.call({"k": "flame", "x": x_7 + 12, "y": bb + 2, "side": 1})
				A2.call({"k": "pulse", "x": x_7 + 5, "y": bb + 4, "r": 4, "c": "#ff8a30", "a": 0.35})
			"cell":
				box.call(x_7, bb, 8, 4, "#2a8ad0")
				R.call((x_7 + 2), (bb + 1), 4, 2, "#9ff")
				R.call((x_7 + 1), (bb - 1), 1, 1, dark)
				R.call((x_7 + 6), (bb - 1), 1, 1, dark)
				A2.call({"k": "pulse", "x": (x_7 + 4), "y": (bb + 2), "r": 2, "c": "#6ff", "a": 0.3})
			"thermite":
				layer.call(27, Profiles.cylH((bb + 2.5), 3, 2.5))
				box.call(x_7, bb, 10, 6, "#e06a1a")
				R.call((x_7 + 2), bb, 1, 6, "#ffb050")
				R.call((x_7 + 6), bb, 1, 6, "#ffb050")
				R.call((x_7 + 10), (bb + 2), 2, 2, "#777")
				R.call((x_7 + 1), (bb - 1), 2, 1, dark)
				A2.call({"k": "flame", "x": (x_7 + 12), "y": (bb + 3), "side": 1})
			"bleed":
				R.call(x_7, bb, 10, 2, "#ccd4dc")
				R.call(x_7, bb, 10, 1, "#f0f4f8")
				var i_6 = 0
				while truth((i_6 < 10)):
					P.call((x_7 + i_6), (bb + 2), "#ccd4dc")
					i_6 += 2
				R.call((x_7 + 1), (bb - 1), 2, 1, dark)
				P.call((x_7 + 3), (bb + 2), "#a01020")
				P.call((x_7 + 3), (bb + 3), "#a01020")
			"virus":
				layer.call(27, Profiles.cylH((bb + 3), 3.5, 2.5))
				box.call(x_7, bb, 8, 7, "#9acd32")
				R.call(x_7, (bb + 1), 8, 1, "#6a9a12")
				R.call(x_7, (bb + 5), 8, 1, "#6a9a12")
				R.call((x_7 + 3), (bb + 2), 2, 2, "#222")
				P.call((x_7 + 2), (bb + 3), "#222")
				P.call((x_7 + 5), (bb + 3), "#222")
				A2.call({"k": "bubble", "x": x_7, "y": (bb + 7), "w": 8, "h": 3, "c": "#c8f060"})
			"grenade":
				box.call(x_7, bb, 8, 4, "#4a5a3a")
				R.call((x_7 + 1), (bb + 1), 6, 1, "#2a3a1a")
				layer.call(28, Profiles.dome((x_7 + 10), (bb + 2), 2, 2, 2))
				ell.call((x_7 + 10), (bb + 2), 2, 2, "#4a6a2a")
				P.call((x_7 + 9), (bb + 1), "#6a8a3a")
				R.call((x_7 + 10), (bb - 1), 2, 1, "#ccc")
			"auto":
				var i_7 = 0
				while truth((i_7 < 10)):
					var yy = ((bb + (2 if truth((fmod(i_7, 3) == 0)) else 1)) + js_round(sin((i_7 * 0.8))))
					layer.call(27, Profiles.cylH((yy + 1), 1.5, 1.5))
					R.call((x_7 + i_7), yy, 1, 3, "#c9a227")
					P.call((x_7 + i_7), (yy + 3), "#ffd76a")
					i_7 += 1
			"disint":
				layer.call(28, Profiles.dome((x_7 + 3), (bb + 2.5), 3, 3, 2.5))
				R.call((x_7 + 2), bb, 2, 1, "#ff2a2a")
				R.call((x_7 + 1), (bb + 1), 4, 1, "#ff2a2a")
				R.call(x_7, (bb + 2), 6, 2, "#ff2a2a")
				R.call((x_7 + 1), (bb + 4), 4, 1, "#c01010")
				R.call((x_7 + 2), (bb + 5), 2, 1, "#a01010")
				P.call((x_7 + 2), (bb + 1), "#ffb0b0")
				P.call((x_7 + 1), (bb + 2), "#ffd0d0")
				A2.call({"k": "pulse", "x": (x_7 + 3), "y": (bb + 3), "r": 3, "c": "#ff2a2a", "a": 0.3})
			"reactor":
				box.call(x_7, bb, 10, 7, "#2a3a2a")
				layer.call(28, Profiles.dome((x_7 + 5), (bb + 3), 2, 2, 1.5))
				ell.call((x_7 + 5), (bb + 3), 2, 2, "#7dff3a")
				P.call((x_7 + 5), (bb + 3), "#e8ffe0")
				layer.call(27, null)
				R.call(x_7, (bb + 6), 10, 1, "#ffd23c")
				A2.call({"k": "pulse", "x": (x_7 + 5), "y": (bb + 3), "r": 3, "c": "#7dff3a", "a": 0.35})
			"singular":
				box.call(x_7, bb, 8, 8, "#333")
				lift.call((-1))
				R.call((x_7 + 1), (bb + 1), 6, 6, "#110018")
				lift.call(0)
				A2.call({"k": "sing", "x": (x_7 + 4), "y": (bb + 4), "small": 1})
		bx += (ww_3 + 2)
	layer.call(27, Profiles.cylH(0, (max(F, (h0 + 1)) + 0.5), 2.5))
	if truth((F > (h0 + 1))):
		var i_8 = 0
		while truth((i_8 < 6)):
			var hh = (h0 + js_round((((F - h0) * (i_8 + 1)) / float(6))))
			R.call((L + i_8), (-hh), 1, ((2 * hh) + 1), (metalL if truth((i_8 == 5)) else (brass if truth((fr == "blunder")) else metalD)))
			P.call((L + i_8), (-hh), metalL)
			P.call((L + i_8), hh, shade(metalD, (-0.3)))
			i_8 += 1
		if truth(n.call("flare")):
			R.call((L + 5), ((-F) - 1), 1, ((2 * F) + 3), brass)
			P.call((L + 5), ((-F) - 1), "#fff0b0")
	else:
		box.call(L, ((-h0) - 1), 4, ((2 * h0) + 3), dark)
		if truth(n.call("flare")):
			R.call((L + 3), ((-h0) - 2), 1, ((2 * h0) + 5), brass)
	var mx = ((L + 6) if truth((F > (h0 + 1))) else (L + 4))
	var sh = getv(X, "shots")
	layer.call(28, null)
	var i_9 = 0
	while truth((i_9 < sh)):
		var y_6 = (js_round(((-(F - 1)) + (((2 * (F - 1)) * i_9) / float((sh - 1))))) if truth((sh > 1)) else 0)
		R.call(mx, (y_6 - 1), 2, 3, dark)
		P.call((mx + 1), y_6, getv(ammo, "col"))
		i_9 += 1
	var muz = (mx + 2)
	if truth((getv(ammo, "id") == "razor")):
		layer.call(28, Profiles.dome((mx + 7), 0, 6, 6, 2))
		ell.call((mx + 7), 0, 6, 6, "#8a949e")
		A2.call({"k": "saw", "x": (mx + 7), "y": 0, "r": 6})
		muz = (mx + 13)
	if truth((getv(ammo, "id") == "hook")):
		# claw prongs in the muzzle; drawn as an effect so it can vanish while the hook is out
		layer.call(28, null)
		R.call(mx, (-2), 3, 5, "#2a3038")
		A2.call({"k": "claw", "x": (mx + 2), "y": 0})
		muz = (mx + 3)
	if truth(n.call("drill")):
		var x0 = muz
		layer.call(28, Profiles.cylH(0, 3, 2.5))
		var i_10 = 0
		while truth((i_10 < 9)):
			var hh_2 = max(0, js_round((3 - (i_10 / float(3)))))
			R.call((x0 + i_10), (-hh_2), 1, ((2 * hh_2) + 1), "#c8ccd2")
			P.call((x0 + i_10), (-hh_2), "#eef0f4")
			i_10 += 1
		A2.call({"k": "drill", "x": x0, "y": 0, "len": 9})
		muz = (x0 + 9)
	anims.append({"k": "muzzle", "x": muz, "y": 0})
	var anchors = {"shoulder": {"x": 0, "y": 0}, "elbow": {"x": elb, "y": ey}, "grip": {"x": (G + 1), "y": 4}, "trigger": {"x": (G + 7), "y": 6}, "stock": {"x": (G - 14), "y": 0}, "railTop": {"x": (G - 2), "y": topBase}, "railBottom": {"x": (G + 15), "y": (h0 + 2)}, "wrap": {"x": (G + 15), "y": 0}, "barrelEnd": {"x": L, "y": 0}, "muzzle": {"x": muz, "y": 0}}
	return {"cv": c.outlined_image(), "depth": Z, "muz": muz, "anims": anims, "gunY": gunY, "anchors": anchors, "bend": bend, "off": off}

## Live pixel overlays share the same painter primitives as the cached images.
func draw_effect(p, a, o, t):
	var g = p
	var R = p.R
	var P = p.P
	match getv(a, "k"):
		"capacitor":
			var charge: float = clampf(float(o.get("capacitor_charge",0.0)),0.0,1.0)
			for window in 3:
				var intensity := clampf(charge*3.0-window,0.0,1.0)
				p.R(a.x+window*2,a.y,1,3,"#"+Color("#725842").lerp(Color("#ffe7a0"),intensity).to_html(false))
			if charge>=0.999: p.P(a.x+5,a.y-2,"#fff9d9")
		"tank":
			var i = 0
			while truth((i < 4)):
				var yy = (((getv(a, "y") + getv(a, "h")) - 1) - floor(fmod(((t * 9) + (i * 3.7)), getv(a, "h"))))
				P.call((getv(a, "x") + fmod(((i * 4) + floor(((t * 2) + i))), getv(a, "w"))), yy, getv(a, "c"))
				i += 1
		"jar":
			var i_2 = 0
			while truth((i_2 < 3)):
				var yy_2 = (((getv(a, "y") + getv(a, "h")) - 1) - floor(fmod(((t * 6) + (i_2 * 5.3)), getv(a, "h"))))
				P.call((getv(a, "x") + fmod(((i_2 * 5) + 3), getv(a, "w"))), yy_2, "#f0ffff")
				i_2 += 1
		"bubble":
			if truth((randf() < 0.35)):
				P.call((getv(a, "x") + floor((randf() * getv(a, "w")))), (getv(a, "y") + floor((randf() * getv(a, "h")))), getv(a, "c"))
		"wheel":
			var sp = (t * (16 if truth(getv(o, "moving")) else 5))
			p.ring(getv(a, "x"), getv(a, "y"), getv(a, "r"), "#b8bcc4")
			p.ring(getv(a, "x"), getv(a, "y"), (getv(a, "r") - 1), "#7a7e86")
			var i_3 = 0
			while truth((i_3 < 6)):
				var an = ((sp / float(2)) + (i_3 * 1.047))
				p.line(getv(a, "x"), getv(a, "y"), js_round((getv(a, "x") + (cos(an) * (getv(a, "r") - 2)))), js_round((getv(a, "y") + (sin(an) * (getv(a, "r") - 2)))), "#6a6e76")
				i_3 += 1
			R.call((getv(a, "x") - 1), (getv(a, "y") - 1), 3, 3, "#555")
			var hx = (getv(a, "x") - 3)
			var hy = ((getv(a, "y") + getv(a, "r")) - 6)
			var st = fmod(floor((sp * 1.5)), 2)
			p.ell((hx + 3), (hy + 2), 3, 2, "#c8884a")
			R.call((hx + 5), hy, 2, 2, "#c8884a")
			P.call((hx + 6), hy, "#111")
			P.call((hx + 7), (hy + 1), "#ff9aa0")
			R.call((hx + 1), (hy + 1), 3, 1, "#f0e0c0")
			P.call(((hx + 1) + (st * 2)), (hy + 4), "#ffb0b0")
			P.call(((hx + 4) - (st * 2)), (hy + 4), "#ffb0b0")
			P.call(hx, ((hy + 1) + st), "#ff9aa0")
			pass
		"spark":
			if truth((randf() < 0.4)):
				var i_4 = 0
				while truth((i_4 < 3)):
					P.call((getv(a, "x") + js_round(((randf() - 0.5) * 5))), (getv(a, "y") + js_round(((randf() - 0.5) * 5))), ((getv(a, "c") if truth(getv(a, "c")) else "#fff36b") if truth((randf() < 0.5)) else "#fff"))
					i_4 += 1
		"led":
			if truth((sin(((t * 6) + (getv(a, "x") * 0.7))) > 0)):
				g.alpha = 0.35
				R.call((getv(a, "x") - 1), (getv(a, "y") - 1), 3, 3, getv(a, "c"))
				g.alpha = 1
				P.call(getv(a, "x"), getv(a, "y"), "#fff")
			else:
				P.call(getv(a, "x"), getv(a, "y"), shade(getv(a, "c"), (-0.5)))
		"flame":
			var h = (2 + floor((randf() * 3)))
			if truth(getv(a, "side")):
				R.call(getv(a, "x"), getv(a, "y"), h, 1, "#ff7a2a")
				P.call((getv(a, "x") + h), getv(a, "y"), "#ffd23c")
			else:
				R.call(getv(a, "x"), (getv(a, "y") - h), 1, h, "#ff7a2a")
				P.call(getv(a, "x"), ((getv(a, "y") - h) - 1), "#ffd23c")
				if truth((randf() < 0.5)):
					P.call((getv(a, "x") + ((-1) if truth((randf() < 0.5)) else 1)), (getv(a, "y") - 1), "#ff4a1a")
			pass
		"claw":
			if not truth(getv(o, "hook_out")):
				var cx = getv(a, "x"); var cy = getv(a, "y")
				R.call(cx, cy - 1, 4, 3, "#2a3038"); R.call(cx, cy, 4, 1, "#c8d2dc")
				for sy in [-1, 1]:
					R.call(cx + 3, cy + 2 * sy, 2, 1, "#2a3038"); P.call(cx + 3, cy + 2 * sy, "#dfe6ec")
					R.call(cx + 5, cy + 3 * sy, 2, 1, "#2a3038"); P.call(cx + 5, cy + 3 * sy, "#dfe6ec")
					P.call(cx + 7, cy + 2 * sy, "#dfe6ec")
				P.call(cx + 1, cy, "#7df9ff")
			pass
		"pulse":
			var s = (0.5 + (0.5 * sin(((t * 5) + getv(a, "x")))))
			g.alpha = ((getv(a, "a") if truth(getv(a, "a")) else 0.3) * (0.5 + s))
			p.ell(getv(a, "x"), getv(a, "y"), (getv(a, "r") + 1), (getv(a, "r") + 1), getv(a, "c"))
			g.alpha = 1
			pass
		"sing":
			var yy_3 = (getv(a, "y") + (0 if truth(getv(a, "small")) else js_round((sin((t * 2)) * 2))))
			var r = (3 if truth(getv(a, "small")) else 5)
			g.alpha = 0.45
			p.ell(getv(a, "x"), yy_3, r, r, "#5a20a0")
			g.alpha = 1
			p.ell(getv(a, "x"), yy_3, (r - 2), (r - 2), "#000")
			var i_5 = 0
			while truth((i_5 < 5)):
				var an_2 = ((t * 4) + (i_5 * 1.256))
				P.call(js_round((getv(a, "x") + (cos(an_2) * r))), js_round((yy_3 + ((sin(an_2) * r) * 0.6))), "#c890ff")
				i_5 += 1
			pass
		"arc":
			if truth((randf() < 0.6)):
				var px = getv(a, "x")
				var py = getv(a, "y")
				var n = 6
				var i_6 = 1
				while truth((i_6 <= n)):
					var nx = js_round((getv(a, "x") + (((getv(a, "x2") - getv(a, "x")) * i_6) / float(n))))
					var ny = js_round(((getv(a, "y") + (((getv(a, "y2") - getv(a, "y")) * i_6) / float(n))) + (((randf() - 0.5) * 4) if truth((i_6 < n)) else 0)))
					p.line(px, py, nx, ny, "#fff36b")
					px = nx
					py = ny
					i_6 += 1
		"mist":
			if truth((randf() < 0.4)):
				P.call((getv(a, "x") + js_round(((randf() - 0.3) * 6))), (getv(a, "y") + js_round(((randf() - 0.5) * 6))), "#e8ffff")
		"clock":
			var an_3 = (t * 2.5)
			p.line(getv(a, "x"), getv(a, "y"), js_round((getv(a, "x") + (cos(an_3) * 2))), js_round((getv(a, "y") + (sin(an_3) * 2))), "#222")
			pass
		"hypno":
			p.ell(getv(a, "x"), getv(a, "y"), getv(a, "r"), getv(a, "r"), "#7a20b0")
			var s_2 = 0
			while truth((s_2 < 16)):
				var an_4 = (((-t) * 7) + (s_2 * 0.85))
				var rr = ((s_2 / float(16)) * getv(a, "r"))
				P.call(js_round((getv(a, "x") + (cos(an_4) * rr))), js_round((getv(a, "y") + (sin(an_4) * rr))), "#f0c8ff")
				s_2 += 1
			P.call(getv(a, "x"), getv(a, "y"), "#fff")
			pass
		"saw":
			var rot = (t * (28 if truth(getv(o, "firing")) else 6))
			var r_2 = getv(a, "r")
			p.ell(getv(a, "x"), getv(a, "y"), r_2, r_2, "#c8d0d8")
			p.ell(getv(a, "x"), getv(a, "y"), (r_2 - 2), (r_2 - 2), "#8a949e")
			var i_7 = 0
			while truth((i_7 < 8)):
				var an_5 = (rot + (i_7 * 0.785))
				P.call(js_round((getv(a, "x") + (cos(an_5) * (r_2 + 1)))), js_round((getv(a, "y") + (sin(an_5) * (r_2 + 1)))), "#f0f4f8")
				P.call(js_round((getv(a, "x") + (cos((an_5 + 0.3)) * (r_2 - 1)))), js_round((getv(a, "y") + (sin((an_5 + 0.3)) * (r_2 - 1)))), "#5a646e")
				i_7 += 1
			R.call((getv(a, "x") - 1), (getv(a, "y") - 1), 2, 2, "#333")
			pass
		"drill":
			var off = floor((t * (40 if truth(getv(o, "firing")) else 8)))
			var i_8 = 0
			while truth((i_8 < getv(a, "len"))):
				var hh = max(0, js_round((3 - (i_8 / float(3)))))
				if truth((fmod((i_8 + off), 3) == 0)):
					R.call((getv(a, "x") + i_8), (getv(a, "y") - hh), 1, ((2 * hh) + 1), "#6a7078")
				i_8 += 1
			pass
		"gat":
			if truth(getv(o, "firing")):
				var ph = fmod(floor((t * 30)), 3)
				var i_9 = 0
				while truth((i_9 < 3)):
					R.call(getv(a, "x"), (getv(a, "y") + (i_9 * 3)), getv(a, "w"), 1, ("#ffffff" if truth((i_9 == ph)) else "#7a848e"))
					i_9 += 1
			pass
		"tscope":
			var ext = (6 if truth((getv(o, "firing") if truth(getv(o, "firing")) else ((getv(o, "recoil") if truth(getv(o, "recoil")) else 0) > 0))) else (2 if truth((sin(((t * 1.7) + 1)) > 0.97)) else 0))
			if truth((ext > 0)):
				var x2 = getv(a, "x")
				var l2 = (2 + ext)
				var x3 = (x2 + l2)
				var l3 = (1 + js_round((ext * 0.6)))
				R.call(x2, (getv(a, "y") - 1), l2, 3, "#9aa4ae")
				R.call(x2, (getv(a, "y") - 1), l2, 1, "#d4dce4")
				R.call(x2, (getv(a, "y") + 1), l2, 1, "#5f6872")
				R.call(((x2 + l2) - 1), (getv(a, "y") - 2), 1, 5, "#8a6a18")
				P.call(((x2 + l2) - 1), (getv(a, "y") - 2), "#ffe08a")
				R.call(x3, (getv(a, "y") - 1), l3, 3, "#c9a227")
				R.call(x3, (getv(a, "y") - 1), l3, 1, "#ffe08a")
				R.call(x3, (getv(a, "y") + 1), l3, 1, "#8a6a18")
				R.call((x3 + l3), (getv(a, "y") - 2), 1, 5, "#5f6872")
				R.call(((x3 + l3) + 1), (getv(a, "y") - 1), 1, 3, "#9ccbe0")
				P.call(((x3 + l3) + 1), (getv(a, "y") - 1), "#ffffff")
			var tip = (getv(a, "x") + (((((2 + ext) + 1) + js_round((ext * 0.6))) + 1) if truth((ext > 0)) else 3))
			if truth((sin(((t * 2.3) + getv(a, "x"))) > 0.93)):
				P.call(tip, (getv(a, "y") - 1), "#ffffff")
				P.call((tip + 1), (getv(a, "y") - 2), "#ffffff")
				P.call((tip + 1), getv(a, "y"), "#e8f8ff")
			pass
		"glint":
			var ph_2 = fmod(((t * 0.6) + (getv(a, "x") * 0.03)), 1)
			if truth((ph_2 < 0.12)):
				var k = floor(((ph_2 / float(0.12)) * 5))
				P.call((getv(a, "x") + k), (getv(a, "y") + k), "#ffffff")
				P.call(((getv(a, "x") + k) + 1), (getv(a, "y") + k), "#e8f8ff")
			pass
		"muzzle":
			if truth((getv(o, "flash") > 0)):
				var col = getv(getv(AMMO, getv(build, "ammo")), "col")
				var m = getv(a, "x")
				R.call(m, (-2), 5, 5, col)
				R.call((m + 5), (-1), 5, 3, "#fff")
				R.call((m + 1), (-5), 2, 11, col)
				R.call((m - 1), (-1), 3, 3, "#fff")
				if truth((randf() < 0.5)):
					R.call((m + 3), (-4), 2, 1, "#fff")
					R.call((m + 3), 4, 2, 1, "#fff")

func draw_shout(p, t):
	var sk = skin_palette()
	var hairC = ("#c8ecff" if truth(((getv(CNT, "zero") if truth(getv(CNT, "zero")) else 0) > 0)) else "#a8a8c0")
	var n = func(id = null):
		return (getv(CNT, id) if truth(getv(CNT, id)) else 0)
	p.R(27, 11, 10, 3, getv(sk, "s"))
	p.R(27, 13, 1, 1, getv(sk, "D"))
	p.R(27, 11, 4, 1, hairC)
	p.R(33, 10, 4, 1, hairC)
	p.P(27, 12, hairC)
	p.P(36, 11, hairC)
	var jit = fmod(floor((t * 24)), 2)
	p.R(28, 13, 4, 5, getv(sk, "D"))
	p.R(29, 14, 3, 3, "#f4f0e8")
	p.P((30 + jit), 15, "#1c1214")
	if truth(((not truth(n.call("telescope"))) if truth((not truth(n.call("disint")))) else (not truth(n.call("disint"))))):
		p.R(32, 13, 5, 5, getv(sk, "D"))
		p.R(33, 14, 3, 3, "#f4f0e8")
		p.P((34 + jit), 15, "#1c1214")
	p.R(30, 19, 7, 5, "#3a1010")
	p.R(31, 19, 5, 1, "#f0ece0")
	p.R(31, 23, 5, 1, "#e0dccc")
	p.R(32, 21, 3, 2, "#c84a5a")
	p.P(33, 20, "#5a1818")


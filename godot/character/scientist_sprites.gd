extends RefCounted
## Native 128px scientist layers; gameplay weapons and effects remain live.
const DIR := "res://character/art/scientist_h3/"
const ORIGIN := Vector2(64,102)
const WORLD_SCALE := 0.75
const LEGACY_ORIGIN := Vector2(29,46)
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
static var _data: Dictionary = {}
static var _frames: Dictionary = {}
static var _parts: Dictionary = {}
static var _part_sheets: Dictionary = {}
static var _part_bounds: Dictionary = {}
static var _color: Texture2D
static var _normal: Texture2D
static var _image: Image
static var _normal_image: Image

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DIR+"body.json"))
		_color = load(DIR+"body.png"); _normal = load(DIR+"body_n.png")
		_image = _color.get_image(); _image.decompress()
		_normal_image = _normal.get_image(); _normal_image.decompress()
	return _data

static func part(name: String, pose_index: int = -1) -> CanvasTexture:
	var key := name+"/"+str(pose_index)
	if not _parts.has(key):
		var texture := CanvasTexture.new()
		if pose_index<0:
			texture.diffuse_texture = load(DIR+name+".png")
			texture.normal_texture = load(DIR+name+"_n.png")
		else:
			if not _part_sheets.has(name):
				var albedo: Image = (load(DIR+name+"_poses.png") as Texture2D).get_image(); albedo.decompress()
				var normal: Image = (load(DIR+name+"_poses_n.png") as Texture2D).get_image(); normal.decompress()
				_part_sheets[name] = [albedo,normal]
			var region := Rect2i(pose_index%8*128,pose_index/8*128,128,128)
			texture.diffuse_texture = ImageTexture.create_from_image(_part_sheets[name][0].get_region(region))
			texture.normal_texture = ImageTexture.create_from_image(_part_sheets[name][1].get_region(region))
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_parts[key] = texture
		_part_bounds[key] = texture.diffuse_texture.get_image().get_used_rect()
	return _parts[key]

static var _tinted_parts: Dictionary = {}
## A sleeve or hand with the worn coat and skin colours.
static func worn_part(name: String, pose_index: int, gear) -> CanvasTexture:
	if gear == null or not (gear.recolor.coat>0 or gear.recolor.skin): return part(name,pose_index)
	var key := "%s/%d/%d/%s" % [name,pose_index,gear.recolor.coat,gear.recolor.skin]
	if not _tinted_parts.has(key):
		var base := part(name,pose_index); var texture := CanvasTexture.new()
		texture.diffuse_texture = ImageTexture.create_from_image(gear.tint(base.diffuse_texture.get_image(),"arm"))
		texture.normal_texture = base.normal_texture; texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tinted_parts[key] = texture
	return _tinted_parts[key]

static func part_bounds(name: String, pose_index: int) -> Rect2:
	part(name,pose_index)
	return Rect2(_part_bounds[name+"/"+str(pose_index)])

static func arm_point(side: String, point: String) -> Vector2:
	var pair: Array = data().arms[side][point]
	return Vector2(pair[0],pair[1])

static func aim_pose(side: String, angle: float, recoil: float = 0.0, facing: int = 0) -> Dictionary:
	# Canonical right-facing elevation; left-facing uses the same pose bank mirrored.
	var horizontal := cos(angle)*facing if facing != 0 else absf(cos(angle))
	var elevation := rad_to_deg(atan2(sin(angle),horizontal))
	var best := 0; var distance := INF
	var poses: Array = data().poses[side]
	for i in poses.size():
		var pose: Dictionary = poses[i]
		if pose.kind != "aim": continue
		var delta := absf(float(pose.aim_degrees)-elevation)
		if delta<distance: best = i; distance = delta
	# The drawn recoil has the level aim's bent elbow. Near the extremes the arm is
	# extended, so those use the hand kick alone rather than popping to a bend.
	if recoil>0.02 and absf(elevation)<32.0:
		var kind := "recoil_high" if recoil>0.6 else ("recoil_mid" if recoil>0.3 else "recoil_low")
		for i in poses.size():
			if poses[i].kind == kind: best = i; break
	var result: Dictionary = poses[best].duplicate()
	result.index = best
	return result

## Row of the lower teeth on this frame: bright, directly under the dark open mouth. -1 if not found.
static func jaw_row(frame_data: Dictionary) -> int:
	if frame_data.has("jaw_row"): return frame_data.jaw_row
	# Strongest step from the dark mouth down to the bright teeth. Bobbing frames
	# blur that edge across two rows, so compare rows instead of using thresholds.
	var image: Image = frame_data.img; var found := -1; var best := 2.0
	for y in range(40,49):
		var step := 0.0
		for x in range(61,71):
			step += image.get_pixel(x,y).get_luminance()-image.get_pixel(x,y-1).get_luminance()
		if step>best: best = step; found = y
	frame_data.jaw_row = found
	return found

## The firing shout opens this frame's own jaw, so it always sits on the face.
static func shout_texture(frame_data: Dictionary, drop: int) -> Texture2D:
	var teeth := jaw_row(frame_data)
	if teeth<0: return frame_data.texture
	if not frame_data.has("shouts"): frame_data.shouts = {}
	if frame_data.shouts.has(drop): return frame_data.shouts[drop]
	var image: Image = frame_data.img.duplicate()
	var normal: Image = frame_data.texture.normal_texture.get_image()
	# Lower teeth and chin, including the lips on either side.
	var jaw := Rect2i(54,teeth,21,4)
	for layer in [image,normal]:
		var block: Image = layer.get_region(jaw)
		var lips: Image = layer.get_region(Rect2i(54,teeth-1,21,1))
		for i in drop: layer.blit_rect(lips,Rect2i(0,0,21,1),Vector2i(54,teeth+i))
		for y in 4:
			for x in 21:
				# Collar pixels stay where they are; only the face moves.
				var pixel: Color = frame_data.img.get_pixel(54+x,teeth+y)
				var face := pixel.a>0.5 and (pixel.r>0.55 and pixel.r>pixel.b*1.02 or pixel.get_luminance()>0.7)
				if face: layer.set_pixel(54+x,teeth+y+drop,block.get_pixel(x,y))
	# Inside of the mouth: deep shadow with a tongue resting on the lower teeth.
	for y in range(teeth,teeth+drop):
		for x in range(57,73): image.set_pixel(x,y,Color("#24040a"))
	for x in range(60,70): image.set_pixel(x,teeth+drop-1,Color("#b8404e"))
	for x in range(61,68):
		if drop>1: image.set_pixel(x,teeth+drop-2,Color("#8a2638"))
	# Chin shadow on the collar, matching the sprite's outline colour.
	for x in range(59,72):
		if image.get_pixel(x,teeth+3+drop).get_luminance()>0.35 and image.get_pixel(x,teeth+4+drop).a>0.5: image.set_pixel(x,teeth+4+drop,Color("#140810"))
	# A glint sweeping both lenses.
	var lens := teeth-17
	for glint in [Vector2i(59,lens+2),Vector2i(60,lens+1),Vector2i(61,lens),Vector2i(75,lens+2),Vector2i(76,lens+1)]:
		image.set_pixelv(glint+Vector2i(drop-2,0),Color("#e8f4ff"))
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.normal_texture = ImageTexture.create_from_image(normal)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_data.shouts[drop] = texture
	return texture

static func has_clip(name: String) -> bool: return data().clips.has(name)

static func pose_point(pose: Dictionary, point: String) -> Vector2:
	var pair: Array = pose[point]
	return Vector2(pair[0],pair[1])

static func grip_offset(side: String, pose: Dictionary = {}) -> Vector2:
	if pose.is_empty(): return (arm_point(side,"grip")-arm_point(side,"shoulder"))*WORLD_SCALE
	return (pose_point(pose,"grip")-pose_point(pose,"shoulder")).rotated(-float(pose.weapon_angle))*WORLD_SCALE

static func _tile(clip: String, index: int, armed: bool) -> Dictionary:
	var info: Dictionary = data().clips[clip]
	var fi: int = int(info.start)+posmod(index,int(info.count))
	var key := "%d/%s" % [fi,armed]
	if not _frames.has(key):
		var columns: int = data().columns
		var row: int = fi/columns+(int(data().rows_per_variant) if armed else 0)
		var region := Rect2(fi%columns*128,row*128,128,128)
		# CanvasTexture uses the underlying AtlasTexture RID without its region.
		# Upload each cell once so lit sprites use the selected animation frame.
		var image := _image.get_region(Rect2i(region))
		var texture := CanvasTexture.new()
		texture.diffuse_texture = ImageTexture.create_from_image(image)
		texture.normal_texture = ImageTexture.create_from_image(_normal_image.get_region(Rect2i(region)))
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_frames[key] = {"texture":texture,"img":image,"index":fi}
	return _frames[key]

static func head_texture(frame_data: Dictionary) -> CanvasTexture:
	if frame_data.has("native_head"): return frame_data.native_head
	var texture := CanvasTexture.new()
	var image: Image = frame_data.img.duplicate()
	# The body already has this head. This duplicate is an occlusion layer only
	# when the gun passes behind it during an overhead aiming transition.
	image.fill_rect(Rect2i(0,47,128,81),Color.TRANSPARENT)
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.normal_texture = frame_data.texture.normal_texture
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_data.native_head = texture
	return texture

static func frame(source: Dictionary, clip: String, index: int, armed: bool, gear = null) -> Dictionary:
	var tile := _tile(clip,index,armed)
	var key: String = str(tile.index)+"/"+str(armed)
	if gear != null: key += "/"+String(gear.key)
	if not source.has("native_frames"): source.native_frames = {}
	if source.native_frames.has(key): return source.native_frames[key]
	var result := source.duplicate()
	result.erase("native_frames")
	result.img = tile.img; result.texture = tile.texture
	result.skin = "scientist_h3"; result.native_index = tile.index
	var anchors := {}
	for name in data().frames[tile.index].anchors:
		var pair: Array = data().frames[tile.index].anchors[name]
		var point := (Vector2(pair[0],pair[1])-ORIGIN)*WORLD_SCALE+LEGACY_ORIGIN
		anchors[name] = {"x":point.x,"y":point.y}
	# Gear effects keep their original offsets from the closest body attachment.
	var follow = func(point: Dictionary, xkey: String, ykey: String) -> void:
		if point.get(xkey) == null or point.get(ykey) == null: return
		var nearest := ""; var distance := INF
		for name in source.anchors:
			if not anchors.has(name): continue
			var old: Dictionary = source.anchors[name]
			var delta := Vector2(float(point[xkey])-old.x,float(point[ykey])-old.y).length_squared()
			if delta<distance: nearest = name; distance = delta
		if nearest != "":
			point[xkey] += anchors[nearest].x-source.anchors[nearest].x
			point[ykey] += anchors[nearest].y-source.anchors[nearest].y
	result.anims = source.anims.duplicate(true)
	for effect in result.anims:
		follow.call(effect,"x","y"); follow.call(effect,"x2","y2")
	result.hand = source.hand.duplicate(); follow.call(result.hand,"x","y")
	result.feet = source.feet.duplicate(true)
	for foot in result.feet: follow.call(foot,"x","y")
	result.anchors = source.anchors.duplicate(true)
	result.anchors.merge(anchors,true)
	# The old painter's effects belong to the old body; worn items bring their own.
	result.anims = []
	if gear != null:
		var meta: Dictionary = data().frames[tile.index]
		var torso_at: Array = meta.get("torso",[0,0]); var head_at: Array = meta.get("head",[0,0])
		var dressed: Array = gear.dress(tile.img,tile.texture.normal_texture.get_image(),Vector2i(torso_at[0],torso_at[1]),Vector2i(head_at[0],head_at[1]))
		result.img = dressed[0]
		var texture := CanvasTexture.new()
		texture.diffuse_texture = ImageTexture.create_from_image(dressed[0]); texture.normal_texture = ImageTexture.create_from_image(dressed[1])
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		result.texture = texture
		for fx in dressed[2]:
			for pair in [["x","y"],["x2","y2"]]:
				if not fx.has(pair[0]): continue
				var at := (Vector2(fx[pair[0]],fx[pair[1]])-ORIGIN)*WORLD_SCALE+LEGACY_ORIGIN
				fx[pair[0]] = roundi(at.x); fx[pair[1]] = roundi(at.y)
			for size in ["w","h","r"]:
				if fx.has(size): fx[size] = maxi(1,roundi(float(fx[size])*WORLD_SCALE))
			result.anims.append(fx)
		if gear.recolor.boots:
			result.feet = []
			for box in dressed[3]:
				var at := (Vector2(box.position.x+2,121)-ORIGIN)*WORLD_SCALE+LEGACY_ORIGIN
				result.feet.append({"x":at.x,"y":at.y})
	if gear == null or not gear.recolor.boots: result.feet = []
	source.native_frames[key] = result
	return result

static func front_frame(source: Dictionary, moving: bool) -> Dictionary:
	if source.has("turn_front_frame"): return source.turn_front_frame
	var front := part("turn_front")
	var foreground := front.diffuse_texture.get_image().duplicate() as Image
	var foreground_normal := front.normal_texture.get_image().duplicate() as Image
	var image := source.img.duplicate() as Image
	var normal := source.texture.normal_texture.get_image().duplicate() as Image
	if moving:
		# Keep the walking legs below the waist while the head, chest and coat
		# pass through the real front-facing reference, rather than freezing a walk.
		image.fill_rect(Rect2i(0,0,128,83),Color.TRANSPARENT)
		normal.fill_rect(Rect2i(0,0,128,83),Color.TRANSPARENT)
		for layer in [foreground,foreground_normal]:
			layer.fill_rect(Rect2i(50,83,29,45),Color.TRANSPARENT)
			layer.fill_rect(Rect2i(0,110,128,18),Color.TRANSPARENT)
	else:
		image.fill(Color.TRANSPARENT); normal.fill(Color.TRANSPARENT)
	image.blend_rect(foreground,Rect2i(0,0,128,128),Vector2i.ZERO)
	normal.blend_rect(foreground_normal,Rect2i(0,0,128,128),Vector2i.ZERO)
	var result := source.duplicate(); result.erase("turn_front_frame")
	result.img = image; result.anchors = source.anchors.duplicate(true)
	for name in {"head":Vector2(64,24),"helmet":Vector2(64,6),"neck":Vector2(64,47),"mouth":Vector2(64,43)}:
		var point: Vector2 = ({"head":Vector2(64,24),"helmet":Vector2(64,6),"neck":Vector2(64,47),"mouth":Vector2(64,43)}[name]-ORIGIN)*WORLD_SCALE+LEGACY_ORIGIN
		result.anchors[name] = {"x":point.x,"y":point.y}
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	texture.normal_texture = ImageTexture.create_from_image(normal)
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.texture = texture; result.turn_front = true
	source.turn_front_frame = result
	return result

static var _reactions: Dictionary = {}
const REACTION_FPS := {"tazed":18.0,"burn":14.0,"hurt":18.0,"cackle":24.0}
## A full-body reaction frame, or null when that art is not present. "hurt" holds its last frame.
static func reaction(name: String, time: float) -> Texture2D:
	var count := int(data().get("reactions",{}).get(name,0))
	if count == 0: return null
	if not _reactions.has(name):
		var sheet: Image = (load(DIR+name+".png") as Texture2D).get_image(); sheet.decompress()
		var normals: Image = null
		if ResourceLoader.exists(DIR+name+"_n.png"):
			normals = (load(DIR+name+"_n.png") as Texture2D).get_image(); normals.decompress()
		var list: Array = []
		for i in count:
			var region := Rect2i(i%8*128,i/8*128,128,128)
			if normals == null: list.append(ImageTexture.create_from_image(sheet.get_region(region))); continue
			var texture := CanvasTexture.new()
			texture.diffuse_texture = ImageTexture.create_from_image(sheet.get_region(region))
			texture.normal_texture = ImageTexture.create_from_image(normals.get_region(region))
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			list.append(texture)
		_reactions[name] = list
	var index := int(time*float(REACTION_FPS[name]))
	return _reactions[name][mini(index,count-1) if name == "hurt" else posmod(index,count)]

static func xray(frame_data: Dictionary) -> Texture2D:
	if frame_data.has("native_xray"): return frame_data.native_xray
	var image: Image = frame_data.img
	var raster = Pixels.new(128,128)
	for y in 128:
		for x in 128:
			var pixel := image.get_pixel(x,y)
			if pixel.a>0: raster.image.set_pixel(x,y,Color(0.15,0.28,0.8,pixel.a))
	var p = Pen.new(raster)
	var point = func(name: String) -> Vector2:
		var at: Dictionary = frame_data.anchors[name]
		return (Vector2(at.x,at.y)-LEGACY_ORIGIN)/WORLD_SCALE+ORIGIN
	for pair in [["neck","hip"],["shoulderFar","shoulderNear"],["hip","kneeBack"],
		["kneeBack","footBack"],["hip","kneeFront"],["kneeFront","footFront"]]:
		var a: Vector2 = point.call(pair[0]); var b: Vector2 = point.call(pair[1])
		p.line(a.x,a.y,b.x,b.y,"#f6fbff",2)
	var head: Vector2 = point.call("head")
	p.ell(head.x,head.y,11,11,"#f6fbff")
	frame_data.native_xray = ImageTexture.create_from_image(raster.image)
	return frame_data.native_xray

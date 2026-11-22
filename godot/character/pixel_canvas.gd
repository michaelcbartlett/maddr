extends RefCounted
## Albedo + physical height rasterizer. Normals use the prototype's clamped Sobel filter.
const Profiles = preload("res://character/height_profiles.gd")
var image: Image
var width: int
var height: int
var depth := PackedFloat32Array()
var occupied := PackedByteArray()
var alpha := 1.0
var _outlined: Image
var _normal: Image
static var _shades: Dictionary = {}

func _init(w: int, h: int) -> void:
	width = w; height = h
	image = Image.create(w,h,false,Image.FORMAT_RGBA8)
	depth.resize(w*h); occupied.resize(w*h)

func clearRect(x, y, w, h) -> void:
	image.fill_rect(Rect2i(x,y,w,h), Color.TRANSPARENT)

func ensure_width(required: int) -> void:
	# Called before painting a gun, after the module layout is known.
	if required <= width: return
	width = required; image = Image.create(width,height,false,Image.FORMAT_RGBA8)
	depth.resize(width*height); occupied.resize(width*height)

func rect(bounds: Rect2i, color: Color, base: float, profile, ox: float, oy: float) -> void:
	var clipped = bounds.intersection(Rect2i(0,0,width,height))
	if clipped.size.x <= 0 or clipped.size.y <= 0: return
	color.a *= alpha
	if color.a >= 1.0: image.fill_rect(clipped, color)
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			if color.a < 1.0: image.set_pixel(x,y,image.get_pixel(x,y).blend(color))
			var index = y*width+x
			depth[index] = base + Profiles.sample(profile, x-ox, y-oy)
			occupied[index] = 1

func outlined_image() -> Image:
	if _outlined: return _outlined
	var w = width+2; var h = height+2
	_outlined = Image.create(w,h,false,Image.FORMAT_RGBA8)
	_outlined.blit_rect(image,Rect2i(0,0,width,height),Vector2i.ONE)
	var raw = _outlined.get_data(); var filled = PackedByteArray(); filled.resize(w*h)
	var padded = PackedFloat32Array(); padded.resize(w*h)
	for y in height:
		for x in width:
			var dest = (y+1)*w+x+1; var src = y*width+x
			if occupied[src]: padded[dest] = depth[src]; filled[dest] = 1
	for y in h:
		for x in w:
			var index = y*w+x
			if raw[index*4+3] > 0: continue
			var best = -1; var top = false; var rim_height = -INF
			for delta in [Vector2i(0,1),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0)]:
				var q = Vector2i(x,y)+delta
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h: continue
				var neighbor = q.y*w+q.x
				if raw[neighbor*4+3] > 0 and (best < 0 or raw[neighbor*4+3] > raw[best*4+3]):
					best = neighbor; top = delta.y == 1
				if filled[neighbor] == 1: rim_height = maxf(rim_height,padded[neighbor])
			if best >= 0:
				var k = 0.4 if top else 0.24
				_outlined.set_pixel(x,y,Color8(int(floor(raw[best*4]*k*0.8+12.5)),int(floor(raw[best*4+1]*k*0.8+8.5)),int(floor(raw[best*4+2]*k+24.5))))
			if rim_height >= 0:
				padded[index] = rim_height*0.75; filled[index] = 2
	width = w; height = h; depth = padded; occupied = filled
	return _outlined

func _difference(x: int, y: int, center: float) -> float:
	if x < 0 or y < 0 or x >= width or y >= height or not occupied[y*width+x]: return -2.5
	return clampf(depth[y*width+x]-center,-2.5,2.5)

func normal_image() -> Image:
	if _normal: return _normal
	if not _outlined: outlined_image()
	_normal = Image.create(width,height,false,Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var index = y*width+x
			if not occupied[index]: continue
			var center = depth[index]
			var gx = _difference(x+1,y-1,center)+2*_difference(x+1,y,center)+_difference(x+1,y+1,center)-_difference(x-1,y-1,center)-2*_difference(x-1,y,center)-_difference(x-1,y+1,center)
			var gy = _difference(x-1,y+1,center)+2*_difference(x,y+1,center)+_difference(x+1,y+1,center)-_difference(x-1,y-1,center)-2*_difference(x,y-1,center)-_difference(x+1,y-1,center)
			var normal = Vector3(-gx/8.0,gy/8.0,1.0).normalized()
			_normal.set_pixel(x,y,Color8(int(floor((normal.x*0.5+0.5)*255+0.5)),int(floor((normal.y*0.5+0.5)*255+0.5)),int(floor((normal.z*0.5+0.5)*255+0.5))))
	return _normal

static func shade(hex: String, amount: float) -> String:
	var key = hex+str(amount)
	if _shades.has(key): return _shades[key]
	# Match the source painter's numeric HSL input, including its short-hex shades.
	var packed = hex.substr(1).hex_to_int()
	var color = Color8((packed>>16)&255,(packed>>8)&255,packed&255)
	var highest = maxf(color.r,maxf(color.g,color.b)); var lowest = minf(color.r,minf(color.g,color.b))
	var lightness = (highest+lowest)/2.0; var hue = 0.0; var saturation = 0.0
	if highest != lowest:
		var delta = highest-lowest
		saturation = delta/(2.0-highest-lowest) if lightness>0.5 else delta/(highest+lowest)
		if highest == color.r: hue = (color.g-color.b)/delta+(6.0 if color.g<color.b else 0.0)
		elif highest == color.g: hue = (color.b-color.r)/delta+2.0
		else: hue = (color.r-color.g)/delta+4.0
		hue *= 60.0
	var fraction = minf(1.0,absf(amount))
	if amount < 0:
		if saturation < 0.06: hue = 235.0
		hue += (fposmod(235.0-hue+540.0,360.0)-180.0)*fraction*0.28
		saturation = minf(1.0,saturation+fraction*0.18); lightness *= 1.0-fraction
	else:
		if saturation < 0.06: hue = 50.0
		hue += (fposmod(52.0-hue+540.0,360.0)-180.0)*fraction*0.2
		if saturation < 0.06: saturation = minf(1.0,saturation+fraction*0.12)
		lightness += (1.0-lightness)*fraction
	hue = fposmod(hue,360.0)
	var channels: Array[int] = []
	for n in [0.0,8.0,4.0]:
		var k = fposmod(n+hue/30.0,12.0); var a = saturation*minf(lightness,1.0-lightness)
		channels.append(int(floor(255.0*(lightness-a*maxf(-1.0,minf(minf(k-3.0,9.0-k),1.0)))+0.5)))
	var result = "#%02x%02x%02x" % channels
	_shades[key] = result
	return result

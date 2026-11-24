extends Node2D
## Sprite-sheet scenery with a shared prop/collision record and live police lamps.
const CATALOG_PATH := "res://art/vehicles/catalog.json"
const LightPoolScript = preload("res://fx/light_pool.gd")
static var _catalog: Array=[]
static var _textures: Dictionary={}
static var _lens_masks: Dictionary={}
const BODY_HEIGHT := 38.0
const BUMPER_CLEARANCE := 8.0
var record: Dictionary={}
var kind := "car"
var sprite: Sprite2D
var lens_red: Sprite2D
var lens_blue: Sprite2D
var _bulbs: Array[Vector2]=[]
var _phase:=0.0
var _clock:=0.0
var _scale:=1.0
var _police:=false

static func catalog() -> Array:
	if _catalog.is_empty(): _catalog=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return _catalog

static func model(id: String) -> Dictionary:
	for entry in catalog():
		if entry.id==id: return entry
	return catalog()[0]

static func visual_size(id: String, view: String) -> Vector2:
	var data:=model(id)
	var bounds: Array=data.frames[view].region
	var factor:=float(data.world_length)/float(data.frames.left.region[2])
	return Vector2(bounds[2],bounds[3])*factor

static func footprint(id: String, view: String) -> Vector2:
	var visible:=visual_size(id,view)
	# The old nominal dimensions were narrower than the rendered hood/bumpers.
	# Cover the complete painted body, leaving room for the scientist's head
	# beyond his small gameplay hit circle. Only the elevated body height is
	# removed from the ground footprint; the sprite stays anchored at its wheels.
	return Vector2(visible.x+BUMPER_CLEARANCE*2.0,maxf(24.0,visible.y-BODY_HEIGHT))

func setup(data: Dictionary) -> void:
	record=data; position=Vector2(data.rect.get_center().x,data.rect.end.y)
	var entry:=model(data.vehicle_id); var frame: Dictionary=entry.frames[data.view]
	if not _textures.has(entry.id):
		# Lit by MoGe normals when the sheet has them (tools/pixelstudio/build_vehicle_normals.py).
		var lit:=CanvasTexture.new(); lit.diffuse_texture=load(entry.sheet)
		var normals:=String(entry.sheet).replace(".png","_n.png")
		if ResourceLoader.exists(normals): lit.normal_texture=load(normals)
		lit.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; _textures[entry.id]=lit
	var bounds:=Rect2(frame.region[0],frame.region[1],frame.region[2],frame.region[3])
	_scale=float(entry.world_length)/float(entry.frames.left.region[2])
	sprite=Sprite2D.new(); sprite.centered=false; sprite.texture=_textures[entry.id]
	sprite.region_enabled=true; sprite.region_rect=bounds
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position=Vector2(-bounds.size.x*0.5,-bounds.size.y)*_scale; sprite.scale=Vector2.ONE*_scale
	add_child(sprite)
	_police=entry.police; _phase=float(data.get("siren_phase",0.0))
	if _police:
		for point in frame.bulbs: _bulbs.append(sprite.position+Vector2(point[0],point[1])*_scale)
		var material:=CanvasItemMaterial.new(); material.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED; material.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
		for i in 2:
			var region: Array=frame.lens_regions[i]
			var lens:=Sprite2D.new(); lens.texture=_lens_mask(entry,frame,String(data.view),i); lens.material=material
			# Share the base sprite's origin, scale and source-pixel offset. This
			# avoids independently snapped rectangles drifting off the roof glass.
			lens.centered=false; lens.position=sprite.position; lens.scale=sprite.scale
			lens.offset=Vector2(region[0],region[1]); lens.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			lens.set_meta("emitter_pixel",Vector2(frame.bulbs[i][0],frame.bulbs[i][1]))
			lens.modulate=Color("#ff4433") if i==0 else Color("#398bff")
			add_child(lens)
			if i==0: lens_red=lens
			else: lens_blue=lens
	update_visual(0.0); queue_redraw()

static func _lens_mask(entry: Dictionary, frame: Dictionary, view: String, index: int) -> Texture2D:
	var key:=String(entry.id)+"/"+view+"/"+str(index)
	if not _lens_masks.has(key):
		var source: Image=(_textures[entry.id] as CanvasTexture).diffuse_texture.get_image()
		if source.is_compressed(): source.decompress()
		var region: Array=frame.lens_regions[index]
		var image:=Image.create(region[2],region[3],false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
		for y in image.get_height():
			for x in image.get_width():
				var color:=source.get_pixel(frame.region[0]+region[0]+x,frame.region[1]+region[1]+y)
				var colored: bool=(color.r>56.0/255.0 and color.r>color.g*1.45 and color.r>color.b*1.2) if index==0 else (color.b>56.0/255.0 and color.b>color.r*1.35 and color.b>color.g*1.08)
				if colored and color.a>0.5: image.set_pixel(x,y,Color(1,1,1,color.a*(0.25+0.55*maxf(color.r,maxf(color.g,color.b)))))
		_lens_masks[key]=ImageTexture.create_from_image(image)
	return _lens_masks[key]

func siren_on(red: bool) -> bool:
	if not _police or record.get("broken",false): return false
	var cycle:=fposmod(_clock+_phase,0.9)
	if red: return cycle<0.13 or (cycle>=0.2 and cycle<0.33)
	return (cycle>=0.45 and cycle<0.58) or (cycle>=0.65 and cycle<0.78)

func update_visual(clock: float) -> void:
	_clock=clock
	if sprite==null: return
	var broken: bool=record.get("broken",false)
	sprite.modulate=Color("#32323c") if broken else Color.WHITE.darkened(float(record.get("char",0.0))*0.6)
	if float(record.get("flash",0.0))>0.0 and not broken: sprite.modulate=Color(1.6,1.6,1.6)
	sprite.scale=Vector2(_scale,_scale*(0.32 if broken else 1.0))
	var bounds: Rect2=sprite.region_rect
	sprite.position=Vector2(-bounds.size.x*0.5,-bounds.size.y*(0.32 if broken else 1.0))*_scale
	if _police: lens_red.visible=siren_on(true); lens_blue.visible=siren_on(false)
	queue_redraw()

func glows() -> Array:
	var result: Array=[]
	if _police:
		for i in 2:
			if siren_on(i==0): result.append({"pos":to_global(_bulbs[i]),"col":Color("#ff342c") if i==0 else Color("#3f82ff"),"e":1.5,"r":235.0,"height":60.0,"glow":18.0})
	return result

func wet_emissions() -> Array:
	var result: Array=[]
	for light in glows():
		var reflected: Dictionary=light.duplicate()
		# Use the same foot plane and compression as the mirrored sprite pass.
		reflected.pos=Vector2(light.pos.x,global_position.y*1.65-light.pos.y*0.65)
		result.append(reflected)
	return result

func _draw() -> void:
	if record.is_empty(): return
	var footprint: Rect2=record.rect
	draw_set_transform(Vector2(0,-footprint.size.y*0.45),0.0,footprint.size*Vector2(0.48,0.45))
	draw_circle(Vector2.ZERO,1.0,Color(0,0,0,0.22)); draw_set_transform(Vector2.ZERO)

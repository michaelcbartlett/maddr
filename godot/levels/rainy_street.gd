extends RefCounted
## Empty street block, sized for the 128px scientist. No encounter geometry.
const SIZE := Vector2i(3200,2200)
const SPAWN := Vector2(1600,1160)
const NORTH := 870
const SOUTH := 1330
const WEST := 1400
const EAST := 1800
const Vehicles = preload("res://levels/parked_vehicle.gd")
static var _water: Image
static var _wet_cells := {}

static func water_image() -> Image:
	if _water!=null: return _water
	_water=Image.create(SIZE.x/4,SIZE.y/4,false,Image.FORMAT_RF)
	var noise:=FastNoiseLite.new(); noise.seed=231123; noise.frequency=0.008
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.fractal_octaves=3
	for y in _water.get_height():
		for x in _water.get_width():
			var value:=noise.get_noise_2d(x*4.0,y*6.0)*0.5+0.5
			_water.set_pixel(x,y,Color(value,0,0))
			if value>0.525: _wet_cells[Vector2i(x/16,y/16)]=true
	return _water

static func water_near(rect: Rect2) -> bool:
	water_image()
	for y in range(floori(rect.position.y/64.0),ceili(rect.end.y/64.0)+1):
		for x in range(floori(rect.position.x/64.0),ceili(rect.end.x/64.0)+1):
			if _wet_cells.has(Vector2i(x,y)): return true
	return false

static func lamp_positions() -> Array:
	var out: Array = []
	for x in [300,820,1340,1860,2380,2900]:
		out.append(Vector2(x,NORTH-16)); out.append(Vector2(x,SOUTH+28))
	for y in [240,570,1710,2080]:
		out.append(Vector2(WEST-30,y)); out.append(Vector2(EAST+30,y))
	return out

static func crosswalks() -> Array[Rect2]:
	return [Rect2(WEST,NORTH-92,EAST-WEST,64),Rect2(WEST,SOUTH+28,EAST-WEST,64),
		Rect2(WEST-92,NORTH,64,SOUTH-NORTH),Rect2(EAST+28,NORTH,64,SOUTH-NORTH)]

static func parking_layout(seed_value: int) -> Array:
	var rng:=RandomNumberGenerator.new(); rng.seed=seed_value
	var slots: Array=[]
	for x in [180,500,820,1140,2060,2380,2700,3020]:
		slots.append({"at":Vector2(x,NORTH+72),"view":"left"})
		slots.append({"at":Vector2(x,SOUTH-72),"view":"right"})
	for y in [180,520,1730,2040]:
		slots.append({"at":Vector2(WEST+85,y),"view":"front"})
		slots.append({"at":Vector2(EAST-85,y),"view":"rear"})
	for i in range(slots.size()-1,0,-1):
		var j:=rng.randi_range(0,i); var slot=slots[i]; slots[i]=slots[j]; slots[j]=slot
	var ids: Array=[]
	for data in Vehicles.catalog(): ids.append(data.id)
	for i in range(ids.size()-1,0,-1):
		var j:=rng.randi_range(0,i); var id=ids[i]; ids[i]=ids[j]; ids[j]=id
	ids.append("police-sedan") # At least two cruisers, with staggered live lightbars.
	var weighted: Array=["boxy-sedan","boxy-sedan","compact-hatchback","compact-hatchback","grand-wagoneer","pickup","cargo-van","police-sedan","delorean"]
	var result: Array=[]; var count:=rng.randi_range(16,20)
	for slot in slots:
		if result.size()>=count: break
		var id: String=ids[result.size()] if result.size()<ids.size() else weighted[rng.randi_range(0,weighted.size()-1)]
		var position: Vector2=slot.at
		if slot.view in ["left","right"]: position+=Vector2(rng.randf_range(-16,16),rng.randf_range(-3,3))
		else: position+=Vector2(rng.randf_range(-3,3),rng.randf_range(-16,16))
		var size:=Vehicles.footprint(id,slot.view); var rect:=Rect2((position-size/2.0).round(),size.round())
		if rect.grow(24).has_point(SPAWN): continue
		if crosswalks().any(func(c): return c.grow(16).intersects(rect)): continue
		if result.any(func(p): return p.rect.grow(14).intersects(rect)): continue
		if lamp_positions().any(func(p): return rect.grow(18).has_point(p)): continue
		result.append({"rect":rect,"view":slot.view,"vehicle_id":id,"siren_phase":rng.randf_range(0,0.9)})
	return result

static func make_floor() -> Image:
	var image := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	image.fill(Color("#303944"))
	var rng := RandomNumberGenerator.new(); rng.seed = 237119
	# Broad concrete pavements, understated slab joints and raised kerbs.
	for y in range(0,SIZE.y,56):
		for x in range(0,SIZE.x,64):
			image.fill_rect(Rect2i(x+1,y+1,62,54).intersection(Rect2i(Vector2i.ZERO,SIZE)),
				[Color("#353f49"),Color("#37414b"),Color("#323c46")][rng.randi()%3])
	image.fill_rect(Rect2i(0,NORTH-10,SIZE.x,SOUTH-NORTH+20),Color("#657079"))
	image.fill_rect(Rect2i(WEST-10,0,EAST-WEST+20,SIZE.y),Color("#657079"))
	image.fill_rect(Rect2i(0,NORTH-3,SIZE.x,SOUTH-NORTH+6),Color("#111b25"))
	image.fill_rect(Rect2i(WEST-3,0,EAST-WEST+6,SIZE.y),Color("#111b25"))
	image.fill_rect(Rect2i(0,NORTH,SIZE.x,SOUTH-NORTH),Color("#222e39"))
	image.fill_rect(Rect2i(WEST,0,EAST-WEST,SIZE.y),Color("#222e39"))
	# Sparse fine grain reads as asphalt without competing with the character.
	for i in 36000:
		var p := Vector2i(rng.randi_range(0,SIZE.x-3),rng.randi_range(0,SIZE.y-3))
		if (p.y>NORTH and p.y<SOUTH) or (p.x>WEST and p.x<EAST):
			image.fill_rect(Rect2i(p,Vector2i(2,2)),[Color("#27343f"),Color("#1d2934")][rng.randi()%2])
	var paint := Color("#a39a71")
	for x in range(32,SIZE.x-72,128):
		if x>WEST-200 and x<EAST+120: continue
		image.fill_rect(Rect2i(x,1091,64,3),paint); image.fill_rect(Rect2i(x,1105,64,3),paint)
	for y in range(20,SIZE.y-72,128):
		if y>NORTH-180 and y<SOUTH+100: continue
		image.fill_rect(Rect2i(1592,y,3,64),paint); image.fill_rect(Rect2i(1606,y,3,64),paint)
	# Four crosswalks with worn paint and a clear open intersection.
	for x in range(WEST+30,EAST-30,42):
		image.fill_rect(Rect2i(x,NORTH-92,22,64),Color("#8b979f"))
		image.fill_rect(Rect2i(x,SOUTH+28,22,64),Color("#8b979f"))
	for y in range(NORTH+30,SOUTH-30,44):
		image.fill_rect(Rect2i(WEST-92,y,64,22),Color("#8b979f"))
		image.fill_rect(Rect2i(EAST+28,y,64,22),Color("#8b979f"))
	for i in 1600:
		var p := Vector2i(rng.randi_range(WEST-100,EAST+100),rng.randi_range(NORTH-100,SOUTH+100))
		if image.get_pixelv(p)==Color("#8b979f"): image.fill_rect(Rect2i(p,Vector2i(2,1)),Color("#596775"))
	# Kerb seams keep the street from reading as a flat painted rectangle.
	for x in range(0,SIZE.x,64):
		if x>=WEST-16 and x<=EAST+16: continue
		for y in [NORTH-9,SOUTH+4]: image.fill_rect(Rect2i(x,y,2,6),Color("#29333f"))
	for y in range(0,SIZE.y,64):
		if y>=NORTH-16 and y<=SOUTH+16: continue
		for x in [WEST-9,EAST+4]: image.fill_rect(Rect2i(x,y,6,2),Color("#29333f"))
	return image

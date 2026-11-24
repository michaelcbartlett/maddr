extends RefCounted
## Worn items for the native scientist, painted in 128px cell coordinates on three layers:
## `back` (behind the body), `torso` and `head`. Each layer follows that frame's tracked offset.
## Coat, skin, hair and shoe changes are recolors, so they also reach the separate sleeves and hands.
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Profiles = preload("res://character/height_profiles.gd")

## Every item that changes the body (gun-only items are drawn by the weapon renderer).
const WORN := ["coat","boots","magnet","serum","thermite","acid","poison","bleed","tesla","cryo","hypno","virus","grenade","clock","remote",
	"syringe","goggles","greed","disint","reactor","hive","zero","storm","nuke","moon","mutagen","singular","telescope","monocle","tesla_helmet",
	"core_isotope","core_hamster","core_battery","core_brain","vault_plating","payraise","teleport","zigzag","iron_slam","spores"]

var back
var torso
var head
var images: Dictionary = {}
var anims: Array = []          # {layer, effect} in cell coordinates
var recolor: Dictionary = {}   # coat level, skin, hair, boots, ankles
var key := ""

static func has_any(items: Array) -> bool:
	return items.any(func(id): return id in WORN)

func build(items: Array) -> RefCounted:
	var n := {}
	for id in items: n[id] = int(n.get(id,0))+1
	key = JSON.stringify(n)
	back = Pixels.new(128,128); torso = Pixels.new(128,128); head = Pixels.new(128,128)
	recolor = {"coat":int(n.get("coat",0)),"skin":n.has("mutagen"),"hair":n.has("zero"),"boots":n.has("boots"),
		"zigzag":n.has("zigzag"),"pistons":n.has("iron_slam")}
	_paint_back(Pen.new(back),n); _paint_torso(Pen.new(torso),n); _paint_head(Pen.new(head),n)
	for name in ["back","torso","head"]:
		var canvas = get(name)
		if not canvas.occupied.has(1): continue
		images[name] = [canvas.outlined_image(),canvas.normal_image()]   # 130x130, offset by -1
	return self

func has_recolor() -> bool:
	return recolor.coat>0 or recolor.skin or recolor.hair or recolor.boots

func _fx(layer: String, effect: Dictionary) -> void: anims.append({"layer":layer,"fx":effect})

# ---------------------------------------------------------------- behind the body
func _paint_back(p, n: Dictionary) -> void:
	if n.has("syringe"):                                        # vampire cape
		p.layer(2,Profiles.slab(22,48,86,112,3,3))
		for y in range(48,114):
			var u := (y-48)/66.0
			var left := roundi(34-16*u); var right := roundi(74+14*u)
			p.R(left,y,right-left,1,"#7a1020"); p.R(left,y,3,1,"#540814"); p.R(right-3,y,3,1,"#540814")
			for fold in [0.25,0.5,0.75]: p.R(roundi(lerpf(left,right,fold)),y,2,1,"#931a2c")
		for x in range(18,88,6): p.R(x,112,3,2,"#540814")
		p.layer(4,Profiles.slab(34,38,44,54,2,2)); p.R(34,38,9,16,"#a01828"); p.R(35,39,3,14,"#e03848")
		p.layer(4,Profiles.slab(70,40,78,54,2,2)); p.R(71,40,8,14,"#a01828"); p.R(72,41,3,12,"#e03848")
	var pack: bool = n.has("magnet") or n.has("remote") or n.has("moon")
	if n.has("core_isotope"):
		p.layer(5,Profiles.slab(9,46,35,51,2,2)); p.box(10,46,25,5,"#8a8a8a")
		p.layer(4,Profiles.cylV(22,13,6)); p.R(9,51,27,34,"#24342a")
		p.layer(5,Profiles.cylV(22,11,6)); p.R(11,53,23,30,"#4dc81a"); p.R(11,53,23,3,"#8dff4a"); p.R(13,56,4,24,"#b8ff80"); p.R(13,56,2,5,"#f0ffe0"); p.R(31,56,2,26,"#3a9a14")
		p.layer(6,Profiles.slab(9,62,35,64,1,1)); p.R(9,62,27,2,"#2a3a2e"); p.R(9,73,27,2,"#2a3a2e")
		p.layer(5,Profiles.slab(9,85,35,90,2,2)); p.box(10,85,25,5,"#8a8a8a")
		p.layer(6,Profiles.dome(22,44,4,2,2)); p.R(19,43,7,3,"#ffd23c")
		_fx("back",{"k":"tank","x":12,"y":54,"w":21,"h":28,"c":"#e0ffc8"}); _fx("back",{"k":"pulse","x":18,"y":68,"r":9,"c":"#7dff3a","a":0.18})
	elif n.has("core_hamster"):
		p.layer(3,Profiles.cylV(14,2,2)); p.R(13,82,3,10,"#666"); p.R(27,82,3,10,"#666"); p.R(10,91,23,3,"#555")
		p.layer(4,Profiles.dome(20,70,17,17,3)); p.ell(20,70,16,16,"#2c3038")
		for r in [17,16]: p.ring(20,70,r,"#8a8e96"); p.ring(20,70,r-2,"#5a5e66")
		_fx("back",{"k":"wheel","x":20,"y":70,"r":16})
	elif n.has("core_battery"):
		p.layer(4,Profiles.slab(7,54,37,88,5,3)); p.box(8,54,29,34,"#26282c"); p.R(8,54,29,6,"#c83030"); p.R(8,54,29,2,"#ff6a6a"); p.R(10,62,2,24,"#3a3e44")
		p.layer(6,Profiles.dome(14,50,3,3,2)); p.box(11,48,6,6,"#c83030"); p.R(12,49,2,2,"#ffffff")
		p.layer(6,Profiles.dome(30,50,3,3,2)); p.box(27,48,6,6,"#9aa4ae")
		p.layer(8,Profiles.slab(13,66,31,76,1,1)); p.R(13,67,18,9,"#ffd23c")
		for bolt in [[22,68],[21,70],[20,72],[23,71],[22,73]]: p.R(bolt[0],bolt[1],3,2,"#26282c")
		_fx("back",{"k":"spark","x":14,"y":46}); _fx("back",{"k":"spark","x":30,"y":46})
	elif n.has("core_brain"):
		p.layer(5,Profiles.slab(8,44,36,49,2,2)); p.box(9,44,27,5,"#7a7a7a")
		p.layer(4,Profiles.cylV(22,14,6)); p.R(8,49,29,36,"#5fa6b8"); p.R(10,51,25,32,"#9ed8e6"); p.R(11,51,4,32,"#dcf4fa"); p.R(33,51,2,32,"#78b8c8")
		p.layer(7,Profiles.dome(22,65,9,8,5)); p.ell(22,65,9,8,"#ff8fb0")
		for groove in [[16,61,2,7],[21,59,2,10],[26,62,2,6],[18,57,7,1],[19,70,6,1]]: p.R(groove[0],groove[1],groove[2],groove[3],"#d0607e")
		p.R(18,58,6,2,"#ffc0d4"); p.R(21,73,2,8,"#e07090")
		p.layer(5,Profiles.slab(8,85,36,90,2,2)); p.box(9,85,27,5,"#7a7a7a")
		_fx("back",{"k":"jar","x":12,"y":52,"w":20,"h":29}); _fx("back",{"k":"pulse","x":22,"y":65,"r":8,"c":"#ff8fb0","a":0.15})
	elif pack:
		p.layer(4,Profiles.slab(12,52,36,84,4,3)); p.box(13,52,24,32,"#5a5e66"); p.R(15,60,20,2,"#3a3e46"); p.R(15,71,20,2,"#3a3e46"); p.R(16,55,3,3,"#44ff66")
	if n.has("magnet"):
		p.layer(3,Profiles.slab(2,16,25,44,4,3))
		p.R(3,18,7,20,"#d83030"); p.R(18,18,7,20,"#d83030"); p.R(3,34,22,8,"#d83030"); p.R(5,42,18,2,"#a02020")
		p.R(3,18,2,22,"#ff7a7a"); p.R(18,18,2,16,"#ff7a7a")
		p.layer(4,Profiles.slab(2,11,25,18,2,1)); p.box(3,12,7,6,"#e8e8f0"); p.box(18,12,7,6,"#e8e8f0")
		p.layer(4,Profiles.cylV(14,2,2)); p.R(12,44,4,9,"#555555")
		_fx("back",{"k":"spark","x":14,"y":9,"c":"#8fd8ff"})
	if n.has("remote"):
		p.layer(5,Profiles.cap(29,54,20,4,1.5,1)); p.line(29,54,21,4,"#8a8a8a",2); p.R(27,51,5,5,"#333333")
		_fx("back",{"k":"led","x":21,"y":3,"c":"#ff3030"})
	if n.has("moon"):
		p.layer(4,Profiles.cap(16,52,12,24,2,1.5)); p.line(16,52,12,24,"#777777",3)
		p.layer(5,Profiles.dome(11,20,11,6,3)); p.ell(11,20,11,5,"#a8a8b0"); p.ell(11,19,9,3,"#c8c8d0"); p.R(3,17,12,1,"#e8e8f0")
		p.line(11,18,11,9,"#888888",2)
		_fx("back",{"k":"led","x":11,"y":8,"c":"#ff3030"})

# ---------------------------------------------------------------- torso
func _paint_torso(p, n: Dictionary) -> void:
	var lvl: int = n.get("coat",0)
	if lvl>0:
		p.layer(12)
		for rivet in [[47,58],[46,70],[45,84],[43,98],[75,62],[76,76],[78,92]]: p.R(rivet[0],rivet[1],2,2,"#4a4a52"); p.R(rivet[0],rivet[1],1,1,"#aab0be")
	if lvl>=3:
		p.layer(14,Profiles.slab(55,51,73,74,3,2)); p.box(56,51,17,23,"#7a8292"); p.R(58,53,13,2,"#9aa2b2")
		for bolt in [[58,56],[69,56],[58,70],[69,70]]: p.R(bolt[0],bolt[1],2,2,"#3c424e")
	if n.has("vault_plating"):                                  # riveted steel slabs
		for plate in [[38,62,15,18],[52,84,10,16],[70,84,10,15]]:
			p.layer(14,Profiles.slab(plate[0],plate[1],plate[0]+plate[2],plate[1]+plate[3],2,2)); p.box(plate[0],plate[1],plate[2],plate[3],"#8b93a0"); p.R(plate[0]+2,plate[1]+2,plate[2]-5,1,"#c3cad4")
			for c in [[1,1],[plate[2]-3,1],[1,plate[3]-3],[plate[2]-3,plate[3]-3]]: p.R(plate[0]+c[0],plate[1]+c[1],2,2,"#4b515c")
	if lvl>=2:                                                  # far pad; the near shoulder is the moving sleeve
		p.layer(15,Profiles.dome(76,52,6,5,4)); p.box(71,48,10,7,"#6a7282"); p.R(72,49,7,2,"#9aa2b2"); p.R(73,52,2,2,"#c0c8d4")
	if n.has("magnet") or n.has("remote") or n.has("moon") or n.has("core_isotope") or n.has("core_hamster") or n.has("core_battery") or n.has("core_brain"):
		p.layer(13,Profiles.cap(47,48,45,78,2,1)); p.line(48,48,46,78,"#4a3424",4); p.line(47,48,45,78,"#6a4c36",1)
		p.R(44,62,5,4,"#c9a227"); p.R(45,63,2,1,"#fff0a0")
	if n.has("bleed"):
		p.layer(12)
		for s in [[43,66,4,3],[46,70,2,2],[41,72,2,3],[75,70,3,4],[77,76,2,2],[42,94,3,4],[46,99,2,2],[76,92,3,3],[50,58,2,2]]: p.R(s[0],s[1],s[2],s[3],"#a01020"); p.R(s[0],s[1],1,1,"#d03040")
	if n.has("acid"):
		p.layer(12)
		for s in [[38,98,6,4],[42,102,3,3],[76,88,4,6],[47,90,3,3]]: p.R(s[0],s[1],s[2],s[3],"#b8c830"); p.R(s[0]+1,s[1]+1,2,1,"#1a1a1a"); p.R(s[0],s[1],2,1,"#e8f86a")
	if n.has("spores"):
		p.layer(14,Profiles.dome(77,100,3,3,2)); p.ell(77,100,3,3,"#6fae3a"); p.R(76,98,2,2,"#c8f07a"); _fx("torso",{"k":"mist","x":77,"y":97})
	if n.has("nuke"):
		p.layer(14,Profiles.slab(44,66,54,76,1,1)); p.box(44,66,10,10,"#ffd23c")
		p.R(48,70,2,2,"#222222"); p.R(46,68,2,2,"#222222"); p.R(50,68,2,2,"#222222"); p.R(48,73,2,2,"#222222")
	if n.has("hypno"):
		p.layer(15,Profiles.dome(47,88,4,4,2)); p.ell(47,88,4,4,"#9a40d0"); p.ring(47,88,3,"#f0c8ff"); p.R(46,87,3,3,"#5a1a8a"); p.P(47,88,"#ffffff")
	if n.has("virus"):
		p.layer(14,Profiles.slab(74,66,82,74,1,1)); p.box(74,66,7,8,"#b0d030"); p.R(77,69,1,2,"#222222"); p.R(75,71,1,1,"#222222"); p.R(79,71,1,1,"#222222")
	if n.has("reactor"):
		p.layer(17,Profiles.dome(65,62,6,6,3)); p.ell(65,62,6,6,"#3b4652"); p.ell(65,62,5,5,"#2f6a2a"); p.ell(65,62,3,3,"#7dff3a"); p.ell(65,62,1,1,"#e8ffe0"); p.R(62,58,3,1,"#8ea0b0")
		_fx("torso",{"k":"pulse","x":65,"y":62,"r":6,"c":"#7dff3a","a":0.35})
	if n.has("grenade"):                                        # bandolier
		p.layer(14,Profiles.cap(49,50,75,82,3,2)); p.line(50,50,74,80,"#4a3418",5); p.line(50,49,74,79,"#7a5a30",2)
		for u in [0.22,0.5,0.78]:
			var gx := roundi(lerpf(50,74,u)); var gy := roundi(lerpf(50,80,u))
			p.layer(17,Profiles.dome(gx,gy,3,4,3)); p.ell(gx,gy,3,4,"#4a6a2a"); p.R(gx-1,gy-3,2,3,"#7c9c44"); p.R(gx,gy-6,2,2,"#cccccc")
	if n.has("greed"):
		p.layer(15); p.line(53,48,65,60,"#8a6a18",3); p.line(65,60,73,48,"#8a6a18",3); p.line(53,48,65,60,"#e8c030",2); p.line(65,60,73,48,"#e8c030",2)
		p.layer(17,Profiles.dome(65,64,4,4,2)); p.ell(65,64,4,4,"#ffd23c"); p.R(63,62,2,2,"#fff6c0"); p.R(65,63,1,4,"#b08a18")
	if n.has("payraise"):
		p.layer(14,Profiles.slab(34,76,46,84,1,1))
		for i in 3: p.R(36+i*2,77-i,8,6,["#3f8a4c","#58ad62","#79cf80"][i]); p.R(37+i*2,78-i,6,1,"#d8f0d0")
	if n.has("teleport"):                                       # pads clipped to the coat hem
		for x in [36,72]:
			p.layer(14,Profiles.dome(x+4,101,6,3,2)); p.ell(x+4,101,6,3,"#4a2a6a"); p.ell(x+4,100,4,2,"#b070ff"); p.R(x+2,99,4,1,"#f0dcff")
			_fx("torso",{"k":"pulse","x":x+4,"y":100,"r":5,"c":"#b070ff","a":0.25})
	var vials := []
	for entry in [["serum","#7dff3a"],["acid","#e8f040"],["poison","#3ad83a"],["virus","#b0d030"]]:
		if n.has(entry[0]): vials.append(entry[1])
	if not vials.is_empty() or n.has("clock"):
		p.layer(14,Profiles.cylH(80,2,2)); p.R(70,78,13,5,"#3a2818"); p.R(70,78,13,2,"#5a4028")
		var x := 70
		for color in vials:
			p.layer(16,Profiles.cylV(x+1.5,2,2)); p.R(x,82,4,10,color); p.R(x,83,1,8,Pixels.shade(color,0.5)); p.R(x+3,83,1,8,Pixels.shade(color,-0.3)); p.R(x,80,4,2,"#d8d8e0"); p.R(x,78,4,2,"#a07040")
			x += 5
		if n.has("clock"):
			p.layer(16,Profiles.dome(54,86,5,5,2)); p.ell(54,86,5,5,"#c8302a"); p.ell(54,86,4,4,"#f2f2ee"); p.R(50,80,3,2,"#c83030"); p.R(56,80,3,2,"#c83030")
			_fx("torso",{"k":"clock","x":54,"y":86})
	if n.has("cryo") or n.has("zero"):
		for spike in [[72,46,7],[76,48,6],[79,50,5]]:
			p.layer(17); p.R(spike[0],spike[1]-spike[2]/2,2,spike[2],"#bff4ff"); p.R(spike[0]+1,spike[1]-spike[2]/2+1,1,spike[2]-2,"#ffffff"); p.R(spike[0]-1,spike[1],1,3,"#8ad0ec")
		_fx("torso",{"k":"mist","x":77,"y":47})
	if n.has("poison"):                                         # gas mask hanging at the neck
		p.layer(17,Profiles.dome(64,51,8,4,3)); p.ell(64,51,8,4,"#3a5a3a"); p.R(58,49,12,2,"#56785a")
		p.layer(19,Profiles.dome(72,52,3,3,3)); p.ell(72,52,3,3,"#2a2a2a"); p.R(71,51,2,2,"#7dff3a")
		p.layer(19,Profiles.dome(57,52,3,3,3)); p.ell(57,52,3,3,"#2a2a2a")

# ---------------------------------------------------------------- head
func _paint_head(p, n: Dictionary) -> void:
	if n.has("core_isotope"):
		p.layer(20)
		for s in [[26,20],[22,30],[30,36],[78,16],[82,26]]: p.R(s[0],s[1],3,3,"#7de03a"); p.R(s[0],s[1],1,1,"#d8ffa8")
	if n.has("thermite"):
		for at in [[22,24],[28,14],[36,10],[46,8],[24,34],[78,10],[84,20],[74,7]]: _fx("head",{"k":"flame","x":at[0],"y":at[1]})
	if n.has("core_battery"):
		p.layer(20); p.line(16,50,18,30,"#d02020",2); p.line(18,30,42,26,"#d02020",2); p.line(30,50,32,42,"#222222",2); p.line(32,42,42,40,"#222222",2)
		p.layer(22,Profiles.dome(43,27,2,3,2)); p.box(42,24,5,7,"#c83030"); p.layer(22,Profiles.dome(43,41,2,2,2)); p.box(42,38,5,5,"#666666")
	if n.has("core_brain"):
		p.layer(20); p.line(30,45,34,24,"#3a8ad0",2); p.line(34,24,44,20,"#3a8ad0",2); p.layer(22,Profiles.dome(45,20,2,2,2)); p.box(43,18,5,5,"#aab4bc")
	if n.has("tesla"):
		p.layer(20); p.line(50,10,42,2,"#9a9aa4",2); p.R(47,7,4,3,"#c97a3a"); p.layer(22,Profiles.dome(41,2,2,2,2)); p.ell(41,2,2,2,"#fff36b")
		_fx("head",{"k":"spark","x":41,"y":2})
	if n.has("storm"):
		p.layer(20); p.line(72,9,80,2,"#9a9aa4",2); p.R(72,6,4,3,"#c97a3a"); p.layer(22,Profiles.dome(81,2,2,2,2)); p.ell(81,2,2,2,"#fff36b")
		_fx("head",{"k":"spark","x":81,"y":2})
		if n.has("tesla"): _fx("head",{"k":"arc","x":43,"y":2,"x2":79,"y2":2})
	if n.has("disint"):                                         # cyber-eye over the front lens
		p.layer(19,Profiles.dome(76,28,5,5,3)); p.ell(76,28,5,5,"#5a5e68"); p.ell(76,28,4,4,"#2a2c32"); p.ell(76,28,3,3,"#ff2a2a"); p.R(75,27,2,2,"#ffd0d0"); p.R(72,24,4,1,"#aab0ba")
		_fx("head",{"k":"pulse","x":76,"y":28,"r":4,"c":"#ff2a2a","a":0.4})
	if n.has("monocle"):
		p.layer(21,Profiles.dome(59,28,8,8,3)); p.ell(59,28,8,8,"#5a4210"); p.ell(59,28,7,7,"#c9a227"); p.R(53,23,5,2,"#ffe08a"); p.R(52,25,2,4,"#ffe08a"); p.R(63,32,3,2,"#8a6a18")
		p.layer(22,Profiles.dome(59,28,5,5,4)); p.ell(59,28,5,5,"#9ccbe0"); p.ell(60,29,3,3,"#1c1214"); p.R(55,25,3,2,"#ffffff"); p.R(61,28,2,2,"#ffffff")
		for i in 12: p.R(52-i*0.5,36+i,2,2,"#c9a227" if i%2==0 else "#8a6a18")
		_fx("head",{"k":"glint","x":55,"y":24})
	if n.has("telescope"):
		p.layer(20); p.line(72,24,46,18,"#4a3424",3); p.line(72,32,46,36,"#4a3424",2)
		p.layer(22,Profiles.dome(77,28,5,5,2)); p.ell(77,28,5,5,"#8a6a18"); p.ell(77,28,3,3,"#1c1214")
		p.layer(23,Profiles.cylH(28,5,4)); p.R(80,23,8,11,"#c9a227"); p.R(80,24,8,2,"#ffe08a"); p.R(80,32,8,2,"#8a6a18"); p.R(86,23,2,11,"#8a6a18")
		p.layer(24,Profiles.cylH(28,3,3)); p.R(88,25,5,7,"#9aa4ae"); p.R(88,26,5,1,"#d4dce4"); p.R(88,30,5,1,"#5f6872")
		p.layer(25,Profiles.cylH(28,3,3)); p.R(93,24,2,9,"#c9a227"); p.R(95,25,2,7,"#9ccbe0"); p.R(95,26,1,2,"#ffffff")
		_fx("head",{"k":"tscope","x":88,"y":28})
	if n.has("goggles"):                                        # pushed up on the forehead
		p.layer(22,Profiles.cylH(16,2,2)); p.R(44,14,37,5,"#3a3a3a"); p.R(44,14,37,2,"#5a5a5a")
		for x in [60,74]:
			p.layer(23,Profiles.dome(x,16,6,5,3)); p.ell(x,16,6,5,"#5a3a1a"); p.ell(x,16,5,4,"#8a5a28"); p.ell(x,16,4,3,"#ffb030"); p.R(x-3,14,3,2,"#fff4c8"); p.R(x+1,18,2,1,"#c06a10")
	if n.has("greed"): p.layer(22); p.R(64,37,2,3,"#ffd23c"); p.P(64,37,"#fff6c0")
	if n.has("syringe"): p.layer(22); p.R(60,40,2,3,"#ffffff"); p.R(71,39,2,3,"#ffffff")
	if n.has("hive"):                                           # glass dome and extra brain
		p.layer(18,Profiles.dome(62,10,10,6,4)); p.ell(62,9,10,6,"#ff8fb0"); p.R(57,6,2,6,"#d0607e"); p.R(62,4,2,8,"#d0607e"); p.R(67,6,2,6,"#d0607e"); p.R(58,5,4,2,"#ffc0d4")
		p.layer(19,Profiles.dome(62,16,24,16,8)); head.alpha = 0.26; p.ell(62,17,25,15,"#a8dcff"); head.alpha = 1.0
		p.layer(20,Profiles.cylH(32,1,1)); p.R(42,21,3,2,"#ffffff"); p.R(46,17,5,2,"#ffffff")
		_fx("head",{"k":"pulse","x":62,"y":9,"r":8,"c":"#ff8fb0","a":0.3})
	if n.has("tesla_helmet"):
		p.layer(28,Profiles.dome(62,14,20,11,6))
		p.line(43,20,82,20,"#596775",5); p.line(43,18,82,18,"#8fa2b2",1)
		for wire in [[44,18,50,8],[50,8,62,4],[62,4,74,8],[74,8,81,18],[50,9,72,16],[52,16,72,8],[62,4,62,18]]: p.line(wire[0],wire[1],wire[2],wire[3],"#5e7080",3); p.line(wire[0],wire[1],wire[2],wire[3],"#dfe9f0",1)
		for x in [47,62,78]:
			p.layer(29,Profiles.cylV(x,3,3)); p.R(x-2,2,5,12,"#c58e4b"); p.R(x-2,2,1,12,"#eebc7c"); p.R(x-3,1,7,3,"#b1eeff"); p.R(x-2,1,2,1,"#ffffff")
			_fx("head",{"k":"pulse","x":x,"y":2,"r":4,"c":"#70dcff","a":0.35})
		p.line(45,22,46,40,"#566679",2)
	if n.has("singular"): _fx("head",{"k":"sing","x":104,"y":18})

# ---------------------------------------------------------------- recolors
## region: "body" (hair above the collar, coat and shoes below), "arm" (sleeve and hand).
func tint(image: Image, region: String, head_offset := Vector2i.ZERO) -> Image:
	if not has_recolor(): return image
	var out: Image = image.duplicate()
	var used := image.get_used_rect()
	var collar := 46+head_offset.y
	var coat_tint: Color = [Color.WHITE,Color(0.74,0.77,0.84),Color(0.66,0.7,0.79),Color(0.58,0.63,0.74)][mini(recolor.coat,3)]
	for y in range(used.position.y,used.end.y):
		for x in range(used.position.x,used.end.x):
			var c := image.get_pixel(x,y)
			if c.a<0.5: continue
			var is_head := region == "body" and y<collar
			var light := c.get_luminance()
			var cloth := light>0.3 and absf(c.r-c.g)<0.13 and c.b>=c.g-0.02 and c.b-c.g<0.2
			if cloth:
				if is_head:
					# Keep teeth and the lens highlights; everything else this colour is hair.
					var face := x>54+head_offset.x and x<76+head_offset.x and y>21+head_offset.y
					if recolor.hair and not face: out.set_pixel(x,y,Color(light*0.72,light*0.93,minf(1.0,light*1.18+0.06),c.a))
				elif recolor.coat>0: out.set_pixel(x,y,Color(c.r*coat_tint.r,c.g*coat_tint.g,c.b*coat_tint.b,c.a))
			elif c.r>c.g*1.1 and c.r>c.b*1.05 and c.g>0.16 and c.g>c.b*0.72 and (region == "arm" or y<100) and recolor.skin:
				out.set_pixel(x,y,Color(light*0.62,minf(1.0,light*1.25),light*0.5,c.a))
			elif region == "body" and y>=104 and recolor.boots and c.r>c.g*1.35 and c.r>0.16:
				out.set_pixel(x,y,Color(minf(1.0,c.r*1.75+0.06),c.g*0.55,c.b*0.6,c.a))
	return out

## Shoe boxes on this frame (cell coordinates), for ankle gear and jets.
static func shoes(image: Image) -> Array:
	var columns := PackedInt32Array(); columns.resize(128); columns.fill(-1)
	for x in range(8,120):
		for y in range(108,124):
			var c := image.get_pixel(x,y)
			if c.a>0.5 and c.r>c.g*1.35 and c.r>0.2: columns[x] = y; break
	var boxes: Array = []; var start := -1; var gap := 0; var last := -1
	for x in 129:
		var filled := x<128 and columns[x]>=0
		if filled:
			if start<0: start = x
			last = x; gap = 0
		elif start>=0:
			gap += 1
			if gap>3 or x==128:
				if last-start>=9:
					var top := 128
					for i in range(start,last+1):
						if columns[i]>=0: top = mini(top,columns[i])
					boxes.append(Rect2i(start,top,last-start+1,124-top))
				start = -1
	return boxes

func paint_feet(image: Image, normal: Image, body: Image) -> Array:
	var feet := shoes(body)   # the undressed body: a red cape must not read as shoes
	if not (recolor.zigzag or recolor.pistons): return feet
	var canvas = Pixels.new(128,128); var p = Pen.new(canvas)
	for box in feet:
		var x: int = box.position.x; var y: int = box.position.y
		if recolor.zigzag:
			for i in 3: p.layer(20,Profiles.cylH(y-2-i*3,1,1)); p.R(x+1,y-3-i*3,11,2,"#ff5aa8"); p.R(x+2,y-3-i*3,4,1,"#ffc4e2")
		if recolor.pistons:
			p.layer(22,Profiles.slab(x,y,x+12,y+6,2,1)); p.box(x-1,y+1,9,7,"#d4a640"); p.R(x,y+2,4,1,"#fff0b0"); p.R(x+1,y-4,3,6,"#9aa4ae"); p.R(x+5,y-4,3,6,"#9aa4ae")
	image.blend_rect(canvas.outlined_image(),Rect2i(0,0,130,130),Vector2i(-1,-1))
	normal.blend_rect(canvas.normal_image(),Rect2i(0,0,130,130),Vector2i(-1,-1))
	return feet

## Body cell + gear -> [image, normal, effects in cell coordinates, shoe boxes].
func dress(body: Image, body_normal: Image, torso_offset: Vector2i, head_offset: Vector2i) -> Array:
	var image := Image.create(128,128,false,Image.FORMAT_RGBA8); var normal := Image.create(128,128,false,Image.FORMAT_RGBA8)
	var offsets := {"back":torso_offset,"torso":torso_offset,"head":head_offset}
	var put := func(name: String) -> void:
		if not images.has(name): return
		image.blend_rect(images[name][0],Rect2i(0,0,130,130),offsets[name]-Vector2i.ONE)
		normal.blend_rect(images[name][1],Rect2i(0,0,130,130),offsets[name]-Vector2i.ONE)
	put.call("back")
	var tinted := tint(body,"body",head_offset); var lit: Image = body_normal.duplicate()
	if tinted.get_format()!=Image.FORMAT_RGBA8: tinted.convert(Image.FORMAT_RGBA8)
	if lit.get_format()!=Image.FORMAT_RGBA8: lit.convert(Image.FORMAT_RGBA8)
	image.blend_rect(tinted,Rect2i(0,0,128,128),Vector2i.ZERO); normal.blend_rect(lit,Rect2i(0,0,128,128),Vector2i.ZERO)
	var feet := paint_feet(image,normal,body)
	put.call("torso"); put.call("head")
	var effects: Array = []
	for entry in anims:
		var fx: Dictionary = entry.fx.duplicate(); var off: Vector2i = offsets[entry.layer]
		fx.x += off.x; fx.y += off.y
		if fx.has("x2"): fx.x2 += off.x; fx.y2 += off.y
		effects.append(fx)
	return [image,normal,effects,feet]

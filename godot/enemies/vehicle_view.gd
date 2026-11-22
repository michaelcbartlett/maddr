extends RefCounted
## Turn on the ground plane; height always projects upward, like the map's parked cars.
var canvas: CanvasItem
var heading := Vector2.RIGHT
var origin := Vector2.ZERO
var tint := Color.TRANSPARENT
var opacity := 1.0

static func draw(ci: CanvasItem, kind: String, direction: Vector2, at := Vector2.ZERO, time := 0.0, color := Color.TRANSPARENT, alpha := 1.0, wreck := false) -> void:
	var view := new()
	view.canvas = ci; view.heading = direction.normalized(); view.origin = at; view.tint = color; view.opacity = alpha
	if kind == "tank": view._tank(time, wreck)
	else: view._car(time, wreck)

func _q(x: float, y: float, height: float) -> Vector2:
	return origin + heading * x + heading.orthogonal() * y - Vector2(0, height)

func _color(hex: String) -> Color:
	var col := Color(hex).lerp(Color(tint,1.0),tint.a)
	col.a *= opacity
	return col

func _poly(points: Array, hex: String) -> void:
	var area := 0.0
	for i in points.size():
		var a: Vector2 = points[i]; var b: Vector2 = points[(i+1)%points.size()]
		area += a.x*b.y - b.x*a.y
	if absf(area) < 0.02: return # edge-on tyre caps and faces have no visible area
	canvas.draw_colored_polygon(PackedVector2Array(points),_color(hex))

func _line(a: Vector2, b: Vector2, hex: String, width := 1.0) -> void:
	canvas.draw_line(a,b,_color(hex),width)

func _block(x: float, y: float, length: float, width: float, bottom: float, top: float, roof: String, wall: String, roof_length := -1.0, roof_width := -1.0) -> void:
	var l := length*0.5; var w := width*0.5
	var rl := (roof_length if roof_length > 0.0 else length)*0.5
	var rw := (roof_width if roof_width > 0.0 else width)*0.5
	var low := [_q(x-l,y-w,bottom),_q(x+l,y-w,bottom),_q(x+l,y+w,bottom),_q(x-l,y+w,bottom)]
	var high := [_q(x-rl,y-rw,top),_q(x+rl,y-rw,top),_q(x+rl,y+rw,top),_q(x-rl,y+rw,top)]
	for i in 4:
		var next := (i+1)%4
		var edge: Vector2 = low[next]-low[i]
		if edge.x >= -0.001: continue
		_poly([low[i],low[next],high[next],high[i]],wall)
		_line(low[i],low[next],"#19262b")
	_poly(high,roof)
	for i in 4: _line(high[i],high[(i+1)%4],"#9ca58a" if roof.begins_with("#7") else "#71818a")

func _wheel(x: float, side: float, t: float) -> void:
	# A rubber cylinder, with a circular sidewall and a recessed metal hub.
	var near_y := side + (5.0 if heading.x >= 0.0 else -5.0)
	var far_y := side - (5.0 if heading.x >= 0.0 else -5.0)
	var outer: Array = []
	var rim: Array = []
	for i in 24:
		var a := i*TAU/24.0
		outer.append(_q(x+cos(a)*12,near_y,12+sin(a)*12))
		rim.append(_q(x+cos(a)*6.5,near_y+signf(near_y-side)*0.2,12+sin(a)*6.5))
	for i in 24:
		var next := (i+1)%24
		var a := i*TAU/24.0; var b := next*TAU/24.0
		_poly([outer[i],outer[next],_q(x+cos(b)*12,far_y,12+sin(b)*12),_q(x+cos(a)*12,far_y,12+sin(a)*12)],"#2b343a" if sin(a)>0 else "#10191f")
		if i%3 == 0: _line(outer[i],_q(x+cos(a)*12,far_y,12+sin(a)*12),"#465159")
	_poly(outer,"#111a22"); _poly(rim,"#8998a2")
	for n in 5:
		var a := n*TAU/5.0 + t*3.0
		_line(_q(x+cos(a)*2,near_y,12+sin(a)*2),_q(x+cos(a)*5.2,near_y,12+sin(a)*5.2),"#354752",2.0)
	canvas.draw_circle(_q(x,near_y,12),1.5,_color("#d1d9dc"))

func _car(t: float, wreck: bool) -> void:
	var white := "#dce5eb" if not wreck else "#56616a"
	var dark := "#24415e" if not wreck else "#26333b"
	for x in [-41.0,41.0]:
		for y in [-30.0,30.0]: _wheel(x,y,t)
	_block(0,0,132,60,8,25,white,"#a4b5c2")
	_block(0,0,126,61,13,18,"#4772a2","#326295")
	_block(0,0,128,58,19,25,white,"#aab9c6")
	var near_side := 30.0 if heading.x >= 0.0 else -30.0
	for x in [-41.0,41.0]: _wheel(x,near_side,t)
	_block(47,0,34,54,25,26,"#355d86","#294663")
	_block(-51,0,24,54,25,26,"#355d86","#294663")
	# The raised cabin keeps its visible south-facing wall when the car turns.
	_block(-7,0,62,53,25,45,dark,"#29485e",43,39)
	_block(-7,0,43,39,45,47,white,"#9eafbb")
	_line(_q(16,-18,44),_q(24,-23,27),"#9bcbdc",2)
	_line(_q(16,18,44),_q(24,23,27),"#9bcbdc",2)
	_line(_q(-3,-19,47),_q(-3,19,47),"#bdc9d1")
	_line(_q(29,-20,26),_q(29,20,26),"#f3f4eb",2)
	_line(_q(48,-20,26),_q(48,20,26),"#c1cdd4")
	for y in [-21.0,21.0]:
		_block(64,y,5,10,15,21,"#fff1c0","#fff1c0")
		_block(-64,y,4,9,15,21,"#e25a54","#a7323f")
		_block(5,y*1.5,6,4,26,29,white,"#687c8a")
	_block(-7,0,12,29,48,50,"#283640","#18262e")
	_block(-7,-8,10,11,50,53,"#ff5757" if sin(t*14)>0 else "#a02a37","#802c38")
	_block(-7,8,10,11,50,53,"#579dff" if sin(t*14)<=0 else "#284b9d","#284681")
	var side := 30.6 if heading.x >= 0 else -30.6
	var badge := _q(-2,side,21)
	_poly([badge+Vector2(-3,0),badge+Vector2(0,-4),badge+Vector2(3,0),badge+Vector2(0,4)],"#e6c466")
	if wreck:
		_line(_q(-38,-20,26),_q(28,22,32),"#14222b",3)
		_block(-18,5,22,13,48,55,"#3b454c","#242f35")

func _track(side: float, t: float, wreck: bool) -> void:
	_block(0,side,248,26,0,28,"#495543","#242e2c")
	var offset := int(t*18.0)%10
	for n in 24:
		var x := -117+n*10+offset
		_line(_q(x,side-11,29),_q(x,side+11,29),"#8b9579",2)
	var outside := side + signf(side)*14.0
	for n in 22:
		var x := -112+n*10
		_line(_q(x,outside,8),_q(x,outside,24),"#5b6653",2)
	if wreck: _line(_q(-45,side-12,30),_q(60,side+12,8),"#1b2628",5)

func _tank(t: float, wreck: bool) -> void:
	var olive := "#78875b" if not wreck else "#535b47"
	var shadow := "#46583d" if not wreck else "#303c34"
	var near_side := 60.0 if heading.x >= 0 else -60.0
	_track(-near_side,t,wreck)
	_block(0,0,228,112,15,39,olive,shadow,210,104)
	for x in [-84.0,-61.0,-38.0]:
		_block(x,0,16,73,40,42,"#526344","#334936")
		for y in [-26.0,-13.0,0.0,13.0,26.0]: _line(_q(x-6,y,43),_q(x+6,y,43),"#283b32",2)
	_block(15,0,108,88,39,72,olive,shadow,83,68)
	_block(11,0,78,64,72,75,"#87946b",shadow)
	_block(67,0,25,36,48,66,"#5f734c",shadow)
	_block(122,0,106,12,54,65,"#819266","#465b3d")
	_block(177,0,16,19,51,68,"#536946","#293c32")
	_poly([_q(186,-6,55),_q(186,6,55),_q(186,6,64),_q(186,-6,64)],"#162b2c")
	_block(-8,-13,31,27,76,79,"#566c48","#324933")
	_block(-8,-13,25,21,79,81,"#89976a","#526744")
	_line(_q(-38,-23,73),_q(-38,-23,115),"#2c4036",2)
	_line(_q(-37,-23,114),_q(-35,-23,123),"#adb381",1)
	for side in [-1.0,1.0]:
		_line(_q(82,side*36,40),_q(105,side*36,40),"#b1b78a",2)
		_block(-100,side*34,12,14,40,43,"#9da47b",shadow)
		_block(35,side*47,33,9,40,48,"#697c50",shadow)
	_track(near_side,t,wreck)
	_line(_q(-93,near_side*0.78,44),_q(-72,near_side*0.78,44),"#e2dfbd",3)
	_line(_q(-83,near_side*0.78-7,44),_q(-83,near_side*0.78+7,44),"#e2dfbd",3)
	if wreck:
		_line(_q(-55,-38,41),_q(47,39,51),"#172c2a",4)
		_block(-5,0,42,31,76,85,"#34463c","#243930")

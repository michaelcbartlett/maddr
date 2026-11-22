extends RefCounted
## Mechanical reinforcements use the same pixel and height-map primitives as humanoids.
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Profiles = preload("res://character/height_profiles.gd")
var anchors := {}

func paint(kind: String, state: String, frame: int) -> Pixels:
	if kind in ["vex_sentry","vex_mine"]: return _gadget(kind,state,frame)
	return _dog(state, frame) if kind == "robodog" else _vehicle(kind, state, frame)

func _gadget(kind: String, state: String, i: int) -> Pixels:
	var c := Pixels.new(44,40); var p := Pen.new(c,0,0)
	var mine := kind == "vex_mine"
	var y := 28+(i%2); var dead := state == "death"
	if dead: y += i
	p.layer(3)
	for leg in [-1,1]:
		p.line(22,y-4,22+leg*13,36,"#53677d",3)
		p.box(20+leg*13,34,5,3,"#28384b")
	p.layer(8,Profiles.dome(22,y,12,7,5)); p.ell(22,y,12,7,"#6e5b84" if not dead else "#3a3d4f")
	p.box(13,y-5,18,6,"#9b80b0")
	if mine:
		p.layer(15); p.ell(22,y-7,6,5,"#ed87ff" if i%2==0 else "#885cb9")
		p.R(21,y-10,2,5,"#f5d2ff")
	else:
		p.layer(14,Profiles.slab(14,y-21,34,y-10,3,1))
		p.box(14,y-21,20,11,"#637a8c"); p.box(27,y-19,12,7,"#37455e")
		p.R(37,y-18,3,5,"#6bf5ef"); p.R(18,y-19,6,3,"#9ce1d7")
		p.line(15,y-21,12,y-28,"#4b5f75",1); p.P(12,y-29,"#ed87ff")
		if state == "attack": p.R(40,y-17,1+i,3,"#f2ffee")
	# Bevelled access panels, screws and alternating laboratory status lamps.
	p.layer(18)
	p.R(14,y+1,16,1,"#c4b0cd"); p.R(16,y+3,12,1,"#3d4059")
	for screw in [14,30]: p.P(screw,y-2,"#e1d5da")
	if not dead:
		p.P(17,y-3,"#6bf5ef"); p.P(20,y-3,"#ed87ff" if i%2==0 else "#825ca2")
	if mine:
		p.R(12,y-1,3,2,"#edbd63"); p.R(29,y-1,3,2,"#edbd63")
	else:
		for vent in 3: p.R(16+vent*3,y-15,1,3,"#334357")
		p.R(28,y-19,7,1,"#b5ccd2")
	if state == "frozen": p.line(13,y-8,29,y+4,"#b0f4ff",2)
	if state == "hurt": p.R(13,y-2,18,1,"#ffffff")
	if state == "stunned": p.R(20,2+i,3,2,"#ffe699")
	if dead: p.line(17+i,y-9,26,y+5,"#202e44",2); p.box(7+i*2,30-i,4,3,"#8f759d")
	anchors = {"head":Vector2(22,y-16),"chest":Vector2(22,y-2),"muzzle":Vector2(40,y-16)}
	return c

func _vehicle(kind: String, state: String, i: int) -> Pixels:
	var c := Pixels.new(112, 84); var p := Pen.new(c, 0, 0)
	var tank := kind == "tank"
	var dead := state == "death"
	var bob := i % 2 if state == "walk" else 0
	var y := 38 + bob
	var body := "#596c47" if tank else "#d4dfe4"
	if dead: body = ["#92927d", "#5a5d50", "#383d3a", "#292e31"][i % 4]
	if tank:
		for ty in [y-19, y+15]:
			p.layer(3, Profiles.slab(15, ty, 91, ty+12, 3, 2)); p.box(15, ty, 76, 12, "#252c2b")
			for wheel in 8:
				var wx := 20 + wheel*9
				p.ell(wx, ty+6, 4, 4, "#535d4b"); p.R(wx-1, ty+4, 2, 4, "#1e2826")
			for tread in 16: p.R(17+tread*4+(i%2), ty+1, 1, 2, "#929382")
		p.layer(9, Profiles.slab(20, y-16, 87, y+20, 7, 3)); p.box(20, y-16, 67, 36, body)
		p.box(26, y-12, 52, 23, "#748157" if not dead else body)
		for at in [Vector2(30,y-8), Vector2(56,y+3), Vector2(71,y-10)]: p.R(at.x, at.y, 10, 5, "#414e37")
		p.layer(17, Profiles.dome(51, y-4, 21, 15, 8)); p.ell(51,y-4,21,15, body)
		p.box(37,y-15,27,19,"#7e8a60" if not dead else body)
		p.layer(24, Profiles.slab(58,y-10,104,y-3,4,2)); p.box(58,y-10,46,7,"#566644" if not dead else body)
		p.box(99,y-12,7,11,"#3d4937"); p.R(104,y-10,3,7,"#182225")
		p.layer(25); p.ell(46,y-10,7,4,"#3e4d36"); p.R(42,y-12,9,2,"#a3ac7c")
		p.line(33,y-16,30,y-32,"#303c30",1); p.P(30,y-33,"#d6b577")
		# Small white recognition cross on the rear hull.
		p.R(24,y,8,2,"#ded9b4"); p.R(27,y-3,2,8,"#ded9b4")
	else:
		for wx in [27, 80]:
			p.layer(2); p.box(wx-8,y-17,16,9,"#17212b"); p.box(wx-8,y+13,16,12,"#17212b")
			p.ell(wx,y+20,5,3,"#57616b"); p.P(wx,y+20,"#b0bac4")
		p.layer(8, Profiles.slab(10,y-12,99,y+18,6,3)); p.box(10,y-12,89,30,body)
		p.R(11,y+5,86,6,"#3765a2" if not dead else "#384148")
		p.box(18,y-14,69,11,body)
		p.layer(16, Profiles.slab(34,y-24,71,y,8,3)); p.box(34,y-24,37,24,body)
		p.box(39,y-22,27,6,"#3e697e"); p.R(40,y-21,24,2,"#8cbdce")
		p.box(38,y-13,30,9,"#233b51"); p.R(39,y-12,27,2,"#70a2bc"); p.R(52,y-13,2,9,body)
		p.box(72,y-11,18,10,body); p.R(77,y-9,10,1,"#f0f3ea")
		p.R(11,y-6,5,4,"#dc574f"); p.R(94,y-8,5,5,"#fff0ae"); p.R(94,y+7,5,5,"#fff0ae")
		p.layer(25); p.box(45,y-26,18,4,"#263247")
		p.R(46,y-27,7,4,"#ff6767" if i%2==0 else "#922d3d")
		p.R(55,y-27,7,4,"#579fff" if i%2==1 else "#254d89")
		# Door badge and white NYPD stripe.
		p.R(43,y+5,22,3,"#eff5f3"); p.R(44,y+6,3,1,"#28558c"); p.R(50,y+6,3,1,"#28558c"); p.R(56,y+6,3,1,"#28558c")
		p.ell(70,y+7,3,4,"#e8c877")
	p.layer(27)
	if tank:
		for bolt in [29,43,65,77]: p.P(bolt,y+12,"#c3c4a2")
		for vent in 4: p.R(24+vent*4,y-8,2,6,"#354532")
		p.R(68,y-9,22,1,"#b4bd91")
	else:
		p.R(73,y-6,14,1,"#a7bfcd"); p.R(74,y+9,12,1,"#718a9e")
		p.R(48,y-3,6,1,"#5f7b91"); p.R(11,y+15,85,1,"#8eabb9")
	if state == "attack": p.R(103,y-11,4+i,3,"#ffe6a3")
	if dead:
		p.layer(28); p.line(28,y-16,75,y+16,"#131c23",2+i%2)
		p.box(23+i*7,y-18-i*3,8,5,"#777d78")
		p.ell(70,y-12-i*3,6+i,4+i,"#414c53")
	if state == "hurt": p.layer(29); p.R(22,y+2,69,2,"#ffe1a8")
	if state == "frozen": p.layer(30); p.line(20,y-18,83,y+20,"#b6f1ff",3); p.line(35,y+19,72,y-20,"#7cd6f0",2)
	if state == "stunned": p.layer(30); p.R(50,y-31,4,4,"#ffe796")
	anchors = {"head":Vector2(55,y-25), "chest":Vector2(55,y), "muzzle":Vector2(105,y-7)}
	return c

func _dog(state: String, i: int) -> Pixels:
	var c := Pixels.new(52,40); var p := Pen.new(c,0,0)
	var y := 20 + (i%2 if state == "walk" else 0)
	var dead := state == "death"
	if dead: y = 26
	# Four articulated legs, with exposed copper pistons and rubber feet.
	for leg in 4:
		var lx := 13 + (leg%2)*20; var far := leg<2
		var stride := sin((i+leg*2)*PI/3.0)*4.0 if state == "walk" else 0.0
		if dead: stride = (i+1)*2.0
		var knee := Vector2(lx+stride, y+7); var foot := Vector2(lx-stride+2,35 if not dead else 35-leg%2)
		p.layer(3 if far else 12, Profiles.cap(lx,y,knee.x,knee.y,2,3))
		p.line(lx,y,knee.x,knee.y,"#8a9c9a" if not far else "#465654",3)
		p.line(knee.x,knee.y,foot.x,foot.y,"#d5a157",2)
		p.ell(knee.x,knee.y,3,3,"#394c50"); p.P(knee.x,knee.y,"#8ac3ca")
		p.box(foot.x-2,foot.y-1,6,3,"#1b252d")
	p.layer(10, Profiles.slab(9,y-8,36,y+4,5,2)); p.box(9,y-8,27,12,"#7e918c" if not dead else "#495553")
	p.box(13,y-10,17,7,"#c3b45b" if not dead else "#73755c")
	p.R(15,y-8,12,2,"#e5d58a")
	for vent in 4: p.R(13+vent*4,y-2,2,4,"#33464b")
	p.layer(17, Profiles.slab(33,y-12,47,y-2,4,2)); p.box(33,y-12,14,10,"#344952")
	p.R(39,y-10,8,3,"#ff554a" if state != "frozen" else "#84e2ff"); p.R(43,y-10,3,1,"#ffd4b2")
	p.R(34,y-15,3,4,"#93a8a0"); p.line(12,y-9,6,y-15,"#748781",2)
	p.layer(19)
	p.R(11,y-6,24,1,"#c0d4ce"); p.R(29,y-5,2,7,"#394f54")
	for bolt in [12,32]: p.P(bolt,y-4,"#edf0d0")
	p.R(36,y-5,9,1,"#708d9c"); p.P(40,y-9,"#fff0d7" if not dead else "#744a45")
	p.R(17,y-9,3,2,"#343f43"); p.P(18,y-9,"#9be3e6" if not dead else "#466064")
	if state == "attack": p.R(46,y-7,3+i,2,"#91e5ee")
	if state == "hurt": p.R(11,y-5,24,1,"#fff2c8")
	if dead: p.line(18+i*2,y-10,30,y+4,"#1c292e",2); p.box(35+i,y-16,4,3,"#b7b28c")
	if state == "frozen": p.line(10,y-9,33,y+3,"#c1f0ff",2)
	if state == "stunned": p.R(25,2,3,3,"#ffe889")
	anchors = {"head":Vector2(40,y-10), "chest":Vector2(22,y-4), "eye":Vector2(44,y-9)}
	return c

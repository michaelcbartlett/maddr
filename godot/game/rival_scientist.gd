extends RefCounted
## A rival inventor: committed twin-blaster volleys alternate with destructible gadgets.
const CYAN := Color("#6bf5ef")
const PINK := Color("#ed87ff")
const MINE_RADIUS := 76.0

static func tick(e, dt: float, speed: float) -> void:
	var a = e.A
	var origin := Vector2(e.x,e.y)
	var target := Vector2(a.P.x,a.P.y)
	var direction := origin.direction_to(target)
	var rage: bool = e.hp < e.max_hp * 0.5
	if e.action_phase == "":
		e.face = 1 if direction.x >= 0.0 else -1
		e.action_cd -= dt
		if e.action_cd <= 0.0:
			e.action_target = target
			if e.attack_cycle % 2 == 0:
				e.action_phase = "vex_aim"; e.action_t = 0.85
			else:
				var mine: bool = e.attack_cycle % 4 == 3
				e.gadget_targets = _placements(e,mine,3 if rage and mine else 2)
				e.action_phase = "vex_mines" if mine else "vex_deploy"; e.action_t = 1.0
			return
		var distance := origin.distance_to(target)
		if distance > 330.0 or not a.nav.clear_segment(origin,target,e.r):
			var waypoint: Vector2 = a.nav.waypoint(e,target,dt)
			var move := origin.direction_to(waypoint)*speed*dt
			e._move(move.x,move.y)
		elif distance < 220.0:
			e._move(-direction.x*speed*0.65*dt,-direction.y*speed*0.65*dt)
		else:
			var side := direction.orthogonal()*speed*0.28*sin(e.walk*0.25)*dt
			e._move(side.x,side.y)
		return
	e.action_t -= dt
	if e.action_t > 0.0: return
	match e.action_phase:
		"vex_aim":
			e.action_phase = "vex_burst"; e.burst_left = 4 if rage else 3
			_fire_pair(e)
		"vex_burst":
			if e.burst_left > 0: _fire_pair(e)
			else: _recover(e)
		"vex_deploy", "vex_mines":
			var kind := "vex_mine" if e.action_phase == "vex_mines" else "vex_sentry"
			var cap := 5 if kind == "vex_mine" else 2
			var present: int = a.enemies.filter(func(o): return not o.dead and o.type == kind and o.summoner_id == e.get_instance_id()).size()
			for point in e.gadget_targets:
				if present >= cap: break
				if a.in_wall(point.x,point.y,15): continue
				var gadget = a.make_enemy(kind,point.x,point.y)
				gadget.summoner_id = e.get_instance_id(); gadget.action_t = 2.0; gadget.shoot_cd = 1.15
				a.poof(point.x,point.y,CYAN if kind == "vex_sentry" else PINK,10,60)
				present += 1
			e.gadget_targets.clear(); a.snd("pick"); _recover(e)
		"vex_recover":
			e.action_phase = ""; e.action_cd = 0.7 if rage else 1.0

static func _recover(e) -> void:
	e.action_phase = "vex_recover"; e.action_t = 1.15; e.attack_cycle += 1

static func _fire_pair(e) -> void:
	for index in 2:
		var anchor := "muzzle" if index == 0 else "muzzle_f"
		var muzzle := EnemyView.muzzle_world(e,anchor)
		var delta: Vector2 = e.action_target - muzzle
		if not e.A.nav.clear_segment(Vector2(e.x,e.y),muzzle,0) or not e.A.nav.clear_segment(muzzle,e.action_target,0): continue
		var dir := delta.normalized()
		var color := CYAN if index == 0 else PINK
		e.A.ebul.append({"x":muzzle.x,"y":muzzle.y,"vx":dir.x*320.0,"vy":dir.y*320.0,"r":4.0,"dmg":e.dmg*0.38,"t":2.6,"laser_bolt":true,"col":color,"summoner_id":e.get_instance_id()})
		EnemyView._fire_flash(e,e.gfx,dir,anchor,"flash" if index == 0 else "flash_far",color)
	e.burst_left -= 1; e.action_t = 0.22; e.A.snd("ebul")

static func _placements(e, mine: bool, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var player := Vector2(e.A.P.x,e.A.P.y)
	var center := player if mine else Vector2(e.x,e.y)
	for i in count:
		for attempt in 18:
			var angle := (i+0.5)*TAU/count+attempt*0.37
			var radius := 115.0+attempt*4.0 if mine else 160.0
			var point := (center+Vector2.from_angle(angle)*radius).clamp(Vector2(50,50),Vector2(e.A.AW-50,e.A.AH-50))
			if point.distance_to(player) < 85 or e.A.in_wall(point.x,point.y,18): continue
			if result.any(func(other): return other.distance_to(point) < 60): continue
			result.append(point); break
	return result

static func gadget_tick(e, dt: float) -> void:
	if e.type == "vex_mine":
		e.action_t -= dt
		if e.action_t > 0.0: return
		e.dead = true
		e.A.booms.append({"x":e.x,"y":e.y,"r":MINE_RADIUS,"t":0.3,"col":PINK})
		e.A.poof(e.x,e.y,PINK,16,150); e.A.snd("boom")
		var player := Vector2(e.A.P.x,e.A.P.y)
		if player.distance_to(Vector2(e.x,e.y)) < MINE_RADIUS+e.A.P.r and e.A.nav.clear_segment(Vector2(e.x,e.y),player,0): e.A.hurt_player(e.dmg)
		return
	var target := Vector2(e.A.P.x,e.A.P.y)
	e.face = 1 if target.x >= e.x else -1
	e.shoot_cd -= dt
	if e.shoot_cd > 0.0: return
	var muzzle := EnemyView.muzzle_world(e)
	if muzzle.distance_to(target) > 460.0 or not e.A.nav.clear_segment(muzzle,target,0): return
	var dir := muzzle.direction_to(target)
	e.A.ebul.append({"x":muzzle.x,"y":muzzle.y,"vx":dir.x*235,"vy":dir.y*235,"r":3.0,"dmg":e.dmg,"t":2.2,"laser_bolt":true,"col":CYAN,"summoner_id":e.summoner_id})
	e.shoot_cd = 2.5; e.gfx.shot_t = 0.0; EnemyView._fire_flash(e,e.gfx,dir,"muzzle","flash",CYAN); e.A.snd("ebul")

static func cancel(e) -> void:
	e.action_phase = "vex_recover"; e.action_t = 1.15; e.burst_left = 0; e.gadget_targets.clear()

static func cleanup(e) -> void:
	for gadget in e.A.enemies:
		if gadget.summoner_id == e.get_instance_id():
			gadget.dead = true; e.A.poof(gadget.x,gadget.y,CYAN,6,45)
	for bullet in e.A.ebul:
		if int(bullet.get("summoner_id",0)) == e.get_instance_id(): bullet.t = 0.0

static func draw_warning(e) -> void:
	if e.hero == "vex":
		if e.action_phase == "vex_aim":
			for anchor in ["muzzle","muzzle_f"]:
				var muzzle := EnemyView.muzzle_local(e,anchor)
				var end: Vector2 = e.action_target-Vector2(e.x,e.y)
				var delta := end-muzzle
				var length: float = e.A.ray_len(e.x+muzzle.x,e.y+muzzle.y,delta.normalized().x,delta.normalized().y,delta.length())
				e.draw_line(muzzle,muzzle+delta.normalized()*length,Color(CYAN if anchor == "muzzle" else PINK,0.65),2)
		elif e.action_phase in ["vex_deploy","vex_mines"]:
			for point in e.gadget_targets:
				var radius := MINE_RADIUS if e.action_phase == "vex_mines" else 24.0
				e.draw_arc(point-Vector2(e.x,e.y),radius,0,TAU,40,Color(PINK,0.65),2)
	elif e.type == "vex_mine":
		e.draw_arc(Vector2.ZERO,MINE_RADIUS,0,TAU,40,Color(PINK,0.45),2)
		e.draw_arc(Vector2.ZERO,MINE_RADIUS*clampf(1.0-e.action_t/2.0,0,1),0,TAU,40,Color(PINK,0.8),2)
	elif e.type == "vex_sentry" and e.shoot_cd < 0.7:
		var muzzle := EnemyView.muzzle_local(e)
		var delta := Vector2(e.A.P.x-e.x,e.A.P.y-e.y)-muzzle
		var length: float = e.A.ray_len(e.x+muzzle.x,e.y+muzzle.y,delta.normalized().x,delta.normalized().y,minf(460,delta.length()))
		e.draw_line(muzzle,muzzle+delta.normalized()*length,Color(CYAN,0.5),1)

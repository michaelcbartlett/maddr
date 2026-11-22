extends RefCounted
## Y / Q uses a charge; D-pad Up / E selects a carried consumable. Supplies last for this run.
var grenades: Array = []
var pads: Array[Vector2] = []
var pads_armed := false
var use_cd := 0.0

func reset() -> void:
	grenades.clear(); pads.clear(); pads_armed = false; use_cd = 0.0

func tick(a, dt: float, firing: bool) -> void:
	a.P.disguise_t = maxf(0.0, a.P.disguise_t - dt)
	use_cd = maxf(0.0, use_cd - dt)
	if firing and a.P.disguise_t > 0.0:
		a.P.disguise_t = 0.0; a.add_num(a.P.x, a.P.y-52, "SPOTTED!", Color("#ffb260"), false)
	if Input.is_action_just_pressed("consume_cycle"): Run.cycle_consumable()
	if Input.is_action_just_pressed("consume") and use_cd <= 0.0: activate(a)
	for grenade in grenades:
		grenade.t -= dt
		var old: Vector2 = grenade.position
		var move: Vector2 = grenade.velocity * dt
		var clear: float = a.ray_len(old.x, old.y, move.normalized().x, move.normalized().y, move.length() + 5.0)
		if clear < move.length() + 5.0: grenade.velocity = Vector2.ZERO
		else: grenade.position += move
		grenade.velocity *= exp(-2.0 * dt)
		if grenade.t <= 0.0:
			a.explode(grenade.position.x, grenade.position.y, 38.0 + Run.D.dmg * 1.5, 95.0 * sqrt(Run.S.boomMul), Color("#ffb249"))
	grenades = grenades.filter(func(g): return g.t > 0.0)
	if pads.size() == 2:
		var player := Vector2(a.P.x, a.P.y)
		if not pads_armed:
			if player.distance_to(pads[0]) > 30 and player.distance_to(pads[1]) > 30: pads_armed = true
		else:
			for i in 2:
				if player.distance_to(pads[i]) > 24: continue
				var exit := pads[1-i]
				a.poof(player.x, player.y, Color("#b48bff"), 18, 120)
				a.P.x = exit.x; a.P.y = exit.y; a.P.inv = maxf(a.P.inv, 0.65)
				a.grapple.reset()
				a.poof(exit.x, exit.y, Color("#b48bff"), 18, 120); a.snd("blink")
				pads.clear(); pads_armed = false
				a.action_cooldown = TELEPORT_COOLDOWN   # the long wait starts once the trip is used
				break

## Teleport Pads (B action): first press drops a pad, the second drops its partner; stepping on either pad warps
## to the other once, then the action cooldown starts. Pads left at wave end are cleared and cost nothing.
const TELEPORT_COOLDOWN := 14.0
func place_pad(a) -> bool:
	if a.state != "play" or use_cd > 0.0 or a.action_cooldown > 0.0: return false
	var center := Vector2(a.P.x, a.P.y)
	if pads.size() == 2:
		a.add_num(center.x, center.y-52, "PADS READY", Color("#b48bff"), false); return false
	# Pad positions must remain safe destinations for the player's collision radius.
	if a.in_wall(center.x, center.y, a.P.r + 2.0): return false
	if pads.size() == 1 and center.distance_to(pads[0]) < 90.0:
		a.add_num(center.x, center.y-52, "MOVE FURTHER", Color("#b48bff"), false); return false
	pads.append(center); pads_armed = false; use_cd = 0.35; a.snd("blink")
	if pads.size() == 1: a.add_num(center.x, center.y-52, "B: SECOND PAD", Color("#b48bff"), false)
	return true

func activate(a) -> bool:
	if a.state != "play" or use_cd > 0.0: return false
	var center := Vector2(a.P.x, a.P.y)
	var id: String = Run.selected_consumable
	if int(Run.consumable_charges[id]) <= 0:
		Run.cycle_consumable(); id = Run.selected_consumable
	id = Run.spend_consumable()
	if id == "": return false
	use_cd = 0.35
	match id:
		"disguise":
			a.P.disguise_t = 4.0; a.grapple.reset(); a.P.melee_t = 0.0
			for enemy in a.enemies:
				if not enemy.dead and not enemy.ally and not enemy.civ: Enemy.Tactics.distracted(enemy, 0.0)
			a.add_num(center.x, center.y-58, "JUST A TOURIST", Color("#9be6bf"), false); a.snd("mind")
		"grenade":
			a.P.disguise_t = 0.0
			grenades.append({"position":center, "velocity":Vector2.from_angle(a.P.aim) * 560.0, "t":0.85})
			a.snd("throw")
	return true

func draw_ground(a, g: Node2D) -> void:
	for i in pads.size():
		var color := Color("#72d9ff") if i == 0 else Color("#bf88ff")
		var radius := 23.0 + sin(a.time*5.0)*2.0
		g.draw_circle(pads[i], 22.0, Color(color,0.13))
		g.draw_arc(pads[i],radius,0.0,TAU,32,color,3.0)
		g.draw_arc(pads[i],14.0,a.time,-PI+a.time,16,Color.WHITE,2.0)
		for n in 4:
			var d := Vector2.from_angle(n*PI/2.0)
			g.draw_line(pads[i]+d*27,pads[i]+d*33,color,3.0)
	for grenade in grenades:
		g.draw_arc(grenade.position, 95.0, 0.0, TAU, 36, Color("#ffba53",0.25),1.0)

func draw_fx(a, g: Node2D) -> void:
	for grenade in grenades:
		var lift := sin((1.0-grenade.t/0.85)*PI)*26.0
		var point: Vector2 = grenade.position - Vector2(0,lift)
		g.draw_circle(grenade.position, 5.0, Color(0,0,0,0.35))
		g.draw_rect(Rect2(point-Vector2(5,6),Vector2(10,12)), Color("#344c32"))
		g.draw_rect(Rect2(point-Vector2(2,9),Vector2(5,4)), Color("#a6bda2"))
		g.draw_circle(point-Vector2(0,5),2.0,Color("#fff5b0") if sin(grenade.t*35)>0 else Color("#ff654a"))
	if a.P.disguise_t > 0.0:
		var point := Vector2(a.P.x, a.P.y)
		# An actual visual disguise: tan overcoat, trilby, sunglasses and a false moustache.
		var bob: float = sin(a.P.walk * 8.0) if a.P.moving else 0.0
		g.draw_rect(Rect2(point+Vector2(-10,7),Vector2(7,12)),Color("#3b4655"))
		g.draw_rect(Rect2(point+Vector2(4,7),Vector2(7,12)),Color("#3b4655"))
		g.draw_rect(Rect2(point+Vector2(-11,18),Vector2(10,3)),Color("#f0e5cd"))
		g.draw_rect(Rect2(point+Vector2(3,18),Vector2(10,3)),Color("#f0e5cd"))
		g.draw_rect(Rect2(point+Vector2(-9,-37+bob),Vector2(18,16)),Color("#e8b488"))
		g.draw_rect(Rect2(point+Vector2(-12,-23+bob),Vector2(24,34)),Color("#a38a62"))
		g.draw_rect(Rect2(point+Vector2(-3,-23+bob),Vector2(5,32)),Color("#d4bd90"))
		g.draw_line(point+Vector2(-11,-23+bob),point+Vector2(-2,-11+bob),Color("#e8d0a1"),3)
		g.draw_line(point+Vector2(11,-23+bob),point+Vector2(2,-11+bob),Color("#e8d0a1"),3)
		g.draw_rect(Rect2(point+Vector2(-10,-47+bob),Vector2(20,10)),Color("#826b48"))
		g.draw_rect(Rect2(point+Vector2(-14,-39+bob),Vector2(28,4)),Color("#d4ba85"))
		g.draw_rect(Rect2(point+Vector2(-10,-32+bob),Vector2(20,4)),Color("#172630"))
		g.draw_rect(Rect2(point+Vector2(-6,-26+bob),Vector2(12,3)),Color("#352b25"))

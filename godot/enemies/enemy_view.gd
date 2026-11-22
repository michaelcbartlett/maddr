extends RefCounted
class_name EnemyView
## Rendering for Enemy nodes: picks an animation state from the enemy's (read-only) gameplay fields,
## draws the lit sprite + tint overlay, drives emissive FX, the detective muzzle flash and death corpses.
## Only enemy.gd's render functions call into this; nothing here changes gameplay state.
const Sheets = preload("res://enemies/enemy_sheets.gd")
const Corpse = preload("res://enemies/enemy_corpse.gd")
const Flash = preload("res://enemies/muzzle_flash.gd")
const Fx = preload("res://enemies/enemy_fx.gd")
const Vehicles = preload("res://enemies/vehicle_view.gd")

const TINT_FLASH := Color(1, 1, 1, 0.85)
const TINT_ALLY := Color("#c46bff", 0.5)
const TINT_FROZEN := Color("#9ef0ff", 0.6)
const TINT_SICK := Color("#8fdc3a", 0.4)
const SHADOW := {"human": Vector2(11, 3.5), "hero": Vector2(20, 5.5), "dog": Vector2(15, 3.5), "drone": Vector2(9, 3), "vehicle":Vector2(43,18)}

static func sprite_key(e) -> String:
	return "drone" if e.type == "drone" or e.spr == "" else e.spr

## Called from Enemy._ready(): adds the emissive overlay node, and a muzzle flash for shooters.
static func attach(e) -> void:
	var g: Dictionary = e.gfx
	var fx := Fx.new(); fx.enemy = e; e.add_child(fx); g.fx = fx
	if e.ranged:
		var f := Flash.new(); e.add_child(f); g.flash = f
		if e.hero == "vex":
			var far := Flash.new(); e.add_child(far); g.flash_far = far
	if e.boss:
		var light := PointLight2D.new(); light.texture = preload("res://fx/light_pool.gd").light_tex()
		light.energy = 0.0; light.height = 22.0; light.texture_scale = 0.7; light.blend_mode = Light2D.BLEND_MODE_ADD
		e.add_child(light); g.light = light

## Called from Enemy.sync() once per frame: advances render-only bookkeeping and picks the frame.
static func update(e) -> void:
	var g: Dictionary = e.gfx
	var t: float = e.A.time if e.A != null else 0.0
	if not g.has("t"):
		g.merge({"t": t, "px": e.x, "py": e.y, "speed": 0.0, "shoot_cd": e.shoot_cd, "shot_t": 9.0, "blink_cd": e.blink_cd,
			"blink_t": 9.0, "shard_cd": e.shard_cd, "throw_t": 9.0, "slam_on": false, "land_t": 9.0, "seed": randf() * 10.0})
	var dt := clampf(t - g.t, 0.0, 0.1); g.t = t
	if dt > 0.0:
		var v := Vector2(e.x - g.px, e.y - g.py).length() / dt
		g.speed = lerpf(g.speed, minf(v, 600.0), 0.35)
	g.px = e.x; g.py = e.y
	g.shot_t += dt; g.blink_t += dt; g.throw_t += dt; g.land_t += dt
	# detect gameplay events by watching cooldowns reset (no gameplay hooks needed)
	if e.ranged and e.behavior == "" and e.shoot_cd > g.shoot_cd + 0.5: g.shot_t = 0.0; _fire_flash(e, g)
	g.shoot_cd = e.shoot_cd
	if e.boss:
		if e.hero == "surge" and e.blink_cd > g.blink_cd + 0.5: g.blink_t = 0.0
		if e.hero == "glacia" and e.shard_cd > g.shard_cd + 0.3: g.throw_t = 0.0
		if e.hero == "ironclad":
			if g.slam_on and e.slam == null: g.land_t = 0.0
			g.slam_on = e.slam != null
		g.blink_cd = e.blink_cd; g.shard_cd = e.shard_cd
	_pick(e, g, t)
	if g.has("flash"): g.flash.tick(dt)
	if g.has("flash_far"): g.flash_far.tick(dt)
	if g.has("light"): _boss_light(e, g, t)
	if g.has("fx"): g.fx.queue_redraw()

static func muzzle_local(e, anchor := "muzzle") -> Vector2:
	var sheet := EnemyArt.sheet(sprite_key(e))
	var m := Sheets.anchor(sheet, "attack", 1, anchor, Vector2(22, -30))
	return Vector2(0, sheet.foot) + Vector2(m.x * e.face, m.y)

static func muzzle_world(e, anchor := "muzzle") -> Vector2:
	return Vector2(e.x,e.y) + muzzle_local(e,anchor)

static func _fire_flash(e, g: Dictionary, shot_direction := Vector2.ZERO, anchor := "muzzle", flash_key := "flash", color := Color("#ffb347")) -> void:
	if not g.has(flash_key): return
	var at := muzzle_local(e,anchor)
	var f: Node2D = g[flash_key]
	f.position = at
	var target := shot_direction
	if target == Vector2.ZERO: target = Vector2(e.A.P.x,e.A.P.y) - muzzle_world(e) if e.A != null and e.A.P != null else Vector2(e.face,0)
	f.rotation = target.angle()
	f.fire(color)

static func _pick(e, g: Dictionary, t: float) -> void:
	var idle_fps := Sheets.CopEditedArt.fps("idle") if e.spr == "cop" else 2.4
	var st := "idle"; var fi := int(t * idle_fps + g.seed)
	var moving: bool = g.speed > 12.0
	var walk_i := int(e.walk * 0.9)
	if moving: st = "walk"; fi = walk_i
	var lift := 0.0; var jitter := Vector2.ZERO
	if e.civ:
		if e.panic: st = "panic"; fi = walk_i
	elif e.boss:
		var r := _boss_state(e, g, t, st, fi)
		st = r[0]; fi = r[1]; lift = r[2]; jitter = r[3]
	elif e.ranged:
		if g.shot_t < 0.12: st = "attack"; fi = 1
		elif g.shot_t < 0.3 or (not moving and e.A != null and Vector2(e.A.P.x - e.x, e.A.P.y - e.y).length() < 400): st = "attack"; fi = 0
	else:
		var window := 0.25 if e.ally else 0.4
		var start := 0.5 if e.ally else 1.0
		var k: float = (start - e.atk_cd) / window
		var swinger: bool = e.swings() and not e.ally
		if e.action_phase == "swing": st = "attack"; fi = 0   # wind-up: baton raised / shield drawn back
		elif e.atk_cd > 0.0 and k >= 0.0 and k < 1.0:
			st = "attack"; fi = 1 + mini(1, int(k * 2.0)) if swinger else int(k * 3.0)
	if e.type == "drone": lift = 0.0
	if e.action_phase == "rush": st = "attack"; fi = int(t * 12.0) % 3
	# status overrides
	var tint := Color(0, 0, 0, 0)
	if e.frozen_t > 0.0: st = "frozen"; fi = 0
	elif e.time_lock > 0.0: st = "stunned"; fi = int(t * 4.0)
	elif e.flash > 0.0: st = "hurt"; fi = 0
	if e.flash > 0.0: tint = TINT_FLASH
	elif e.ally: tint = TINT_ALLY
	elif e.frozen_t > 0.0: tint = Color(TINT_FROZEN, 0.3)
	elif e.time_lock > 0.0: tint = TINT_FROZEN
	elif e.sick_t > 0.0: tint = TINT_SICK
	g.state = st; g.frame = fi; g.lift = lift; g.jitter = jitter; g.tint = tint

static func _boss_state(e, g: Dictionary, t: float, st: String, fi: int) -> Array:
	var lift := 0.0; var jitter := Vector2.ZERO
	match e.hero:
		"vex":
			if e.action_phase == "vex_aim": st = "aim"; fi = 1 if e.action_t < 0.4 else 0
			elif e.action_phase == "vex_burst": st = "attack"; fi = 1
			elif e.action_phase in ["vex_deploy","vex_mines"]: st = "deploy"; fi = int(t*5.0)%2
		"ironclad":
			if e.slam != null:
				var s: Dictionary = e.slam
				var k: float = 1.0 - maxf(0.0, s.t) / s.T
				lift = e.air * 70.0
				if k < 0.18: st = "windup"; fi = 0 if k < 0.09 else 1
				else: st = "air"; fi = 0
			elif g.land_t < 0.4: st = "slam"; fi = 0
			elif e.charging > 0.0: st = "charge"; fi = int(t * 12.0)
			elif e.charge_t < 0.0:
				st = "windup"; fi = 1 if e.charge_t < -e.charge_windup * 0.5 else 0
				jitter = Vector2(randf_range(-2, 2), randf_range(-1, 1))
		"surge":
			if e.blink_cd < 0.24: st = "blink"; fi = clampi(int((0.24 - e.blink_cd) / 0.08), 0, 2)
			elif g.blink_t < 0.2: st = "blink"; fi = clampi(2 - int(g.blink_t / 0.07), 0, 2)
			elif g.blink_t < 0.55: st = "cast"; fi = 1 if g.blink_t < 0.38 else 0
		"viper":
			if e.action_phase == "zigzag": st = "charge"; fi = int(t * 14.0)
			elif e.action_phase == "windup": st = "windup"; fi = 1 if e.action_t < 0.28 else 0
			elif e.missile_cd > (3.25 if e.hp < e.max_hp * 0.5 else 4.25): st = "cast"; fi = int(t * 8.0) % 2
		"glacia":
			if e.nova_cd < 0.5: st = "nova"; fi = clampi(int((0.5 - e.nova_cd) / 0.5 * 3.0), 0, 2)
			elif e.nova_cd > 5.6: st = "nova"; fi = 2
			elif g.throw_t < 0.22: st = "throw"; fi = 1
			elif e.shard_cd < 0.3: st = "throw"; fi = 0
		"paragon":
			lift = 6.0 + sin(t * 3.0 + g.seed) * 3.0
			if e.laser != null: st = "laser"; fi = 1 if e.laser.phase == "fire" else 0
			elif e.charging > 0.0: st = "dive"; fi = 0
	return [st, fi, lift, jitter]

static func _boss_light(e, g: Dictionary, t: float) -> void:
	var light: PointLight2D = g.light
	var sheet := EnemyArt.sheet(sprite_key(e))
	var face: int = e.face
	var energy := 0.0; var col := Color.WHITE; var at := Vector2.ZERO
	var st: String = g.get("state", "idle"); var fi: int = g.get("frame", 0)
	var base := Vector2(0, sheet.foot - g.get("lift", 0.0))
	match e.hero:
		"vex":
			col = Color("#6bf5ef"); energy = 1.1 if st in ["aim","attack","deploy"] else 0.25
			at = Sheets.anchor(sheet,st,fi,"chest")
		"surge":
			col = Color("#fff36b"); energy = 0.5 + 0.35 * absf(sin(t * 23.0)); at = Sheets.anchor(sheet, st, fi, "chest")
			if st == "blink" or st == "cast": energy = 1.6
		"viper":
			col = Color("#ff70b8"); energy = 0.5 if st in ["windup","charge","cast"] else 0.15
			at = Sheets.anchor(sheet,st,fi,"chest")
		"glacia":
			col = Color("#9ef0ff"); energy = 0.4; at = Sheets.anchor(sheet, st, fi, "chest")
			if st == "nova": energy = 1.0 + fi * 0.5; at = Sheets.anchor(sheet, st, fi, "hand_n")
			elif st == "throw": energy = 1.0; at = Sheets.anchor(sheet, st, fi, "hand_n")
		"ironclad":
			col = Color("#ffd890")
			if st == "windup" or st == "slam": energy = 1.3; at = Sheets.anchor(sheet, st, fi, "hand_n")
		"paragon":
			col = Color("#ff8a20"); at = Sheets.anchor(sheet, st, fi, "eye"); energy = 0.35
			if st == "laser": energy = 1.0 + fi * 1.2
	if e.frozen_t > 0.0 or e.time_lock > 0.0: energy *= 0.3
	light.color = col; light.energy = energy; light.position = base + Vector2(at.x * face, at.y)

## The lit sprite (called from Enemy._draw()).
static func draw(e) -> void:
	var g: Dictionary = e.gfx
	if not g.has("state"): update(e)
	e.Tactics.draw_warning(e)
	var key := sprite_key(e)
	if e.vehicle:
		e.draw_set_transform(Vector2.ZERO, 0.0, Vector2(e.r * 1.10,e.r * 0.55))
		e.draw_circle(Vector2.ZERO,1.0,Color(0,0,0,0.32)); e.draw_set_transform(Vector2.ZERO)
		Vehicles.draw(e,e.type,e.aim_dir,Vector2.ZERO,e.A.time,g.tint)
		return
	var sheet := EnemyArt.sheet(key)
	var fam: String = sheet.family
	var lift: float = g.lift
	var foot := Vector2(0, sheet.foot)
	# ground shadow (shrinks while airborne)
	var sh: Vector2 = SHADOW[fam]
	var shrink := maxf(0.4, 1.0 - lift / 120.0)
	var sy := foot.y + (9.0 if fam == "drone" else 0.0)
	e.draw_set_transform(Vector2(0, sy), 0.0, Vector2(sh.x * shrink, sh.y * shrink))
	e.draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.32))
	e.draw_set_transform(Vector2.ZERO)
	var at: Vector2 = foot + Vector2(0, -lift) + g.jitter
	var sq := _squash(e)
	if sq != Vector2.ONE:   # scaled about the foot point, so the feet stay planted on the shadow
		e.draw_set_transform(at, 0.0, sq)
		draw_sprite(e, sheet, g.state, g.frame, Vector2.ZERO, e.face, g.tint)
		e.draw_set_transform(Vector2.ZERO)
	else:
		draw_sprite(e, sheet, g.state, g.frame, at, e.face, g.tint)
	if e.civ and e.panic and sin(e.A.time * 12.0 + e.juke) > 0.0:
		var head := Sheets.anchor(sheet, g.state, g.frame, "head", Vector2(0, -44))
		var hx: float = at.x + head.x * e.face; var hy: float = at.y + head.y - 20.0
		e.draw_rect(Rect2(hx - 1, hy, 3, 7), Color.WHITE); e.draw_rect(Rect2(hx - 1, hy + 9, 3, 2), Color.WHITE)

## Brief squash and stretch for weight: stretch while winding up a blow, squash on impact and when hit.
static func _squash(e) -> Vector2:
	var k := 0.5 if e.shrunk_t > 0.0 else 1.0   # Shrink Ray
	return _squash_pose(e) * k

static func _squash_pose(e) -> Vector2:
	if e.boss or e.vehicle or e.civ or e.frozen_t > 0.0 or e.time_lock > 0.0: return Vector2.ONE
	if e.flash > 0.0: return Vector2(1.1, 0.9)
	if e.action_phase == "swing": return Vector2(0.94, 1.07)
	if not e.ally and e.atk_cd > 0.9 and e.atk_cd <= 1.0 and (e.swings() or e.type == "k9"): return Vector2(1.12, 0.9)
	return Vector2.ONE

## Draws one frame with its foot point at `at` (node space). Left-facing sprites use the baked mirror
## atlas (normal x inverted), so they stay on their shadow and light correctly.
static func draw_sprite(ci: CanvasItem, sheet: Dictionary, state: String, index: int, at: Vector2, face: int, tint := Color(0, 0, 0, 0), alpha := 1.0) -> void:
	var src := Sheets.frame(sheet, state, index)
	var o: Vector2 = sheet.origin
	var tex: Texture2D = sheet.tex; var sil: Texture2D = sheet.sil
	var dest := Rect2(at.x - o.x, at.y - o.y, src.size.x, src.size.y)
	if face < 0:   # baked mirror atlas: same cell, mirrored; the foot column lands on `at` again
		src = Rect2(sheet.width - src.position.x - src.size.x, src.position.y, src.size.x, src.size.y)
		dest = Rect2(at.x - (src.size.x - 1.0 - o.x), at.y - o.y, src.size.x, src.size.y)
		tex = sheet.tex_l; sil = sheet.sil_l
	ci.draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, alpha))
	if tint.a > 0.0:
		ci.draw_texture_rect_region(sil, dest, src, Color(tint.r, tint.g, tint.b, tint.a * alpha))

## Called when a dead enemy leaves the tree: leaves a short-lived corpse playing the death animation.
static func leave_corpse(e) -> void:
	if not e.dead or e.hp > 0.0: return   # escaped civilians / wave clear despawns leave nothing
	var parent: Node = e.get_parent()
	if parent == null or parent.is_queued_for_deletion() or not parent.is_inside_tree(): return
	if Corpse.live >= Corpse.MAX_LIVE: return
	var c := Corpse.new()
	c.setup(EnemyArt.sheet(sprite_key(e)), e.face, Vector2(roundf(e.x), roundf(e.y)),
		"shatter" if e.frozen_t > 0.0 else ("vaporize" if e.disint else ("sick" if e.sick_t > 0.0 else "")), e.boss, e.gfx.get("lift", 0.0))
	if e.vehicle: c.vehicle_angle = e.aim_dir.angle(); c.vehicle_kind = e.type; c.face = 1
	parent.add_child.call_deferred(c)

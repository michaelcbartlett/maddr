extends RefCounted
## Damage belongs to the shared prop record, so art, collision and navigation agree.
const MAX_MARKS := 32
const CAR_BLAST_DAMAGE := 36.0
const CAR_BLAST_RADIUS := 130.0

static func weapon_hit(a, wall: Dictionary, amount: float, kind: String, point: Vector2, pfm := 1.0, player_shot := true) -> void:
	var index := int(wall.get("prop_index", -1))
	if index < 0 or index >= a.arena_level.props.size(): return
	var p: Dictionary = a.arena_level.props[index]
	if p.get("broken", false) or amount <= 0.0: return
	var stats: Dictionary = a.get_node("/root/Run").S
	var burn := float(stats.burn) * (1.0 + float(stats.dmgPct) * 0.5) if player_shot else 0.0
	damage(a, p, amount, kind, point, burn)
	# Explosive ammo also procs against scenery, using the same per-shot rate as enemies.
	if not player_shot or amount <= 0.0: return
	var run = a.get_node("/root/Run")
	if run.S.explode > 0 and randf() < run.S.explode * run.D.pf * pfm:
		a.explode(point.x, point.y, (14.0 + run.D.dmg * 0.8) * run.S.boomMul, 55.0 * sqrt(run.S.boomMul), Color("#ffa030"))

static func damage(a, p: Dictionary, amount: float, kind: String, point: Vector2, burn := 0.0) -> void:
	if amount <= 0.0 or p.get("broken", false) or not p.has("hp"): return
	if kind != "burn":
		p.flash = 0.08
		var rect: Rect2 = p.rect
		var inset := rect.grow(-5.0)
		var local := point.clamp(inset.position, inset.end) - Vector2(rect.get_center().x, rect.end.y) - Vector2(0, p.h * 0.7)
		p.marks.append({"pos":local, "kind":kind, "angle":randf() * TAU})
		if p.marks.size() > MAX_MARKS: p.marks.pop_front()
		var tint := Color("#b3a48d") if p.material == "stone" else (Color("#ae7944") if p.material == "wood" else (Color("#a7efff") if p.material == "glass" else Color("#ffd17b")))
		a.poof(point.x, point.y - p.h * 0.5, tint, 5, 75, 2)
	if kind in ["explosion", "burn"] or burn > 0.0:
		p.char = minf(1.0, p.char + (0.25 if kind == "explosion" else 0.08))
		if p.flammable:
			p.burn_t = maxf(p.burn_t, 3.0)
			p.burn_dps = maxf(p.burn_dps, maxf(8.0, burn))
			if p.kind == "car":
				var fuse := 0.8 if kind == "explosion" else 2.2
				p.fuse = fuse if p.fuse < 0.0 else minf(p.fuse, fuse)
	if p.kind == "case":
		a.damage_case(p, amount)
		return
	p.hp = maxf(0.0, p.hp - amount)
	if p.hp <= 0.0: destroy(a, p)

static func blast(a, center: Vector2, amount: float, radius: float) -> void:
	if amount <= 0.0: return # Defeated-boss celebrations are visual only.
	for p in a.arena_level.props:
		var rect: Rect2 = p.rect
		var nearest := center.clamp(rect.position, rect.end)
		if center.distance_to(nearest) <= radius: damage(a, p, amount, "explosion", nearest)

static func tick(a, dt: float) -> void:
	for p in a.arena_level.props:
		p.flash = maxf(0.0, p.flash - dt)
		p.wreck_t = maxf(0.0, p.wreck_t - dt)
		if p.broken: continue
		if p.burn_t > 0.0:
			var burning := minf(dt, p.burn_t)
			p.burn_t = maxf(0.0, p.burn_t - dt)
			p.char = minf(1.0, p.char + burning * 0.16)
			p.hp = maxf(0.0, p.hp - p.burn_dps * burning)
		if p.fuse >= 0.0: p.fuse = maxf(0.0, p.fuse - dt)
		if p.hp <= 0.0 or p.fuse == 0.0: destroy(a, p)

static func destroy(a, p: Dictionary) -> void:
	if p.broken: return
	var center: Vector2 = p.rect.get_center()
	var was_burning: bool = p.burn_t > 0.0 or p.fuse >= 0.0
	# Open the wall before detonating: a wreck can never explode or pay out twice.
	a.arena_level.break_prop(p)
	p.burn_t = 0.0; p.fuse = -1.0; p.char = 1.0 if was_burning or p.kind == "car" else p.char
	p.wreck_t = 2.5 if was_burning or p.kind == "car" else 0.0
	if p.kind == "car":
		a.explode(center.x, center.y, CAR_BLAST_DAMAGE, CAR_BLAST_RADIUS, Color("#ff8735"))
		var player := Vector2(a.P.x, a.P.y)
		if center.distance_to(player) < CAR_BLAST_RADIUS + a.P.r and a.nav.clear_segment(center, player, 0):
			a.hurt_player(12.0)
	else:
		var tint := Color("#b3a48d") if p.material == "stone" else (Color("#ae7944") if p.material == "wood" else Color("#8a949f"))
		a.poof(center.x, center.y, tint, 22, 145, 4); a.snd("break")

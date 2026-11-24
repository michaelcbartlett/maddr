extends Node2D
## Plays an enemy's death animation where it fell, lies there briefly, then fades.
## Ebola corpses are contagious only while this same visible node exists.
## Modes: "" normal, "poison" / "melt" / "burnt" (own animation where drawn), "sick" (green tint), "vaporize" (burns away fast), "shatter" (frozen: bursts into ice).
const MAX_LIVE := 40
static var live := 0
var sheet: Dictionary
var face := 1
var mode := ""
var t := 0.0
var hold := 2.6
var lift := 0.0
var shards: Array = []
var vehicle_angle := 0.0
var vehicle_kind := ""
var arena: Node
var infection_dps := 0.0
var infection_radius := 20.0
var state := "death"
var fps := 11.0
var frames := 4

func setup(s: Dictionary, f: int, pos: Vector2, m: String, boss: bool, air := 0.0) -> void:
	sheet = s; face = f; position = pos; mode = m; lift = air
	if boss: hold = 6.0
	state = "death_" + mode if sheet.frames.has("death_" + mode) else "death"
	var meta: Dictionary = EnemySheets.EditedArt.clip(sheet.kind, state).get("metadata", {})
	if meta.get("native", false):
		fps = float(meta.fps); frames = int(meta.frame_count)
		hold = maxf(hold, frames / fps + 1.4)
	if mode == "vaporize": hold = 0.3
	if mode == "shatter":
		for k in 14:
			var a := randf() * TAU
			shards.append({"p": Vector2(randf_range(-8, 8), sheet.foot - randf_range(4, 40)), "v": Vector2(cos(a), sin(a) - 0.6) * randf_range(40, 120), "s": randi_range(1, 3)})

func _enter_tree() -> void: live += 1; add_to_group("enemy_corpses")
func _exit_tree() -> void: live -= 1

func _process(dt: float) -> void:
	t += dt; lift = maxf(0.0, lift - dt * 200.0)
	for s in shards: s.v.y += 260.0 * dt; s.p += s.v * dt
	if t >= hold + 0.6: queue_free(); return
	spread_infection()
	queue_redraw()

func spread_infection() -> void:
	if infection_dps <= 0.0 or t >= hold+0.6 or is_queued_for_deletion() or not is_inside_tree(): return
	if not is_instance_valid(arena) or arena.state != "play": return
	for enemy in arena.enemies:
		if enemy.dead or enemy.ally or enemy.civ or enemy.fly or enemy.damage_taken("poison") <= 0.0: continue
		var point := Vector2(enemy.x,enemy.y)
		var previous := Vector2(enemy.px,enemy.py)
		if preload("res://game/shot_geometry.gd").circle_fraction(previous,point,position,infection_radius+enemy.r) < 0.0: continue
		if not arena.nav.clear_segment(position,point,0.0): continue
		arena.infect_ebola(enemy,infection_dps)

func _draw() -> void:
	var alpha := clampf((hold + 0.6 - t) / 0.6, 0.0, 1.0)
	if vehicle_kind != "":
		preload("res://enemies/vehicle_view.gd").draw(self,vehicle_kind,Vector2.from_angle(vehicle_angle),Vector2.ZERO,0.0,Color("#718180",0.25),alpha,true)
		return
	var at := Vector2(0, sheet.foot - lift)
	if infection_dps > 0.0:
		draw_circle(Vector2.ZERO,infection_radius,Color(0.45,0.5,0.06,0.15*alpha))
		draw_arc(Vector2.ZERO,infection_radius,0,TAU,24,Color(0.78,0.85,0.2,0.45*alpha),1.0)
		for i in 3:
			var point := Vector2.from_angle(i*TAU/3.0+t*0.6)*(infection_radius-4.0)
			draw_circle(point,1.5,Color(0.85,0.92,0.3,alpha*0.8))
	if sheet.family == "vehicle":
		draw_set_transform(Vector2.ZERO, vehicle_angle)
		at = Vector2(0, 23)
	if mode == "shatter":
		if t < 0.08: EnemyView.draw_sprite(self, sheet, "frozen", 0, at, face, Color("#9ef0ff", 0.5))
		for s in shards:
			var a2 := clampf(1.0 - t / 0.9, 0.0, 1.0)
			if a2 > 0.0: draw_rect(Rect2(s.p.round(), Vector2(s.s, s.s)), Color("#bff4ff", a2))
		return
	var fi := mini(frames - 1, int(t * fps))
	var tint := Color(0, 0, 0, 0)
	match mode:
		"sick": tint = Color("#8fdc3a", 0.4)
		"ebola": tint = Color("#c7da3a",0.55)
		"vaporize": tint = Color("#ff4a2a", clampf(0.5 + t * 2.0, 0.0, 1.0)); alpha = clampf(1.0 - t / (hold + 0.3), 0.0, 1.0)
	if fi < 3 or t < 0.3:
		pass
	EnemyView.draw_sprite(self, sheet, state, fi, at, face, tint, alpha)

extends Node2D
## Plays an enemy's death animation where it fell, lies there briefly, then fades. Purely visual.
## Modes: "" normal, "sick" (green tint), "vaporize" (burns away fast), "shatter" (frozen: bursts into ice).
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

func setup(s: Dictionary, f: int, pos: Vector2, m: String, boss: bool, air := 0.0) -> void:
	sheet = s; face = f; position = pos; mode = m; lift = air
	if boss: hold = 6.0
	if mode == "vaporize": hold = 0.3
	if mode == "shatter":
		for k in 14:
			var a := randf() * TAU
			shards.append({"p": Vector2(randf_range(-8, 8), sheet.foot - randf_range(4, 40)), "v": Vector2(cos(a), sin(a) - 0.6) * randf_range(40, 120), "s": randi_range(1, 3)})

func _enter_tree() -> void: live += 1
func _exit_tree() -> void: live -= 1

func _process(dt: float) -> void:
	t += dt; lift = maxf(0.0, lift - dt * 200.0)
	for s in shards: s.v.y += 260.0 * dt; s.p += s.v * dt
	if t > hold + 0.6: queue_free()
	queue_redraw()

func _draw() -> void:
	var alpha := clampf((hold + 0.6 - t) / 0.6, 0.0, 1.0)
	if vehicle_kind != "":
		preload("res://enemies/vehicle_view.gd").draw(self,vehicle_kind,Vector2.from_angle(vehicle_angle),Vector2.ZERO,0.0,Color("#718180",0.25),alpha,true)
		return
	var at := Vector2(0, sheet.foot - lift)
	if sheet.family == "vehicle":
		draw_set_transform(Vector2.ZERO, vehicle_angle)
		at = Vector2(0, 23)
	if mode == "shatter":
		if t < 0.08: EnemyView.draw_sprite(self, sheet, "frozen", 0, at, face, Color("#9ef0ff", 0.5))
		for s in shards:
			var a2 := clampf(1.0 - t / 0.9, 0.0, 1.0)
			if a2 > 0.0: draw_rect(Rect2(s.p.round(), Vector2(s.s, s.s)), Color("#bff4ff", a2))
		return
	var fi := mini(3, int(t * 11.0))
	var tint := Color(0, 0, 0, 0)
	match mode:
		"sick": tint = Color("#8fdc3a", 0.4)
		"vaporize": tint = Color("#ff4a2a", clampf(0.5 + t * 2.0, 0.0, 1.0)); alpha = clampf(1.0 - t / (hold + 0.3), 0.0, 1.0)
	if fi < 3 or t < 0.3:
		pass
	EnemyView.draw_sprite(self, sheet, "death", fi, at, face, tint, alpha)

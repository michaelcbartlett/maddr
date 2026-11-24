extends RefCounted
## B / Shift: a short phase dash along the left stick (or the aim when the stick is idle).
## He is untouchable while phased, passes through enemies and bullets, and stops at walls.
## Keep the button held while moving to carry the dash into a sprint. Firing drops out of the sprint.

const DISTANCE := 170.0
const DURATION := 0.2
const SAFE_AFTER := 0.06       # grace after he reappears
const COOLDOWN := 0.75         # from the start of one dash to the next
const SPRINT := 1.45
const BUFFER := 0.12           # a press this early still counts
const GHOST_EVERY := 0.03
const GHOST_LIFE := 0.28

var t := 0.0                   # time left in the dash
var safe_t := 0.0
var cd := 0.0
var buffer_t := 0.0
var dir := Vector2.RIGHT
var sprinting := false
var ghosts: Array = []
var _ghost_t := 0.0
var _carry := false            # held since the dash began

func reset() -> void:
	t = 0.0; safe_t = 0.0; cd = 0.0; buffer_t = 0.0; sprinting = false; _carry = false; ghosts.clear()

func active() -> bool: return t > 0.0
func safe() -> bool: return t > 0.0 or safe_t > 0.0
func progress() -> float: return clampf(1.0 - t / DURATION, 0.0, 1.0)

func press() -> void: buffer_t = BUFFER

## Runs before normal movement. Returns true while the dash owns his position.
func update(a, dt: float, move: Vector2, aim: float, held: bool, firing: bool) -> bool:
	cd = maxf(0.0, cd - dt); safe_t = maxf(0.0, safe_t - dt); buffer_t = maxf(0.0, buffer_t - dt)
	for ghost in ghosts: ghost.t -= dt
	ghosts = ghosts.filter(func(g): return g.t > 0.0)
	if not held: _carry = false
	if buffer_t > 0.0 and cd <= 0.001 and t <= 0.0 and a.boss_move.is_empty(): _start(a, move, aim)
	if t <= 0.0:
		sprinting = held and _carry and move != Vector2.ZERO and not firing and not a.P.primary_swinging
		return false
	sprinting = false
	var step_dt := minf(dt, t)
	# Ease out: fast leave, soft arrival. The integral over DURATION is exactly DISTANCE.
	var u0 := progress(); t -= step_dt; var u1 := progress()
	var travel := (_ease(u1) - _ease(u0)) * DISTANCE
	var from := Vector2(a.P.x, a.P.y); var to := from + dir * travel
	var contact: Dictionary = a._projectile_wall_hit(from, to, a.P.r)
	if not contact.is_empty(): to = from.lerp(to, maxf(0.0, contact.fraction - 0.01))
	a.P.x = to.x; a.P.y = to.y; a.P.idle_t = 0.0
	_ghost_t -= step_dt
	if _ghost_t <= 0.0: _ghost_t = GHOST_EVERY; _add_ghost(a)
	if t <= 0.0001:
		t = 0.0; safe_t = SAFE_AFTER; _burst(a)
	return true

static func _ease(u: float) -> float: return 1.0 - (1.0 - u) * (1.0 - u)

func _start(a, move: Vector2, aim: float) -> void:
	dir = move.normalized() if move != Vector2.ZERO else Vector2.from_angle(aim)
	t = DURATION; cd = COOLDOWN; buffer_t = 0.0; _ghost_t = 0.0; _carry = true
	a.grapple.reset()
	_burst(a); a.snd("blink"); a.get_node("/root/Controls").rumble(0.25, 0.15, 70)

func _burst(a) -> void:
	a.poof(a.P.x, a.P.y - 14.0, color(a), 9, 130, 2.5)

static func color(a) -> Color:
	return a.villain.rig.AMMO_COL.get(a.villain.rig.ammo, Color("#9d7bff"))

func _add_ghost(a) -> void:
	var body: Sprite2D = a.villain.rig.body
	if body.texture == null: return
	ghosts.append({"tex": body.texture.diffuse_texture if body.texture is CanvasTexture else body.texture,
		"xf": body.global_transform, "offset": body.offset, "t": GHOST_LIFE})

## Additive afterimages, drawn on the arena's effects layer.
func draw(g: Node2D, a) -> void:
	var tint := color(a)
	for ghost in ghosts:
		g.draw_set_transform_matrix(g.global_transform.affine_inverse() * ghost.xf)
		g.draw_texture(ghost.tex, ghost.offset, Color(tint, 0.5 * ghost.t / GHOST_LIFE))
	g.draw_set_transform(Vector2.ZERO)

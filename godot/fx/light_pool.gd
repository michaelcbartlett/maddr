extends Node2D
class_name LightPool
## A pool of PointLight2D nodes that the arena requests each frame (muzzle flashes, lasers, orbs, explosions,
## alarm, reactor/isotope glows, ...). begin() hides everything; add() places one light. Lights shade the
## villain's normal maps (CanvasTexture) and light up the floor under the CanvasModulate darkness.

const MAX := 96
var _lights: Array[PointLight2D] = []
var _n := 0
static var _tex: Texture2D

static func light_tex() -> Texture2D:
	if _tex: return _tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5); gt.width = 256; gt.height = 256
	_tex = gt
	return _tex

func _ready() -> void:
	for i in MAX:
		var l := PointLight2D.new(); l.texture = light_tex(); l.enabled = false; l.height = 24.0
		l.blend_mode = Light2D.BLEND_MODE_ADD
		add_child(l); _lights.append(l)

func begin() -> void:
	for i in _n: _lights[i].enabled = false
	_n = 0

## radius in world px (texture is 256 px wide, so scale = radius / 128)
func add(pos: Vector2, col: Color, energy: float, radius: float, height := 24.0) -> void:
	if _n >= MAX or energy <= 0.01: return
	var l := _lights[_n]; _n += 1
	l.enabled = true; l.position = pos; l.color = col; l.energy = energy
	l.texture_scale = radius / 128.0; l.height = height

func count() -> int: return _n

extends Node2D
class_name LightPool
## A pool of PointLight2D nodes that the arena requests each frame (muzzle flashes, lasers, orbs, explosions,
## alarm, reactor/isotope glows, ...). begin() hides everything; add() places one light. Lights shade the
## villain's normal maps (CanvasTexture) and light up the floor under the CanvasModulate darkness.

const MAX := 96
var _lights: Array[PointLight2D] = []
var _n := 0
static var _tex: Texture2D
static var _down_tex: Texture2D

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
	l.enabled = true; l.texture = light_tex(); l.position = pos; l.color = col; l.energy = energy
	l.texture_scale = radius / 128.0; l.height = height

## A hooded street fixture illuminates only below its bulb in the screen plane.
func add_downlight(pos: Vector2, col: Color, energy: float, radius: float, height := 24.0) -> void:
	if _n>=MAX or energy<=0.01: return
	if _down_tex==null:
		var image := Image.create(256,256,false,Image.FORMAT_RGBA8); image.fill(Color(0,0,0,0))
		for y in range(129,256):
			var down := float(y-128)/128.0
			for x in 256:
				var across := absf(float(x-128)/128.0)
				var spread := 0.07+down*0.8
				var alpha := (1.0-smoothstep(spread*0.7,spread,across))*pow(1.0-down,1.3)*smoothstep(0.0,0.03,down)
				image.set_pixel(x,y,Color(alpha,alpha,alpha,alpha))
		_down_tex = ImageTexture.create_from_image(image)
	add(pos,col,energy,radius,height)
	_lights[_n-1].texture = _down_tex

func count() -> int: return _n

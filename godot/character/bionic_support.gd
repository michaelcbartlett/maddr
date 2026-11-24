extends Node2D
## A back-mounted articulated cable. Cached lit sprites also join puddle reflections.
const Pixels = preload("res://character/pixel_canvas.gd")
const Pen = preload("res://character/pixel_pen.gd")
const Profiles = preload("res://character/height_profiles.gd")
const LINKS := 24
static var _link: CanvasTexture
static var _mount: CanvasTexture
var links: Array[Sprite2D] = []
var mount: Sprite2D
var start := Vector2.ZERO
var tip := Vector2.ZERO

func _ready() -> void:
	if _link == null:
		var pixels = Pixels.new(8,8); var p = Pen.new(pixels,0,0)
		p.layer(8,Profiles.cylH(3.5,3.5,3))
		p.R(0,1,8,6,"#263b4b"); p.R(1,1,5,6,"#688a9c")
		p.R(1,1,5,2,"#c4dce4"); p.R(2,4,4,2,"#4d6f80")
		p.R(6,2,1,4,"#182b3e"); p.P(3,2,"#73f4ff")
		_link = _texture(pixels)
		pixels = Pixels.new(14,14); p = Pen.new(pixels,6,6)
		p.layer(10,Profiles.dome(0,0,6,6,4))
		p.ell(0,0,6,6,"#263b4b"); p.ell(0,0,4,4,"#819eae")
		p.ell(0,0,2,2,"#244c65"); p.P(0,-1,"#73f4ff")
		_mount = _texture(pixels)
	mount = _sprite(_mount); mount.name = "BackMount"
	for i in LINKS:
		var link := _sprite(_link); link.name = "Link%d" % i; links.append(link)

func _sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new(); sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; add_child(sprite)
	return sprite

static func _texture(pixels) -> CanvasTexture:
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(pixels.outlined_image())
	texture.normal_texture = ImageTexture.create_from_image(pixels.normal_image())
	return texture

func pose(base: Vector2, end: Vector2, face: float) -> void:
	start = base; tip = end; mount.position = base
	var c1 := base+Vector2(-32*face,-2)
	var c2 := end+Vector2(-30*face,12)
	for i in LINKS:
		var u := i/float(LINKS-1)
		var point := base.bezier_interpolate(c1,c2,end,u)
		var tangent := base.bezier_derivative(c1,c2,end,u)
		links[i].position = point; links[i].rotation = tangent.angle()

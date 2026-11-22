extends Node2D
## A short shader muzzle flash plus a point light. Position it at the muzzle, rotate it to the shot
## direction and call fire(). It fades itself out; tick(dt) advances it from the owner.
const DURATION := 0.12
const SIZE := Vector2(26, 16)
static var _material: ShaderMaterial
static var _quad: Texture2D

var life := 0.0
var color := Color("#ffb347")
var light: PointLight2D

func _ready() -> void:
	if _material == null:
		_material = ShaderMaterial.new(); _material.shader = preload("res://enemies/muzzle_flash.gdshader")
		_material.set_shader_parameter("size", SIZE)
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8); img.fill(Color.WHITE)
		_quad = ImageTexture.create_from_image(img)
	material = _material
	z_index = 2
	light = PointLight2D.new(); light.texture = preload("res://fx/light_pool.gd").light_tex()
	light.texture_scale = 0.55; light.height = 18.0; light.energy = 0.0; light.color = color
	light.blend_mode = Light2D.BLEND_MODE_ADD; light.position = Vector2(4, 0)
	add_child(light)

func fire(col := Color("#ffb347")) -> void:
	color = col; life = 1.0; light.color = col.lerp(Color.WHITE, 0.3)
	light.energy = 2.2
	queue_redraw()

func tick(dt: float) -> void:
	if life <= 0.0: return
	life = maxf(0.0, life - dt / DURATION)
	light.energy = 2.2 * life
	queue_redraw()

func _draw() -> void:
	if life <= 0.0: return
	draw_texture_rect(_quad, Rect2(Vector2(-1, -SIZE.y / 2), SIZE), false, Color(color.r, color.g, color.b, life))

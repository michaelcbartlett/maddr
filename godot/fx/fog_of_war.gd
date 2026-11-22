extends Node2D
const FogShader = preload("res://fx/fog_of_war.gdshader")
var mask: Image
var texture: ImageTexture
var fog_material := ShaderMaterial.new()
var last_cell := Vector2i(-1,-1)

func _init() -> void:
	mask = Image.create(128,128,false,Image.FORMAT_RGBA8); mask.fill(Color.BLACK)
	texture = ImageTexture.create_from_image(mask)
	fog_material.shader = FogShader; fog_material.set_shader_parameter("explored_mask",texture)
	material = fog_material; visible = false

func reset() -> void:
	mask.fill(Color.BLACK); texture.update(mask); last_cell = Vector2i(-1,-1)

func reveal(point: Vector2) -> void:
	fog_material.set_shader_parameter("player_position",point)
	var cell = Vector2i(point/64.0)
	if cell==last_cell: return
	last_cell = cell
	for y in range(maxi(0,cell.y-4),mini(128,cell.y+5)):
		for x in range(maxi(0,cell.x-4),mini(128,cell.x+5)):
			if Vector2(x,y).distance_to(Vector2(cell))<4.0: mask.set_pixel(x,y,Color.WHITE)
	texture.update(mask)

func _draw() -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(8192,0),Vector2(8192,8192),Vector2(0,8192)]),PackedColorArray([Color.WHITE]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]))

extends Node2D
## One shader strip per active ray. The capsule mask rounds both the core and its glow.
const BeamShader = preload("res://fx/laser_beam.gdshader")
var shader_material := ShaderMaterial.new()
var _length := 1.0
var _radius := 5.0
var _padding := 22.0

func _init() -> void:
	shader_material.shader = BeamShader
	material = shader_material

func configure(start: Vector2, finish: Vector2, width: float, color: Color, fade: float, time: float, stats: Dictionary) -> void:
	position = start; rotation = (finish-start).angle()
	_length = start.distance_to(finish); _radius = maxf(1.0,width/2.0)
	visible = _length>0.01 and fade>0.0
	shader_material.set_shader_parameter("beam_length",_length)
	shader_material.set_shader_parameter("beam_radius",_radius)
	shader_material.set_shader_parameter("padding",_padding)
	shader_material.set_shader_parameter("beam_color",color)
	shader_material.set_shader_parameter("opacity",clampf(fade,0.0,1.0))
	shader_material.set_shader_parameter("clock",time)
	shader_material.set_shader_parameter("chain",1.0 if stats.chain>0 else 0.0)
	shader_material.set_shader_parameter("burning",1.0 if stats.burn>0 else 0.0)
	shader_material.set_shader_parameter("frost",1.0 if stats.freeze>0 else 0.0)
	shader_material.set_shader_parameter("toxic",1.0 if stats.poison>0 or stats.sick>0 else 0.0)
	shader_material.set_shader_parameter("mind",1.0 if stats.mind>0 else 0.0)
	queue_redraw()

func _draw() -> void:
	var left = -_padding-_radius; var right = _length+_padding+_radius; var half_height = _radius+_padding
	draw_polygon(PackedVector2Array([Vector2(left,-half_height),Vector2(right,-half_height),Vector2(right,half_height),Vector2(left,half_height)]),
		PackedColorArray([Color.WHITE]),PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]))

extends Node2D
## Run-opening beam. Arena owns the clock; combat is held until materialization ends.
const DURATION:=1.15
const COLOR:=Color("#59ff8b")
const Wipe=preload("res://fx/teleport_materialize.gdshader")
var active:=false
var elapsed:=0.0
var reveal_height:=0.0
var _beam_height:=800.0
var _originals:={}
var _wipe: ShaderMaterial

func begin(a) -> void:
	reset(a);active=true;elapsed=0.0;position=Vector2(a.P.x,a.P.y);visible=true
	_beam_height=a.get_viewport_rect().size.y/a.cam.zoom.y+200.
	var additive:=CanvasItemMaterial.new();additive.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD;material=additive
	z_index=20;_wipe=ShaderMaterial.new();_wipe.shader=Wipe
	a.P.moving=false;a.P.move_velocity=Vector2.ZERO
	a.snd("arrival")
	apply(a);queue_redraw()

func tick(a,dt: float) -> void:
	if not active:return
	elapsed=minf(DURATION,elapsed+maxf(0.0,dt))
	if elapsed>=DURATION:reset(a)
	queue_redraw()

func strength() -> float:
	return smoothstep(.1,.26,elapsed)*(1.-smoothstep(.72,DURATION,elapsed)) if active else 0.0

func _sprites(node: Node,result: Array) -> void:
	if node is Sprite2D:result.append(node)
	for child in node.get_children():_sprites(child,result)

func apply(a) -> void:
	if not active:return
	reveal_height=120.*a.P.size_scale*smoothstep(.24,.76,elapsed)
	_wipe.set_shader_parameter("ground_y",position.y)
	_wipe.set_shader_parameter("reveal_height",reveal_height)
	_wipe.set_shader_parameter("glow",strength()*.55)
	var sprites: Array=[];_sprites(a.villain,sprites)
	for sprite: Sprite2D in sprites:
		var id:=sprite.get_instance_id()
		if not _originals.has(id):_originals[id]={"source":weakref(sprite),"material":sprite.material}
		sprite.material=_wipe
	a.villain.set_meta("arrival_reveal_height",reveal_height)

func reset(a) -> void:
	for row in _originals.values():
		var sprite=row.source.get_ref()
		if sprite!=null:sprite.material=row.material
	_originals.clear();active=false;visible=false;reveal_height=-1.0
	if a.villain!=null and a.villain.has_meta("arrival_reveal_height"):a.villain.remove_meta("arrival_reveal_height")

func _draw() -> void:
	if not active:return
	var landing:=smoothstep(0.0,.22,elapsed)
	var tip: float=-_beam_height*(1.-landing)
	var power:=strength();var width: float=roundf(5.+22.*power)
	var fade:=1.-smoothstep(.83,DURATION,elapsed)
	for layer in [3.,2.,1.]:
		draw_rect(Rect2(-width*layer/2.,-_beam_height,width*layer,_beam_height+tip),Color(COLOR,(.035 if layer>1 else .22)*fade))
	draw_rect(Rect2(-2.,-_beam_height,4.,_beam_height+tip),Color("#d1ffe2")*Color(1,1,1,fade))
	if elapsed>.22:
		draw_set_transform(Vector2.ZERO,0,Vector2(1,.28))
		draw_circle(Vector2.ZERO,22.+power*12.,Color(COLOR,power*.15))
		draw_arc(Vector2.ZERO,12.+smoothstep(.22,.65,elapsed)*35.,0,TAU,40,Color(COLOR,power*.8),2.)
		draw_set_transform(Vector2.ZERO)

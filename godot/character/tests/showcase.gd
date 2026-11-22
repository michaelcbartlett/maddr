extends Node2D
## Native character gallery. Run this scene to inspect gear, lighting and reactions.
## Optional -- --shot path.png captures the gallery and exits.
const Rig = preload("res://character/villain.gd")
const LOADOUTS = [
	{"title":"BARE · RAY PISTOL","items":[],"ammo":"laser","frame":"pistol","aim":-0.12},
	{"title":"BATTERY · TELESCOPING MONOCLE","items":["core_battery","telescope","scope","cell","coat","boots"],"ammo":"bullet","frame":"rifle","aim":-0.1},
	{"title":"MUTAGEN · CRYO · RAZOR","items":["mutagen","zero","cryo","drill","goggles","core_brain"],"ammo":"razor","frame":"blunder","aim":0.1},
	{"title":"DUAL GUNS · STACKED MODULES","items":["core_hamster","gLaser","gRazor","tesla","storm","hypno","fins"],"ammo":"bullet","frame":"repeater","aim":-0.12,"off":{"ammo":0,"frame":0,"items":["sustain","cell"]}},
	{"title":"HURT · MIRRORED LIGHTING","items":["coat","coat","serum","acid","monocle","core_isotope"],"ammo":"laser","frame":"rifle","aim":3.3,"hurt":true},
	{"title":"STATIC SURGE · X-RAY REACTION","items":["thermite","reactor","hive","moon","singular"],"ammo":"laser","frame":"pistol","aim":-0.2,"zap":true}
]
var rigs: Array[Node2D] = []
var _shot := ""
var _frames := 0
var _capturing := false

func _ready() -> void:
	var args = OS.get_cmdline_user_args(); var index = args.find("--shot")
	if index >= 0 and index+1 < args.size(): _shot = args[index+1]
	var ambient = CanvasModulate.new(); ambient.color = Color(0.55,0.57,0.66); add_child(ambient)
	var background = Polygon2D.new(); background.polygon = PackedVector2Array([Vector2.ZERO,Vector2(960,0),Vector2(960,540),Vector2(0,540)]); background.color = Color("#141e22"); add_child(background)
	var hud = CanvasLayer.new(); add_child(hud)
	_label(hud,"THE DIABOLICAL DOCTOR / NATIVE GODOT CHARACTER",Vector2(24,16),20,Color("#b4ff3c"))
	for i in LOADOUTS.size():
		var config: Dictionary = LOADOUTS[i]
		var origin = Vector2(16+(i%3)*314,64+(i/3)*234)
		_label(hud,config.title,origin+Vector2(4,4),12,Color("#d8e4e0"))
		var rig = Rig.new(); add_child(rig); rig.set_items(config.items,config.ammo,config.frame,config.get("off"))
		rig.set_state({"aim":config.aim,"off_aim":config.aim+0.08,"moving":i==3,"walk_phase":0.25,"white":config.get("hurt",false),"zap":config.get("zap",false)})
		var bounds = rig.visual_bounds(); var scale_factor = minf(3.0,minf(282.0/bounds.size.x,166.0/bounds.size.y))
		rig.scale = Vector2.ONE*scale_factor
		rig.position = origin+Vector2((300-bounds.size.x*scale_factor)/2-bounds.position.x*scale_factor,202-bounds.end.y*scale_factor)
		rigs.append(rig)
		var light = PointLight2D.new(); light.texture = Rig._light_tex(); light.color = Color("#fff2dc"); light.energy = 1.2; light.height = 70.0
		light.texture_scale = 1.4; light.position = origin+Vector2(95,105); add_child(light)
	_label(hud,"Procedural gear / OpenGL normal maps / independent weapons / eight-frame walk / pose-following skeleton",Vector2(24,518),12,Color("#8aa09a"))

func _label(parent: Node, text: String, position: Vector2, size: int, color: Color) -> void:
	var label = Label.new(); label.text = text; label.position = position; label.add_theme_font_size_override("font_size",size); label.add_theme_color_override("font_color",color); parent.add_child(label)

func _process(_delta: float) -> void:
	for i in rigs.size():
		var rig = rigs[i]; rig.t = 0.0 if i==5 else 0.8
		rig.set_state({"firing":i in [1,3],"flash":0.08 if i==3 else 0.0,"firing2":i==3,"flash2":0.08 if i==3 else 0.0})
	_frames += 1
	if _shot != "" and _frames >= 12 and not _capturing:
		_capturing = true
		await RenderingServer.frame_post_draw
		var result = get_viewport().get_texture().get_image().save_png(_shot)
		print("SHOWCASE screenshot: ",_shot," result=",result)
		get_tree().quit()

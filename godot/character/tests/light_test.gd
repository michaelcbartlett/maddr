extends Node2D
## Lighting test bench for the villain rig.
##   Mouse        : moves the point light          Mouse wheel : light height
##   LMB (hold)   : fire (muzzle flash light)      RMB         : toggle off-hand weapon
##   A / D        : aim sweep left/right           W           : toggle walk
##   B            : toggle laser beam lights       N           : ambient dark / bright
## Run with  -- --shot <file.png>  to save a screenshot after a few frames and quit (used for automated checks).

const Villain := preload("res://character/villain.gd")

var villain: Node2D
var light: PointLight2D
var beam: Array[PointLight2D] = []
var ambient: CanvasModulate
var hud: Label
var fx: Node2D
var beam_on := false
var _shot_path := ""
var _frames := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size(): _shot_path = args[i + 1]
	# floor: a mid-grey checker so lights read clearly
	var floor_img := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for y in 360:
		for x in 640:
			var c := 0.30 if ((x / 16 + y / 16) % 2 == 0) else 0.27
			floor_img.set_pixel(x, y, Color(c, c + 0.02, c + 0.02))
	var fl := Sprite2D.new(); fl.texture = ImageTexture.create_from_image(floor_img); fl.centered = false; add_child(fl)
	ambient = CanvasModulate.new(); ambient.color = Color(0.28, 0.28, 0.34); add_child(ambient)
	villain = Villain.new(); villain.auto_demo = true; villain.position = Vector2(250, 200); add_child(villain)
	villain.aim = -0.15
	light = PointLight2D.new(); light.texture = Villain._light_tex(); light.texture_scale = 1.6
	light.color = Color("#fff2dc"); light.energy = 1.4; light.height = 40.0; light.position = Vector2(215, 175)
	add_child(light)
	var cam := Camera2D.new(); cam.position = villain.position + Vector2(20, -10); cam.zoom = Vector2(3, 3); add_child(cam)
	var j := args.find("--aim")
	if j >= 0: villain.aim = float(args[j + 1])
	var lj := args.find("--light")
	if lj >= 0:
		var xy := (args[lj + 1] as String).split(",")
		light.position = Vector2(float(xy[0]), float(xy[1])); light.height = float(xy[2]) if xy.size() > 2 else light.height
	for k in 8:
		var bl := PointLight2D.new(); bl.texture = Villain._light_tex(); bl.texture_scale = 0.25
		bl.color = Color("#ff4a4a"); bl.energy = 0.0; bl.height = 8.0; add_child(bl); beam.append(bl)
	# FX + HUD live on their own CanvasLayer so the CanvasModulate darkness and lights don't touch them (emissive look)
	var layer := CanvasLayer.new(); add_child(layer)
	fx = Node2D.new(); var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; fx.material = mat
	fx.draw.connect(_draw_fx); layer.add_child(fx)
	hud = Label.new(); hud.position = Vector2(6, 4); hud.add_theme_font_size_override("font_size", 8); layer.add_child(hud)
	if _shot_path != "":
		villain.firing = true; villain.firing2 = true; villain.set_items([], "laser", "pistol", {"ammo": "bullet", "frame": "rifle", "items": []}); beam_on = false

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: light.height += 4
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: light.height = maxf(0, light.height - 4)
		elif e.button_index == MOUSE_BUTTON_RIGHT: villain.set_items([], "laser", "pistol", null if villain.armed else {"ammo": "bullet", "frame": "pistol", "items": []})
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_W: villain.moving = not villain.moving
			KEY_B: beam_on = not beam_on
			KEY_N: ambient.color = Color(0.8, 0.8, 0.85) if ambient.color.r < 0.5 else Color(0.28, 0.28, 0.34)

func _process(dt: float) -> void:
	if _shot_path == "":
		light.position = get_global_mouse_position()
		villain.firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT); villain.firing2 = villain.firing
	var turn := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	villain.aim = wrapf(villain.aim + turn * dt * 2.0, -PI, PI)
	villain.off_aim = villain.aim + 0.2
	# laser beam = a row of small red lights along the barrel direction
	var m: Vector2 = villain.muzzle_global()
	var dir := Vector2.RIGHT.rotated(villain.aim)
	for k in beam.size():
		beam[k].position = m + dir * (6 + k * 22)
		beam[k].energy = (0.9 + randf() * 0.3) if beam_on else 0.0
	hud.text = "mouse: light  wheel: light height (%d)  LMB fire  A/D aim  W walk  RMB off-hand gun  B beam  N ambient" % int(light.height)
	fx.queue_redraw()
	_frames += 1
	if _shot_path != "" and _frames == 40:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		get_tree().quit()

func _draw_fx() -> void:
	if beam_on:   # beam sprite itself: emissive, drawn on top (unlit look comes from the additive colour)
		var m: Vector2 = villain.muzzle_global()
		var e := m + Vector2.RIGHT.rotated(villain.aim) * 400
		fx.draw_line(m, e, Color(1, 0.3, 0.3, 0.35), 7)
		fx.draw_line(m, e, Color(1, 0.4, 0.4), 3)
		fx.draw_line(m, e, Color.WHITE, 1)

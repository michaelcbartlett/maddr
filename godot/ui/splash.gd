extends Control
## Opening company logo: the AngryRatGames animation (62 frames, 12 fps, from an 8x8 sheet) with the studio name
## in Shantell Sans popping in once the camera lands on the rat's face. Holds briefly, fades out, then `finished`.
## Any key, click or pad button skips it. main.gd never shows it in test runs.
signal finished

const SHEET := preload("res://ui/splash/angryrat_sheet.png")
const FONT := preload("res://ui/splash/ShantellSans-ExtraBold.ttf")
const FRAME := Vector2i(344, 192)
const COLUMNS := 8
const FRAMES := 62
const FPS := 12.0
const NAME_FROM := 43          # first close-up frame of the rat's face: the name pops in here
const HOLD := 1.3              # seconds on the last frame before fading out
const FADE := 0.45

var _t := 0.0
var _done := false
var _atlas := AtlasTexture.new()
var _picture := TextureRect.new()
var _name := Label.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new(); black.color = Color.BLACK; black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(black)
	_atlas.atlas = SHEET
	_picture.texture = _atlas
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	_name.text = "AngryRatGames"
	_name.add_theme_font_override("font", FONT)
	_name.add_theme_font_size_override("font_size", 62)
	_name.add_theme_color_override("font_color", Color.WHITE)
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 18)
	_name.add_theme_color_override("font_shadow_color", Color("#d8261c"))
	_name.add_theme_constant_override("shadow_offset_x", 5); _name.add_theme_constant_override("shadow_offset_y", 6)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_name.offset_left = -400; _name.offset_right = 400; _name.offset_top = -128; _name.offset_bottom = -40
	_name.pivot_offset = Vector2(400, 44)
	_name.modulate.a = 0.0
	add_child(_name)
	_show_frame(0)

func _show_frame(i: int) -> void:
	_atlas.region = Rect2(Vector2((i % COLUMNS) * FRAME.x, (i / COLUMNS) * FRAME.y), Vector2(FRAME))

func _process(dt: float) -> void:
	if _done: return
	_t += dt
	var frame := mini(int(_t * FPS), FRAMES - 1)
	_show_frame(frame)
	var name_t := _t - NAME_FROM / FPS
	if name_t > 0.0:
		var k := clampf(name_t / 0.25, 0.0, 1.0)
		_name.modulate.a = k
		_name.scale = Vector2.ONE * (1.0 + 0.35 * (1.0 - k) * (1.0 - k)) * (1.0 + 0.06 * sin(clampf(name_t / 0.4, 0.0, 1.0) * PI))
	var end := FRAMES / FPS + HOLD
	if _t > end: modulate.a = clampf(1.0 - (_t - end) / FADE, 0.0, 1.0)
	if _t > end + FADE: _finish()

func _input(e: InputEvent) -> void:
	if _done or _t < 0.2: return
	if (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton) and e.is_pressed():
		get_viewport().set_input_as_handled(); _finish()

func _finish() -> void:
	if _done: return
	_done = true
	finished.emit()
	queue_free()

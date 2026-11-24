extends Node
## Autoload "Controls": input map (registered at startup), aim source, rumble, controller status.
## Controller-first. Left stick moves, ONLY the right stick aims, RT fires the main gun, LT the off-hand gun,
## B dashes (hold to sprint), X uses a consumable, Y uses an equipped ability, LB / RB detonate mines,
## Start pauses, A selects, Y rerolls in the shop. There is no autofire.
## Mouse/keyboard fallback: WASD, mouse aim, left/right click, Space, Esc.
## Godot maps every pad to the SDL "standard" layout (so an 8BitDo in DirectInput mode is handled by SDL's
## controller database). joy_status() reports whether the connected pad is recognised.

const DZ_MOVE := 0.2
const DZ_AIM := 0.3
const DZ_TRIG := 0.3

var aim_src := "mouse"   # "mouse" or "pad"
var device := -1         # active joypad id
var muted := false

signal pad_changed(text: String)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_actions()
	Input.joy_connection_changed.connect(_on_joy)
	var pads := Input.get_connected_joypads()
	if pads.size() > 0: device = pads[0]; aim_src = "pad"

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new(); e.physical_keycode = code; return e

func _jb(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new(); e.button_index = b; e.device = -1; return e

func _ja(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new(); e.axis = a; e.axis_value = v; e.device = -1; return e

func _mb(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = b; return e

func _add(action: String, events: Array, dz := 0.5) -> void:
	if InputMap.has_action(action): InputMap.erase_action(action)
	InputMap.add_action(action, dz)
	for e in events: InputMap.action_add_event(action, e)

func _setup_actions() -> void:
	_add("move_left", [_key(KEY_A), _key(KEY_LEFT), _ja(JOY_AXIS_LEFT_X, -1)], DZ_MOVE)
	_add("move_right", [_key(KEY_D), _key(KEY_RIGHT), _ja(JOY_AXIS_LEFT_X, 1)], DZ_MOVE)
	_add("move_up", [_key(KEY_W), _key(KEY_UP), _ja(JOY_AXIS_LEFT_Y, -1)], DZ_MOVE)
	_add("move_down", [_key(KEY_S), _key(KEY_DOWN), _ja(JOY_AXIS_LEFT_Y, 1)], DZ_MOVE)
	# right stick only (never the left stick)
	_add("aim_left", [_ja(JOY_AXIS_RIGHT_X, -1)], 0.0)
	_add("aim_right", [_ja(JOY_AXIS_RIGHT_X, 1)], 0.0)
	_add("aim_up", [_ja(JOY_AXIS_RIGHT_Y, -1)], 0.0)
	_add("aim_down", [_ja(JOY_AXIS_RIGHT_Y, 1)], 0.0)
	_add("fire", [_ja(JOY_AXIS_TRIGGER_RIGHT, 1), _mb(MOUSE_BUTTON_LEFT)], DZ_TRIG)
	_add("fire_off", [_ja(JOY_AXIS_TRIGGER_LEFT, 1), _mb(MOUSE_BUTTON_RIGHT)], DZ_TRIG)
	_add("detonate", [_jb(JOY_BUTTON_LEFT_SHOULDER), _jb(JOY_BUTTON_RIGHT_SHOULDER), _key(KEY_SPACE)])
	_add("dash", [_jb(JOY_BUTTON_B), _key(KEY_SHIFT)])
	_add("boss_action", [_jb(JOY_BUTTON_Y), _key(KEY_F)])
	_add("pause", [_jb(JOY_BUTTON_START), _key(KEY_ESCAPE), _key(KEY_P)])
	_add("select", [_jb(JOY_BUTTON_A), _key(KEY_ENTER)])
	_add("menu_back", [_jb(JOY_BUTTON_B), _key(KEY_ESCAPE), _key(KEY_BACKSPACE)])
	# Native Control focus activation: A presses the currently highlighted button.
	_add("ui_accept", [_jb(JOY_BUTTON_A), _key(KEY_ENTER), _key(KEY_SPACE)])
	_add("ui_left", [_jb(JOY_BUTTON_DPAD_LEFT), _key(KEY_LEFT), _ja(JOY_AXIS_LEFT_X, -1)])
	_add("ui_right", [_jb(JOY_BUTTON_DPAD_RIGHT), _key(KEY_RIGHT), _ja(JOY_AXIS_LEFT_X, 1)])
	_add("ui_up", [_jb(JOY_BUTTON_DPAD_UP), _key(KEY_UP), _ja(JOY_AXIS_LEFT_Y, -1)])
	_add("ui_down", [_jb(JOY_BUTTON_DPAD_DOWN), _key(KEY_DOWN), _ja(JOY_AXIS_LEFT_Y, 1)])
	_add("reroll", [_jb(JOY_BUTTON_Y), _key(KEY_R)])
	_add("consume", [_jb(JOY_BUTTON_X), _key(KEY_Q)])
	_add("consume_cycle", [_jb(JOY_BUTTON_DPAD_UP), _key(KEY_E)])
	_add("mute", [_key(KEY_M)])

func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if (e as InputEventMouseMotion).relative.length() > 4.0: aim_src = "mouse"
	elif e is InputEventMouseButton:
		aim_src = "mouse"
	elif e is InputEventJoypadButton and e.pressed:
		aim_src = "pad"; device = e.device
	elif e is InputEventJoypadMotion and absf(e.axis_value) > 0.3:
		aim_src = "pad"; device = e.device
	if e.is_action_pressed("mute"): muted = not muted; AudioServer.set_bus_mute(0, muted)

func _process(_dt: float) -> void:
	var cursor := Input.MOUSE_MODE_HIDDEN if (aim_src == "pad" or Run.aim_guide_level() >= 2) and get_tree().paused == false and _in_play() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != cursor: Input.mouse_mode = cursor

func _in_play() -> bool:
	var m := get_tree().current_scene
	return m != null and m.has_method("is_playing") and m.is_playing()

func _on_joy(id: int, connected: bool) -> void:
	if connected: device = id; aim_src = "pad"
	elif id == device:
		var pads := Input.get_connected_joypads(); device = pads[0] if pads.size() > 0 else -1
		if device < 0: aim_src = "mouse"
	pad_changed.emit(joy_status())

func joy_status() -> String:
	if device < 0: return ""
	var nm := Input.get_joy_name(device)
	return "🎮 %s" % nm

# ---- queries ----
func move_vec() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down", DZ_MOVE)
	return v

func aim_stick() -> Vector2:
	## raw right stick; zero inside the dead zone
	if device < 0: return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	return v if v.length() > DZ_AIM else Vector2.ZERO

func firing() -> bool: return Input.is_action_pressed("fire")
func firing_off() -> bool: return Input.is_action_pressed("fire_off")

func rumble(weak: float, strong: float, ms: float) -> void:
	if device < 0 or aim_src != "pad": return
	Input.start_joy_vibration(device, weak, strong, ms / 1000.0)

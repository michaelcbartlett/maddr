extends Control
## THE LAB: every run starts with a Laser Ray Pistol. Other ammo and frames are bought in the shop during a run;
## going further unlocks them as alternative STARTING parts (game/unlocks.gd), picked here. Name the weapon, see stats.

signal begin

var ammo_box: VBoxContainer
var frame_box: VBoxContainer
var name_edit: LineEdit
var stats_box: VBoxContainer
var begin_btn: Button
var intel_btn: Button
var intel_s: Control     # RIG THE DEPOT overlay (ui/intel_screen.gd)
var _panel: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := UiKit.screen(920); add_child(s[0]); var vb: VBoxContainer = s[1]; _panel = s[0]
	var top := HBoxContainer.new(); vb.add_child(top)
	var h := UiKit.label("⚗ DESIGN YOUR WEAPON", 22, UiKit.NEON); h.autowrap_mode = TextServer.AUTOWRAP_OFF; top.add_child(h)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	intel_btn = UiKit.button("🗂 Intel", open_intel, true); top.add_child(intel_btn)
	intel_btn.tooltip_text = "Rig the depot (Select/Back): assign banked Intel to modules so they appear more often in shop offers."
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12); vb.add_child(row)
	ammo_box = _column(row, "PRIMARY WEAPON"); frame_box = _column(row, "GUN FRAME")
	var right := VBoxContainer.new(); right.custom_minimum_size.x = 300; row.add_child(right)
	right.add_child(VillainPreview.new(3.0, Vector2(300, 200)))
	name_edit = LineEdit.new(); name_edit.max_length = 40; name_edit.focus_mode = Control.FOCUS_CLICK
	name_edit.text_changed.connect(func(_t): Run.custom_name = true)
	right.add_child(name_edit)
	stats_box = VBoxContainer.new(); right.add_child(stats_box)
	begin_btn = UiKit.button("Begin ▶", _on_begin); right.add_child(begin_btn)
	refresh()

func _column(parent: Control, title: String) -> VBoxContainer:
	var c := VBoxContainer.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(c)
	c.add_child(UiKit.label(title, 15, UiKit.NEON))
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true; c.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6); scroll.add_child(list)
	return list

func _card(o: Dictionary, sel: bool, cb: Callable, locked := false) -> Button:
	var b := Button.new(); b.custom_minimum_size = Vector2(0, 62); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ""; b.pressed.connect(cb)
	if locked:
		# locked starting part: shown so you know what to aim for, but not selectable
		b.disabled = true; b.focus_mode = Control.FOCUS_NONE; b.set_meta("locked", true)
		b.add_theme_stylebox_override("disabled", UiKit.box(Color("#101514"), UiKit.LINE, 2, 8))
	var border := UiKit.NEON if sel else UiKit.LINE
	b.add_theme_stylebox_override("normal", UiKit.box(Color("#1f2c18") if sel else Color("#141d1c"), border, 2, 8))
	b.add_theme_stylebox_override("hover", UiKit.box(Color("#1f2c18") if sel else Color("#182322"), UiKit.DIM if not sel else border, 2, 8))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color("#1f2c18"), UiKit.NEON, 2, 8))
	b.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), Color.WHITE, 3, 8))
	var vb := VBoxContainer.new(); vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); vb.offset_left = 10; vb.offset_top = 6; vb.offset_right = -10
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(vb)
	var n := UiKit.label(("🔒 " + o.name) if locked else o.name, 14, UiKit.DIM if locked else UiKit.TEXT); n.mouse_filter = Control.MOUSE_FILTER_IGNORE; vb.add_child(n)
	var d := UiKit.label(o.desc, 11, UiKit.DIM)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE; vb.add_child(d)
	b.focus_entered.connect(Sfx.play.bind("ui"))
	return b

func refresh(keep_focus := "") -> void:
	for c in ammo_box.get_children(): c.queue_free()
	for c in frame_box.get_children(): c.queue_free()
	var focus_me: Control = null
	var U = Run.unlocks
	for i in Run.AMMO.size():
		if Run.AMMO[i].get("no_start", false): continue   # shop-only weapons never appear as starting options
		var b := _card(Run.AMMO[i], Run.build.ammo == i, _pick.bind("ammo", i), not U.is_unlocked("ammo", Run.AMMO[i].id)); ammo_box.add_child(b)
		if keep_focus == "ammo%d" % i: focus_me = b
	for i in Run.FRAMES.size():
		var b := _card(Run.FRAMES[i], Run.build.frame == i, _pick.bind("frame", i), not U.is_unlocked("frame", Run.FRAMES[i].id)); frame_box.add_child(b)
		if Run.has_primary_melee(): b.disabled = true; b.tooltip_text = "Gun frames apply when a ranged primary is equipped."
		if keep_focus == "frame%d" % i: focus_me = b
	Run.recompute()
	if not Run.custom_name: name_edit.text = Run.weapon_name()
	intel_btn.text = "🗂 Intel %d" % Run.intel.unspent
	for c in stats_box.get_children(): c.queue_free()
	stats_box.add_child(UiKit.stats_grid(Run.stats_rows()))
	if focus_me: focus_me.call_deferred("grab_focus")

func _pick(key: String, i: int) -> void:
	if not Run.set_start(key, i): return
	Sfx.play("select", 1.0 + i * 0.18); refresh(key + str(i))

func focus_default() -> void: begin_btn.grab_focus()

func _on_begin() -> void:
	var n := name_edit.text.strip_edges()
	Run.build.name = n if n != "" else Run.weapon_name()
	begin.emit()

func open_intel() -> void:
	if intel_s == null:
		intel_s = preload("res://ui/intel_screen.gd").new(); add_child(intel_s)
		intel_s.closed.connect(func():
			_panel.visible = true; refresh(); intel_btn.call_deferred("grab_focus"))
	_panel.visible = false; intel_s.open()

func _unhandled_input(e: InputEvent) -> void:
	if not visible or (intel_s != null and intel_s.visible): return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_BACK: open_intel(); get_viewport().set_input_as_handled(); return
	if visible and e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START:
		_on_begin(); get_viewport().set_input_as_handled()

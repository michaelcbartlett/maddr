extends Control
## RIG THE DEPOT: spend persistent Villain Intel (game/intel.gd) on modules to raise their odds in shop offers.
## Opened as an overlay from the shop (Select/Back button or the Intel button) and the Lab (Intel button).
## Controller: D-pad up/down picks a module, right / A adds a point, left / X removes one, Y clears the module,
## B closes. Mouse: left-click adds, right-click removes. Points move freely: removing one returns it to the pool.

signal closed

var free_l: Label
var info_l: Label
var odds_l: Label
var list: VBoxContainer
var scroll: ScrollContainer
var clear_btn: Button
var done_btn: Button
var _rows := {}           # item id -> Button
var _focused_id := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var s := UiKit.screen(900); add_child(s[0]); var vb: VBoxContainer = s[1]
	var top := HBoxContainer.new(); vb.add_child(top)
	var h := UiKit.label("🗂 RIG THE DEPOT", 20, UiKit.NEON); h.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(h)
	free_l = UiKit.label("", 16, INTEL); free_l.autowrap_mode = TextServer.AUTOWRAP_OFF; top.add_child(free_l)
	vb.add_child(UiKit.label("Cops sometimes drop Intel dossiers. Banked Intel stays between runs: assign it to modules to make them show up more often in the Evil Supply Depot. Move points whenever you like.", 11, UiKit.DIM))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12); vb.add_child(row)
	scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(520, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus = true; row.add_child(scroll)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3); scroll.add_child(list)
	var side := VBoxContainer.new(); side.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(side)
	info_l = UiKit.label("", 12, UiKit.TEXT); side.add_child(info_l)
	odds_l = UiKit.label("", 12, UiKit.GOLD); side.add_child(odds_l)
	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; side.add_child(sp)
	side.add_child(UiKit.label("→ / A add · ← / X remove\nY clear module · B back\nMouse: click add, right-click remove", 10, UiKit.DIM))
	var btns := HBoxContainer.new(); vb.add_child(btns)
	clear_btn = UiKit.button("Refund All", _on_clear_all, true); btns.add_child(clear_btn)
	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btns.add_child(sp2)
	done_btn = UiKit.button("Done", close); btns.add_child(done_btn)

const INTEL := Color("#ff6ad5")

func open() -> void:
	visible = true
	_build()
	var first: Button = _rows.get(_focused_id, null)
	if first == null and list.get_child_count() > 0: first = list.get_child(0)
	_focus_later(first if first else done_btn)

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

## Modules that can be rigged: every unlocked shop module, cheapest tier first.
func rig_ids() -> Array:
	var ids: Array = []
	for it in Run.ITEMS:
		if Run.unlocks.is_unlocked("item", it.id): ids.append(it.id)
	ids.sort_custom(func(a, b):
		var ta := int(Run.ITEM[a].t); var tb := int(Run.ITEM[b].t)
		return ta < tb or (ta == tb and String(Run.ITEM[a].name) < String(Run.ITEM[b].name)))
	# assigned modules that are no longer unlocked/listed still show, so their points can be moved back
	for id in Run.intel.alloc:
		if not ids.has(id) and Run.ITEM.has(id): ids.append(id)
	return ids

func _build() -> void:
	for c in list.get_children(): list.remove_child(c); c.queue_free()
	_rows = {}
	for id in rig_ids():
		var b := Button.new(); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", UiKit.box(Color("#141d1c"), UiKit.LINE, 2, 5))
		b.add_theme_stylebox_override("hover", UiKit.box(Color("#1c2827"), UiKit.DIM, 2, 5))
		b.add_theme_stylebox_override("focus", UiKit.box(Color("#1c2827"), Color.WHITE, 2, 5))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color("#2a1a28"), INTEL, 2, 5))
		b.pressed.connect(_adjust.bind(id, 1))
		b.gui_input.connect(_row_input.bind(id))
		b.focus_entered.connect(_on_focus.bind(id))
		b.focus_entered.connect(Sfx.play.bind("ui"))
		b.mouse_entered.connect(_show_info.bind(id))
		list.add_child(b); _rows[id] = b
	_refresh_rows()

func _row_text(id: String) -> String:
	var it: Dictionary = Run.ITEM[id]
	var n: int = Run.intel.points(id); var cap: int = Run.intel.max_per_item()
	var pips := "◆".repeat(n) + "◇".repeat(maxi(0, cap - n))
	return "%s %-24s %s  ×%.1f" % [it.ic, String(it.name).left(24), pips, Run.intel.weight(id)]

func _refresh_rows() -> void:
	for id in _rows:
		var b: Button = _rows[id]
		b.text = _row_text(id)
		var col: Color = INTEL if Run.intel.points(id) > 0 else UiKit.TIER[int(Run.ITEM[id].t)]
		b.add_theme_color_override("font_color", col); b.add_theme_color_override("font_hover_color", col)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
	free_l.text = "INTEL %d free · %d total" % [Run.intel.unspent, Run.intel.total()]
	clear_btn.disabled = Run.intel.alloc.is_empty()
	if _focused_id != "": _show_info(_focused_id)
	elif _rows.is_empty():
		info_l.text = "No modules unlocked yet."; odds_l.text = ""

func _on_focus(id: String) -> void:
	_focused_id = id; _show_info(id)

## Tier pool the module competes in when the shop rolls its tier (unlocked modules of the same tier).
func _tier_pool(id: String) -> Array:
	var t := int(Run.ITEM[id].t)
	return Run.ITEMS.filter(func(it): return int(it.t) == t and Run.unlocks.is_unlocked("item", it.id))

func _show_info(id: String) -> void:
	var it: Dictionary = Run.ITEM[id]
	var tier_name: String = Run.RULES.shop.tier_names[int(it.t)]
	info_l.text = "%s %s · %s\n%s" % [it.ic, it.name, tier_name, it.desc]
	var pool := _tier_pool(id)
	var share: float = Run.pick_share(pool, id)
	var base: float = 1.0 / pool.size() if pool.has(it) and pool.size() > 0 else 0.0
	var n: int = Run.intel.points(id)
	odds_l.text = "%d / %d points · weight ×%.1f\n%.1f%% of %s slots (base %.1f%%)" % [n, Run.intel.max_per_item(), Run.intel.weight(id), share * 100.0, tier_name, base * 100.0]

## +1 / −1 point on a module. Feedback on refusals (no free points, cap reached, nothing to remove).
func _adjust(id: String, delta: int) -> void:
	if Run.intel.assign(id, delta):
		Sfx.play("select" if delta > 0 else "reroll")
		_refresh_rows()
	else:
		Sfx.play("ui")
		if delta > 0:
			odds_l.text = ("Max %d points per module." % Run.intel.max_per_item()) if Run.intel.points(id) >= Run.intel.max_per_item() else "No free Intel. Remove points from another module, or collect more dossiers."
		else: odds_l.text = "No points on this module."

func _row_input(e: InputEvent, id: String) -> void:
	if e.is_action_pressed("ui_right"): _adjust(id, 1); accept_event()
	elif e.is_action_pressed("ui_left"): _adjust(id, -1); accept_event()
	elif e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_X: _adjust(id, -1); accept_event()
	elif e.is_action_pressed("reroll"):
		if Run.intel.clear(id): Sfx.play("reroll"); _refresh_rows()
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT: _adjust(id, -1); accept_event()

func _on_clear_all() -> void:
	if Run.intel.clear_all(): _refresh_rows()

func _focus_later(c: Control) -> void:
	var f := func():
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree(): c.grab_focus()
	f.call_deferred()

func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if e.is_action_pressed("menu_back") or (e is InputEventJoypadButton and e.pressed and e.button_index in [JOY_BUTTON_BACK, JOY_BUTTON_START]):
		close(); get_viewport().set_input_as_handled()
	elif e.is_action_pressed("reroll") or (e is InputEventJoypadButton and e.pressed):
		get_viewport().set_input_as_handled()   # Y / other pad buttons must not reach the screen underneath

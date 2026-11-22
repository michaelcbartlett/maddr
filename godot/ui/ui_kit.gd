extends RefCounted
class_name UiKit
## Shared look for the menus (ported from the index.html CSS): fonts, colours, theme, small builders.

const BG := Color("#141c1d")
const PANEL := Color("#1b2526")
const LINE := Color("#3a4d4e")
const NEON := Color("#b4ff3c")
const TEXT := Color("#dfe8e0")
const DIM := Color("#8a9b94")
const BAD := Color("#ff5a5a")
const GOLD := Color("#ffd23c")
const TIER := [Color("#b8c4c0"), Color("#b8c4c0"), Color("#4fb4ff"), Color("#c77bff"), Color("#ffc83c")]
const DESIGN := Vector2(960, 540)     # logical UI size; scaled to the real viewport

static var _mono: Font
static var _theme: Theme

static func mono() -> Font:
	if _mono: return _mono
	# Bundled (not system) fonts so the web build, which can't see the player's OS fonts, matches desktop.
	var emoji: FontFile = load("res://ui/fonts/NotoColorEmoji.ttf")
	var f: FontFile = (load("res://ui/fonts/JetBrainsMono-Bold.ttf") as FontFile).duplicate()
	f.fallbacks = [emoji]; f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	# JetBrains Mono runs wider and taller than the Consolas the layouts were tuned for; tighten to match.
	var v := FontVariation.new(); v.base_font = f
	v.spacing_glyph = -1; v.spacing_top = -1; v.spacing_bottom = -1
	_mono = v
	return v

static func box(bg: Color, border: Color, w := 3, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border
	s.set_border_width_all(w); s.set_content_margin_all(pad)
	return s

static func theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new(); t.default_font = mono(); t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 3, 14))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 3, 14))
	# buttons (neon)
	t.set_stylebox("normal", "Button", box(Color("#22301a"), NEON, 3, 8))
	t.set_stylebox("hover", "Button", box(Color("#2e4220"), NEON, 3, 8))
	t.set_stylebox("pressed", "Button", box(NEON, NEON, 3, 8))
	t.set_stylebox("disabled", "Button", box(Color("#1a2216"), Color(NEON, 0.35), 3, 8))
	var fs := box(Color("#2e4220"), Color.WHITE, 3, 8); t.set_stylebox("focus", "Button", fs)
	t.set_color("font_color", "Button", NEON); t.set_color("font_hover_color", "Button", NEON)
	t.set_color("font_pressed_color", "Button", Color("#111111")); t.set_color("font_disabled_color", "Button", Color(NEON, 0.35))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 16)
	t.set_stylebox("normal", "LineEdit", box(Color("#0f1616"), LINE, 2, 8)); t.set_stylebox("focus", "LineEdit", box(Color("#0f1616"), NEON, 2, 8))
	t.set_color("font_color", "LineEdit", NEON); t.set_font_size("font_size", "LineEdit", 15)
	_theme = t
	return t

static func label(txt: String, size := 14, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new(); l.text = txt; l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func title(txt: String, size := 56, col := NEON) -> Label:
	var l := label(txt, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_shadow_color", Color("#2d4a12")); l.add_theme_constant_override("shadow_offset_x", 4); l.add_theme_constant_override("shadow_offset_y", 4)
	return l

static func button(txt: String, cb: Callable, secondary := false) -> Button:
	var b := Button.new(); b.text = txt; b.pressed.connect(cb)
	b.pressed.connect(Sfx.play.bind("select"))
	if secondary:
		b.add_theme_stylebox_override("normal", box(Color("#223031"), DIM, 3, 8)); b.add_theme_color_override("font_color", TEXT)
		b.add_theme_stylebox_override("hover", box(Color("#2c3c3d"), DIM, 3, 8)); b.add_theme_color_override("font_hover_color", TEXT)
	b.focus_entered.connect(Sfx.play.bind("ui"))
	return b

## a full-screen dimmed screen with a centred panel; returns [screen, vbox inside the panel]
static func screen(max_w := 760.0) -> Array:
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new(); dim.color = Color(0.03, 0.05, 0.05, 0.9); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(cc)
	var pc := PanelContainer.new(); pc.custom_minimum_size.x = max_w; cc.add_child(pc)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 10); pc.add_child(vb)
	return [root, vb]

static func stats_grid(rows: Array) -> GridContainer:
	var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 16); g.add_theme_constant_override("v_separation", 1)
	for r in rows:
		var a := label(r[0], 12, TEXT); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL; a.autowrap_mode = TextServer.AUTOWRAP_OFF
		var b := label(r[1], 12, Color("#ffb84a") if r[2] else NEON, HORIZONTAL_ALIGNMENT_RIGHT); b.autowrap_mode = TextServer.AUTOWRAP_OFF
		g.add_child(a); g.add_child(b)
	return g

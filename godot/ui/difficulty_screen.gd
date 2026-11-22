extends Control
## CHOOSE YOUR DIFFICULTY after the weapon design screen (like Brotato's danger levels).
## Five cards, Petty Crook to Arch-Nemesis. The pick is constant for the run: enemy HP, damage,
## spawn rate and speed go up; payout per cop goes down (Run.TIER). Controller: stick / d-pad + A.

signal chosen(level: int)

const COLORS := [Color("#b4ff3c"), Color("#7ad0ff"), Color("#ffd23c"), Color("#ff8a3a"), Color("#ff5a5a")]
var detail: Label
var first_button: Button
var buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = UiKit.screen(940); add_child(panel[0]); var column: VBoxContainer = panel[1]
	column.add_child(UiKit.title("CHOOSE YOUR DIFFICULTY", 28))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); row.custom_minimum_size.y = 300; column.add_child(row)
	for level in range(1, 6):
		var card := PanelContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UiKit.box(Color("#172126"), COLORS[level - 1], 2, 10)); row.add_child(card)
		var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8); card.add_child(col)
		# ⭐ is in the bundled emoji font (★/☆ aren't); empty slots are the same star, faded
		var stars := HBoxContainer.new(); stars.alignment = BoxContainer.ALIGNMENT_CENTER; stars.add_theme_constant_override("separation", 0); col.add_child(stars)
		var lit := UiKit.label("⭐".repeat(level), 16, UiKit.GOLD); lit.autowrap_mode = TextServer.AUTOWRAP_OFF; stars.add_child(lit)
		if level < 5:
			var unlit := UiKit.label("⭐".repeat(5 - level), 16, UiKit.GOLD); unlit.autowrap_mode = TextServer.AUTOWRAP_OFF; unlit.modulate.a = 0.22; stars.add_child(unlit)
		col.add_child(UiKit.label(Run.DIFFICULTY[level - 1], 15, COLORS[level - 1], HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UiKit.label(Run.DIFFICULTY_FLAVOR[level - 1], 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var info := UiKit.label("Cop HP ×%.2f\nCop damage ×%.2f\nSpawns ×%.2f\nCop speed ×%.2f\nPayout ×%.2f" % [Run.tier("hp", level), Run.tier("dmg", level), Run.tier("spawn", level), Run.tier("speed", level), Run.payout_for(level)], 12, UiKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
		info.size_flags_vertical = Control.SIZE_EXPAND_FILL; col.add_child(info)
		var b := UiKit.button("PICK", _pick.bind(level)); col.add_child(b); buttons.append(b)
		b.focus_entered.connect(_describe.bind(level))
		if level == 1: first_button = b
	detail = UiKit.label("", 13, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER); column.add_child(detail)

func _describe(level: int) -> void:
	detail.text = "%s · %s" % ["⭐".repeat(level), Run.DIFFICULTY[level - 1]]

func _pick(level: int) -> void:
	if Run.set_difficulty(level): chosen.emit(level)

func refresh() -> void:
	for i in buttons.size():
		var unlocked: bool = Run.unlocks.difficulty_available(i + 1)
		buttons[i].disabled = not unlocked
		buttons[i].text = "PICK" if unlocked else "🔒"
		buttons[i].tooltip_text = ""
	_describe(Run.difficulty)

func focus_default() -> void:
	buttons[clampi(Run.difficulty - 1, 0, 4)].grab_focus()

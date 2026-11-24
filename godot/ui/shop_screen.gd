extends Control
## EVIL SUPPLY DEPOT between waves (index.html #sShop): 4 offers by tier weight, reroll (Y), next wave (Start).

signal next_wave

var title_l: Label
var scrap_l: Label
var name_l: Label
var stats_box: VBoxContainer
var offers_box: HBoxContainer
var owned_box: HFlowContainer
var reroll_btn: Button
var next_btn: Button
var sell_l: Label
var consumables_box: HFlowContainer
var consumable_l: Label
var secondary_l: Label
var swap_btn: Button   # ⇄ trade the main-hand and Bionic Arm melee weapons
var arm_btn: Button    # 🦾 cycle which owned arm item is mounted
const SUPPLY_DESCS := {"disguise":"Disguise · Lose pursuit for 4s. Firing reveals you.", "grenade":"Grenade · Throw along your aim; explodes after a short fuse.",
	"shrink_pill":"Shrinking Pill · 55% size and hitbox for 10s. Replaces enlargement.",
	"enlarge_pill":"Enlargement Pill · 160% size for 10s. Walk over small ground enemies to stomp them.",
	"tesla_coil":"Tesla Coil · Place for 15s. Stay within 240 units: random lightning pulses shock enemies between you and the coil. Walls block the link."}
var intel_btn: Button
var intel_s: Control     # RIG THE DEPOT overlay (ui/intel_screen.gd): Select/Back or the Intel button
var _panel: Control
var _confirm_id := ""   # owned item waiting for a second press to sell ("part:ammo"/"part:frame" = the main gun's parts)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var s := UiKit.screen(940); add_child(s[0]); var vb: VBoxContainer = s[1]; _panel = s[0]
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14); vb.add_child(row)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 260; row.add_child(left)
	left.add_child(VillainPreview.new(2.5, Vector2(260, 180)))
	name_l = UiKit.label("", 13, UiKit.NEON); left.add_child(name_l)
	secondary_l = UiKit.label("", 10, UiKit.DIM); left.add_child(secondary_l)
	secondary_l.tooltip_text = "Choose a primary knife, sword or whip in the Lab: sweep the right stick or mouse to attack. Bionic Arm opens a separate automatic secondary melee slot for dual wielding, or a rear gun and utilities. Melee upgrades apply to both hands. Triple Seeker Rack also needs Viper's blueprint."
	var loadout := HBoxContainer.new(); loadout.add_theme_constant_override("separation", 6); left.add_child(loadout)
	swap_btn = UiKit.button("⇄ Swap hands", _on_swap_hands, true); swap_btn.add_theme_font_size_override("font_size", 11); loadout.add_child(swap_btn)
	swap_btn.tooltip_text = "Trade weapons between your main hand (manual sweep) and the Bionic Arm (automatic swing)."
	arm_btn = UiKit.button("🦾 Arm ▸", _on_cycle_arm, true); arm_btn.add_theme_font_size_override("font_size", 11); loadout.add_child(arm_btn)
	arm_btn.tooltip_text = "Choose which owned arm equipment is mounted on the Bionic Arm."
	var stats_scroll := ScrollContainer.new(); stats_scroll.custom_minimum_size.y = 178
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(stats_scroll)
	stats_box = VBoxContainer.new(); stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stats_scroll.add_child(stats_box)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right.add_theme_constant_override("separation", 6); row.add_child(right)
	var top := HBoxContainer.new(); right.add_child(top)
	title_l = UiKit.label("EVIL SUPPLY DEPOT", 18, UiKit.NEON); title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title_l)
	scrap_l = UiKit.label("⚙ 0", 20, UiKit.GOLD); scrap_l.autowrap_mode = TextServer.AUTOWRAP_OFF; top.add_child(scrap_l)
	offers_box = HBoxContainer.new(); offers_box.add_theme_constant_override("separation", 8); right.add_child(offers_box)
	var btns := HBoxContainer.new(); right.add_child(btns)
	reroll_btn = UiKit.button("Reroll", _on_reroll, true); btns.add_child(reroll_btn)
	intel_btn = UiKit.button("🗂 Intel", open_intel, true); btns.add_child(intel_btn)
	intel_btn.tooltip_text = "Rig the depot (Select/Back): assign banked Intel to modules so they appear more often. Takes effect on the next reroll or shop."
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btns.add_child(sp)
	next_btn = UiKit.button("Next Wave ▶", func(): next_wave.emit()); btns.add_child(next_btn)
	right.add_child(UiKit.label("CONSUMABLES · carry 3 of each", 11, UiKit.NEON))
	consumables_box = HFlowContainer.new(); consumables_box.add_theme_constant_override("h_separation", 6); right.add_child(consumables_box)
	consumable_l = UiKit.label("X / Q use · D-UP / E switch consumable",10,UiKit.DIM); right.add_child(consumable_l)
	var owned_head := HBoxContainer.new(); owned_head.add_theme_constant_override("separation", 12); right.add_child(owned_head)
	var owned_title := UiKit.label("INSTALLED MODULES", 14, UiKit.NEON); owned_title.autowrap_mode = TextServer.AUTOWRAP_OFF; owned_head.add_child(owned_title)
	# sell hint shares the heading row so hovering a module never shifts the layout
	sell_l = UiKit.label("", 11, UiKit.DIM); sell_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_l.autowrap_mode = TextServer.AUTOWRAP_OFF; sell_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; owned_head.add_child(sell_l)
	var owned_scroll := ScrollContainer.new(); owned_scroll.custom_minimum_size.y = 96
	owned_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(owned_scroll)
	owned_box = HFlowContainer.new(); owned_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned_box.add_theme_constant_override("h_separation", 5); owned_box.add_theme_constant_override("v_separation", 5); owned_scroll.add_child(owned_box)

func refresh(focus_idx := -1) -> void:
	Run.recompute()
	title_l.text = "EVIL SUPPLY DEPOT · %d" % Run.wave
	scrap_l.text = "⚙ %d" % Run.scrap
	name_l.text = Run.display_name()
	secondary_l.text = "SECONDARY · Buy a Bionic Arm" if Run.CNT.get("bionic_arm",0)==0 else "SECONDARY · Arm equipment in shop pool"
	if Run.build.off != null:
		var kind: String = Run.build.off.get("kind","gun")
		secondary_l.text = "SECONDARY · " + ("Rear weapon" if kind=="gun" else Run.arm_name(kind))
	if Run.has_primary_melee() and Run.build.off != null:
		var arm_kind: String = Run.arm_off().get("kind", "gun")
		secondary_l.text = "MAIN · %s   ARM · %s" % [Run.arm_name(Run.primary_kind()), "Rear weapon" if arm_kind == "gun" else Run.arm_name(arm_kind)]
	swap_btn.visible = Run.can_swap_hands()
	var arms := Run.arm_options()
	arm_btn.visible = arms.size() > 1
	if arm_btn.visible:
		var nxt: String = arms[(arms.find(Run.mounted_arm_id()) + 1) % arms.size()]
		arm_btn.text = "🦾 Mount %s" % Run.ITEM[nxt].name
	consumable_l.text = "X / Q use · D-UP / E switch consumable"
	for c in stats_box.get_children(): stats_box.remove_child(c); c.queue_free()
	stats_box.add_child(UiKit.stats_grid(Run.stats_rows()))
	for c in offers_box.get_children(): offers_box.remove_child(c); c.queue_free()   # detach now: focus_default() must never pick a card that is about to be freed
	var focus_me: Control = null
	for i in Run.offers.size():
		var card := _offer(i); offers_box.add_child(card[0])
		if i == focus_idx: focus_me = card[1]
	intel_btn.text = "🗂 Intel %d" % Run.intel.unspent
	reroll_btn.text = "Reroll ⚙ %d" % Run.reroll_cost; reroll_btn.disabled = Run.scrap < Run.reroll_cost
	for c in consumables_box.get_children(): consumables_box.remove_child(c); c.queue_free()
	if Run.consumables_owned.is_empty():
		var hint := UiKit.label("Supply kits show up in the offers above · buy one to unlock refills", 10, UiKit.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF; consumables_box.add_child(hint)
	for id in Run.CONSUMABLE_IDS:
		if not Run.owns_consumable(id): continue
		var price: int = Run.wave_price(Run.CONSUMABLE_PRICES[id])
		var count: int = Run.consumable_charges[id]
		var text := "%s %d/3 · ⚙%d" % [Run.CONSUMABLE_NAMES[id],count,price]
		var button := UiKit.button(text, func():
			if Run.buy_consumable(id): refresh(); next_btn.call_deferred("grab_focus")
		, true)
		button.add_theme_font_size_override("font_size",10)
		button.tooltip_text = SUPPLY_DESCS[id]
		button.disabled = count >= 3 or Run.scrap < price
		button.focus_entered.connect(func(): consumable_l.text = SUPPLY_DESCS[id])
		button.mouse_entered.connect(func(): consumable_l.text = SUPPLY_DESCS[id])
		consumables_box.add_child(button)
	for c in owned_box.get_children(): owned_box.remove_child(c); c.queue_free()   # detach now so a stale button can never be pressed
	for id in ["part:ammo", "part:frame"] + Run.CNT.keys():
		var b := _sell_chip(id)
		if focus_idx < 0 and id == _confirm_id: focus_me = b
	if not _owned(_confirm_id): _confirm_id = ""
	if focus_me and not focus_me.disabled: _focus_later(focus_me)
	elif focus_idx >= 0: next_btn.call_deferred("grab_focus")

## Deferred focus that skips a button a later refresh() already removed (two presses in one frame).
func _focus_later(c: Control) -> void:
	var f := func():
		if is_instance_valid(c) and c.is_inside_tree(): c.grab_focus()
	f.call_deferred()

func _chip(txt: String, col: Color, tip := "") -> void:
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", UiKit.box(Color("#141d1c"), UiKit.LINE, 2, 4)); p.tooltip_text = tip
	var l := UiKit.label(txt, 11, col); l.autowrap_mode = TextServer.AUTOWRAP_OFF; p.add_child(l); owned_box.add_child(p)

func _owned(id: String) -> bool: return id.begins_with("part:") or Run.CNT.has(id)

## Display info for an owned thing: a module id, or "part:ammo" / "part:frame" for the main gun's current parts.
func _info(id: String) -> Dictionary:
	if id.begins_with("part:"):
		var part := id.substr(5); var i: int = Run.build[part]
		var d: Dictionary = Run.AMMO[i] if part == "ammo" else Run.FRAMES[i]
		var bought := Run.sell_block_reason(id) == ""
		return {"name": d.name, "ic": "💥" if part == "ammo" else "🔧", "desc": d.desc, "n": 1,
			"col": UiKit.TIER[int(Run.part_def(part, i).get("t", 1))] if bought else UiKit.TEXT}
	var it: Dictionary = Run.ITEM[id]
	return {"name": it.name, "ic": it.ic, "desc": it.desc, "n": int(Run.CNT[id]), "col": UiKit.TIER[int(it.t)]}

func _chip_text(id: String) -> String:
	var f := _info(id)
	return "%s %s%s" % [f.ic, f.name, (" ×%d" % f.n) if f.n > 1 else ""]

## An owned module (or gun part) as a focusable button: first press arms the sale, second press sells one copy.
func _sell_chip(id: String) -> Button:
	var it := _info(id)
	var nm := _chip_text(id)
	var b := Button.new(); b.tooltip_text = it.desc
	b.text = ("SELL %s for ⚙ %d?" % [it.name, Run.sell_price(id)]) if id == _confirm_id else nm
	var col: Color = UiKit.BAD if id == _confirm_id else it.col
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", col); b.add_theme_color_override("font_hover_color", col)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.box(Color("#141d1c"), UiKit.BAD if id == _confirm_id else UiKit.LINE, 2, 4))
	b.add_theme_stylebox_override("hover", UiKit.box(Color("#1c2827"), UiKit.DIM, 2, 4))
	b.add_theme_stylebox_override("focus", UiKit.box(Color("#1c2827"), Color.WHITE, 2, 4))
	b.add_theme_stylebox_override("pressed", UiKit.box(Color("#2a1616"), UiKit.BAD, 2, 4))
	b.pressed.connect(_on_sell.bind(id))
	b.focus_entered.connect(_on_chip_focus.bind(id))
	b.focus_entered.connect(Sfx.play.bind("ui"))
	owned_box.add_child(b)
	return b

func _on_chip_focus(id: String) -> void:
	if _confirm_id != "" and id != _confirm_id:
		# moving to another module cancels the pending sale
		for c in owned_box.get_children():
			if c is Button and c.text.begins_with("SELL "):
				var old: String = _confirm_id
				c.text = _chip_text(old)
				c.add_theme_color_override("font_color", _info(old).col)
				c.add_theme_stylebox_override("normal", UiKit.box(Color("#141d1c"), UiKit.LINE, 2, 4))
		_confirm_id = ""
	if id == _confirm_id: return
	var why := Run.sell_block_reason(id)
	var what: String = _info(id).name
	sell_l.text = why if why != "" else "%s · ⚙ %d" % [what, Run.sell_price(id)]
	sell_l.add_theme_color_override("font_color", UiKit.BAD if why != "" else UiKit.DIM)

func _on_sell(id: String) -> void:
	var why := Run.sell_block_reason(id)
	if why != "":
		sell_l.text = why; sell_l.add_theme_color_override("font_color", UiKit.BAD); Sfx.play("ui"); return
	if _confirm_id != id:
		_confirm_id = id; refresh()
		sell_l.text = ""
		sell_l.add_theme_color_override("font_color", UiKit.GOLD)
		return
	var nm: String = _info(id).name
	var got := Run.sell(id); _confirm_id = ""
	Sfx.play("reroll")
	refresh()
	sell_l.text = "Sold %s for ⚙ %d." % [nm, got]; sell_l.add_theme_color_override("font_color", UiKit.NEON)
	# keep the controller on the owned list
	var target: Control = null
	for c in owned_box.get_children():
		if c is Button and Run.CNT.has(id) and c.text.contains(Run.ITEM[id].name): target = c
		elif c is Button and id.begins_with("part:") and c.text == _chip_text(id): target = c
	if target == null:
		for c in owned_box.get_children():
			if c is Button: target = c
	if target: _focus_later(target)
	else: call_deferred("focus_default")

func _offer(i: int) -> Array:
	var o: Dictionary = Run.offers[i]; var it: Dictionary = o.it; var tc: Color = UiKit.TIER[int(it.t)]
	var p := PanelContainer.new(); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL; p.custom_minimum_size = Vector2(0, 236)
	p.add_theme_stylebox_override("panel", UiKit.box(Color("#141d1c"), tc, 3, 8))
	if o.sold: p.modulate.a = 0.25
	var vb := VBoxContainer.new(); p.add_child(vb)
	vb.add_child(UiKit.label(it.ic, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var name_text: String = it.name
	var description: String = it.desc
	if it.id == "telescope" and Run.aim_guide_level() >= 1:
		name_text += " II"
		description = "Crosshair at max range. Mouse aim: follows the cursor."
	vb.add_child(UiKit.label(name_text, 13, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UiKit.label(Run.RULES.shop.tier_names[int(it.t)], 10, tc, HORIZONTAL_ALIGNMENT_CENTER))
	var d := UiKit.label(description, 11, UiKit.TEXT); d.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(d)
	var back := 0
	if it.has("swap"):
		# ammo/frame swap: a bought part being replaced is traded in towards the price
		back = Run.part_trade_in(it.swap)
		var cur: String = (Run.AMMO[Run.build.ammo] if it.swap == "ammo" else Run.FRAMES[Run.build.frame]).name
		vb.add_child(UiKit.label(("Trade in %s: −⚙ %d" % [cur, back]) if back > 0 else "Replaces %s" % cur, 10, UiKit.GOLD))
		if not Run.has_primary_melee() and Run.ammo_id() != "hook" and not (it.swap == "ammo" and (Run.AMMO[int(it.idx)].id == "hook" or Run.AMMO[int(it.idx)].has("melee"))):
			var dps := Run.part_dps_change(it)
			var pellets: String = " (all pellets hit)" if it.swap == "frame" and int(Run.FRAMES[int(it.idx)].get("add", {}).get("shots", 0)) > 0 else ""
			vb.add_child(UiKit.label("Gun DPS %+d%%%s" % [roundi(dps * 100.0), pellets], 10, Color("#7dff8a") if dps >= 0.0 else Color("#ff7a7a")))
	var short: int = o.price - back - Run.scrap   # scrap still missing; offers are only ever disabled for this (or SOLD)
	if not o.sold and short > 0:
		var need := UiKit.label("Need ⚙ %d more" % short, 10, UiKit.BAD, HORIZONTAL_ALIGNMENT_CENTER); need.name = "NeedScrap"; vb.add_child(need)
	var b := UiKit.button("SOLD" if o.sold else ("⚙ %d" % (o.price - back)), _on_buy.bind(i))
	b.disabled = o.sold or short > 0
	vb.add_child(b)
	return [p, b]

func _on_buy(i: int) -> void:
	_confirm_id = ""
	if Run.buy(i):
		Sfx.play("buy1"); get_tree().create_timer(0.07).timeout.connect(Sfx.play.bind("buy2"))
		refresh(i)
		var it: Dictionary = Run.offers[i].it
		if (it.has("arm") or (it.has("swap") and it.swap == "ammo")) and Run.can_swap_hands():
			# offer the hand choice for the new weapon: A on the highlighted button swaps it into the other hand
			secondary_l.text = "%s is on the Bionic Arm · A: swap it to your main hand" % Run.arm_name(Run.arm_off().kind) if it.has("arm") else "New main-hand weapon · A: swap it onto the Bionic Arm"
			_focus_later(swap_btn)

func _on_swap_hands() -> void:
	if not Run.swap_hands(): return
	refresh(); _focus_later(swap_btn)

func _on_cycle_arm() -> void:
	var arms := Run.arm_options()
	if arms.size() < 2: return
	Run.mount_arm(arms[(arms.find(Run.mounted_arm_id()) + 1) % arms.size()])
	refresh(); _focus_later(arm_btn if arm_btn.visible else next_btn)

func _on_reroll() -> void:
	if not Run.reroll(): return
	Sfx.play("reroll"); refresh()
	if not reroll_btn.disabled: reroll_btn.call_deferred("grab_focus")
	else: call_deferred("focus_default")

func focus_default() -> void:
	for c in offers_box.get_children():
		var b: Button = c.get_child(0).get_child(c.get_child(0).get_child_count() - 1)
		if not b.disabled: b.grab_focus(); return
	next_btn.grab_focus()

func open_intel() -> void:
	if intel_s == null:
		intel_s = preload("res://ui/intel_screen.gd").new(); add_child(intel_s)
		intel_s.closed.connect(func():
			_panel.visible = true; refresh(); _focus_later(intel_btn))
	_panel.visible = false; intel_s.open()

func _unhandled_input(e: InputEvent) -> void:
	if not visible or (intel_s != null and intel_s.visible): return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_BACK: open_intel(); get_viewport().set_input_as_handled(); return
	if e.is_action_pressed("reroll") and not (get_viewport().gui_get_focus_owner() is LineEdit): _on_reroll(); get_viewport().set_input_as_handled()
	elif e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START: next_wave.emit(); get_viewport().set_input_as_handled()

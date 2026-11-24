extends Control
## A simple 2x2 native save picker, shared by keyboard, mouse and controller.
signal chosen(slot: int)
signal back
var buttons: Array[Button]=[]
var message: Label
var back_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=UiKit.screen(760);add_child(panel[0]);var column: VBoxContainer=panel[1]
	column.add_child(UiKit.title("SELECT GAME",34))
	column.add_child(UiKit.label("Choose a game to begin a mission.",14,UiKit.DIM,HORIZONTAL_ALIGNMENT_CENTER))
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",14);column.add_child(grid)
	for slot in range(1,5):
		var button:=UiKit.button("GAME %d"%slot,func(): chosen.emit(slot))
		button.custom_minimum_size=Vector2(350,100);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(button);buttons.append(button)
	message=UiKit.label("",13,UiKit.BAD,HORIZONTAL_ALIGNMENT_CENTER);column.add_child(message)
	back_button=UiKit.button("Back",func(): back.emit(),true);back_button.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;column.add_child(back_button)

func refresh() -> void:
	message.text=""
	for index in buttons.size():
		var data: Dictionary=Run.save_slots.summary(index+1);var button:=buttons[index]
		button.disabled=data.has("error")
		if button.disabled:
			button.text="GAME %d\nSave unavailable"%(index+1);button.tooltip_text=data.error
		elif not data.used:
			button.text="GAME %d\nNew game"%(index+1);button.tooltip_text="Start a fresh game in this empty slot."
		else:
			button.text="GAME %d\n%d missions started · Best wave %d"%[index+1,int(data.runs_started),int(data.best_wave)]
			button.tooltip_text="Start a mission with this game's saved unlocks and Intel."

func focus_default() -> void:
	var index:=maxi(0,Run.save_slots.active_slot-1)
	if not buttons[index].disabled:buttons[index].grab_focus();return
	for button in buttons:
		if not button.disabled:button.grab_focus();return
	back_button.grab_focus()

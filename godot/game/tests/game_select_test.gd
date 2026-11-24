extends SceneTree
## Real menu events and isolated save round-trips, including old-save import.
const Slots=preload("res://game/save_slots.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+label)
func _write(path: String,data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close()
func _tap(button: JoyButton) -> void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new();event.button_index=button;event.pressed=down;Input.parse_input_event(event)
		await process_frame
func _run() -> void:
	var root_path:="user://game_select_selftest_%d"%Time.get_ticks_usec()
	var saves=Slots.new(true);saves.persist=true;saves.directory=root_path.path_join("games");saves.legacy_directory=root_path.path_join("legacy")
	for slot in range(1,5):_check(not saves.summary(slot).used,"four slots begin empty")
	_check(not saves.activate(0) and not saves.activate(5),"only slots one through four can be activated")
	var old_unlocks={"version":1,"best_wave":8,"unlocked":["ammo:bullet"],"highest_difficulty":2}
	var old_intel={"version":1,"unspent":14,"alloc":{"fins":2}}
	_write(saves.legacy_directory.path_join("unlocks.json"),old_unlocks);_write(saves.legacy_directory.path_join("intel.json"),old_intel)
	_check(saves.summary(1).legacy and saves.summary(1).best_wave==8,"Game 1 discovers the existing single-profile save")
	_check(not saves.summary(2).used,"the old save does not leak into Game 2")
	_check(saves.activate(1),"Game 1 can import the previous saves")
	for file in ["unlocks.json","intel.json"]:
		_check(FileAccess.get_file_as_string(saves.slot_path(1,file))==FileAccess.get_file_as_string(saves.legacy_directory.path_join(file)),"import copies %s while retaining its original"%file)
	saves.note_run();saves.note_wave(9);saves.note_result(false,true)
	var reload=Slots.new(true);reload.persist=true;reload.directory=saves.directory;reload.legacy_directory=saves.legacy_directory
	var info: Dictionary=reload.summary(1)
	_check(info.runs_started==1 and info.best_wave==9 and info.deaths==1,"profile summary survives a restart")
	_check(reload.activate(1) and reload.summary(1).runs_started==1,"reopening does not reset a used slot")
	var run=root.get_node("Run");run.save_slots=reload
	_check(run.select_save_slot(1) and run.unlocks.best_wave==8 and run.intel.unspent==14,"Run binds the imported unlock and Intel files")
	run.unlocks.note_wave(10);run.intel.collect(3)
	_check(run.select_save_slot(2),"a second game can be opened")
	_check(run.unlocks.best_wave==0 and run.intel.total()==0 and run.unlocks.highest_difficulty==1,"new slots have independent progression")
	run.unlocks.note_wave(4);run.intel.collect(5)
	_check(run.select_save_slot(1) and run.unlocks.best_wave==10 and run.intel.unspent==17,"switching back restores Game 1 progress")
	_check(run.select_save_slot(2) and run.unlocks.best_wave==4 and run.intel.unspent==5,"Game 2 keeps its own progress")
	_check(FileAccess.get_file_as_string(saves.legacy_directory.path_join("unlocks.json"))==JSON.stringify(old_unlocks),"new progress never overwrites the original flat save")
	_write(saves.slot_path(3),{"version":999})
	var future:=FileAccess.get_file_as_string(saves.slot_path(3))
	_check(not reload.activate(3) and FileAccess.get_file_as_string(saves.slot_path(3))==future,"an unsupported save is refused without overwriting it")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.slot_path(4).get_base_dir()))
	var damaged:=FileAccess.open(saves.slot_path(4),FileAccess.WRITE);damaged.store_string("{broken");damaged.close()
	_check(not reload.activate(4) and FileAccess.get_file_as_string(saves.slot_path(4))=="{broken","a damaged save is refused without overwriting it")
	_write(saves.slot_path(4),{"version":1,"runs_started":{"bad":1}})
	_check(not reload.activate(4),"invalid counter types are refused instead of crashing the selector")
	var scene=load("res://game/main.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.set_process(false);scene.arena.set_process(false);scene._return_to_title()
	_check(scene.state=="title" and not scene.arena.visible,"the title keeps gameplay hidden")
	await _tap(JOY_BUTTON_A);await process_frame
	_check(scene.state=="game_select" and scene.game_select_s.buttons.size()==4,"controller A opens exactly four slots")
	_check(scene.game_select_s.buttons[2].disabled and scene.game_select_s.buttons[3].disabled,"unreadable saves cannot be accidentally replaced through the menu")
	await _tap(JOY_BUTTON_B)
	_check(scene.state=="title","controller Back returns to the title")
	scene._open_game_select();await process_frame;scene.game_select_s.buttons[0].grab_focus()
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	_check(root.gui_get_focus_owner()==scene.game_select_s.buttons[1],"the D-pad moves between game slots")
	await _tap(JOY_BUTTON_A);await process_frame
	_check(scene.state=="play" and run.save_slots.active_slot==2,"the focused slot starts its mission")
	_check(scene.arena.teleport_arrival.active,"selecting a game starts the teleport arrival")
	_check(run.ammo_id()=="laser" and run.FRAMES[run.build.frame].id=="pistol","mission-first entry uses the existing starter loadout")
	_check(run.unlocks.best_wave==4 and run.intel.unspent==5,"starting a mission preserves that slot's meta progression")
	scene._return_to_title();_check(scene.state=="title" and not paused,"return to title leaves a usable unpaused menu")
	scene.free()
	print("GAME SELECT TESTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

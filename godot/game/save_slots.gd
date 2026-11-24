extends RefCounted
## Four independent campaign profiles. Slot 1 can copy the old flat saves once.
## Tests use memory unless they explicitly supply a private directory and persist=true.
const COUNT:=4
const VERSION:=1
var directory:="user://games"
var legacy_directory:="user://"
var persist:=true
var active_slot:=0
var error:=""
var _memory:={}

func _init(test_mode:=false) -> void: persist=not test_mode

func slot_path(slot: int,file: String="profile.json") -> String:
	return directory.path_join("slot_%d"%slot).path_join(file)

func _fresh(slot: int) -> Dictionary:
	return {"version":VERSION,"slot":slot,"runs_started":0,"best_wave":0,"wins":0,"deaths":0,"story_flags":{},"endings":[]}

func _object(path: String) -> Dictionary:
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:
		return {"error":"Save data could not be read."}
	var value: Dictionary=parser.data
	if typeof(value.get("version",1)) not in [TYPE_INT,TYPE_FLOAT]:return {"error":"Save data could not be read."}
	if int(value.get("version",1))>VERSION:return {"error":"This save was created by a newer version."}
	for key in ["runs_started","best_wave","wins","deaths","highest_difficulty","unspent"]:
		if value.has(key) and (typeof(value[key]) not in [TYPE_INT,TYPE_FLOAT] or float(value[key])<0):
			return {"error":"Save data could not be read."}
	for key in ["endings","bosses","unlocked","heists","banks"]:
		if value.has(key) and not value[key] is Array:return {"error":"Save data could not be read."}
	for key in ["story_flags","alloc"]:
		if value.has(key) and not value[key] is Dictionary:return {"error":"Save data could not be read."}
	if value.has("alloc"):
		for n in value.alloc.values():
			if typeof(n) not in [TYPE_INT,TYPE_FLOAT]:return {"error":"Save data could not be read."}
	return value

func summary(slot: int) -> Dictionary:
	if slot<1 or slot>COUNT:return {"error":"Invalid game slot."}
	var data:=_fresh(slot);var used:=false;var legacy:=false
	if not persist:
		if _memory.has(slot): data=_memory[slot].duplicate(true);used=true
	else:
		if FileAccess.file_exists(slot_path(slot)):
			var stored:=_object(slot_path(slot))
			if stored.has("error"):return stored
			data.merge(stored,true);used=true
		for file in ["unlocks.json","intel.json"]:
			var path:=slot_path(slot,file)
			if not FileAccess.file_exists(path) and slot==1 and not FileAccess.file_exists(slot_path(slot)):
				path=legacy_directory.path_join(file)
				if FileAccess.file_exists(path):legacy=true
			if not FileAccess.file_exists(path):continue
			var stored:=_object(path)
			if stored.has("error"):return stored
			used=true
			if file=="unlocks.json":data.best_wave=maxi(int(data.best_wave),int(stored.get("best_wave",0)))
	data["used"]=used;data["legacy"]=legacy
	return data

func activate(slot: int) -> bool:
	error=""
	var data:=summary(slot)
	if data.has("error"):error=data.error;return false
	if persist:
		var folder:=ProjectSettings.globalize_path(slot_path(slot).get_base_dir())
		if DirAccess.make_dir_recursive_absolute(folder)!=OK:error="Could not create the save folder.";return false
		# Copy, never move/delete/overwrite the previous single-profile files.
		if data.legacy:
			for file in ["unlocks.json","intel.json"]:
				var source:=legacy_directory.path_join(file);var target:=slot_path(slot,file)
				if FileAccess.file_exists(source) and not FileAccess.file_exists(target):
					if DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(target))!=OK:
						error="Could not copy the previous save into Game 1.";return false
	data.erase("used");data.erase("legacy")
	if not _write(slot,data):return false
	active_slot=slot
	return true

func _write(slot: int,data: Dictionary) -> bool:
	if not persist:_memory[slot]=data.duplicate(true);return true
	var path:=ProjectSettings.globalize_path(slot_path(slot));var temp:=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:error="Could not save game progress.";return false
	file.store_string(JSON.stringify(data,"  "));file.flush()
	var result:=file.get_error();file.close()
	if result!=OK or DirAccess.rename_absolute(temp,path)!=OK:
		error="Could not finish saving game progress.";return false
	return true

func note_run() -> bool:
	if active_slot==0:return true
	var data:=summary(active_slot)
	if data.has("error"):error=data.error;return false
	data.runs_started=int(data.runs_started)+1;data.erase("used");data.erase("legacy")
	return _write(active_slot,data)

func note_wave(wave: int) -> bool:
	if active_slot==0:return true
	var data:=summary(active_slot)
	if data.has("error"):error=data.error;return false
	if wave<=int(data.best_wave):return true
	data.best_wave=wave;data.erase("used");data.erase("legacy")
	return _write(active_slot,data)

func note_result(win: bool,died: bool) -> bool:
	if active_slot==0:return true
	var data:=summary(active_slot)
	if data.has("error"):error=data.error;return false
	if win:data.wins=int(data.wins)+1
	elif died:data.deaths=int(data.deaths)+1
	data.erase("used");data.erase("legacy")
	return _write(active_slot,data)

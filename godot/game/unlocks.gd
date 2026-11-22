extends RefCounted
## Meta-progression (Dead Cells style): progress that outlives a run and opens alternative STARTING parts.
## Every run still starts with Laser + Ray Pistol by default; unlocked parts can be picked on the design screen instead.
## Rules live in data/rules.json "unlocks"; progress is saved to user://unlocks.json.
##
## Test runs (`--script`, or the `--autoplay` / `--wave` hooks) never touch the player's save: they start empty and
## keep progress in memory only. Tests that check saving set `path` and `persist` themselves.

const SAVE_PATH := "user://unlocks.json"
const VERSION := 1

var path := SAVE_PATH
var persist := true
var best_wave := 0             # highest wave started in any run
var bosses: Array = []         # waves whose boss has been defeated (ints)
var unlocked: Array = []       # part keys, e.g. "ammo:bullet", "frame:rifle"
var fresh: Array = []          # keys unlocked during the current run (cleared by begin_run)
var rules: Array = []          # [{part, id, need: {reach_wave|boss: n}}]
var highest_difficulty := 1
var heists: Array = []         # difficulty levels (1..5) on which the train heist's vault was reached
var banks: Array = []          # difficulty levels (1..5) on which the bank vault was opened
var difficulty_names: Array = []   # set by Run (for requirement text)
var fresh_difficulty := 0

func _init(unlock_rules: Array = [], test_mode := false) -> void:
	rules = unlock_rules
	if test_mode: persist = false
	else: load_save()

static func key(part: String, id: String) -> String: return part + ":" + id

func is_unlocked(part: String, id: String) -> bool:
	return rule_for(part, id).is_empty() or unlocked.has(key(part, id))

func rule_for(part: String, id: String) -> Dictionary:
	for r in rules:
		if r.part == part and r.id == id: return r
	return {}

## Human-readable requirement, e.g. "Reach wave 4" / "Defeat the wave-10 boss".
func requirement(part: String, id: String) -> String:
	var r := rule_for(part, id)
	if r.is_empty(): return ""
	if r.need.has("pickup_boss"):
		var boss_name: String = {"ironclad":"Captain Ironclad", "viper":"Velvet Viper"}.get(r.need.pickup_boss,r.need.pickup_boss)
		return "Collect %s's %sblueprint" % [boss_name,"rare " if r.need.get("rare",false) else ""]
	if r.need.has("heist"):
		var level := int(r.need.heist)
		var tier: String = difficulty_names[level - 1] if level - 1 < difficulty_names.size() else "difficulty %d" % level
		return "Reach the vault car in the train heist on %s" % tier
	if r.need.has("bank"):
		var level := int(r.need.bank)
		var tier: String = difficulty_names[level - 1] if level - 1 < difficulty_names.size() else "difficulty %d" % level
		return "Open the bank vault on %s" % tier
	if r.need.has("case"): return "Collect a blueprint from a shattered jewel case (wave 5+)"
	if r.need.has("boss"): return "Defeat the wave-%d boss" % int(r.need.boss)
	return "Reach wave %d" % int(r.need.reach_wave)

func begin_run() -> void: fresh = []; fresh_difficulty = 0

func difficulty_available(level: int) -> bool:
	return level >= 1 and level <= highest_difficulty

func note_difficulty_wave(level: int, wave: int) -> bool:
	if wave < 20 or level < 1 or level >= 5 or not difficulty_available(level) or highest_difficulty >= level + 1: return false
	highest_difficulty = level + 1
	if not save(): highest_difficulty = level; return false
	fresh_difficulty = highest_difficulty
	return true

## Train heist (game/train_heist.gd): reaching the vault car on a difficulty unlocks that difficulty's reward(s)
## once. Returns the newly unlocked keys (empty when already earned or the save can't be written).
func note_heist(level: int) -> Array:
	var got: Array = []
	for r in rules:
		var k := key(r.part, r.id)
		if int(r.need.get("heist", 0)) == level and not unlocked.has(k): got.append(k)
	var first := not heists.has(level)
	if first: heists.append(level)
	if got.is_empty() and not first: return []
	unlocked.append_array(got)
	if not save():
		for k in got: unlocked.erase(k)
		if first: heists.erase(level)
		return []
	fresh.append_array(got)
	return got

## Bank robbery (game/bank_vault.gd): opening the vault on a difficulty unlocks that difficulty's bank reward once.
func note_bank(level: int) -> Array:
	var got: Array = []
	for r in rules:
		var k := key(r.part, r.id)
		if int(r.need.get("bank", 0)) == level and not unlocked.has(k): got.append(k)
	var first := not banks.has(level)
	if first: banks.append(level)
	if got.is_empty() and not first: return []
	unlocked.append_array(got)
	if not save():
		for k in got: unlocked.erase(k)
		if first: banks.erase(level)
		return []
	fresh.append_array(got)
	return got

## Physical blueprints unlock only on collection, never from the boss/wave hooks.
func collect_blueprint(id: String) -> bool:
	var r := rule_for("item", id)
	if r.is_empty() or (not r.need.has("pickup_boss") and not r.need.has("case")): return false
	var k := key("item", id)
	if unlocked.has(k): return false
	unlocked.append(k); fresh.append(k)
	if not save():
		unlocked.erase(k); fresh.erase(k); return false
	return true

func note_wave(w: int) -> Array:
	if w <= best_wave: return []
	best_wave = w
	return _evaluate()

func note_boss(w: int) -> Array:
	if bosses.has(w): return []
	bosses.append(w)
	return _evaluate()

## Re-checks every rule; returns (and saves) the keys that just unlocked.
func _evaluate() -> Array:
	var got: Array = []
	for r in rules:
		var k := key(r.part, r.id)
		if unlocked.has(k): continue
		var ok := false
		if r.need.has("reach_wave"): ok = best_wave >= int(r.need.reach_wave)
		elif r.need.has("boss"): ok = bosses.has(int(r.need.boss))
		if ok: unlocked.append(k); got.append(k); fresh.append(k)
	save()
	return got

func reset() -> void:
	best_wave = 0; bosses = []; unlocked = []; fresh = []; heists = []; banks = []
	highest_difficulty = 1
	fresh_difficulty = 0
	save()

func save() -> bool:
	if not persist: return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: push_warning("unlocks: can't write " + path); return false
	f.store_string(JSON.stringify({"version": VERSION, "best_wave": best_wave, "bosses": bosses, "unlocked": unlocked, "highest_difficulty":highest_difficulty, "heists": heists, "banks": banks}, "  "))
	f.flush()
	return f.get_error() == OK

func load_save() -> void:
	best_wave = 0; bosses = []; unlocked = []; fresh = []; heists = []; banks = []
	highest_difficulty = 1; fresh_difficulty = 0
	if not FileAccess.file_exists(path): return
	var j := JSON.new()   # (JSON.parse_string would log an engine error for a damaged file)
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		push_warning("unlocks: ignoring unreadable " + path); return
	var v: Dictionary = j.data
	highest_difficulty = clampi(int(v.get("highest_difficulty", 1)), 1, 5)
	best_wave = int(v.get("best_wave", 0))
	for b in v.get("bosses", []): bosses.append(int(b))
	for h in v.get("heists", []):
		if not heists.has(int(h)): heists.append(int(h))
	for b in v.get("banks", []):
		if not banks.has(int(b)): banks.append(int(b))
	for k in v.get("unlocked", []):
		if k is String and not unlocked.has(k): unlocked.append(k)

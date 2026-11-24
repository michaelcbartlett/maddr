extends RefCounted
## Villain Intel: a meta currency that outlives runs (like game/unlocks.gd). Cops sometimes drop an Intel dossier;
## collected dossiers bank as points. Points can be assigned to shop modules to "rig the depot": every point on a
## module raises its weight whenever offers are rolled. Points can be moved freely: removing one returns it to the
## unspent pool. Rules live in data/rules.json "intel"; progress is saved to user://intel.json.
##
## Test runs keep everything in memory only (same rule as unlocks); tests that check saving set `path`/`persist`.

const SAVE_PATH := "user://intel.json"
const VERSION := 1

var path := SAVE_PATH
var persist := true
var rules: Dictionary = {}
var unspent := 0                  # unassigned points
var alloc: Dictionary = {}     # item id -> points assigned (> 0 only)
var earned_run := 0            # points collected during the current run (cleared by begin_run)

func _init(intel_rules: Dictionary = {}, test_mode := false) -> void:
	rules = intel_rules
	if test_mode: persist = false
	else: load_save()

func begin_run() -> void: earned_run = 0

func per_point() -> float: return float(rules.get("weight_per_point", 0.25))
func max_per_item() -> int: return maxi(1, int(rules.get("max_points_per_item", 8)))

func points(id: String) -> int: return int(alloc.get(id, 0))
func assigned() -> int:
	var n := 0
	for k in alloc: n += int(alloc[k])
	return n
func total() -> int: return unspent + assigned()

## Offer-roll weight multiplier for an item: 1 + points * weight_per_point (points are capped per item).
func weight(id: String) -> float:
	return 1.0 + mini(points(id), max_per_item()) * per_point()

## Banks collected dossiers. Returns false only if the save can't be written (the points are still kept in memory).
func collect(n := 1) -> bool:
	if n <= 0: return true
	unspent += n; earned_run += n
	return save()

## Moves `delta` points onto (+) or off (-) an item. Refuses when out of unspent points, over the per-item cap, or
## removing points the item doesn't have. Returns true if anything changed.
func assign(id: String, delta: int) -> bool:
	if delta == 0 or id == "": return false
	var cur := points(id)
	var next := clampi(cur + delta, 0, max_per_item())
	if next > cur: next = mini(next, cur + unspent)
	if next == cur: return false
	unspent -= next - cur
	if next == 0: alloc.erase(id)
	else: alloc[id] = next
	save()
	return true

## Returns every point on an item to the unspent pool.
func clear(id: String) -> bool: return assign(id, -points(id))

## Returns every assigned point to the unspent pool.
func clear_all() -> bool:
	if alloc.is_empty(): return false
	unspent = total(); alloc = {}
	save()
	return true

func reset() -> void:
	unspent = 0; alloc = {}; earned_run = 0
	save()

func save() -> bool:
	if not persist: return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: push_warning("intel: can't write " + path); return false
	f.store_string(JSON.stringify({"version": VERSION, "unspent": unspent, "alloc": alloc}, "  "))
	f.flush()
	return f.get_error() == OK

func load_save() -> void:
	unspent = 0; alloc = {}; earned_run = 0
	if not FileAccess.file_exists(path): return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		push_warning("intel: ignoring unreadable " + path); return
	var v: Dictionary = j.data
	unspent = maxi(0, int(v.get("unspent", 0)))
	var a: Variant = v.get("alloc", {})
	if a is Dictionary:
		for k in a:
			# over-cap allocations (rules changed since the save) refund the excess instead of losing it
			var n := maxi(0, int(a[k]))
			var kept := mini(n, max_per_item())
			unspent += n - kept
			if k is String and kept > 0: alloc[k] = kept

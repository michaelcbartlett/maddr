extends Node
## Autoload "Run": data tables, the current build, stat math and shop rules.
## Port of index.html: AMMO/FRAMES/ITEMS, baseStats(), recompute() -> S, D, CNT, genOffers(), itemAvailable().
## Data lives in res://data/*.json; this file holds only the formulas.

const DATA := "res://data/"

var AMMO: Array = []
var FRAMES: Array = []
var ITEMS: Array = []
var ITEM: Dictionary = {}
var ET: Dictionary = {}          # enemy types
var BOSSES: Dictionary = {}      # wave(int) -> boss def
var SPAWN_TABLE: Array = []
var SCALING: Dictionary = {}
var RULES: Dictionary = {}
var PARTS: Array = []            # shop offers that swap the main gun's ammo/frame (pseudo-items, see _build_parts)
const UnlocksT = preload("res://game/unlocks.gd")
var unlocks: RefCounted          # persistent starting-part unlocks (game/unlocks.gd)
const IntelT = preload("res://game/intel.gd")
var intel: RefCounted            # persistent Intel points assigned to modules to rig offer rolls (game/intel.gd)
const SaveSlotsT=preload("res://game/save_slots.gd")
var save_slots: RefCounted
var _slot_memory:={}

# ---- run state ----
## ammo/frame = the main gun's current parts (indices into AMMO/FRAMES). start = the parts the run began with;
## swapped[part] = the current part was bought in the shop (so it can be sold back / traded in).
var build := {"ammo": 0, "frame": 0, "items": [], "name": "", "off": null, "start": {"ammo": 0, "frame": 0}, "swapped": {"ammo": false, "frame": false}}
var custom_name := false
var run_serial := 0
var arm_cooldowns := {"time_freeze":0.0,"proximity_bomb":0.0,"seeker_rack":0.0,"shrink_ray":0.0,"freeze_ray":0.0}
## Teleport Pads used to be a supply; they are now a B action (item "teleport", consumables.gd place_pad).
const CONSUMABLE_IDS := ["disguise", "grenade", "shrink_pill", "enlarge_pill", "tesla_coil"]
const CONSUMABLE_NAMES := {"disguise":"Disguise", "grenade":"Grenade", "shrink_pill":"Shrinking Pill", "enlarge_pill":"Enlargement Pill", "tesla_coil":"Tesla Coil"}
const CONSUMABLE_PRICES := {"disguise":14, "grenade":10, "shrink_pill":14, "enlarge_pill":18, "tesla_coil":20}
var consumable_charges := {"disguise":0, "grenade":0, "shrink_pill":0, "enlarge_pill":0, "tesla_coil":0}
var selected_consumable := "disguise"
## Supplies are unlocked by buying their kit from the depot offers (3 charges); refills are bought after that.
var consumables_owned := {}
const KIT_CHARGES := 3

func owns_consumable(id: String) -> bool: return consumables_owned.has(id)

func buy_consumable(id: String) -> bool:
	if not CONSUMABLE_IDS.has(id) or not owns_consumable(id) or int(consumable_charges[id]) >= 3: return false
	var price := wave_price(CONSUMABLE_PRICES[id])
	if scrap < price: return false
	scrap -= price; consumable_charges[id] += 1
	if int(consumable_charges.get(selected_consumable, 0)) == 0: selected_consumable = id
	return true

func cycle_consumable() -> void:
	var current := CONSUMABLE_IDS.find(selected_consumable)
	for offset in range(1, CONSUMABLE_IDS.size()):
		var id: String = CONSUMABLE_IDS[(current + offset) % CONSUMABLE_IDS.size()]
		if int(consumable_charges[id]) > 0: selected_consumable = id; return

func spend_consumable() -> String:
	if int(consumable_charges[selected_consumable]) <= 0: cycle_consumable()
	if int(consumable_charges[selected_consumable]) <= 0: return ""
	var id := selected_consumable
	consumable_charges[id] -= 1
	if int(consumable_charges[id]) == 0: cycle_consumable()
	return id
var scrap := 0
var scrap_f := 0.0
var kills := 0
var total_scrap := 0
var wave := 1
var offers: Array = []
var reroll_cost := 0

# ---- derived ----
var S: Dictionary = {}
var D: Dictionary = {}
var CNT: Dictionary = {}

signal build_changed

func _ready() -> void:
	AMMO = _load("ammo.json")
	FRAMES = _load("frames.json")
	ITEMS = _load("items.json")
	for it in ITEMS: ITEM[it.id] = it
	var en: Dictionary = _load("enemies.json")
	ET = en.types
	for k in en.bosses: BOSSES[int(k)] = en.bosses[k]
	SPAWN_TABLE = en.spawn_table
	SCALING = en.scaling
	RULES = _load("rules.json")
	_build_parts()
	unlocks = UnlocksT.new(RULES.get("unlocks", []), is_test_process())
	unlocks.difficulty_names = DIFFICULTY
	intel = IntelT.new(RULES.get("intel", {}), is_test_process())
	save_slots=SaveSlotsT.new(is_test_process())
	recompute()

func select_save_slot(slot: int) -> bool:
	if save_slots.active_slot>0:
		if not unlocks.save() or not intel.save():save_slots.error="Could not save the current game.";return false
		_slot_memory[save_slots.active_slot]={"unlocks":unlocks,"intel":intel}
	if not save_slots.activate(slot):return false
	if not save_slots.persist and _slot_memory.has(slot):
		unlocks=_slot_memory[slot].unlocks;intel=_slot_memory[slot].intel
	else:
		unlocks=UnlocksT.new(RULES.get("unlocks",[]),true);unlocks.difficulty_names=DIFFICULTY
		intel=IntelT.new(RULES.get("intel",{}),true)
		unlocks.path=save_slots.slot_path(slot,"unlocks.json");intel.path=save_slots.slot_path(slot,"intel.json")
		unlocks.persist=save_slots.persist;intel.persist=save_slots.persist
		if save_slots.persist:unlocks.load_save();intel.load_save()
	return true

## Headless test scripts and the --autoplay/--wave hooks must not write the player's unlock save.
static func is_test_process() -> bool:
	var u := OS.get_cmdline_user_args()
	return OS.get_cmdline_args().has("--script") or u.has("--autoplay") or u.has("--wave")

func _load(f: String) -> Variant:
	var txt := FileAccess.get_file_as_string(DATA + f)
	var v: Variant = JSON.parse_string(txt)
	if v == null: push_error("bad json: " + f)
	return v

# =============== BUILD / STATS ===============
static func base_stats() -> Dictionary:
	return {"dmg": 0.0, "dmgMul": 1.0, "dmgPct": 0.0, "cd": 1.0, "atkSpd": 0.0, "range": 300.0, "rangeAdd": 0.0, "width": 10.0, "widthPct": 0.0,
		"shots": 1, "spread": 0.0, "pierce": 0, "drill": 0,
		"burn": 0.0, "acid": 0.0, "poison": 0.0, "bleed": 0.0, "sick": 0.0, "freeze": 0.0, "mind": 0.0, "mindDur": 6.0, "minionMul": 1.0,
		"chain": 0, "chainMul": 1.0, "execute": 0.0, "explode": 0.0, "bomb": 0.0, "remote": 0.0, "boomMul": 1.0, "lifesuck": 0.0, "frozenMul": 1.0,
		"sustain": 0, "maxHp": 30.0, "regen": 0.0, "armor": 0.0, "hitProtection": 0.0, "speed": 210.0, "speedPct": 0.0, "pickup": 70.0, "pickupPct": 0.0,
		"scrapPct": 0.0, "dropPct": 0.0, "burnSpread": 0.0, "poisonSpread": 0.0, "orbs": 0, "moon": 0, "crit": 0.05, "meleeSpd": 0.0, "meleeReach": 0.0, "meleeDmg": 0.0, "burnMul": 1.0, "poisonMul": 1.0, "lightningMul": 1.0, "rad": 0.0, "radMul": 1.0, "ebola":0.0, "aimGuide": 0, "beam": 0, "guns": []}

static func apply_def(s: Dictionary, def: Dictionary) -> void:
	if def.has("set"):
		for k in def.set: s[k] = def.set[k]
	if def.has("add"):
		for k in def.add:
			if typeof(s[k]) == TYPE_INT: s[k] = int(s[k] + def.add[k])
			else: s[k] = s[k] + float(def.add[k])
	if def.has("mul"):
		for k in def.mul: s[k] = s[k] * float(def.mul[k])
	if def.has("gun"): (s.guns as Array).append(def.gun)

func ammo_id(i: int = -1) -> String:
	return AMMO[build.ammo if i < 0 else i].id

## True when the main gun fires the Shock Grapple (game/grapple.gd) instead of shots.
func has_hook() -> bool: return ammo_id() == "hook"

func has_primary_melee() -> bool: return AMMO[build.ammo].has("melee")

## ---- hand loadout ----
## A melee primary and a melee weapon on the Bionic Arm can trade hands (main hand = manual sweep, arm = auto swing).
## build.hands_swapped only flips which hand holds which owned weapon; ownership, selling and trade-ins are unchanged.
func _arm_melee_kind() -> String:
	if build.off == null: return ""
	var kind: String = build.off.get("kind", "gun")
	return kind if ITEM.has(kind) and ITEM[kind].get("arm", "") == kind and ITEM[kind].has("melee") else ""

func can_swap_hands() -> bool:
	return has_primary_melee() and _arm_melee_kind() != "" and _arm_melee_kind() != String(AMMO[build.ammo].melee)

func hands_swapped() -> bool: return bool(build.get("hands_swapped", false)) and can_swap_hands()

func swap_hands() -> bool:
	if not can_swap_hands(): return false
	build.hands_swapped = not hands_swapped()
	if not custom_name: build.name = weapon_name()
	recompute()
	return true

## Melee kind in the main hand ("" for a ranged primary).
func primary_kind() -> String:
	if not has_primary_melee(): return ""
	return _arm_melee_kind() if hands_swapped() else String(AMMO[build.ammo].melee)

## Id the main hand draws/fires with: the primary melee kind, or the gun's ammo id.
func primary_weapon_id() -> String: return primary_kind() if has_primary_melee() else ammo_id()

## build.off as actually mounted on the arm (with the hands swap applied).
func arm_off() -> Variant:
	return {"kind": String(AMMO[build.ammo].melee)} if hands_swapped() else build.off

## Owned things that can go in the Bionic Arm slot, newest first, one entry per id.
func arm_options() -> Array:
	var out: Array = []
	if CNT.get("bionic_arm", 0) == 0: return out
	for i in range(build.items.size() - 1, -1, -1):
		var id: String = build.items[i]
		if (id == "offhand" or ITEM[id].has("arm")) and not out.has(id): out.append(id)
	return out

## Mount an owned arm item (makes it the newest so _rebuild_off() and later sales keep it).
func mount_arm(id: String) -> bool:
	if not arm_options().has(id): return false
	build.items.remove_at(build.items.rfind(id)); build.items.append(id)
	_rebuild_off(); recompute()
	return true

## The arm item currently mounted ("" for none / bare fist).
func mounted_arm_id() -> String:
	if build.off == null: return ""
	var kind: String = build.off.get("kind", "gun")
	if kind == "gun": return "offhand"
	for it in ITEMS:
		if it.get("arm", "") == kind: return it.id
	return ""

## The rear (off-hand) gun shoots the next ammo after the main gun's. The grapple is main-gun only.
func off_ammo() -> int:
	var i: int = build.ammo
	for step in AMMO.size():
		i = (i + 1) % AMMO.size()
		if AMMO[i].id != "hook" and not AMMO[i].has("melee"): return i
	return 0

func recompute(emit := true) -> void:
	S = base_stats(); CNT = {}
	apply_def(S, AMMO[build.ammo])
	if not has_primary_melee(): apply_def(S, FRAMES[build.frame])
	(S.guns as Array).push_front(ammo_id())
	for id in build.items:
		apply_def(S, ITEM[id]); CNT[id] = CNT.get(id, 0) + 1
	if has_primary_melee(): S.guns = [primary_weapon_id()]
	var is_laser := ammo_id() == "laser"
	D = {
		"dmg": maxf(1.0, S.dmg * S.dmgMul * (1.0 + S.dmgPct) * (1.0 + 0.1 * S.drill if is_laser else 1.0)),
		"cd": maxf(0.07, S.cd / (1.0 + S.atkSpd)),
		"range": S.range + S.rangeAdd,
		"width": S.width * (1.0 + S.widthPct),
		"shots": mini(9, S.shots),
		"speed": S.speed * (1.0 + S.speedPct),
		"pickup": S.pickup * (1.0 + S.pickupPct),
		"maxHp": maxi(10, roundi(S.maxHp)),
		"hitProtection": maxf(0.0,1.0+float(S.hitProtection)),
	}
	D.pf = clampf(D.cd / 0.6, 0.3, 1.5) / sqrt(D.shots)   # proc scaling for fast / multi-shot weapons
	if emit: build_changed.emit()

## Brotato's normal-mode hit grace, scaled by the build's Hit Protection stat.
## Use damage after armor, as a fraction of maximum (not current) health.
func hit_protection_duration(damage_taken: float) -> float:
	var base := clampf(0.4 * maxf(0.0,damage_taken) / maxf(1.0,float(D.maxHp)) / 0.15,0.2,0.4)
	return base * float(D.hitProtection)

## Half-width of a fired shot. Upgrades scale the frame's own size, so the floor never swallows one.
func shot_radius(type: String) -> float:
	var base := maxf(6.0, float(S.width) / 2.2) if type == "razor" else maxf(3.0, float(S.width) / 3.5)
	return base * (1.0 + float(S.widthPct))

## Main gun's direct damage per second (every pellet hits, crits averaged in; no DOTs or procs).
func main_gun_dps() -> float:
	return D.dmg * D.shots * (1.0 + S.crit) / D.cd

## Fractional change in main_gun_dps() if this ammo/frame part offer were bought (0.25 = +25%).
func part_dps_change(it: Dictionary) -> float:
	var before := main_gun_dps(); var keep: int = build[it.swap]
	var s0 := S; var d0 := D; var c0 := CNT
	build[it.swap] = int(it.idx); recompute(false)
	var after := main_gun_dps()
	build[it.swap] = keep; S = s0; D = d0; CNT = c0
	return after / maxf(0.001, before) - 1.0

func weapon_name() -> String:
	if has_primary_melee():
		var noun: String = AMMO[build.ammo].noun
		for d in AMMO:
			if d.get("melee", "") == primary_kind(): noun = d.noun
		return "The Diabolical " + noun
	return "The Diabolical %s %s" % [AMMO[build.ammo].noun, FRAMES[build.frame].noun]

func display_name() -> String:
	return build.name if build.name != "" else weapon_name()

func worn_core() -> String:
	for i in range(build.items.size() - 1, -1, -1):
		var id: String = build.items[i]
		if id.begins_with("core_"): return id.substr(5)
	return ""

func wave_len(w: int) -> float:
	var duration := float(RULES.waves.len.get(str(w), RULES.waves.len_default))
	return float(RULES.heist.get("duration", duration)) if is_heist_wave(w) else duration

func boss_for(w: int) -> Variant:
	return BOSSES.get(w, null)

# =============== FLOW ===============
## Every run starts with Laser (0) + Ray Pistol (0); the design screen may then pick unlocked parts (set_start).
func new_run() -> void:
	run_serial += 1
	build = {"ammo": 0, "frame": 0, "items": [], "name": "", "off": null, "start": {"ammo": 0, "frame": 0}, "swapped": {"ammo": false, "frame": false}}
	unlocks.begin_run(); intel.begin_run()
	custom_name = false; scrap = 0; scrap_f = 0.0; kills = 0; total_scrap = 0; wave = 1
	arm_cooldowns = {"time_freeze":0.0,"proximity_bomb":0.0,"seeker_rack":0.0,"shrink_ray":0.0,"freeze_ray":0.0}
	consumable_charges = {"disguise":0, "grenade":0, "shrink_pill":0, "enlarge_pill":0, "tesla_coil":0}; selected_consumable = "disguise"; consumables_owned = {}
	set_difficulty(1); theme_order = []
	heist_wave = pick_heist_wave(); bank_cracked = false
	recompute()

## Design screen: choose an unlocked starting part (part = "ammo" | "frame"). Locked parts are refused.
func set_start(part: String, i: int) -> bool:
	if part == "frame" and has_primary_melee(): return false
	var table: Array = AMMO if part == "ammo" else FRAMES
	if i < 0 or i >= table.size() or not unlocks.is_unlocked(part, table[i].id): return false
	if table[i].get("no_start", false): return false   # shop-only (the Shock Whip is a rare shop find, never a starting weapon)
	build[part] = i; build.start[part] = i; build.swapped[part] = false
	recompute()
	return true

## Unlock hooks (main.gd on wave start, arena.gd on boss kill). Return the newly unlocked part keys.
func note_wave_reached(w: int) -> Array:
	unlocks.note_difficulty_wave(difficulty, w)
	return unlocks.note_wave(w)
func note_boss_defeated(w: int) -> Array: return unlocks.note_boss(w)

## "Bullets (start)", "Focusing Lens (shop)"... for an unlock key like "ammo:bullet" / "item:lens".
func part_name(k: String) -> String:
	var bits := k.split(":")
	if bits[0] == "item": return ITEM[bits[1]].name if ITEM.has(bits[1]) else k
	var table: Array = AMMO if bits[0] == "ammo" else FRAMES
	for d in table:
		if d.id == bits[1]: return d.name
	return k

## Scrap a pickup of value v would pay right now (same multipliers as gain_scrap, without banking it).
func scrap_value(v: float) -> float:
	return v * float(RULES.get("economy",{}).get("income_multiplier",0.15)) * (1.0 + S.scrapPct) * payout_mult()

## Loot left on the floor when a wave ends pays this fraction (rules.json economy.leftover_rate).
func leftover_rate() -> float:
	return clampf(float(RULES.get("economy",{}).get("leftover_rate", 1.0)), 0.0, 1.0)

func gain_scrap(v: float) -> int:
	scrap_f += v * float(RULES.get("economy",{}).get("income_multiplier",0.15)) * (1.0 + S.scrapPct) * payout_mult()
	var n := floori(scrap_f); scrap_f -= n; scrap += n; total_scrap += n
	return n

## Brotato-style loot roll: a downed cop drops scrap only this often (bosses always drop). Base from
## rules.json economy.drop_chance, raised/lowered by the dropPct stat from modules. A drop is worth 1/base_chance
## so the expected income at the base chance matches the old always-drop economy.
func drop_chance() -> float:
	return clampf(float(RULES.economy.get("drop_chance", 1.0)) + float(S.get("dropPct", 0.0)), 0.05, 1.0)

func drop_value_mult() -> float:
	return 1.0 / maxf(0.05, float(RULES.economy.get("drop_chance", 1.0)))

## Intel dossiers dropped by a kill (rules.json "intel"): bosses drop boss_drop; cops drop one with drop_chance
## from min_wave on. `roll` is a uniform 0..1 random number (passed in so tests can be deterministic).
func intel_drops(is_boss: bool, roll: float, w: int = -1) -> int:
	var r: Dictionary = RULES.get("intel", {})
	if (wave if w < 0 else w) < int(r.get("min_wave", 1)): return 0
	if is_boss: return int(r.get("boss_drop", 0))
	return 1 if roll < float(r.get("drop_chance", 0.0)) else 0

## Scrap per cop kill falls off with the wave: kill counts grow ~15x over a run while prices only
## double, so without this the bank snowballs. Crates, cash and boss drops are not affected.
func kill_scrap_mult(w: int = -1) -> float:
	return 1.0 / (1.0 + float(RULES.economy.get("kill_scrap_falloff", 0.0)) * ((wave if w < 0 else w) - 1))

# =============== SHOP ===============
## One pseudo-item per ammo/frame, priced from rules.json "parts". Not in ITEMS/ITEM: they never go into build.items.
func _build_parts() -> void:
	PARTS = []
	var pr: Dictionary = RULES.get("parts", {})
	for part in ["ammo", "frame"]:
		var table: Array = AMMO if part == "ammo" else FRAMES
		var prices: Dictionary = pr.get("ammo" if part == "ammo" else "frames", {})
		for i in table.size():
			var d: Dictionary = table[i]
			if not prices.has(d.id): continue
			PARTS.append({"id": "part_%s_%s" % [part, d.id], "swap": part, "idx": i, "t": int(prices[d.id].t), "c": int(prices[d.id].c),
				"ic": "💥" if part == "ammo" else "🔧", "name": d.name,
				"desc": ("NEW PRIMARY · " if d.has("melee") else ("NEW AMMO · " if part == "ammo" else "NEW FRAME · ")) + d.desc,
				"look": "Replaces your main gun's %s" % part})

func part_def(part: String, i: int) -> Dictionary:
	for p in PARTS:
		if p.swap == part and p.idx == i: return p
	return {}

func _swapped(part: String) -> bool: return bool(build.get("swapped", {}).get(part, false))
func _start_part(part: String) -> int: return int(build.get("start", {}).get(part, 0))

## A part is offered only if it isn't already on the gun and isn't the run's starting part
## (selling a bought part puts the starting part back, so buying it would be pointless).
func part_available(it: Dictionary) -> bool:
	if it.swap == "frame" and has_primary_melee(): return false
	return int(build[it.swap]) != int(it.idx) and _start_part(it.swap) != int(it.idx)

func wave_price(c: float, w: int = -1) -> int:
	return roundi(c * (1.0 + RULES.shop.price_growth * ((wave if w < 0 else w) - 1)))

## Scrap you get back for the part currently on the gun when it's replaced or sold (0 for a starting part).
func part_trade_in(part: String) -> int:
	if not _swapped(part): return 0
	var d := part_def(part, int(build[part]))
	return 0 if d.is_empty() else maxi(1, roundi(wave_price(d.c) * SELL_RATE))

func item_available(it: Dictionary) -> bool:
	if it.id == "capacitor" and (CNT.get("capacitor",0)>0 or not has_laser()): return false
	if it.id == "telescope" and aim_guide_level() >= 2: return false
	if it.has("swap"): return part_available(it)
	if it.has("consumable"): return not owns_consumable(it.consumable)
	if it.has("action") and build.items.has(it.id): return false
	if it.id == "tesla_helmet" and CNT.get("tesla_helmet", 0) > 0: return false
	if not unlocks.is_unlocked("item", it.id): return false
	var unlock_rule: Dictionary = unlocks.rule_for("item", it.id)
	if wave < int(unlock_rule.get("min_wave", 1)): return false
	if it.id=="bionic_arm" and CNT.get("bionic_arm",0)>0: return false
	if (it.id=="offhand" or it.has("arm")) and CNT.get("bionic_arm",0)==0: return false
	if it.has("needs_arm") and CNT.get("bionic_arm",0)==0 and not has_primary_melee(): return false
	if it.id == "offhand" and build.off != null and build.off.get("kind","gun")=="gun": return false
	if it.has("arm") and build.off!=null and build.off.get("kind","gun")==it.arm: return false
	if it.id == "sustain" and (not (S.guns as Array).has("laser") or S.sustain >= 2 or not S.beam): return false
	# spread modules only make sense once the effect is on the gun
	if it.id == "napalm" and not S.burn: return false
	if it.id == "spores" and not S.poison: return false
	# damage amplifiers only appear once their effect is in the build
	if it.id == "bellows" and not S.burn: return false
	if it.id == "venom" and not S.poison: return false
	if it.id == "geiger" and not S.rad: return false
	if it.id == "payraise" and not S.mind: return false
	if it.id == "windings" and not (S.chain or CNT.get("tesla_helmet",0) > 0 or has_hook()): return false
	# Focusing Lens: laser bolts -> piercing beam. Meta-unlocked (reach wave 5), one copy, only with a laser equipped.
	if it.id == "lens" and (not unlocks.is_unlocked("item", "lens") or S.beam or not has_laser()): return false
	if it.id == "split" and (D.shots >= 9 or has_hook() or has_primary_melee()): return false
	if it.id in ["gLaser", "gBullet", "gRazor"] and has_primary_melee(): return false
	if it.id in ["gLaser", "gBullet", "gRazor"] and (S.guns as Array).size() >= 4: return false
	return true

## Any laser on the villain: main gun, an extra Laser Emitter, or the off-hand gun.
func has_laser() -> bool:
	if (S.guns as Array).has("laser"): return true
	return build.off != null and build.off.get("kind", "gun") == "gun" and AMMO[int(build.off.get("ammo", 0))].id == "laser"

func aim_guide_level() -> int:
	return clampi(int(CNT.get("telescope",0)),0,2)

func tier_weights(w: int) -> Dictionary:
	var sh: Dictionary = RULES.shop
	return {1: float(sh.t1), 2: sh.t2_base + w * sh.t2_per_wave, 3: maxf(0.0, (w - sh.t3_from) * sh.t3_per_wave), 4: maxf(0.0, (w - sh.t4_from) * sh.t4_per_wave)}

func gen_offers() -> void:
	offers = []
	var w := wave
	var wt := tier_weights(w)
	for i in int(RULES.shop.offers):
		var tot := 0.0
		for t in wt: tot += wt[t]
		var r := randf() * tot; var tier := 1
		for t in wt:
			r -= wt[t]
			if r <= 0.0: tier = t; break
		var pool: Array = []
		# at most one ammo/frame swap per shop; a rolled tier also offers cheaper-tier parts
		if w >= int(RULES.get("parts", {}).get("min_wave", 1)) and not offers.any(func(o): return o.it.has("swap")) and randf() < float(RULES.get("parts", {}).get("chance", 0.0)):
			pool = PARTS.filter(func(it): return int(it.t) <= tier and part_available(it))
		if pool.is_empty():
			pool = ITEMS.filter(func(it): return int(it.t) == tier and item_available(it) and not offers.any(func(o): return o.it.id == it.id))
		if pool.is_empty(): pool = ITEMS.filter(func(x): return int(x.t) == 1 and item_available(x) and not offers.any(func(o): return o.it.id == x.id))
		if pool.is_empty(): break
		var it: Dictionary = weighted_pick(pool)
		offers.append({"it": it, "price": wave_price(it.c, w), "sold": false})

## Picks one entry from an offer pool, weighted by the Intel points assigned to each module (game/intel.gd).
## With no points assigned this is a uniform pick. Use it anywhere modules are rolled.
func weighted_pick(pool: Array) -> Dictionary:
	if pool.is_empty(): return {}
	var tot := 0.0
	for it in pool: tot += intel.weight(String(it.get("id", "")))
	var r := randf() * tot
	for it in pool:
		r -= intel.weight(String(it.get("id", "")))
		if r < 0.0: return it
	return pool[-1]

## Chance that an item is among the very next pick from `pool` (for the Intel screen's odds readout).
func pick_share(pool: Array, id: String) -> float:
	var tot := 0.0
	for it in pool: tot += intel.weight(String(it.get("id", "")))
	return intel.weight(id) / tot if tot > 0.0 and pool.any(func(it): return it.get("id", "") == id) else 0.0

func open_shop_for_next_wave() -> void:
	wave += 1
	reroll_cost = int(RULES.shop.reroll_base) + ceili(wave * float(RULES.shop.reroll_wave))
	gen_offers()

func buy(i: int) -> bool:
	var o: Dictionary = offers[i]
	if o.it.has("swap"): return _buy_part(o)
	if o.sold or scrap < o.price or not item_available(o.it): return false
	scrap -= o.price; o.sold = true
	if o.it.has("consumable"):   # a supply kit, not a module: fills that supply and unlocks its refills
		var id: String = o.it.consumable
		consumables_owned[id] = true; consumable_charges[id] = KIT_CHARGES
		if int(consumable_charges.get(selected_consumable, 0)) == 0: selected_consumable = id
		return true
	build.items.append(o.it.id)
	if o.it.id == "offhand":
		build.off = {"kind":"gun","ammo": off_ammo(), "frame": 0, "items": []}
	elif o.it.has("arm"): build.off = {"kind":o.it.arm}
	if o.it.id == "offhand" or o.it.has("arm"): build.hands_swapped = false   # a new weapon goes on the arm (the shop then offers the swap)
	recompute()
	return true

## Swap the main gun's ammo/frame. A bought part being replaced is traded in for its sell refund
## (counted towards the price); a starting part is just dropped.
func _buy_part(o: Dictionary) -> bool:
	var part: String = o.it.swap
	var back := part_trade_in(part)
	if o.sold or scrap + back < o.price or not part_available(o.it): return false
	scrap += back - o.price; o.sold = true
	build[part] = int(o.it.idx)
	if not build.has("swapped"): build.swapped = {"ammo": false, "frame": false}
	build.swapped[part] = true
	if part == "ammo": build.hands_swapped = false
	if not custom_name: build.name = weapon_name()
	recompute()
	return true

## ---- selling (shop only): 45% of the item's current wave-scaled price ----
const SELL_RATE := 0.45

func sell_price(id: String) -> int:
	if id.begins_with("part:"): return part_trade_in(id.substr(5))
	var it: Dictionary = ITEM[id]
	return maxi(1, roundi(it.c * (1.0 + RULES.shop.price_growth * (wave - 1)) * SELL_RATE))

## "" if the item can be sold, otherwise the reason (shown in the shop).
## Owned things in the shop list: build.items ids plus "part:ammo" / "part:frame" for the main gun's parts.
func sell_block_reason(id: String) -> String:
	if id.begins_with("part:"):
		var part := id.substr(5)
		if _swapped(part): return ""
		return "Starting %s" % part
	if not build.items.has(id): return "Not installed"
	if id == "bionic_arm":
		var deps: Array = []
		for d in build.items:
			if d == "offhand" or ITEM[d].has("arm"):
				if not deps.has(ITEM[d].name): deps.append(ITEM[d].name)
		if not deps.is_empty(): return "Mounted: " + ", ".join(deps)
	if id == "lens" and CNT.get("lens", 0) == 1 and CNT.has("sustain"): return "Sustained Beam installed"
	return ""

func sell(id: String) -> int:
	if sell_block_reason(id) != "": return 0
	if id.begins_with("part:"):
		# selling a bought part puts the run's starting part back on the gun
		var part := id.substr(5); var got := part_trade_in(part)
		build[part] = _start_part(part); build.swapped[part] = false; build.hands_swapped = false
		if not custom_name: build.name = weapon_name()
		scrap += got
		recompute()
		return got
	var refund := sell_price(id)
	build.items.remove_at(build.items.rfind(id))   # remove one copy (the newest)
	if id == "offhand" or ITEM[id].has("arm"): _rebuild_off()
	scrap += refund
	recompute()
	return refund

## Kind the arm will hold after _rebuild_off(): the newest owned slot item.
func _rebuilt_kind() -> String:
	for i in range(build.items.size() - 1, -1, -1):
		var id: String = build.items[i]
		if id == "offhand": return "gun"
		if ITEM[id].has("arm"): return ITEM[id].arm
	return ""

## The arm slot holds the most recently bought slot item that is still owned (same rule as buy()).
func _rebuild_off() -> void:
	var prev = build.off
	if prev == null or prev.get("kind", "gun") != _rebuilt_kind(): build.hands_swapped = false
	build.off = null
	for i in range(build.items.size() - 1, -1, -1):
		var id: String = build.items[i]
		if id == "offhand":
			if prev != null and prev.get("kind", "gun") == "gun": build.off = prev
			else: build.off = {"kind": "gun", "ammo": off_ammo(), "frame": 0, "items": []}
			return
		if ITEM[id].has("arm"):
			build.off = {"kind": ITEM[id].arm}
			return

func reroll() -> bool:
	if scrap < reroll_cost: return false
	scrap -= reroll_cost; reroll_cost += ceili(wave / 2.0)
	gen_offers()
	return true

# =============== STATS TEXT ===============
func equipped_action() -> String:
	for i in range(build.items.size() - 1,-1,-1):
		var it: Dictionary = ITEM[build.items[i]]
		if it.has("action"): return it.action
	return ""

func arm_name(kind: String) -> String:
	for it in ITEMS:
		if it.get("arm","") == kind: return it.name
	return kind

## Bare bionic fist: what the arm swings when no melee weapon is mounted.
const FIST_MELEE := {"reach":58.0,"arc":0.4,"swing":0.26,"cd":0.72,"dmg":10.0,"scale":0.35,"knock":130.0,"targets":1,"proc":false}

## Manual main-hand melee is independent of the automatic bionic arm.
func primary_melee_spec() -> Dictionary:
	if not has_primary_melee(): return {}
	var kind: String = primary_kind()
	var spec: Dictionary = ITEM[kind].melee.duplicate()
	spec.kind = kind; spec.proc = true
	spec.dmg *= 2.5; spec.scale = 1.75; spec.cd *= 0.6
	return _scaled_melee(spec)

## Auto-swing stats for the arm slot: the mounted melee weapon, the bare fist, or {} when the arm is busy or absent.
func melee_spec() -> Dictionary:
	if CNT.get("bionic_arm",0) == 0: return {}
	if build.off == null: return _scaled_melee(FIST_MELEE.duplicate())
	var kind: String = arm_off().get("kind","gun")
	for it in ITEMS:
		if it.get("arm","") == kind and it.has("melee"):
			var spec: Dictionary = it.melee.duplicate(); spec.kind = kind; spec.proc = true
			return _scaled_melee(spec)
	return {}

## Melee upgrades: attack speed shortens swing + cooldown, reach and damage scale directly.
func _scaled_melee(spec: Dictionary) -> Dictionary:
	var speed: float = 1.0 + float(S.meleeSpd)
	spec.cd = maxf(0.12, float(spec.cd) / speed); spec.swing = maxf(0.08, float(spec.swing) / sqrt(speed))
	spec.reach = float(spec.reach) * (1.0 + float(S.meleeReach))
	spec.dmg = float(spec.dmg) * (1.0 + float(S.meleeDmg)); spec.scale = float(spec.scale) * (1.0 + float(S.meleeDmg))
	return spec

func stats_rows() -> Array:
	## [label, value, is_effect]
	var r: Array = []
	var pct := func(v): return str(roundi(v * 100)) + "%"
	if has_primary_melee():
		var main := primary_melee_spec()
		r.append(["Swing damage", "%.1f" % (main.dmg + D.dmg * main.scale), false])
		r.append(["Blade reach", str(roundi(main.reach)), false])
		r.append(["Control", "Sweep stick / mouse", false])
	else:
		r.append(["Damage", "%.1f" % D.dmg, false]); r.append(["Fire rate", "%.2f/s" % (1.0 / D.cd), false])
		r.append(["Range", str(roundi(D.range)), false]); r.append(["Shot width", str(roundi(D.width)), false])
	if D.shots > 1: r.append(["Shots per fire", str(D.shots), false])
	if S.guns.size() > 1: r.append(["Guns", " + ".join(S.guns), false])
	if has_laser(): r.append(["Laser", "beam" if S.beam else "bolt", false])
	if CNT.get("capacitor",0)>0: r.append(["Capacitor", "2.5× laser · 1.5s charge", false])
	r.append(["Pierce", "∞" if ammo_id() == "laser" and S.beam else str(S.pierce), false])
	r.append(["Loot drop", pct.call(drop_chance()), false])
	if build.off != null:
		var kind: String = arm_off().get("kind","gun")
		var label: String = AMMO[build.off.ammo].name+" · rear fire" if kind=="gun" else arm_name(kind)
		var spec := melee_spec()
		if not spec.is_empty(): label += " · auto melee %.2fs" % float(spec.cd)
		r.append(["Arm slot",label,false])
	elif CNT.get("bionic_arm",0)>0: r.append(["Arm slot","Bionic fist · auto melee",false])
	if equipped_action() != "": r.append(["B action", ITEM[equipped_action()].name, false])
	if S.burn: r.append(["🔥 Burn", "%.1f/s" % S.burn, true])
	if S.acid: r.append(["🧫 Chem burn", "%.1f/s" % S.acid, true])
	if S.burnSpread: r.append(["🔥 Fire spread", pct.call(S.burnSpread) + "/s", true])
	if S.poison: r.append(["☠ Poison", "%s/s·stack" % str(S.poison), true])
	if S.poisonSpread: r.append(["☠ Poison spread", pct.call(S.poisonSpread) + "/s", true])
	if S.bleed: r.append(["🩸 Bleed", "%.1f/s·stack" % S.bleed, true])
	if S.sick: r.append(["🦠 Sickness", pct.call(S.sick), true])
	if S.ebola: r.append(["🦠 Ebola Ammo", "%.0f/s · infectious bodies" % (4.0*S.ebola), true])
	if S.freeze: r.append(["🧊 Chill", pct.call(S.freeze), true])
	if S.mind: r.append(["🌀 Mind control", pct.call(S.mind), true])
	if S.chain: r.append(["⚡ Chain jumps", str(S.chain), true])
	if CNT.get("tesla_helmet", 0): r.append(["⚡ Helmet", "3 dmg · 110 radius · 3 foes", true])
	if S.explode: r.append(["💣 Explode", pct.call(S.explode), true])
	if S.bomb: r.append(["⏰ Time bomb", pct.call(S.bomb), true])
	if S.remote: r.append(["📡 Remote mine", pct.call(S.remote), true])
	if S.execute: r.append(["💀 Disintegrate <", pct.call(S.execute), true])
	if S.lifesuck: r.append(["💉 Life suck", pct.call(S.lifesuck), true])
	if S.orbs: r.append(["🟢 Orbs", str(S.orbs), true])
	if S.moon: r.append(["🌕 Moon laser", str(S.moon), true])
	if S.crit > 0.051: r.append(["🧐 Crit", pct.call(S.crit), true])
	r.append(["Max HP", str(D.maxHp), false])
	if S.regen: r.append(["Regen", "%.1f/s" % S.regen, false])
	if S.armor: r.append(["Armor", str(S.armor), false])
	var protection_pct := roundi((float(D.hitProtection)-1.0)*100.0)
	r.append(["Hit protection", "%s%d%% · %.2f–%.2fs" % ["+" if protection_pct>0 else "",protection_pct,0.2*float(D.hitProtection),0.4*float(D.hitProtection)], false])
	r.append(["Speed", str(roundi(D.speed)), false])
	if S.scrapPct: r.append(["Scrap bonus", "+" + pct.call(S.scrapPct), false])
	return r

# =============== DIFFICULTY (picked after the design screen) ===============
# Like Brotato's danger levels: a constant for the whole run. Heat is the fixed value of the pick.
const DIFFICULTY := ["PETTY CROOK","NUISANCE","MENACE","SUPERVILLAIN","ARCH-NEMESIS"]
const DIFFICULTY_FLAVOR := ["Mall cops and parking wardens. A gentle start.","The precinct takes you seriously now.",
	"Every squad car in town has your photo.","SWAT is on speed dial. They hit hard.","The whole force, at full strength. Good luck."]
const OPENING_HEAT := [0.0,1.5,3.0,4.5,6.0]
## Per-tier multipliers (index = stars-1). Each tier moves several dials at once so the jump is felt:
## Petty Crook is forgiving (soft hits, sparse cops), Arch-Nemesis is fast, dense, and hits twice as hard.
## HP stays low enough at every tier that the starting gun still one-shots a wave-1 cop.
## Payout falls as spawns rise, so harder tiers aren't simply richer (more cops = more drops already).
const TIER := {
	"hp":     [0.85, 1.0, 1.1, 1.2, 1.3],
	"dmg":    [0.6, 1.0, 1.25, 1.5, 1.7],
	"spawn":  [0.75, 1.0, 1.25, 1.45, 1.6],
	"speed":  [0.92, 1.0, 1.06, 1.11, 1.15],
	"payout": [1.0, 1.0, 0.95, 0.92, 0.9],
	"unlock": [0, 0, 1, 2, 3],   # tougher cop types show up this many waves earlier
}
const LevelTheme = preload("res://levels/arena_level.gd")
var heat := 0.0
var difficulty := 1          # 1..5
var theme_order: Array = []  # wave themes for this run (cosmetic only)

func difficulty_name(stars: int = -1) -> String: return DIFFICULTY[clampi((difficulty if stars<0 else stars)-1,0,4)]
func set_difficulty(level: int) -> bool:
	if not unlocks.difficulty_available(level): return false
	difficulty = level; heat = OPENING_HEAT[difficulty-1]
	return true
func tier(key: String, level: int = -1) -> float:
	return float(TIER[key][clampi((difficulty if level < 0 else level) - 1, 0, 4)])
## Cop HP multiplier.
func tough_mult() -> float: return tier("hp")
## Cop damage multiplier.
func damage_mult() -> float: return tier("dmg")
## Spawn-rate multiplier (also scales group size).
func spawn_mult() -> float: return tier("spawn")
## Cop move-speed multiplier.
func speed_mult() -> float: return tier("speed")
## Scrap/cash multiplier.
func payout_mult() -> float: return tier("payout")
func payout_for(level: int) -> float: return tier("payout", level)

# =============== TRAIN HEIST (game/train_heist.gd) ===============
## One wave per run (picked from rules.json heist.waves, never a boss wave) is the train heist: reach the vault car
## before the wave timer runs out to win this difficulty's reward (heist.rewards[difficulty-1]).
var heist_wave := 0
var bank_cracked := false   # the bank vault opens once per run (game/bank_vault.gd)

func pick_heist_wave() -> int:
	var waves: Array = RULES.get("heist", {}).get("waves", []).filter(func(w): return boss_for(int(w)) == null)
	return int(waves.pick_random()) if not waves.is_empty() else 0

func is_heist_wave(w: int = -1) -> bool: return heist_wave > 0 and (wave if w < 0 else w) == heist_wave

## Item id of the heist reward for a difficulty (1..5).
func heist_reward(level: int = -1) -> String:
	var rewards: Array = RULES.get("heist", {}).get("rewards", [])
	var i := (difficulty if level < 0 else level) - 1
	return str(rewards[i]) if i >= 0 and i < rewards.size() else ""

## The villain cracked the vault: unlock this difficulty's reward for good (first time only) and bolt a free copy
## onto the gun for the rest of the run. Returns {id, unlocked: bool}.
func claim_heist() -> Dictionary:
	var id := heist_reward()
	var got: Array = unlocks.note_heist(difficulty)
	if id != "" and ITEM.has(id):
		build.items.append(id); recompute()
	return {"id": id, "unlocked": got.has("item:" + id)}

## Item id of the bank vault reward for a difficulty (1..5).
func bank_reward(level: int = -1) -> String:
	var rewards: Array = RULES.get("bank", {}).get("rewards", [])
	var i := (difficulty if level < 0 else level) - 1
	return str(rewards[i]) if i >= 0 and i < rewards.size() else ""

## The villain opened the bank vault: unlock this difficulty's bank reward for good (first time only) and bolt a
## free copy onto the gun for the rest of the run. Returns {id, unlocked: bool}.
func claim_bank() -> Dictionary:
	var id := bank_reward()
	var got: Array = unlocks.note_bank(difficulty)
	if id != "" and ITEM.has(id):
		build.items.append(id); recompute()
	return {"id": id, "unlocked": got.has("item:" + id)}

## Wave 1 is always the street; the rest of the themes are shuffled per run.
func theme_for_wave(w: int) -> String:
	if is_heist_wave(w): return "train"
	if theme_order.is_empty():
		var rest: Array = LevelTheme.ORDER.slice(1); rest.shuffle()
		theme_order = [LevelTheme.ORDER[0]] + rest
	return LevelTheme.theme_for_wave(w,theme_order)

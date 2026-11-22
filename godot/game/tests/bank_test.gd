extends SceneTree
## Bank Lobby robbery (game/bank_vault.gd): a random customer carries the vault key, dropping them drops it, the
## key opens the vault door, the vault pays cash plus this difficulty's reward (unlocked once per difficulty, saved),
## and it only happens once per run. Uses its own save file; the player's user://unlocks.json is never touched.
const UnlocksT = preload("res://game/unlocks.gd")
const SAVE := "user://bank_selftest.json"
const REWARDS := ["vault_plating", "money_counter", "dye_pack", "tumbler_scope", "gold_reserve"]
var checks := 0
var failures := 0
var run
var scene
var a

func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", label)

## A non-boss, non-heist wave whose theme is the Bank Lobby, started through the real flow.
func _start_bank(level: int, fresh_run := true) -> void:
	if fresh_run:
		run.new_run(); run.unlocks.highest_difficulty = 5
		_check(run.set_difficulty(level), "difficulty %d selectable for the test" % level)
	var w := 0
	for candidate in range(2, 21):
		if run.theme_for_wave(candidate) == "bank" and run.boss_for(candidate) == null and not run.is_heist_wave(candidate): w = candidate; break
	_check(w > 0, "the run has a bank wave")
	run.wave = w; scene._start_wave()
	a.spawn_t = 1000; a.crate_t = 1000; a.P.inv = 1000
	for e in a.enemies: e.dead = true

func _customer(x: float, y: float):
	var e = a.make_enemy("civ", x, y); e.civ = true
	return e

func _rob() -> void:
	var c = _customer(a.P.x + 200, a.P.y)
	a.bank_vault.update(a, 0.016)
	c.dead = true; a.bank_vault.update(a, 0.016)
	a.P.x = a.bank_vault.key_pos.x; a.P.y = a.bank_vault.key_pos.y; a.bank_vault.update(a, 0.016)
	a.P.x = a.BankVault.DOOR.x; a.P.y = a.BankVault.DOOR.y + 40; a.bank_vault.update(a, 0.016)

func _run() -> void:
	seed(2024)
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)
	run.unlocks.path = SAVE; run.unlocks.persist = true; run.unlocks.reset()

	_check(run.RULES.bank.rewards == REWARDS, "rules.json lists one bank reward per difficulty")
	for i in 5:
		_check(not run.unlocks.is_unlocked("item", REWARDS[i]), "%s starts locked" % REWARDS[i])
		_check(run.unlocks.requirement("item", REWARDS[i]).begins_with("Open the bank vault"), "%s explains how to unlock it" % REWARDS[i])

	# ---- the robbery ----
	_start_bank(1)
	var bv = a.bank_vault
	_check(a.level == "bank" and bv.active, "a bank wave starts the robbery")
	_check(bv.holder == null and bv.objective().contains("CUSTOMERS"), "no key holder until a customer walks in")
	var c1 = _customer(a.P.x + 300, a.P.y); var c2 = _customer(a.P.x - 300, a.P.y)
	bv.update(a, 0.016)
	_check(bv.holder != null and [c1, c2].has(bv.holder) and bv.holder.has_key, "one random customer gets the key")
	_check(c1.bank and c2.bank, "customers are locked in during the robbery")
	var holder = bv.holder; var other = c2 if holder == c1 else c1
	other.dead = true; bv.update(a, 0.016)
	_check(bv.key_pos == null and bv.holder == holder, "dropping a customer without the key drops nothing")
	a.P.x = a.BankVault.DOOR.x; a.P.y = a.BankVault.DOOR.y + 40; bv.update(a, 0.016)
	_check(not bv.opened, "the vault won't open without the key")
	holder.dead = true; bv.update(a, 0.016)
	_check(bv.key_pos != null and bv.key_pos.distance_to(Vector2(holder.x, holder.y)) < 1.0, "the key drops where its holder fell")
	_check(bv.objective().contains("GRAB"), "the HUD points at the dropped key")
	a.P.x = bv.key_pos.x; a.P.y = bv.key_pos.y; bv.update(a, 0.016)
	_check(bv.has_key and bv.key_pos == null, "walking over the key picks it up")
	_check(bv.objective().contains("VAULT DOOR"), "the HUD sends the villain to the vault door")
	var pickups_before: int = a.pickups.size()
	a.P.x = a.BankVault.DOOR.x; a.P.y = a.BankVault.DOOR.y + 40; bv.update(a, 0.016)
	_check(bv.opened and run.bank_cracked, "the key opens the vault")
	_check(a.pickups.size() > pickups_before + 20, "the vault spills cash")
	_check(bv.reward == "vault_plating" and bv.unlocked and run.build.items.has("vault_plating"), "difficulty 1 unlocks and installs Vault Door Plating")
	_check(run.unlocks.is_unlocked("item", "vault_plating"), "the reward stays unlocked")

	# ---- once per run ----
	_start_bank(1, false)
	_check(not a.bank_vault.active, "the vault can only be robbed once per run")
	_start_bank(1)
	_check(a.bank_vault.active, "a new run brings the robbery back")
	_rob()
	_check(a.bank_vault.opened and not a.bank_vault.unlocked, "a repeat vault on the same difficulty installs but doesn't re-unlock")

	# ---- one unlockable per difficulty ----
	for level in range(2, 6):
		_start_bank(level)
		_rob()
		_check(a.bank_vault.reward == REWARDS[level - 1] and a.bank_vault.unlocked, "difficulty %d unlocks %s" % [level, REWARDS[level - 1]])
	_check(REWARDS.all(func(id): return run.unlocks.is_unlocked("item", id)), "all five bank rewards end up unlocked")

	# ---- save round trip ----
	var reloaded = UnlocksT.new(run.RULES.unlocks)
	reloaded.path = SAVE; reloaded.load_save()
	_check(reloaded.banks.size() == 5 and REWARDS.all(func(id): return reloaded.is_unlocked("item", id)), "bank progress survives a reload")

	# ---- not on other themes ----
	run.new_run(); run.wave = 1; scene._start_wave()
	_check(a.level == "street" and not a.bank_vault.active, "no robbery outside the bank")

	run.unlocks.reset(); DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("BANK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

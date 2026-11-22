extends SceneTree
## Shop selling: 45% refund of the wave-scaled price, one copy at a time, arm-slot consistency,
## the Bionic Arm can't be sold while something is mounted on it, and the two-press controller flow.
const MAIN = "res://game/main.tscn"
var failures := 0
var checks := 0
var run: Node

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", what)

func _run() -> void:
	seed(1234)
	run = root.get_node("Run")
	var scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	# ---- price and refund ----
	run.new_run(); run.wave = 5; run.scrap = 0
	run.build.items = ["coat", "coat", "fins"]; run.recompute()
	var exp: int = roundi(run.ITEM.coat.c * (1.0 + run.RULES.shop.price_growth * 4) * 0.45)
	_check(run.sell_price("coat") == exp, "sell price is 45%% of the wave-scaled price (%d)" % exp)
	var hp_before: int = run.D.maxHp
	_check(run.sell("coat") == exp and run.scrap == exp, "selling refunds scrap")
	_check(run.CNT.get("coat", 0) == 1 and run.D.maxHp == hp_before - 15, "selling removes exactly one copy and recomputes stats")
	_check(run.sell("magnet") == 0 and run.scrap == exp, "can't sell what you don't own")
	# ---- arm slot ----
	run.new_run(); run.scrap = 10000
	run.build.items = ["bionic_arm"]; run.recompute()
	run.offers = [{"it": run.ITEM.offhand, "price": 1, "sold": false}]
	_check(run.buy(0) and run.build.off.get("kind", "gun") == "gun", "off-hand gun bought")
	var gun_ammo: int = run.build.off.ammo
	var arm_items: Array = run.ITEMS.filter(func(it): return it.has("arm"))
	if arm_items.size() > 0:
		var arm: Dictionary = arm_items[0]
		run.offers = [{"it": arm, "price": 1, "sold": false}]
		_check(run.buy(0) and run.build.off.kind == arm.arm, "utility replaces the gun in the arm slot")
		_check(run.sell_block_reason("bionic_arm") != "", "bionic arm can't be sold while modules are mounted")
		_check(run.sell("bionic_arm") == 0 and run.CNT.has("bionic_arm"), "blocked sale changes nothing")
		run.sell(arm.id)
		_check(run.build.off != null and run.build.off.get("kind", "gun") == "gun" and run.build.off.ammo == gun_ammo, "selling the utility falls back to the owned off-hand gun")
	run.sell("offhand")
	_check(run.build.off == null, "selling the Off-Hand Rig clears build.off")
	_check(run.sell_block_reason("bionic_arm") == "" and run.sell("bionic_arm") > 0 and not run.CNT.has("bionic_arm"), "bare bionic arm can be sold")
	_check(run.item_available(run.ITEM.bionic_arm), "a sold bionic arm can be bought again")
	_check(not scene.arena.villain.rig.armed, "rig drops the off-hand gun after the sale")
	# ---- shop UI: two presses to sell, focus stays on the owned list ----
	run.new_run(); run.wave = 3; run.build.items = ["coat", "boots"]; run.scrap = 0; run.gen_offers()
	scene.shop_s.refresh(); scene._show("shop")
	await process_frame
	var chip: Button = null
	for c in scene.shop_s.owned_box.get_children():
		if c is Button and c.text.contains("Rocket Boots"): chip = c
	_check(chip != null and chip.focus_mode != Control.FOCUS_NONE, "owned modules are focusable buttons")
	if chip:
		chip.pressed.emit()
		_check(run.CNT.has("boots") and scene.shop_s._confirm_id == "boots", "first press only asks to confirm")
		var confirm: Button = null
		for c in scene.shop_s.owned_box.get_children():
			if c is Button and c.text.begins_with("SELL "): confirm = c
		_check(confirm != null, "confirm button is shown")
		if confirm: confirm.pressed.emit()
		_check(not run.CNT.has("boots") and run.scrap == run.sell_price("coat") * 0 + roundi(run.ITEM.boots.c * (1.0 + run.RULES.shop.price_growth * 2) * 0.45), "second press sells")
		await process_frame; await process_frame
		var f = root.get_viewport().gui_get_focus_owner()
		_check(f != null and f.get_parent() == scene.shop_s.owned_box, "focus stays on the owned list after selling")
	print("SELL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

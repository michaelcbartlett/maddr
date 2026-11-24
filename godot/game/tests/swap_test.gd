extends SceneTree
## Shop ammo/frame swaps: part offers in gen_offers, buying swaps the main gun, trade-in of a bought part,
## selling a bought part restores the starting part, starting parts can't be sold, and the shop UI.
const MAIN = "res://game/main.tscn"
var failures := 0
var checks := 0
var run: Node

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: ", what)

func _offer(id: String, price := -1) -> Dictionary:
	var it: Dictionary = run.PARTS.filter(func(p): return p.id == id)[0]
	return {"it": it, "price": run.wave_price(it.c) if price < 0 else price, "sold": false}

func _run() -> void:
	seed(9001)
	run = root.get_node("Run")
	run.unlocks.highest_difficulty = 5 # balance checks cover every tier
	var scene = load(MAIN).instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	# ---- balance anchor: the default start still one-shots a wave-1 cop on every tier ----
	run.new_run()
	_check(run.ammo_id() == "laser" and run.FRAMES[run.build.frame].id == "pistol", "new runs start with Laser + Ray Pistol")
	for d in range(1, 6):
		run.set_difficulty(d)
		_check(run.D.dmg >= float(run.ET.cop.hp) * run.tough_mult(), "Laser Ray Pistol one-shots a wave-1 cop on tier %d" % d)
	run.set_difficulty(1)
	# ---- part table ----
	_check(run.PARTS.size() == run.AMMO.size() + run.FRAMES.size(), "a part offer exists for every ammo and frame")
	for p in run.PARTS:
		_check(p.has("swap") and p.has("t") and p.has("c") and p.has("name") and p.has("look") and not run.ITEM.has(p.id), "part %s is a shop pseudo-item" % p.id)
	# ---- gen_offers: parts appear, at most one per shop, never the current or starting part ----
	run.new_run()
	var chance: float = run.RULES.parts.chance
	run.RULES.parts.chance = 1.0
	var min_wave := int(run.RULES.parts.get("min_wave", 1))
	_check(min_wave > 5, "no part offers until the wave-5 boss is behind you")
	run.wave = min_wave - 1
	var early := false
	for n in 50:
		run.gen_offers()
		if run.offers.any(func(o): return o.it.has("swap")): early = true
	_check(not early, "shops before wave %d never offer ammo/frame swaps" % min_wave)
	run.wave = min_wave
	var seen := {}
	for n in 200:
		run.gen_offers()
		var parts: Array = run.offers.filter(func(o): return o.it.has("swap"))
		if parts.size() != 1: _check(false, "exactly one part offer per shop when chance = 1 (%d)" % parts.size()); break
		var it: Dictionary = parts[0].it
		seen[it.id] = true
		if it.id in ["part_ammo_laser", "part_frame_pistol"]: _check(false, "the starting part is never offered"); break
	_check(seen.has("part_ammo_bullet") and seen.has("part_frame_blunder") and seen.has("part_frame_rifle"), "common parts show up from the first eligible shop")
	run.RULES.parts.chance = 0.0
	run.gen_offers()
	_check(not run.offers.any(func(o): return o.it.has("swap")), "chance 0 disables part offers")
	run.RULES.parts.chance = chance
	# ---- DPS preview on part cards ----
	run.new_run(); run.build.items = ["cell"]; run.recompute()
	var dps0: float = run.main_gun_dps(); var bullet_change: float = run.part_dps_change(run.part_def("ammo", 1))
	_check(bullet_change > 0.2 and run.ammo_id() == "laser" and is_equal_approx(run.main_gun_dps(), dps0), "Bullets preview a DPS gain without changing the gun")
	_check(run.part_dps_change(run.part_def("frame", 2)) < 0.0, "the Long Rifle previews a DPS loss on a laser")
	# ---- buying a swap ----
	run.new_run(); run.wave = 3; run.scrap = 100
	run.build.items = ["cell"]; run.recompute()
	var dmg_laser: float = run.D.dmg
	run.offers = [_offer("part_ammo_bullet")]
	var price: int = run.offers[0].price
	_check(price == run.wave_price(18), "part price is wave-scaled like items (%d)" % price)
	_check(run.buy(0), "can buy an ammo swap")
	_check(run.ammo_id() == "bullet" and run.build.swapped.ammo and run.scrap == 100 - price, "ammo swapped and charged")
	_check(run.build.items == ["cell"] and not run.CNT.has("part_ammo_bullet"), "parts don't go into the module list")
	_check(run.D.dmg > dmg_laser and run.S.guns[0] == "bullet", "stats follow the new ammo")
	_check(scene.arena.villain.rig.ammo == "bullet", "rig follows the ammo swap")
	_check(run.build.name == "" or run.build.name == run.weapon_name(), "auto name follows the swap")
	_check(not run.buy(0), "a sold offer can't be bought twice")
	# ---- trade-in: replacing a bought part refunds it towards the price ----
	var back: int = run.part_trade_in("ammo")
	_check(back == roundi(run.wave_price(18) * 0.45) and back == run.sell_price("part:ammo"), "trade-in is the 45%% sell refund (%d)" % back)
	run.scrap = 0
	run.offers = [_offer("part_ammo_razor", back + 5)]
	_check(not run.buy(0), "trade-in alone can't cover a pricier part")
	run.scrap = 5
	_check(run.buy(0) and run.ammo_id() == "razor" and run.scrap == 0, "trade-in counts towards the price")
	run.offers = [_offer("part_ammo_laser")]
	_check(not run.item_available(run.offers[0].it), "the starting Laser isn't offered back")
	# ---- selling a bought part restores the starting part ----
	run.scrap = 0
	var refund: int = run.sell_price("part:ammo")
	_check(run.sell_block_reason("part:ammo") == "" and run.sell("part:ammo") == refund and run.scrap == refund, "a bought part can be sold")
	_check(run.ammo_id() == "laser" and not run.build.swapped.ammo, "selling it puts the starting Laser back")
	_check(run.sell_block_reason("part:ammo") != "" and run.sell("part:ammo") == 0 and run.ammo_id() == "laser", "the starting part can't be sold")
	_check(run.sell_block_reason("part:frame") != "", "the starting frame can't be sold")
	# ---- frames ----
	run.scrap = 1000
	run.offers = [_offer("part_frame_repeater")]
	_check(run.buy(0) and run.FRAMES[run.build.frame].id == "repeater" and run.D.cd < 0.3, "frame swap changes fire rate")
	_check(scene.arena.villain.rig.frame_id == "repeater", "rig follows the frame swap")
	run.sell("part:frame")
	_check(run.FRAMES[run.build.frame].id == "pistol", "selling the frame restores the Ray Pistol")
	# ---- unlocked start: parts swap back to that start, and Laser / Pistol can be bought ----
	run.new_run(); run.unlocks.unlocked.append("ammo:bullet")
	_check(run.set_start("ammo", 1) and run.ammo_id() == "bullet", "unlocked Bullets start")
	run.offers = [_offer("part_ammo_laser")]; run.scrap = 1000
	_check(run.item_available(run.offers[0].it) and run.buy(0) and run.ammo_id() == "laser", "a Bullets start can buy the Laser")
	run.sell("part:ammo")
	_check(run.ammo_id() == "bullet", "selling returns to the run's own start")
	run.unlocks.unlocked.erase("ammo:bullet")
	# ---- shop UI ----
	run.new_run(); run.wave = 4; run.scrap = 200; run.build.items = ["coat"]; run.recompute()
	run.offers = [_offer("part_frame_rifle"), {"it": run.ITEM.boots, "price": 5, "sold": false}]
	scene.shop_s.refresh(); scene._show("shop")
	await process_frame
	var card = scene.shop_s.offers_box.get_child(0)
	var txt := _texts(card)
	_check(txt.contains("Long Rifle") and txt.contains("Replaces Ray Pistol"), "part offer card names the part it replaces")
	var buy_btn: Button = card.get_child(0).get_child(card.get_child(0).get_child_count() - 1)
	buy_btn.pressed.emit(); await process_frame
	_check(run.FRAMES[run.build.frame].id == "rifle", "buying from the card swaps the frame")
	var frame_chip: Button = _chip(scene.shop_s, "Long Rifle")
	var ammo_chip: Button = _chip(scene.shop_s, "Laser")
	_check(frame_chip != null and ammo_chip != null, "gun parts are listed with the modules")
	if ammo_chip:
		ammo_chip.pressed.emit()
		_check(run.ammo_id() == "laser" and scene.shop_s._confirm_id == "" and scene.shop_s.sell_l.text.begins_with("Starting ammo"), "starting part chip explains why it can't be sold")
	if frame_chip:
		var before: int = run.scrap
		frame_chip.pressed.emit()
		_check(scene.shop_s._confirm_id == "part:frame", "first press asks to confirm the part sale")
		var confirm := _chip(scene.shop_s, "SELL ")
		if confirm: confirm.pressed.emit()
		_check(run.FRAMES[run.build.frame].id == "pistol" and run.scrap == before + roundi(run.wave_price(20) * 0.45), "second press sells the part back")
	# swap offer with a trade-in shows the net price
	run.offers = [_offer("part_frame_blunder")]
	var b2: Dictionary = run.offers[0].it
	run.scrap = 500; run.offers = [{"it": run.PARTS.filter(func(p): return p.id == "part_frame_rifle")[0], "price": 30, "sold": false}]
	run.buy(0)
	run.offers = [{"it": b2, "price": 40, "sold": false}]
	scene.shop_s.refresh(); await process_frame
	var t2 := _texts(scene.shop_s.offers_box.get_child(0))
	var net: int = 40 - run.part_trade_in("frame")
	_check(t2.contains("Trade in Long Rifle") and t2.contains("⚙ %d" % net), "trade-in is shown and taken off the price")
	# ---- Focusing Lens (laser bolt -> beam) in the shop ----
	run.new_run(); run.unlocks.unlocked.erase("item:lens")
	_check(run.S.beam == 0 and not run.item_available(run.ITEM.lens), "no lens before the meta unlock")
	_check(not run.item_available(run.ITEM.sustain), "Sustained Beam needs the lens first")
	run.unlocks.unlocked.append("item:lens")
	_check(run.item_available(run.ITEM.lens), "unlocked lens is offered with a laser equipped")
	run.offers = [{"it": run.ITEM.lens, "price": 1, "sold": false}]; run.scrap = 10
	_check(run.buy(0) and run.S.beam == 1 and not run.item_available(run.ITEM.lens), "buying the lens makes lasers beams (one copy)")
	_check(run.item_available(run.ITEM.sustain), "Sustained Beam is offered once the lens is owned")
	run.build.items.append("sustain"); run.recompute()
	_check(run.sell_block_reason("lens") != "" and run.sell("lens") == 0, "the lens can't be sold out from under a Sustained Beam")
	run.new_run(); run.offers = [_offer("part_ammo_bullet")]; run.scrap = 100; run.buy(0)
	_check(not run.item_available(run.ITEM.lens), "no lens offers without a laser")
	run.unlocks.unlocked.erase("item:lens")
	# ---- Brotato-style loot roll ----
	run.new_run(); run.wave = 1
	var base: float = run.RULES.economy.drop_chance
	_check(base > 0.0 and base < 1.0 and is_equal_approx(run.drop_chance(), base), "cops drop loot only some of the time (%d%%)" % roundi(base * 100))
	run.build.items = ["pickpocket"]; run.recompute()
	_check(is_equal_approx(run.drop_chance(), base + 0.12), "Pickpocket Glove raises the drop chance")
	run.build.items = ["overkill"]; run.recompute()
	_check(is_equal_approx(run.drop_chance(), base - 0.15) and run.D.dmg > 8.0, "Overkill Charge lowers it for damage")
	run.build.items = ["pickpocket", "pickpocket", "pickpocket", "pickpocket", "pickpocket"]; run.recompute()
	_check(run.drop_chance() == 1.0, "drop chance caps at 100%")
	run.build.items = []; run.recompute()
	var a = scene.arena
	scene._start_wave(); a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000
	var dropped := 0; var value := 0.0; var n := 600
	for k in n:
		a.pickups.clear()
		var e = a.make_enemy("cop", a.P.x + 400, a.P.y); a.hit(e, 1.0e6, {})
		if a.pickups.any(func(p): return not p.has("intel")): dropped += 1   # Intel dossiers roll separately
		for p in a.pickups: value += p.v
		a.enemies.erase(e); e.queue_free()
		if k % 50 == 0: await process_frame
	var rate := float(dropped) / n
	_check(absf(rate - base) < 0.07, "observed drop rate matches the chance (%.2f)" % rate)
	_check(absf(value / n - float(run.ET.cop.scrap)) < 0.25 * float(run.ET.cop.scrap), "average scrap per kill is unchanged at the base chance (%.2f)" % (value / n))
	var b = a.make_enemy("boss", a.P.x + 400, a.P.y); a.pickups.clear(); a.hit(b, 1.0e9, {})
	_check(a.pickups.filter(func(p): return not p.has("blueprint") and not p.has("intel")).size() == 24, "bosses always drop scrap independently of blueprints")
	print("SWAP TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _texts(n: Node) -> String:
	var s := ""
	if n is Label or n is Button: s += n.text + "\n"
	for c in n.get_children(): s += _texts(c)
	return s

func _chip(shop, needle: String) -> Button:
	for c in shop.owned_box.get_children():
		if c is Button and c.text.contains(needle): return c
	return null

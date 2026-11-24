extends SceneTree
## Bionic-arm melee weapons (knife, whip, katana), melee stat upgrades, and damage-type amplifiers incl. radiation.
var scene
var a
var run
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

## Whip primary + Bionic Arm can buy the Mad Katana as the automatic secondary (dual wield). The katana
## offer is gated only by scrap, priced like every offer by wave, and the shop says how much is missing.
func _test_dual_wield_shop() -> void:
	scene._show("title")
	run.new_run(); run.build.ammo = run.AMMO.find_custom(func(d): return d.id == "whip"); run.wave = 9
	run.build.items = ["bionic_arm", "extender", "knuckles", "servos"]; run.build.off = null; run.recompute()
	_check(run.has_primary_melee() and run.item_available(run.ITEM.katana), "katana arm offer is available with a whip primary and a bare Bionic Arm")
	var price: int = run.wave_price(run.ITEM.katana.c)
	_check(price == roundi(62 * (1.0 + run.RULES.shop.price_growth * 8)), "wave 9 katana price is the normal wave scaling of its base cost (%d)" % price)
	run.scrap = 9; run.offers = [{"it": run.ITEM.katana, "price": price, "sold": false}, {"it": run.ITEM.cell, "price": run.wave_price(run.ITEM.cell.c), "sold": false}]
	scene.shop_s.refresh(); scene._show("shop"); await process_frame
	for card in scene.shop_s.offers_box.get_children():
		var vb: VBoxContainer = card.get_child(0)
		var b: Button = vb.get_child(vb.get_child_count() - 1)
		var need: Label = vb.get_node_or_null("NeedScrap")
		_check(b.disabled and need != null and need.text.contains("%d" % (int(b.text.trim_prefix("⚙ ")) - 9)), "unaffordable offer %s is disabled and says how much scrap is missing" % b.text)
	run.scrap = price; scene.shop_s.refresh(); await process_frame
	var kb: Button = scene.shop_s.offers_box.get_child(0).get_child(0).get_child(scene.shop_s.offers_box.get_child(0).get_child(0).get_child_count() - 1)
	_check(not kb.disabled and scene.shop_s.offers_box.get_child(0).get_child(0).get_node_or_null("NeedScrap") == null, "affordable katana offer is enabled with no shortfall note")
	kb.pressed.emit()
	_check(run.build.off != null and run.build.off.kind == "katana" and run.scrap == 0, "buying the katana mounts it on the Bionic Arm")
	_check(run.primary_melee_spec().kind == "whip" and run.melee_spec().kind == "katana", "whip primary and katana secondary are dual wielded")
	# buying the weapon offers the hand choice: the swap button is highlighted, A puts the katana in the main hand
	await process_frame
	_check(root.gui_get_focus_owner() == scene.shop_s.swap_btn and scene.shop_s.swap_btn.visible, "after buying the katana the shop highlights Swap hands")
	var items_before: Array = run.build.items.duplicate(); var ammo_before: int = run.build.ammo
	scene.shop_s.swap_btn.pressed.emit(); await process_frame
	_check(run.primary_melee_spec().kind == "katana" and run.melee_spec().kind == "whip", "Swap hands makes the katana primary and the whip the auto secondary")
	_check(run.primary_weapon_id() == "katana" and run.arm_off().kind == "whip" and run.weapon_name().ends_with("Sword"), "the villain draws and names the swapped hands")
	_check(run.build.items == items_before and run.build.ammo == ammo_before and run.sell_price("katana") == roundi(62 * (1.0 + run.RULES.shop.price_growth * 8) * 0.45), "swapping hands changes no ownership or sale values")
	_check(scene.shop_s.secondary_l.text.contains("MAIN · Mad Katana") and scene.shop_s.secondary_l.text.contains("ARM · Shock Whip"), "shop shows which weapon is in each hand")
	_check(root.gui_get_focus_owner() == scene.shop_s.swap_btn, "the controller stays on Swap hands")
	scene.shop_s.swap_btn.pressed.emit(); await process_frame
	_check(run.primary_melee_spec().kind == "whip" and run.melee_spec().kind == "katana", "pressing again swaps back")
	run.swap_hands()
	# robotic slot: choose which owned arm item is mounted; mounting something else resets the hand swap
	run.build.items.append("time_freeze"); run.build.off = {"kind": "time_freeze"}; run.recompute()
	_check(not run.can_swap_hands() and run.primary_melee_spec().kind == "whip", "a utility on the arm leaves the primary in the main hand")
	scene.shop_s.refresh(); await process_frame
	_check(scene.shop_s.arm_btn.visible and scene.shop_s.arm_btn.text.contains("Mad Katana"), "the arm button offers to mount the owned katana")
	scene.shop_s.arm_btn.pressed.emit(); await process_frame
	_check(run.build.off.kind == "katana" and not run.hands_swapped() and run.melee_spec().kind == "katana", "mounting re-equips the katana on the Bionic Arm")
	_check(root.gui_get_focus_owner() == scene.shop_s.arm_btn, "the controller stays on the arm button")
	run.mount_arm("time_freeze"); run.sell("time_freeze")
	_check(run.build.off.kind == "katana", "selling the mounted utility falls back to the katana")
	# selling the arm weapon while swapped returns the primary to the main hand
	run.swap_hands(); run.sell("katana")
	_check(run.build.off == null and run.primary_melee_spec().kind == "whip" and not run.hands_swapped(), "selling the swapped arm weapon puts the whip back in the main hand")
	# Shock Whip: legendary shop find (arm item and primary part), never a Lab starting weapon
	_check(int(run.ITEM.whip.t) == 4 and int(run.part_def("ammo", run.build.ammo).t) == 4, "the Shock Whip is a LEGENDARY offer as an arm weapon and as a primary")
	_check(run.tier_weights(9)[4] < 0.1 * run.tier_weights(9)[1], "legendary offers are rare")
	run.new_run()
	var whip_i: int = run.AMMO.find_custom(func(d): return d.id == "whip")
	_check(not run.set_start("ammo", whip_i) and run.ammo_id() != "whip", "the whip can't be picked as a starting weapon")
	scene.design_s.refresh(); await process_frame
	var lab_names: Array = scene.design_s.ammo_box.get_children().map(func(c): return c.get_child(0).get_child(0).text)
	_check(not lab_names.any(func(n): return n.contains("Shock Whip")) and lab_names.any(func(n): return n.contains("Mad Sword")), "the Lab lists melee starters but not the Shock Whip")
	scene._show("title")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _start(items: Array) -> void:
	run.new_run(); run.build.items = items.duplicate(); run.build.off = null
	run._rebuild_off(); run.recompute()
	scene._start_wave(); a.walls = []; a.spawn_t = 1000; a.civ_t = 1000; run.S.crit = 0.0
	for e in a.enemies: e.dead = true
	a.P.melee_cd = 0.0; a.P.melee_t = 0.0; a.utility_fields.clear()
	a.villain.set_items()
	a._sync(0.0)

func _cop(dx: float, dy := 0.0):
	var o = a.villain.off_shoulder_global()
	var e = a.make_enemy("cop", o.x + dx, o.y + dy); e.hp = 5000; e.max_hp = 5000
	return e

## Runs the arm until one swing has landed.
func _swing() -> void:
	for i in 60:
		a._update_melee(1.0 / 60.0)
		if a.P.melee_hit and a.P.melee_t <= 0.0: return

func _primary(kind: String, items: Array = []) -> void:
	_start(items)
	run.build.ammo = run.AMMO.find_custom(func(def): return def.id == kind)
	run.recompute(); scene._start_wave()
	a.walls = []; a.spawn_t = 1000; a.civ_t = 1000; a.crate_t = 1000; a.P.inv = 1000; run.S.crit = 0.0
	var controls = root.get_node("Controls"); controls.device = 0; controls.aim_src = "pad"
	a.P.aim = -0.8; a._sync(0.0); a._primary_blade_previous = a.villain.rig.melee_sample(true)
	_stick(-0.8)

func _stick(angle: float) -> void:
	for entry in [[JOY_AXIS_RIGHT_X,cos(angle)],[JOY_AXIS_RIGHT_Y,sin(angle)]]:
		var event := InputEventJoypadMotion.new(); event.device = 0; event.axis = entry[0]; event.axis_value = entry[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _cut_frames(frames: int, dt: float) -> void:
	for i in frames:
		a._update_play(dt); a._update_fx(dt); a._sync(0.0)

func _test_grips() -> void:
	for kind in ["knife","katana"]:
		_primary(kind,["bionic_arm",kind])
		for angle in [0.0,1.2,PI,-1.8]:
			a.P.aim = angle; a.P.melee_aim = angle; a.P.melee_arc = 0
			a.P.melee_t = 0.15; a.P.melee_swing = 0.3; a._sync(0)
			for primary in [true,false]:
				var rig = a.villain.rig
				var grip: Vector2 = rig.melee_grip_local(primary)
				var points: PackedVector2Array = rig.melee_local_points(primary)
				var forearm: Vector2 = grip-rig.melee_elbow_local(primary)
				var blade: Vector2 = points[1]-points[0]
				_check(absf(forearm.normalized().dot(blade.normalized())) < 0.12, "%s exits across the fist like the edited cop baton (%s, %.1f)" % [kind,"primary" if primary else "secondary",angle])
				_check(grip.distance_to(points[0]) <= 8.0, "%s blade begins beside the gripping fingers in either hand" % kind)
				var sample: Dictionary = rig.melee_sample(primary)
				var world: PackedVector2Array = a.MeleeMotion.world_points(sample)
				var pivot: Node2D = rig.gun_pivot if primary else rig.off_pivot
				_check(world[0].distance_to(pivot.to_global(points[0])) < 0.001, "%s trail remains attached to the wrist through facing changes" % kind)
		if OS.get_cmdline_user_args().has("--screenshots"):
			a.P.aim = 0; a.P.melee_aim = -0.85; a.P.inv = 0
			a.banner_t = 0; a.siren_t = 0; a.cam.zoom = Vector2.ONE*3; scene.hud.visible = false
			a._sync(0); a.cam.force_update_scroll()
			await process_frame; await process_frame; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test-results/melee-grip-%s.png" % kind)
			scene.hud.visible = true

func _test_primary() -> void:
	for kind in ["knife","katana","whip"]:
		for dt in [1.0/60.0,1.0/20.0]:
			_primary(kind)
			_check(run.primary_melee_spec().kind == kind and not a.villain.rig.gun.visible, "%s is a visible primary melee weapon" % kind)
			var origin: Vector2 = a.villain.shoulder_global()
			var distance := 42.0 if kind == "knife" else (65.0 if kind == "katana" else 115.0)
			var spot: Vector2 = origin+_blade_heading(distance)
			var enemy = a.make_enemy("cop",spot.x,spot.y); enemy.hp = 5000; enemy.max_hp = 5000; enemy.time_lock = 100
			_stick(0.8); _cut_frames(ceili(0.2/dt),dt)
			_check(enemy.hp < 5000 and a.projs.is_empty(), "%s cuts with the stick alone at %d FPS" % [kind,roundi(1.0/dt)])
			_check(a.utility_fields.any(func(f): return f.kind == "slash" and f.primary), "%s records its actual primary blade path" % kind)
			var damage: float = 5000.0-enemy.hp
			_check(damage >= float(run.primary_melee_spec().dmg), "manual %s deals heavy damage" % kind)
			var hp: float = enemy.hp
			_cut_frames(ceili(0.8/dt),dt)
			_check(is_equal_approx(enemy.hp,hp), "holding %s still cannot repeatedly damage a foe" % kind)
			_check(not a.utility_fields.any(func(f): return f.kind == "slash"), "%s trail diminishes and expires" % kind)
	# Both hands can cut independently in the same simulation frame.
	_primary("katana",["bionic_arm","katana"])
	var front_origin: Vector2 = a.villain.shoulder_global(); var rear_origin: Vector2 = a.villain.off_shoulder_global()
	var front_spot: Vector2 = front_origin+_blade_heading(65.0)
	var front = a.make_enemy("cop",front_spot.x,front_spot.y)
	var rear = a.make_enemy("cop",rear_origin.x-50,rear_origin.y)
	for enemy in [front,rear]: enemy.hp = 5000; enemy.max_hp = 5000; enemy.time_lock = 100
	_stick(0.8); _cut_frames(14,1.0/60.0)
	_check(front.hp < 5000 and rear.hp < 5000, "dual swords hit the manual target and the automatic secondary target")
	_check(a.utility_fields.any(func(f): return f.kind == "slash" and f.primary) and a.utility_fields.any(func(f): return f.kind == "slash" and not f.primary), "dual swords leave separate trails")
	if OS.get_cmdline_user_args().has("--screenshots"):
		a.banner_t = 0; a.siren_t = 0; a.P.inv = 0; scene.hud.visible = false; a.cam.zoom = Vector2.ONE*2.0; a._sync(0.0); a.cam.force_update_scroll()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://test-results")
		root.get_texture().get_image().save_png("res://test-results/melee-dual-sword.png")
		scene.hud.visible = true
	# Trail endpoints are the rendered blade's endpoints; old samples stay in world space.
	var sample: Dictionary = a.villain.rig.melee_sample(true)
	var world: PackedVector2Array = a.MeleeMotion.world_points(sample)
	var local: PackedVector2Array = a.villain.rig.melee_local_points(true)
	_check(world[world.size()-1].distance_to(a.villain.rig.gun_pivot.to_global(local[local.size()-1])) < 0.001, "trail tip exactly matches the rendered sword tip")
	var trail: Dictionary = a.utility_fields.filter(func(f): return f.kind == "slash")[0]
	var captured: PackedVector2Array = trail.current.duplicate()
	a.P.x += 100; a._sync(0.0)
	_check(trail.current == captured, "lingering trails remain at the previous cut while the player moves")
	# Walls block manual cuts, even during a fast sweep.
	_primary("katana")
	var origin: Vector2 = a.villain.shoulder_global()
	var blocked = a.make_enemy("cop",origin.x+65,origin.y); blocked.hp = 5000; blocked.max_hp = 5000; blocked.time_lock = 100
	a.walls = [{"rect":Rect2(origin+Vector2(36,-50),Vector2(8,100)),"open":false}]
	_stick(0.8); _cut_frames(12,1.0/60.0)
	_check(blocked.hp == 5000, "a primary sword cannot cut a cop through a wall")
	# Primary and secondary can use different weapons; reach upgrades change art and damage geometry together.
	_primary("knife",["bionic_arm","katana","extender"])
	_check(run.primary_melee_spec().kind == "knife" and run.melee_spec().kind == "katana", "primary knife and auto sword equip independently")
	_check(is_equal_approx(a.villain.rig.primary_melee_reach,run.primary_melee_spec().reach) and is_equal_approx(a.villain.rig.melee_reach,run.melee_spec().reach), "reach upgrades update both rendered weapons")
	for action in ["fire","fire_off"]: Input.action_press(action)
	a._fire_weapons(0.1,false,false)
	_check(a.projs.is_empty(), "a melee primary never emits hidden gun shots")
	for action in ["fire","fire_off"]: Input.action_release(action)
	_primary("knife",["bionic_arm","offhand"])
	a.P.off_cd = 0.0; Input.action_press("fire_off"); a._update_play(0.05); Input.action_release("fire_off")
	_check(not a.projs.is_empty() and a.projs.all(func(p): return p.source == -1), "a manual knife can coexist with a working rear gun")

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.set_process(false); a = scene.arena; a.set_process(false)

	_start([])
	for id in ["knife", "whip", "katana", "servos", "extender", "knuckles", "berserker"]:
		_check(not run.item_available(run.ITEM[id]), "%s needs the bionic arm" % id)
	_start(["bionic_arm"])
	for id in ["knife", "whip", "katana", "servos", "extender", "knuckles"]:
		_check(run.item_available(run.ITEM[id]), "%s is offered once the arm is owned" % id)
	_check(run.melee_spec().reach == 58.0, "bare arm keeps the fist")

	# per-weapon cooldowns
	for kind in ["knife", "whip", "katana"]:
		_start(["bionic_arm", kind])
		_check(run.build.off.kind == kind, "%s mounts in the arm slot" % kind)
		var e = _cop(30)
		_swing()
		_check(e.hp < 5000, "%s auto-swings at a nearby cop" % kind)
		_check(is_equal_approx(a.P.melee_cd + a.P.melee_swing, float(run.ITEM[kind].melee.cd)) or a.P.melee_cd > 0.0, "%s starts its own cooldown" % kind)
		_check(a.utility_fields.any(func(f): return f.kind == "slash"), "%s leaves a swing trail" % kind)

	# knife: one target, fast
	_start(["bionic_arm", "knife"])
	var k1 = _cop(30, -4); var k2 = _cop(34, 6)
	_swing()
	_check((k1.hp < 5000) != (k2.hp < 5000), "knife stabs a single target")
	_check(run.melee_spec().cd < run.ITEM.katana.melee.cd, "knife cooldown is shorter than the katana")

	# whip: long reach, hits the line, stuns
	_start(["bionic_arm", "whip"])
	var far = _cop(130); var near = _cop(60)
	_swing()
	_check(far.hp < 5000 and near.hp < 5000, "whip lashes everything along its 150px line")
	_check(far.time_lock > 0.0, "whip stuns")
	_start(["bionic_arm", "knife"])
	var out_of_reach = _cop(130)
	_swing()
	_check(out_of_reach.hp == 5000, "knife can't reach a whip-distance cop")

	# katana: wide arc
	_start(["bionic_arm", "katana"])
	var front = _cop(50); var side = _cop(20, 45); var behind = _cop(-60)
	_swing()
	_check(front.hp < 5000 and side.hp < 5000, "katana slash hits a wide arc")
	_check(behind.hp == 5000, "katana misses foes behind the swing")

	# civilians are never auto-attacked
	_start(["bionic_arm", "knife"])
	var o = a.villain.off_shoulder_global()
	var civ = a.make_enemy("civ", o.x + 25, o.y)
	if civ != null:
		civ.civ = true; civ.hp = 100
		for i in 30: a._update_melee(1.0 / 60.0)
		_check(civ.hp == 100 and a.P.melee_t == 0.0, "melee ignores civilians")

	# melee upgrades
	_start(["bionic_arm", "katana"])
	var base: Dictionary = run.melee_spec()
	_start(["bionic_arm", "katana", "servos", "extender", "knuckles"])
	var up: Dictionary = run.melee_spec()
	_check(up.cd < base.cd and up.swing < base.swing, "servos speed up melee")
	_check(is_equal_approx(up.reach, base.reach * 1.2), "telescoping forearm adds 20% reach")
	_check(is_equal_approx(up.dmg, base.dmg * 1.25), "brass knuckles add 25% melee damage")
	_start(["bionic_arm", "servos"])
	_check(run.melee_spec().cd < 0.72, "melee upgrades also apply to the bare fist")

	# damage-type amplifiers gate on their effect and scale it
	_start([])
	for id in ["bellows", "venom", "geiger", "payraise", "windings"]:
		_check(not run.item_available(run.ITEM[id]), "%s waits for its effect" % id)
	_start(["thermite", "poison", "uranium", "hypno", "tesla"])
	for id in ["bellows", "venom", "geiger", "payraise", "windings"]:
		_check(run.item_available(run.ITEM[id]), "%s offered with its effect" % id)
	_start(["thermite", "bellows"])
	var burner = _cop(200); a.hit(burner, 1.0, {"proc": true})
	_check(is_equal_approx(burner.burn_dps, run.S.burn * 1.3 * (1.0 + run.S.dmgPct * 0.5)), "bellows boosts burn damage")
	_start(["tesla_helmet"])
	var z1 = _cop(200); a.hit(z1, 10.0, {"element": "lightning"})
	_start(["tesla_helmet", "windings"])
	var z2 = _cop(200); a.hit(z2, 10.0, {"element": "lightning"})
	_check(is_equal_approx(5000.0 - z2.hp, (5000.0 - z1.hp) * 1.25), "copper windings boost lightning")

	# radiation
	_start(["uranium"])
	var hot = _cop(200)
	a.hit(hot, 1.0, {"proc": true})
	_check(hot.rad_s == 1 and hot.rad_t > 0.0, "uranium slugs irradiate on hit")
	var neighbour = _cop(230)
	hot.rad_s = a.RAD_MAX - 1
	var before: float = hot.hp
	a.hit(hot, 1.0, {"proc": true})
	_check(hot.rad_s == 0 and hot.hp < before - 15.0, "full dose melts down for burst damage")
	_check(neighbour.rad_s > 0, "meltdown irradiates neighbours")

	await _test_primary()
	await _test_grips()
	await _test_dual_wield_shop()
	print("MELEE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Where the primary blade points at aim 0: straight ahead, or up for the scientist's upright katana stance.
## Offset by half the 0.8 rad test sweep so the target sits inside the cut.
func _blade_heading(distance: float) -> Vector2:
	var rig = a.villain.rig
	if not rig.upright_blade(true): return Vector2(distance,0)
	var points: PackedVector2Array = rig.melee_local_points(true)
	return Vector2(distance,0).rotated(points[points.size()-1].angle()+0.4)

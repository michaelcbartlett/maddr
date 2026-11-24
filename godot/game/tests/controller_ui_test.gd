extends SceneTree
## Real controller button events must activate exactly the focused native Control.
var scene
var run
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: " + label)

func _tap(button: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new(); event.device = 0; event.button_index = button; event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	run = root.get_node("Run")
	scene = load("res://game/main.tscn").instantiate(); root.add_child(scene); current_scene = scene
	scene.arena.set_process(false)
	scene._enter_lab(); await process_frame
	var sword: int = run.AMMO.find_custom(func(def): return def.id == "katana")
	var card: Button = scene.design_s.ammo_box.get_child(sword)
	card.grab_focus(); await process_frame
	await _tap(JOY_BUTTON_A)
	_check(run.ammo_id() == "katana" and scene.state == "design", "A selects the highlighted sword card instead of starting the run")
	await process_frame
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_A)
	_check(run.ammo_id() == "knife", "D-pad moves the highlight and A activates the new weapon card")
	scene.design_s.begin_btn.grab_focus(); await _tap(JOY_BUTTON_A)
	_check(scene.state == "difficulty", "A activates the highlighted Begin button")
	await _tap(JOY_BUTTON_B)
	_check(scene.state == "design" and run.ammo_id() == "knife", "B returns from difficulty without losing the chosen weapon")
	await _tap(JOY_BUTTON_B)
	_check(scene.state == "title", "B returns from the weapon design menu to the title")
	await _tap(JOY_BUTTON_A); await process_frame
	_check(scene.state == "game_select", "A opens the four-game selector from the title")
	await _tap(JOY_BUTTON_A); await process_frame
	_check(scene.state == "play" and run.save_slots.active_slot==1, "A starts a mission in the focused game slot")
	scene._enter_lab();await process_frame
	scene.design_s.begin_btn.grab_focus(); await _tap(JOY_BUTTON_A)
	await process_frame
	await _tap(JOY_BUTTON_A)
	_check(scene.state == "play", "A activates the highlighted difficulty choice")
	scene._on_cleared(); await process_frame
	run.scrap = 1000; run.offers = [{"it":run.ITEM.bionic_arm,"price":10,"sold":false}, {"it":run.ITEM.bionic_arm,"price":10,"sold":false}]
	scene.shop_s.refresh(); await process_frame; scene.shop_s.focus_default()
	await _tap(JOY_BUTTON_A)
	_check(run.CNT.get("bionic_arm",0) == 1 and run.scrap == 990, "A buys the focused shop offer exactly once")
	await process_frame
	scene.shop_s.next_btn.grab_focus(); await _tap(JOY_BUTTON_A)
	_check(scene.state == "play", "A starts the next wave when that button is highlighted")
	# Early shops (before wave 5) with scrap left over: the previous shop's still-affordable cards must not
	# steal the opening focus and then be freed, leaving the controller with nothing highlighted.
	for visit in 2:   # the wave 3 and wave 4 shops
		run.scrap = 1000
		scene._on_cleared(); await process_frame; await process_frame
		var owner := root.gui_get_focus_owner()
		var live: bool = owner is Button and is_instance_valid(owner) and owner.is_inside_tree() and scene.shop_s.offers_box.is_ancestor_of(owner)
		_check(scene.state == "shop" and run.wave < 5 and live, "wave %d shop opens with a live offer highlighted for the controller" % run.wave)
		var before: int = run.scrap
		await _tap(JOY_BUTTON_A)
		_check(run.scrap < before, "wave %d shop: A buys the highlighted offer" % run.wave)
		await process_frame
		var after_buy := root.gui_get_focus_owner()
		_check(after_buy != null and after_buy.is_inside_tree(), "wave %d shop: something stays highlighted after buying" % run.wave)
		await _tap(JOY_BUTTON_DPAD_UP); await _tap(JOY_BUTTON_DPAD_LEFT)
		var moved := root.gui_get_focus_owner()
		_check(moved != null and moved.is_inside_tree() and scene.shop_s.is_ancestor_of(moved), "wave %d shop: D-pad keeps a shop button highlighted" % run.wave)
		await _tap(JOY_BUTTON_START)
		_check(scene.state == "play", "wave %d shop: Start begins the next wave" % run.wave)
	scene._show("paused"); await process_frame
	await _tap(JOY_BUTTON_A)
	_check(scene.state == "play" and not paused, "A activates the highlighted Resume button")
	print("CONTROLLER UI TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
